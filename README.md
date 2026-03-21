# tools-repo

The official tool marketplace for the Danhawk platform.

## Structure

Each tool lives in its own folder:

```
tools-repo/
├── any-downloader/
├── lock-folder/
├── multikey-shortcuts/
├── open-calculator/
├── ui-test/
└── native-test/
```

Every tool folder has the same standard layout:

```
tool-name/
├── manifest.json     ← required — tool metadata
├── run.ps1           ← required — single entry point
├── info/             ← optional — .md files become tabs in the platform UI
│   ├── details.md
│   └── changelog.md
└── app/              ← all tool logic lives here, platform never touches this
    └── ...
```

## Tool contract

The platform only ever calls:

```powershell
powershell run.ps1 enable
powershell run.ps1 disable
powershell run.ps1 install
powershell run.ps1 uninstall
```

The `run.ps1` file handles everything internally — starting processes, writing registry entries, installing dependencies, cleanup. The platform stays completely dumb.

## Runtimes

The platform ships with these bundled runtimes available to all tools:

| Runtime | Path | Use for |
|---|---|---|
| Python 3.12 | `%LOCALAPPDATA%\Danhawk\resources\python\python.exe` | Python tools |
| AutoHotkey v2 | `%LOCALAPPDATA%\Danhawk\resources\AutoHotkey64.exe` | Hotkey/automation tools |

## Adding a new tool

1. Create a new folder with your tool id as the name
2. Add `manifest.json` and `run.ps1` (required)
3. Add `info/details.md` and `info/changelog.md`
4. Put all tool logic inside `app/`
5. Push to this repo — the platform will find it automatically

## .gitignore

See `.gitignore` for what to exclude. Never commit `venv/`, `__pycache__/`, or `node_modules/` inside tool folders.
