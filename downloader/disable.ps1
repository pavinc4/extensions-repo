# disable.ps1
# Runs when Any Downloader is disabled in Danhawk.
# Kills the any-downloader.exe process cleanly.

Get-Process -Name "any-downloader" -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Host "[any-downloader] stopped"
