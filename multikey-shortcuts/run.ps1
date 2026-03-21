param([string]$action)

$scriptDir = $PSScriptRoot

# Find AutoHotkey64.exe — checks prod path first, then dev path.
#
# Prod: Tauri bundles AHK into the installed app resources folder.
#       %LOCALAPPDATA%\Danhawk\resources\AutoHotkey64.exe
#
# Dev:  npm run tauri dev — exe is at app\src-tauri\target\debug\danhawk.exe
#       so resources sit two folders up: app\src-tauri\resources\AutoHotkey64.exe
#
function Get-AhkPath {
    # 1 — Production (installed app)
    $prod = "$env:LOCALAPPDATA\Danhawk\resources\AutoHotkey64.exe"
    if (Test-Path $prod) { return $prod }

    # 2 — Dev mode (npm run tauri dev)
    #     Find the running danhawk.exe, go up two levels from target\debug\ to reach src-tauri\
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
        # Nothing extra — AHK is bundled in the platform, not per-tool
    }

    "enable" {
        $ahk = Get-AhkPath
        if (-not $ahk) {
            Write-Error "AutoHotkey64.exe not found in prod or dev resources path"
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