param([string]$action)
$scriptDir = $PSScriptRoot
function Get-AhkPath {
    $prod = "$env:LOCALAPPDATA\Danhawk\resources\AutoHotkey64.exe"
    if (Test-Path $prod) { return $prod }
    $exePath = (Get-Process -Name "danhawk" -ErrorAction SilentlyContinue | Select-Object -First 1).Path
    if ($exePath) {
        $srcTauri = Split-Path (Split-Path (Split-Path $exePath -Parent) -Parent) -Parent
        $dev = Join-Path $srcTauri "resources\AutoHotkey64.exe"
        if (Test-Path $dev) { return $dev }
    }
    return $null
}
switch ($action) {
    "install" {
    }
    "enable" {
        $ahk = Get-AhkPath
        if (-not $ahk) {
            Write-Error "AutoHotkey64.exe not found"
            exit 1
        }
        Start-Process $ahk -ArgumentList "`"$scriptDir\app\shortcuts.ahk`""
    }
    "disable" {
        Get-WmiObject Win32_Process | Where-Object {
            $_.Name -eq "AutoHotkey64.exe" -and $_.CommandLine -like "*multikey-shortcuts*"
        } | ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
    "uninstall" {
        Get-WmiObject Win32_Process | Where-Object {
            $_.Name -eq "AutoHotkey64.exe" -and $_.CommandLine -like "*multikey-shortcuts*"
        } | ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
}
