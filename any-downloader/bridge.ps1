# bridge.ps1
# Loaded by window.ps1 — handles all commands from the UI via window.external.invoke()
# Commands: probe, download, browse

Add-Type -AssemblyName System.Windows.Forms

function Invoke-Bridge {
    param([System.Windows.Forms.WebBrowser]$Browser, [string]$JsonStr)

    try {
        $cmd = $JsonStr | ConvertFrom-Json
    } catch {
        Write-Host "[bridge] bad JSON: $JsonStr"
        return
    }

    switch ($cmd.cmd) {

        # ── Probe: run yt-dlp -J and return parsed info ───────────────────────
        "probe" {
            $url    = $cmd.url
            $ytdlp  = $cmd.ytdlp

            # Run in background thread so UI stays responsive
            $job = Start-Job -ScriptBlock {
                param($ytdlp, $url)
                try {
                    $result = & $ytdlp --no-warnings -J --no-playlist $url 2>&1
                    $json = $result | Where-Object { $_ -notmatch "^\[" -or $_ -match "^\{" } | Out-String
                    return $json
                } catch {
                    return "ERROR:$_"
                }
            } -ArgumentList $ytdlp, $url

            # Poll for job completion (500ms intervals)
            $timer = New-Object System.Windows.Forms.Timer
            $timer.Interval = 500
            $timer.Add_Tick({
                if ($job.State -eq "Completed") {
                    $timer.Stop()
                    $raw = Receive-Job $job
                    Remove-Job $job

                    if ($raw -like "ERROR:*") {
                        $errMsg = $raw -replace "^ERROR:",""
                        $safeErr = $errMsg -replace '"',"'" -replace "`n"," "
                        $Browser.Document.InvokeScript("onProbeError", @($safeErr))
                        return
                    }

                    try {
                        $data = $raw | ConvertFrom-Json

                        # Find best audio format
                        $audioFormats = $data.formats | Where-Object {
                            $_.acodec -ne "none" -and ($_.vcodec -eq "none" -or -not $_.vcodec)
                        } | Sort-Object @{Expression={$_.abr ?? $_.tbr ?? 0}; Descending=$true}

                        $bestAudio = $audioFormats | Select-Object -First 1
                        $bestFid   = if ($bestAudio) { $bestAudio.format_id } else { "bestaudio" }
                        $bestAbr   = if ($bestAudio) { [float]($bestAudio.abr ?? $bestAudio.tbr ?? 0) } else { 0 }
                        $bestExt   = if ($bestAudio) { $bestAudio.ext } else { "webm" }
                        $bestSize  = if ($bestAudio) { $bestAudio.filesize ?? $bestAudio.filesize_approx ?? 0 } else { 0 }

                        # Find video formats by resolution
                        $videoFormats = $data.formats | Where-Object {
                            $_.vcodec -ne "none" -and $_.vcodec -and $_.height
                        }
                        $videoByRes = @{}
                        foreach ($f in ($videoFormats | Sort-Object @{Expression={$_.height}; Descending=$true})) {
                            $h = [int]$f.height
                            if (-not $videoByRes.ContainsKey($h)) {
                                $videoByRes[$h] = $f.format_id
                            }
                        }
                        $videoRes = $videoByRes.GetEnumerator() | Sort-Object Key -Descending | ForEach-Object {
                            @{ height = $_.Key; fid = $_.Value }
                        }

                        # Build response object
                        $response = @{
                            title     = $data.title
                            duration  = $data.duration
                            thumbnail = $data.thumbnail
                            best_fid  = $bestFid
                            best_abr  = $bestAbr
                            best_ext  = $bestExt
                            best_size = $bestSize
                            video_res = @($videoRes)
                        } | ConvertTo-Json -Compress

                        $Browser.Document.InvokeScript("onProbeResult", @($response))

                    } catch {
                        $Browser.Document.InvokeScript("onProbeError", @("Failed to parse video info: $_"))
                    }
                }
            })
            $timer.Start()
        }

        # ── Download: run yt-dlp with given args, stream progress ─────────────
        "download" {
            $key      = $cmd.key
            $args     = $cmd.args
            $dir      = $cmd.outputDir
            $ytdlp    = $cmd.ytdlp
            $ffmpeg   = $cmd.ffmpeg

            # Build full args list
            $fullArgs = [System.Collections.Generic.List[string]]::new()
            foreach ($a in $args) { $fullArgs.Add($a) }

            # ffmpeg location
            $ffmpegDir = Split-Path -Parent $ffmpeg
            if ($ffmpegDir) {
                $fullArgs.Add("--ffmpeg-location")
                $fullArgs.Add($ffmpegDir)
            }

            # Output template
            if ($dir) {
                $fullArgs.Add("-o")
                $fullArgs.Add("$dir\%(title)s.%(ext)s")
            } else {
                $outDir = [System.Environment]::GetFolderPath("MyDocuments") + "\Downloads"
                if (-not (Test-Path $outDir)) { $outDir = [System.Environment]::GetFolderPath("MyDocuments") }
                $fullArgs.Add("-o")
                $fullArgs.Add("$outDir\%(title)s.%(ext)s")
            }

            $fullArgs.Add("--newline")

            # Run download in background job
            $job = Start-Job -ScriptBlock {
                param($ytdlp, $argList)
                $lines = @()
                & $ytdlp @argList 2>&1 | ForEach-Object {
                    $lines += $_
                    Write-Output $_
                }
            } -ArgumentList $ytdlp, $fullArgs

            # Poll and stream progress back to UI
            $timer = New-Object System.Windows.Forms.Timer
            $timer.Interval = 300
            $lastLines = 0

            $timer.Add_Tick({
                $output = Receive-Job $job -Keep
                if ($output -and $output.Count -gt $lastLines) {
                    $newLines = $output[$lastLines..($output.Count-1)]
                    $lastLines = $output.Count
                    foreach ($line in $newLines) {
                        $pct   = if ($line -match '(\d+\.?\d*)%') { $Matches[1] } else { "" }
                        $speed = if ($line -match '([\d.]+\s*[KMG]iB\/s)') { $Matches[1] } else { "" }
                        $eta   = if ($line -match 'ETA\s+(\d+:\d+)') { $Matches[1] } else { "" }
                        if ($pct) {
                            $Browser.Document.InvokeScript("onProgress", @($key, $pct, $speed, $eta))
                        }
                    }
                }

                if ($job.State -eq "Completed" -or $job.State -eq "Failed") {
                    $timer.Stop()
                    $success = $job.State -eq "Completed"
                    Remove-Job $job
                    $Browser.Document.InvokeScript("onDone", @($key, $success.ToString().ToLower(), ""))
                }
            })
            $timer.Start()
        }

        # ── Browse: open folder picker dialog ────────────────────────────────
        "browse" {
            $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
            $dialog.Description = "Choose download folder"
            $dialog.ShowNewFolderButton = $true
            if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $Browser.Document.InvokeScript("onFolderPicked", @($dialog.SelectedPath))
            }
        }
    }
}
