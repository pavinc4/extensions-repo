# on_disable hook — removes registry entry
Remove-Item -Path "HKCU:\Software\Classes\Directory\shell\DanhawkLockFolder" -Recurse -Force -ErrorAction SilentlyContinue