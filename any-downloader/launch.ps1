# launch.ps1
# Danhawk command engine runs this as the long-running entry process.
# It launches the pre-built any-downloader.exe from bin\.
# Auto-downloads ffmpeg via yt-dlp on first run if missing.
# Danhawk kills this process tree (via Job Object) when extension is disabled.

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$binDir    = Join-Path $scriptDir "bin"
$exe       = Join-Path $binDir "any-downloader.exe"
$ytdlp     = Join-Path $binDir "yt-dlp.exe"
$ffmpeg    = Join-Path $binDir "ffmpeg.exe"

# ── Check main exe ────────────────────────────────────────────────────────────
if (-not (Test-Path $exe)) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "any-downloader.exe not found.`n`nBuild it first:`n  cd src`n  npm install`n  npm run tauri build`n`nThen copy the .exe to bin\",
        "Any Downloader — not built",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    exit 1
}

# ── Auto-download ffmpeg if missing ───────────────────────────────────────────
if (-not (Test-Path $ffmpeg)) {
    if (-not (Test-Path $ytdlp)) {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            "yt-dlp.exe not found in bin\.`n`nDownload it from:`nhttps://github.com/yt-dlp/yt-dlp/releases",
            "Any Downloader — yt-dlp missing",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        exit 1
    }

    # Use yt-dlp's built-in ffmpeg downloader
    # --ffmpeg-location with a folder makes yt-dlp download ffmpeg there
    Write-Host "Downloading ffmpeg via yt-dlp (first run only)..."
    & $ytdlp --ffmpeg-location $binDir 2>&1 | Out-Null

    # If that didn't produce ffmpeg.exe, use yt-dlp's dedicated download flag
    if (-not (Test-Path $ffmpeg)) {
        & $ytdlp -v --no-check-certificate `
            "https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip" `
            -o "$binDir\ffmpeg-tmp.zip" 2>&1 | Out-Null

        # Fallback: direct curl download of the ffmpeg binary
        try {
            $ffmpegUrl = "https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
            $zipPath   = Join-Path $binDir "ffmpeg-tmp.zip"
            $expandDir = Join-Path $binDir "ffmpeg-tmp"

            Invoke-WebRequest -Uri $ffmpegUrl -OutFile $zipPath -UseBasicParsing
            Expand-Archive -Path $zipPath -DestinationPath $expandDir -Force

            # Find ffmpeg.exe anywhere in the extracted folder
            $found = Get-ChildItem -Path $expandDir -Filter "ffmpeg.exe" -Recurse | Select-Object -First 1
            if ($found) {
                Copy-Item $found.FullName -Destination $ffmpeg
            }

            # Cleanup
            Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
            Remove-Item $expandDir -Recurse -Force -ErrorAction SilentlyContinue
        } catch {
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.MessageBox]::Show(
                "Could not auto-download ffmpeg.`n`nDownload ffmpeg.exe manually and place it in:`n$binDir`n`nGet it from: https://github.com/yt-dlp/FFmpeg-Builds/releases",
                "Any Downloader — ffmpeg missing",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            # Launch anyway — audio-only downloads still work without ffmpeg
        }
    }
}

# ── Launch app ────────────────────────────────────────────────────────────────
& $exe
