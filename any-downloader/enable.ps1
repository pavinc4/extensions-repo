# enable.ps1
# Runs when user enables Any Downloader in Danhawk.
# 1. Silently installs yt-dlp + ffmpeg to user system if not present
# 2. Launches the tray icon + popup window (WebView2-based, no compile needed)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ── Helper: silent install via winget ────────────────────────────────────────

function Install-IfMissing {
    param([string]$Command, [string]$WingetId, [string]$DisplayName)

    $found = Get-Command $Command -ErrorAction SilentlyContinue
    if ($found) {
        Write-Host "[any-downloader] $DisplayName already installed at $($found.Source)"
        return $true
    }

    Write-Host "[any-downloader] $DisplayName not found — installing via winget..."

    # Check winget is available
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Host "[any-downloader] winget not available — trying direct download..."
        return $false
    }

    $result = winget install --id $WingetId --silent --accept-package-agreements --accept-source-agreements 2>&1
    $installed = Get-Command $Command -ErrorAction SilentlyContinue
    if ($installed) {
        Write-Host "[any-downloader] $DisplayName installed successfully"
        return $true
    }
    return $false
}

# ── Install yt-dlp ────────────────────────────────────────────────────────────

$ytdlpOk = Install-IfMissing -Command "yt-dlp" -WingetId "yt-dlp.yt-dlp" -DisplayName "yt-dlp"

if (-not $ytdlpOk) {
    # Fallback: download yt-dlp.exe directly from GitHub to user's local bin
    $localBin = "$env:LOCALAPPDATA\Programs\yt-dlp"
    New-Item -ItemType Directory -Force -Path $localBin | Out-Null
    $ytdlpExe = "$localBin\yt-dlp.exe"

    if (-not (Test-Path $ytdlpExe)) {
        Write-Host "[any-downloader] Downloading yt-dlp from GitHub..."
        $url = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
        try {
            Invoke-WebRequest -Uri $url -OutFile $ytdlpExe -UseBasicParsing
            Write-Host "[any-downloader] yt-dlp downloaded to $ytdlpExe"
        } catch {
            Write-Host "[any-downloader] ERROR: Could not download yt-dlp: $_"
            exit 1
        }
    }

    # Add to PATH for this session
    $env:PATH = "$localBin;$env:PATH"

    # Add to user PATH permanently
    $currentPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    if ($currentPath -notlike "*$localBin*") {
        [System.Environment]::SetEnvironmentVariable("PATH", "$localBin;$currentPath", "User")
    }
}

# ── Install ffmpeg via yt-dlp (cleanest approach) ────────────────────────────
# yt-dlp can fetch its own ffmpeg build — stores it alongside yt-dlp
# We point --ffmpeg-location to the same folder yt-dlp lives in

$ytdlpPath = (Get-Command yt-dlp -ErrorAction SilentlyContinue)?.Source
if (-not $ytdlpPath) {
    $ytdlpPath = "$env:LOCALAPPDATA\Programs\yt-dlp\yt-dlp.exe"
}
$ytdlpDir = Split-Path -Parent $ytdlpPath
$ffmpegExe = Join-Path $ytdlpDir "ffmpeg.exe"

if (-not (Test-Path $ffmpegExe)) {
    # Try winget first
    $ffOk = Install-IfMissing -Command "ffmpeg" -WingetId "Gyan.FFmpeg" -DisplayName "ffmpeg"

    if (-not $ffOk) {
        # Fallback: use yt-dlp to download ffmpeg into its own directory
        Write-Host "[any-downloader] Downloading ffmpeg via yt-dlp..."
        try {
            # yt-dlp --update downloads a ffmpeg build when told to check
            & $ytdlpPath --ffmpeg-location $ytdlpDir --version 2>&1 | Out-Null

            # Direct download of ffmpeg essentials (small build ~3MB)
            $ffUrl = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/ffmpeg-linux"
            # On Windows, grab the Windows build
            $ffWinUrl = "https://github.com/yt-dlp/FFmpeg-Builds/releases/latest/download/ffmpeg-n7.1-latest-win64-gpl-essentials_build.zip"

            $ffZip = "$env:TEMP\ffmpeg-essentials.zip"
            Invoke-WebRequest -Uri "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip" -OutFile $ffZip -UseBasicParsing
            Expand-Archive -Path $ffZip -DestinationPath "$env:TEMP\ffmpeg-extract" -Force
            $ffExeFound = Get-ChildItem "$env:TEMP\ffmpeg-extract" -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1
            if ($ffExeFound) {
                Copy-Item $ffExeFound.FullName -Destination $ffmpegExe -Force
                Write-Host "[any-downloader] ffmpeg installed to $ffmpegExe"
            }
            Remove-Item $ffZip -Force -ErrorAction SilentlyContinue
            Remove-Item "$env:TEMP\ffmpeg-extract" -Recurse -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Host "[any-downloader] WARNING: ffmpeg install failed: $_"
            Write-Host "[any-downloader] Audio conversion and video merge may not work."
        }
    }
}

# ── Launch the popup window (long-running process) ────────────────────────────

$windowScript = Join-Path $scriptDir "window.ps1"
& powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File $windowScript
