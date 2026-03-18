Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class HotKey {
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}
"@

# Modifiers: MOD_CONTROL = 0x0002, MOD_SHIFT = 0x0004
$MOD_CONTROL = 0x0002
$MOD_SHIFT   = 0x0004
$VK_J        = 0x4A
$HOTKEY_ID   = 1

[HotKey]::RegisterHotKey([IntPtr]::Zero, $HOTKEY_ID, ($MOD_CONTROL -bor $MOD_SHIFT), $VK_J)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class MsgLoop {
    [DllImport("user32.dll")] public static extern bool GetMessage(out MSG msg, IntPtr hWnd, uint min, uint max);
    [DllImport("user32.dll")] public static extern bool TranslateMessage(ref MSG msg);
    [DllImport("user32.dll")] public static extern IntPtr DispatchMessage(ref MSG msg);
    [StructLayout(LayoutKind.Sequential)]
    public struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam; public uint time; public int ptX; public int ptY; }
}
"@

$msg = New-Object MsgLoop+MSG
while ([MsgLoop]::GetMessage([ref]$msg, [IntPtr]::Zero, 0, 0)) {
    if ($msg.message -eq 0x0312 -and $msg.wParam -eq $HOTKEY_ID) {
        Start-Process "calc.exe"
    }
    [MsgLoop]::TranslateMessage([ref]$msg)
    [MsgLoop]::DispatchMessage([ref]$msg)
}

[HotKey]::UnregisterHotKey([IntPtr]::Zero, $HOTKEY_ID)