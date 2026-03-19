# disable.ps1
# Runs when user disables Any Downloader in Danhawk.
# Kills the popup window process.

$pidFile = "$env:TEMP\any-downloader.pid"

if (Test-Path $pidFile) {
    $pid = Get-Content $pidFile -ErrorAction SilentlyContinue
    if ($pid) {
        Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
        Write-Host "[any-downloader] stopped PID $pid"
    }
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
}

# Also kill by window title as fallback
Get-Process | Where-Object { $_.MainWindowTitle -eq "Any Downloader" } | Stop-Process -Force -ErrorAction SilentlyContinue

Write-Host "[any-downloader] disabled"
