param([string]$FolderPath)
if (-not $FolderPath -or -not (Test-Path $FolderPath)) { exit 1 }
icacls "$FolderPath" /remove:d Everyone /T /Q
