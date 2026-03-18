param([string]$FolderPath)

if (-not $FolderPath -or -not (Test-Path $FolderPath)) { exit 1 }

# Check lock state — locked shows as "Everyone:(OI)(CI)(N)" in icacls output
$acl = & cmd.exe /c "icacls `"$FolderPath`"" 2>&1 | Out-String
$isLocked = $acl -match "Everyone:\(OI\)\(CI\)\(N\)"

if ($isLocked) {
    # Unlock — remove Everyone entry and reset to inherited defaults
    & cmd.exe /c "icacls `"$FolderPath`" /remove Everyone /t /c"
    & cmd.exe /c "icacls `"$FolderPath`" /reset /t /c"
} else {
    # Lock — remove any stale Everyone entries first, then deny
    & cmd.exe /c "icacls `"$FolderPath`" /remove Everyone /t /c"
    & cmd.exe /c "icacls `"$FolderPath`" /deny Everyone:(OI)(CI)F"
}