; shortcuts.ahk — DanHawk: Multikey Shortcuts (auto-generated)
; Edit via Manage Shortcuts in the Danhawk app.
#Requires AutoHotkey v2.0
#SingleInstance Force

pidDir := A_AppData "\..\Local\Danhawk\pids"
if !DirExist(pidDir)
    DirCreate(pidDir)
FileOpen(pidDir "\multikey-shortcuts.pid", "w").Write(ProcessExist())

global activeChord := ""

ArmChord(chord, hint) {
    global activeChord
    activeChord := chord
    ToolTip(hint, , , 1)
    SetTimer(Disarm, -2000)
}

Disarm() {
    global activeChord
    activeChord := ""
    ToolTip("", , , 1)
}
; -- Chord triggers

<^<!c::
{
    ArmChord("ctrlaltc", "Ctrl+Alt+C  ->  H: Google Chrome")
}

<^<!y::
{
    ArmChord("ctrlalty", "Ctrl+Alt+Y  ->  T: YT")
}

; -- Second key handlers

~h::
{
    global activeChord
    if (activeChord = "ctrlaltc") {
        Disarm()
        Run "C:\Program Files\Google\Chrome\Application\chrome.exe"
        return
    }
}

~t::
{
    global activeChord
    if (activeChord = "ctrlalty") {
        Disarm()
        Run "https://youtube.com"
        return
    }
}

~Escape::
{
    Disarm()
}

~Space::
{
    Disarm()
}

~Enter::
{
    Disarm()
}

Persistent
