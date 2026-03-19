# Any Downloader — Danhawk Extension

Download audio and video from YouTube and 1000+ sites.
Tray icon → popup window. Fully self-contained, nothing to install.

---

## How to use (end user)

1. Drop the `any-downloader/` folder into your Danhawk extensions repo
2. Open Danhawk → Explore → install and enable **Any Downloader**
3. A tray icon appears in your taskbar
4. Click the tray icon → popup window opens
5. Paste a URL → Fetch → pick your format → download

To disable: toggle off in Danhawk. Tray icon disappears.

---

## How to build (developer)

### 1. Get yt-dlp.exe and ffmpeg.exe

Download and place both in the `bin/` folder:

- **yt-dlp.exe** → https://github.com/yt-dlp/yt-dlp/releases/latest
  - Download `yt-dlp.exe` directly

- **ffmpeg.exe** → https://github.com/BtbN/FFmpeg-Builds/releases
  - Download `ffmpeg-master-latest-win64-gpl.zip`
  - Extract and grab `bin/ffmpeg.exe`

### 2. Prerequisites

- [Node.js](https://nodejs.org/) v18+
- [Rust](https://rustup.rs/) (stable)
- [Tauri CLI v2](https://tauri.app/start/prerequisites/)
- Windows (WebView2 is pre-installed on Windows 10/11)

### 3. Build

```powershell
cd src
npm install
npm run tauri build
```

Output: `src/target/release/any-downloader.exe`

### 4. Copy exe to bin/

```powershell
copy src\target\release\any-downloader.exe bin\any-downloader.exe
```

### 5. Done

Drop the whole `any-downloader/` folder (with `bin/` populated) into the extensions repo.

---

## Folder structure

```
any-downloader/
├── manifest.json          ← Danhawk extension manifest
├── launch.ps1             ← entry point Danhawk runs
├── details.md
├── changelog.md
├── README.md
├── bin/
│   ├── any-downloader.exe ← built Tauri app (ships with extension)
│   ├── yt-dlp.exe         ← bundled downloader engine
│   └── ffmpeg.exe         ← bundled for audio conversion + video merge
└── src/                   ← source code (build once, not shipped to users)
    ├── src/               ← React frontend
    ├── src-tauri/         ← Rust/Tauri backend
    └── ...
```

---

## Tech stack

- **Frontend**: React 18 + TypeScript + Tailwind CSS (exact same as Danhawk)
- **Backend**: Tauri v2 + Rust
- **Window**: 520×620px, frameless custom titlebar, same `#0d0d0d` dark theme
- **Engine**: yt-dlp (bundled) + ffmpeg (bundled)
- **Memory**: ~15–20MB at runtime (reuses system WebView2)

---

## Audio quality logic

| Source bitrate | 320kbps card shown? | 128kbps label |
|---|---|---|
| ≥ 200kbps | Yes — shows "320 kbps" | "128 kbps" |
| 129–199kbps | No | "128 kbps+" |
| ≤ 128kbps | No | "128 kbps" |

WAV and Original format always shown regardless of source quality.

## Video quality logic

- All available resolutions shown dynamically (no hardcoded list)
- Each resolution card auto-pairs with appropriate audio quality:
  - 1080p / 4K → `bestaudio`
  - 720p → `bestaudio[abr>=128]`
  - 480p / 360p → `bestaudio[abr>=96]`
- Output always merged as MP4 via ffmpeg
