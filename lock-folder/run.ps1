param([string]$action)

$scriptDir = $PSScriptRoot
$key = "HKCU:\Software\Classes\Directory\shell\LockFolder"

switch ($action) {

    "install" {
        # Nothing to install for this tool
    }

    "enable" {
        # Register right-click context menu entry in Windows Explorer
        $launcherScript = Join-Path $scriptDir "app\launcher.ps1"
        $cmd = 'powershell.exe -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $launcherScript + '" "%1"'

        New-Item -Path $key -Force | Out-Null
        Set-ItemProperty -Path $key -Name "(Default)" -Value "Lock/Unlock Folder"
        New-Item -Path "$key\command" -Force | Out-Null
        Set-ItemProperty -Path "$key\command" -Name "(Default)" -Value $cmd
    }

    "disable" {
        # Remove context menu entry
        Remove-Item -Path $key -Recurse -Force -ErrorAction SilentlyContinue
    }

    "uninstall" {
        # Clean up registry on uninstall too
        Remove-Item -Path $key -Recurse -Force -ErrorAction SilentlyContinue
    }

}
