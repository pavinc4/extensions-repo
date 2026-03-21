param([string]$action)

$scriptDir = $PSScriptRoot

switch ($action) {

    "install" {
        # Nothing to install
    }

    "enable" {
        # Start the test exe
        Start-Process "$scriptDir\app\test.exe"
    }

    "disable" {
        # Kill the test exe
        Get-Process "test" -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -like "*native-test*" } |
            Stop-Process -Force
    }

    "uninstall" {
        # Nothing extra needed
    }

}
