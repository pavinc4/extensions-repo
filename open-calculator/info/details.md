# Open Calculator

A global hotkey that opens the Windows Calculator from anywhere.

## Shortcut

- **Ctrl + Win + C** — opens Calculator instantly from any window or app

## How it works

- Toggle **ON** — a background PowerShell process starts and listens for the hotkey
- Toggle **OFF** — the background process stops, hotkey no longer works
- The process uses Windows `RegisterHotKey` API directly — no AHK or third-party tools needed
