# Any Downloader — Danhawk Extension

## Build (one time)

```powershell
cd app
npm install
npm run tauri dev     # test it
npm run tauri build   # production build
copy src-tauri\target\release\any-downloader.exe ..\bin\
```

If Rust build fails due to Windows Defender, run once as Administrator:
```powershell
Add-MpPreference -ExclusionPath "$env:USERPROFILE\.cargo"
Add-MpPreference -ExclusionPath "$env:USERPROFILE\.rustup"
Add-MpPreference -ExclusionPath "D:\My Apps\danhawk-project"
Add-MpPreference -ExclusionProcess "cargo.exe"
Add-MpPreference -ExclusionProcess "rustc.exe"
```
Then delete `app\src-tauri\target` and retry.

## Use

1. Drop `any-downloader/` into your Danhawk extensions repo
2. Danhawk → Install → Enable
3. yt-dlp installs silently if not present
4. Tray icon appears → click to open window
5. Disable in Danhawk → tray icon disappears
