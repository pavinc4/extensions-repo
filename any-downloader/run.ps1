param([string]$action)

# Always use platform bundled Python — never system Python
$python = "$env:LOCALAPPDATA\Danhawk\resources\python\python.exe"
$scriptDir = $PSScriptRoot

switch ($action) {

    "install" {
        # Install Python dependencies into tool folder
        & $python -m pip install -r "$scriptDir\app\requirements.txt" --quiet --no-warn-script-location
    }

    "enable" {
        # Start the downloader app
        Start-Process $python -ArgumentList "`"$scriptDir\app\main.py`"" -WindowStyle Hidden
    }

    "disable" {
        # Kill the downloader process
        Get-Process "python" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like "*any-downloader*" } |
            Stop-Process -Force
    }

    "uninstall" {
        # Platform deletes the folder automatically after this runs
        # Add any extra cleanup here if needed (e.g. removing downloaded files)
    }

}
