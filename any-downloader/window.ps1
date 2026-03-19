# window.ps1
# Launches the Any Downloader popup window.
# Uses Windows Forms + WebBrowser (built into all Windows versions — no install).
# window.external.invoke(json) bridges JS -> PowerShell for yt-dlp calls.

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$uiPath    = Join-Path $scriptDir "ui\index.html"
$pidFile   = "$env:TEMP\any-downloader.pid"

$PID | Out-File $pidFile -Force

. (Join-Path $scriptDir "bridge.ps1")

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ── COM bridge object exposed as window.external ──────────────────────────────
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

[ComVisible(true)]
[ClassInterface(ClassInterfaceType.AutoDual)]
public class JsBridge {
    public WebBrowser Browser;
    public string YtDlpPath;
    public string FfmpegPath;
    public string ScriptDir;

    public void invoke(string json) {
        if (Browser != null)
            BridgeHandler.Handle(Browser, json, YtDlpPath, FfmpegPath, ScriptDir);
    }
}
"@ -ReferencedAssemblies System.Windows.Forms

# ── Build form ────────────────────────────────────────────────────────────────
$form                 = New-Object System.Windows.Forms.Form
$form.Text            = "Any Downloader"
$form.ClientSize      = New-Object System.Drawing.Size(520, 620)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox     = $false
$form.StartPosition   = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor       = [System.Drawing.Color]::FromArgb(13, 13, 13)

$browser = New-Object System.Windows.Forms.WebBrowser
$browser.Dock                           = [System.Windows.Forms.DockStyle]::Fill
$browser.ScrollBarsEnabled              = $false
$browser.IsWebBrowserContextMenuEnabled = $false
$browser.WebBrowserShortcutsEnabled     = $false
$browser.AllowWebBrowserDrop            = $false

$form.Controls.Add($browser)

# ── Resolve tool paths ────────────────────────────────────────────────────────
$ytdlpPath = (Get-Command yt-dlp  -ErrorAction SilentlyContinue)?.Source
if (-not $ytdlpPath) { $ytdlpPath = "$env:LOCALAPPDATA\Programs\yt-dlp\yt-dlp.exe" }

$ffmpegPath = (Get-Command ffmpeg -ErrorAction SilentlyContinue)?.Source
if (-not $ffmpegPath) {
    $local = Join-Path (Split-Path -Parent $ytdlpPath) "ffmpeg.exe"
    $ffmpegPath = if (Test-Path $local) { $local } else { "ffmpeg" }
}

# ── Wire bridge ───────────────────────────────────────────────────────────────
$bridge            = New-Object JsBridge
$bridge.Browser    = $browser
$bridge.YtDlpPath  = $ytdlpPath
$bridge.FfmpegPath = $ffmpegPath
$bridge.ScriptDir  = $scriptDir

$browser.ObjectForScripting = $bridge

$browser.Add_DocumentCompleted({
    try { $browser.Document.InvokeScript("initBridge", @($ytdlpPath, $ffmpegPath)) }
    catch {}
})

$browser.Navigate("file:///$($uiPath.Replace('\','/'))")

[System.Windows.Forms.Application]::Run($form)
Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
