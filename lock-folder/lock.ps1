param([string]$FolderPath)
if (-not $FolderPath -or -not (Test-Path $FolderPath)) { exit 1 }
icacls "$FolderPath" /deny Everyone:(OI)(CI)F /T /Q
