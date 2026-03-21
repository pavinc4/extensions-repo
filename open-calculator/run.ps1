param([string]$action)

$scriptDir = $PSScriptRoot

switch ($action) {

    "install" {
        # Nothing to install
    }

    "enable" {
        # Launch the hotkey listener script as a hidden background process
        Start-Process powershell -ArgumentList `
            "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptDir\app\hotkey.ps1`"" `
            -WindowStyle Hidden
    }

    "disable" {
        # Kill the hotkey listener
        Get-Process "powershell" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like "*open-calculator*" } |
            Stop-Process -Force
    }

    "uninstall" {
        # Nothing extra needed
    }

}
