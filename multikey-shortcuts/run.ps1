param([string]$action)

# AHK runtime bundled in platform
$ahk       = "$env:LOCALAPPDATA\Danhawk\resources\AutoHotkey64.exe"
$scriptDir = $PSScriptRoot

switch ($action) {

    "install" {
        # Nothing to install — AHK is bundled in platform
    }

    "enable" {
        # Launch AHK shortcuts script
        Start-Process $ahk -ArgumentList "`"$scriptDir\app\shortcuts.ahk`""
    }

    "disable" {
        # Kill the AHK process running our script
        Get-Process "AutoHotkey64" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like "*multikey-shortcuts*" } |
            Stop-Process -Force
    }

    "uninstall" {
        # Nothing extra needed
    }

}
