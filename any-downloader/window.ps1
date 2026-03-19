# window.ps1
# Any Downloader — tray icon + popup window.
# Pure PowerShell + Windows Forms. No Rust, no compilation, no installs.
# Tray icon lives in taskbar notification area.
# Left-click = show/hide window. Right-click = menu.

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$uiPath    = Join-Path $scriptDir "ui\index.html"
$pidFile   = "$env:TEMP\any-downloader.pid"

$PID | Out-File $pidFile -Force

. (Join-Path $scriptDir "bridge.ps1")

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ── COM bridge exposed as window.external in the HTML page ───────────────────
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

[ComVisible(true)]
[ClassInterface(ClassInterfaceType.AutoDual)]
public class JsBridge {
    public WebBrowser Browser;
    public Form       Window;
    public string     YtDlpPath;
    public string     FfmpegPath;

    public void invoke(string json) {
        if (json == "close") {
            if (Window != null) Window.Hide();
            return;
        }
        if (Browser != null)
            BridgeHandler.Handle(Browser, json, YtDlpPath, FfmpegPath);
    }
}
"@ -ReferencedAssemblies System.Windows.Forms

# ── Draw tray icon (32x32 red download arrow on dark bg) ─────────────────────
function New-TrayIcon {
    $bmp = New-Object System.Drawing.Bitmap(32, 32)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    $bgBrush  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(26, 5, 5))
    $redBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(239, 68, 68))

    # Dark circle
    $g.FillEllipse($bgBrush, 1, 1, 30, 30)

    # Arrow shaft
    $g.FillRectangle($redBrush, 13, 5, 6, 13)

    # Arrow head triangle
    $pts = [System.Drawing.Point[]]@(
        [System.Drawing.Point]::new(7, 16),
        [System.Drawing.Point]::new(25, 16),
        [System.Drawing.Point]::new(16, 25)
    )
    $g.FillPolygon($redBrush, $pts)

    # Bottom line
    $g.FillRectangle($redBrush, 7, 27, 18, 3)

    $g.Dispose()
    $bgBrush.Dispose()
    $redBrush.Dispose()

    return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

# ── Build popup window ────────────────────────────────────────────────────────
$form                 = New-Object System.Windows.Forms.Form
$form.Text            = "Any Downloader"
$form.ClientSize      = New-Object System.Drawing.Size(520, 620)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox     = $false
$form.StartPosition   = [System.Windows.Forms.FormStartPosition]::Manual
$form.BackColor       = [System.Drawing.Color]::FromArgb(13, 13, 13)
$form.ShowInTaskbar   = $false

# X button hides to tray instead of closing
$form.Add_FormClosing({
    param($s, $e)
    if ($e.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
        $e.Cancel = $true
        $form.Hide()
    }
})

# WebBrowser control
$browser = New-Object System.Windows.Forms.WebBrowser
$browser.Dock                           = [System.Windows.Forms.DockStyle]::Fill
$browser.ScrollBarsEnabled              = $false
$browser.IsWebBrowserContextMenuEnabled = $false
$browser.WebBrowserShortcutsEnabled     = $false
$browser.AllowWebBrowserDrop            = $false
$form.Controls.Add($browser)

# ── Resolve tool paths ────────────────────────────────────────────────────────
$ytdlpPath = (Get-Command yt-dlp -ErrorAction SilentlyContinue)?.Source
if (-not $ytdlpPath) {
    $ytdlpPath = "$env:LOCALAPPDATA\Programs\yt-dlp\yt-dlp.exe"
}
$ffmpegPath = (Get-Command ffmpeg -ErrorAction SilentlyContinue)?.Source
if (-not $ffmpegPath) {
    $local = Join-Path (Split-Path -Parent $ytdlpPath) "ffmpeg.exe"
    $ffmpegPath = if (Test-Path $local) { $local } else { "ffmpeg" }
}

# ── Wire JS bridge ────────────────────────────────────────────────────────────
$bridge            = New-Object JsBridge
$bridge.Browser    = $browser
$bridge.Window     = $form
$bridge.YtDlpPath  = $ytdlpPath
$bridge.FfmpegPath = $ffmpegPath
$browser.ObjectForScripting = $bridge

$browser.Add_DocumentCompleted({
    try { $browser.Document.InvokeScript("initBridge", @($ytdlpPath, $ffmpegPath)) }
    catch {}
})

$browser.Navigate("file:///$($uiPath.Replace('\','/'))")

# ── Tray icon ─────────────────────────────────────────────────────────────────
$tray         = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon    = New-TrayIcon
$tray.Text    = "Any Downloader"
$tray.Visible = $true

# Context menu (right-click)
$ctxMenu = New-Object System.Windows.Forms.ContextMenuStrip

$itemOpen = New-Object System.Windows.Forms.ToolStripMenuItem("Open Any Downloader")
$itemOpen.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$itemOpen.Add_Click({ showWindow })

$itemSep  = New-Object System.Windows.Forms.ToolStripSeparator

$itemQuit = New-Object System.Windows.Forms.ToolStripMenuItem("Quit")
$itemQuit.Add_Click({
    $tray.Visible = $false
    $tray.Dispose()
    [System.Windows.Forms.Application]::Exit()
})

$ctxMenu.Items.AddRange(@($itemOpen, $itemSep, $itemQuit))
$tray.ContextMenuStrip = $ctxMenu

# Left-click → toggle window
$tray.Add_MouseClick({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        if ($form.Visible) {
            $form.Hide()
        } else {
            showWindow
        }
    }
})

# ── Show window positioned above tray ────────────────────────────────────────
function showWindow {
    $screen    = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $form.Left = $screen.Right  - $form.Width  - 16
    $form.Top  = $screen.Bottom - $form.Height - 16
    $form.Show()
    $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    $form.BringToFront()
    $form.Activate()
}

# ── Run message loop ──────────────────────────────────────────────────────────
[System.Windows.Forms.Application]::Run()

$tray.Visible = $false
$tray.Dispose()
Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
