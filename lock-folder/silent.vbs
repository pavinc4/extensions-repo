' Runs a PowerShell script silently — zero window flash
' Called by Explorer context menu: wscript.exe silent.vbs "script.ps1" "folder path"
Set objShell = CreateObject("WScript.Shell")
objShell.Run "powershell.exe -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & WScript.Arguments(0) & """ """ & WScript.Arguments(1) & """", 0, False