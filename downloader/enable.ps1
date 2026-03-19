# enable.ps1
# Runs when Any Downloader is enabled in Danhawk.
# 1. Installs yt-dlp if not present (silently)
# 2. Launches the pre-built any-downloader.exe
# PowerShell 5 compatible — no ?. operators.

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$appExe    = Join-Path $scriptDir "bin\any-downloader.exe"

# ── Install yt-dlp if missing ─────────────────────────────────────────────────
$ytdlpCmd = Get-Command "yt-dlp" -ErrorAction SilentlyContinue

if (-not $ytdlpCmd) {
    Write-Host "[any-downloader] yt-dlp not found, installing..."

    # Try winget first
    $wingetCmd = Get-Command "winget" -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        Start-Process "winget" -ArgumentList "install --id yt-dlp.yt-dlp --silent --accept-package-agreements --accept-source-agreements" -Wait -WindowStyle Hidden
        $ytdlpCmd = Get-Command "yt-dlp" -ErrorAction SilentlyContinue
    }

    # Fallback: direct download from official GitHub
    if (-not $ytdlpCmd) {
        Write-Host "[any-downloader] downloading yt-dlp from GitHub..."
        $localBin = "$env:LOCALAPPDATA\Programs\yt-dlp"
        New-Item -ItemType Directory -Force -Path $localBin | Out-Null
        $dest = "$localBin\yt-dlp.exe"
        try {
            Invoke-WebRequest -Uri "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" -OutFile $dest -UseBasicParsing
            # Add to user PATH permanently
            $userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
            if ($userPath -notlike "*$localBin*") {
                [System.Environment]::SetEnvironmentVariable("PATH", "$localBin;$userPath", "User")
            }
            $env:PATH = "$localBin;$env:PATH"
            Write-Host "[any-downloader] yt-dlp installed to $dest"
        } catch {
            Write-Host "[any-downloader] ERROR: $_"
            exit 1
        }
    }
} else {
    Write-Host "[any-downloader] yt-dlp already installed"
}

# ── Launch the app ────────────────────────────────────────────────────────────
if (-not (Test-Path $appExe)) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "any-downloader.exe not found in bin\`n`nBuild it first:`n  cd app`n  npm install`n  npm run tauri build`n`nThen copy target\release\any-downloader.exe to bin\",
        "Any Downloader",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
    exit 1
}

Start-Process -FilePath $appExe
