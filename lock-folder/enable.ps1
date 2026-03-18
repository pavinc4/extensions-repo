# on_enable hook — registers context menu entry
# Registry command calls launcher.ps1 which handles elevation cleanly

$scriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$launcherScript = Join-Path $scriptDir "launcher.ps1"

# launcher.ps1 is the entry point — it knows its own path and elevates properly
$cmd = 'powershell.exe -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $launcherScript + '" "%1"'

$key = "HKCU:\Software\Classes\Directory\shell\DanhawkLockFolder"

New-Item -Path $key -Force | Out-Null
Set-ItemProperty -Path $key -Name "(Default)" -Value "Lock/Unlock Folder"
New-Item -Path "$key\command" -Force | Out-Null
Set-ItemProperty -Path "$key\command" -Name "(Default)" -Value $cmd