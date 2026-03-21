# Lock Folder

Adds a **Lock/Unlock Folder** option to the Windows Explorer right-click context menu.

## How it works

- Toggle **ON** — context menu entry appears instantly in Explorer
- Toggle **OFF** — context menu entry removed instantly
- Right-click any folder → **Lock/Unlock Folder**
- If folder is unlocked → locks it (denies all access via icacls)
- If folder is already locked → unlocks it (restores inherited access)
- Runs completely silent — no popup windows, no background process

## Notes

Uses Windows `icacls` to set and remove deny ACL entries. The context menu registration is stored in `HKCU\Software\Classes\Directory\shell` — no admin rights needed.
