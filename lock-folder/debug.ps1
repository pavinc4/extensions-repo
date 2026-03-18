$testFolder = "C:\Users\$env:USERNAME\Desktop\testing"
$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$toggle     = Join-Path $scriptDir "toggle.ps1"

Write-Host "--- icacls BEFORE ---" -ForegroundColor Cyan
cmd /c icacls "$testFolder"

Write-Host ""
Write-Host "--- Calling toggle.ps1 (lock) ---" -ForegroundColor Cyan
& "$toggle" "$testFolder"

Write-Host ""
Write-Host "--- icacls AFTER lock ---" -ForegroundColor Cyan
cmd /c icacls "$testFolder"

Write-Host ""
Write-Host "--- Calling toggle.ps1 again (unlock) ---" -ForegroundColor Cyan
& "$toggle" "$testFolder"

Write-Host ""
Write-Host "--- icacls AFTER unlock ---" -ForegroundColor Cyan
cmd /c icacls "$testFolder"