# Lock Folder

Adds a **Lock/Unlock Folder** option to the Windows Explorer right-click context menu.

## How it works

- Toggle **ON** — context menu entry appears instantly
- Toggle **OFF** — context menu entry removed instantly
- Right-click any folder → **Lock/Unlock Folder**
- If folder is unlocked → locks it (denies all access)
- If folder is already locked → unlocks it (restores access)
- Runs completely silent, no popup windows

## Engine

Powered by the **Command Engine** with lifecycle hooks. Uses PowerShell to write and remove Windows registry entries — no process stays running.