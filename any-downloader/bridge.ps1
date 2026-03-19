# bridge.ps1
# Defines the BridgeHandler static class called by JsBridge.invoke()
# and the PowerShell timer-based async workers for probe and download.

Add-Type -AssemblyName System.Windows.Forms

# ── BridgeHandler — called from JsBridge.invoke() ────────────────────────────
# This is C# so it runs on the UI thread safely.
# It dispatches to PowerShell functions via a shared delegate.

Add-Type -TypeDefinition @"
using System;
using System.Windows.Forms;

public static class BridgeHandler {
    public static Action<WebBrowser, string, string, string> Dispatch;

    public static void Handle(WebBrowser browser, string json, string ytdlp, string ffmpeg) {
        if (Dispatch != null)
            Dispatch(browser, json, ytdlp, ffmpeg);
    }
}
"@ -ReferencedAssemblies System.Windows.Forms

# ── Wire up the PowerShell dispatch function ──────────────────────────────────
[BridgeHandler]::Dispatch = {
    param(
        [System.Windows.Forms.WebBrowser]$Browser,
        [string]$JsonStr,
        [string]$YtDlpExe,
        [string]$FfmpegExe
    )

    try { $cmd = $JsonStr | ConvertFrom-Json }
    catch { return }

    switch ($cmd.cmd) {

        # ── Probe ─────────────────────────────────────────────────────────────
        "probe" {
            $url   = $cmd.url
            $ytdlp = if ($cmd.ytdlp) { $cmd.ytdlp } else { $YtDlpExe }

            $job = Start-Job -ScriptBlock {
                param($ytdlp, $url)
                try {
                    $out = & $ytdlp --no-warnings -J --no-playlist $url 2>&1
                    # Return only lines that look like JSON
                    $json = ($out | Where-Object { $_ -match '^\{' }) -join ""
                    if (-not $json) { $json = $out | Out-String }
                    return $json
                } catch {
                    return "ERR:$_"
                }
            } -ArgumentList $ytdlp, $url

            $timer = New-Object System.Windows.Forms.Timer
            $timer.Interval = 400
            $timer.Add_Tick({
                if ($job.State -notin @("Running","NotStarted")) {
                    $timer.Stop(); $timer.Dispose()
                    $raw = Receive-Job $job -ErrorAction SilentlyContinue
                    Remove-Job $job -Force

                    if (-not $raw -or ($raw -is [string] -and $raw.StartsWith("ERR:"))) {
                        $msg = if ($raw) { $raw -replace "^ERR:",""} else { "No output from yt-dlp" }
                        $safe = ($msg -replace '"',"'") -replace "`n"," "
                        try { $Browser.Document.InvokeScript("onProbeError", @($safe)) } catch {}
                        return
                    }

                    $rawStr = if ($raw -is [array]) { $raw -join "" } else { "$raw" }

                    try {
                        $data = $rawStr | ConvertFrom-Json

                        $audioFmts = $data.formats | Where-Object {
                            $_.acodec -and $_.acodec -ne "none" -and
                            (-not $_.vcodec -or $_.vcodec -eq "none")
                        } | Sort-Object { [float]($_.abr ?? $_.tbr ?? 0) } -Descending

                        $best     = $audioFmts | Select-Object -First 1
                        $bestFid  = if ($best) { $best.format_id } else { "bestaudio" }
                        $bestAbr  = if ($best) { [float]($best.abr  ?? $best.tbr  ?? 0) } else { 0.0 }
                        $bestExt  = if ($best) { "$($best.ext)" } else { "webm" }
                        $bestSize = if ($best) { [long]($best.filesize ?? $best.filesize_approx ?? 0) } else { 0 }

                        $videoMap = @{}
                        $data.formats | Where-Object {
                            $_.vcodec -and $_.vcodec -ne "none" -and $_.height
                        } | Sort-Object { [int]($_.height ?? 0) } -Descending | ForEach-Object {
                            $h = [int]$_.height
                            if (-not $videoMap.ContainsKey($h)) {
                                $videoMap[$h] = $_.format_id
                            }
                        }

                        $videoRes = $videoMap.GetEnumerator() |
                            Sort-Object Key -Descending |
                            ForEach-Object { [PSCustomObject]@{ height=$_.Key; fid=$_.Value } }

                        $resp = [PSCustomObject]@{
                            title     = "$($data.title)"
                            duration  = [float]($data.duration ?? 0)
                            thumbnail = "$($data.thumbnail)"
                            best_fid  = $bestFid
                            best_abr  = $bestAbr
                            best_ext  = $bestExt
                            best_size = $bestSize
                            video_res = @($videoRes)
                        } | ConvertTo-Json -Compress -Depth 4

                        try { $Browser.Document.InvokeScript("onProbeResult", @($resp)) } catch {}

                    } catch {
                        $safe = ("$_" -replace '"',"'") -replace "`n"," "
                        try { $Browser.Document.InvokeScript("onProbeError", @("Parse error: $safe")) } catch {}
                    }
                }
            })
            $timer.Start()
        }

        # ── Download ──────────────────────────────────────────────────────────
        "download" {
            $key      = "$($cmd.key)"
            $dlArgs   = $cmd.args
            $dir      = "$($cmd.outputDir)"
            $ytdlp    = if ($cmd.ytdlp)   { "$($cmd.ytdlp)"   } else { $YtDlpExe  }
            $ffmpeg   = if ($cmd.ffmpeg)   { "$($cmd.ffmpeg)"  } else { $FfmpegExe }

            $argList = [System.Collections.Generic.List[string]]::new()
            foreach ($a in $dlArgs) { $argList.Add("$a") }

            # ffmpeg location dir
            $ffDir = Split-Path -Parent $ffmpeg
            if ($ffDir -and (Test-Path $ffDir)) {
                $argList.Add("--ffmpeg-location"); $argList.Add($ffDir)
            }

            # Output path
            $outDir = if ($dir -and (Test-Path $dir)) {
                $dir
            } else {
                $dl = [System.Environment]::GetFolderPath("UserProfile") + "\Downloads"
                if (Test-Path $dl) { $dl } else { [System.Environment]::GetFolderPath("MyDocuments") }
            }
            $argList.Add("-o"); $argList.Add("$outDir\%(title)s.%(ext)s")
            $argList.Add("--newline")

            $job = Start-Job -ScriptBlock {
                param($ytdlp, $args)
                & $ytdlp @args 2>&1 | ForEach-Object { Write-Output $_ }
            } -ArgumentList $ytdlp, $argList

            $lastCount = 0
            $timer = New-Object System.Windows.Forms.Timer
            $timer.Interval = 300
            $timer.Add_Tick({
                $out = Receive-Job $job -Keep -ErrorAction SilentlyContinue
                if ($out -and $out.Count -gt $lastCount) {
                    $newLines = $out[$lastCount..($out.Count - 1)]
                    $lastCount = $out.Count
                    foreach ($line in $newLines) {
                        $pct   = if ($line -match '(\d+\.?\d*)%')         { $Matches[1] } else { "" }
                        $spd   = if ($line -match '([\d.]+\s*[KMGk]iB/s)') { $Matches[1] } else { "" }
                        $eta   = if ($line -match 'ETA\s+(\d+:\d+)')       { $Matches[1] } else { "" }
                        if ($pct) {
                            try { $Browser.Document.InvokeScript("onProgress", @($key, $pct, $spd, $eta)) } catch {}
                        }
                    }
                }
                if ($job.State -notin @("Running","NotStarted")) {
                    $timer.Stop(); $timer.Dispose()
                    $ok = ($job.State -eq "Completed")
                    Remove-Job $job -Force
                    try { $Browser.Document.InvokeScript("onDone", @($key, $ok.ToString().ToLower(), "")) } catch {}
                }
            })
            $timer.Start()
        }

        # ── Browse folder ─────────────────────────────────────────────────────
        "browse" {
            $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
            $dialog.Description = "Choose download folder"
            $dialog.ShowNewFolderButton = $true
            if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                try { $Browser.Document.InvokeScript("onFolderPicked", @($dialog.SelectedPath)) } catch {}
            }
        }
    }
}
