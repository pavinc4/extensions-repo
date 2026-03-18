param([string]$FolderPath)

if (-not $FolderPath -or -not (Test-Path $FolderPath)) { exit 1 }

$scriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$toggleScript = Join-Path $scriptDir "toggle.ps1"

& powershell.exe -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "$toggleScript" "$FolderPath"