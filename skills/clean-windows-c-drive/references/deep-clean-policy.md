# Deep-safe cleanup policy

The deep profile is aggressive only inside a fixed allowlist of content that Windows or the owning application can regenerate. It is not a whole-drive deletion scan.

## Included by default

- Current-user temporary files older than 7 days.
- DirectX shader cache. Games or graphical apps may compile shaders again and briefly stutter on first launch.
- All files in Chrome and Edge `Cache`, `Code Cache`, and `GPUCache` for detected local profiles. Close browsers first; locked files are skipped. Login state, cookies, history, passwords, extensions, bookmarks, and profile databases are outside these exact roots.
- Application crash dumps and per-user Windows error reports older than 30 days. Keep these when diagnosing a current failure.
- Squirrel installer temporary files older than 14 days.

## Optional Windows-supported cleanup

- Component store: analyze with `DISM /AnalyzeComponentStore`; execute only with `DISM /StartComponentCleanup`, administrator rights, and explicit approval. Never use `/ResetBase`.
- Delivery Optimization: use `Delete-DeliveryOptimizationCache` only when Windows exposes the cmdlet and administrator rights are available.

## Excluded by design

- Windows, WinSxS, DriverStore, Program Files, ProgramData, recovery partitions, restore points, hibernation, update rollback data, and drivers.
- Downloads, Desktop, Documents, media, archives, projects, VMs, WSL, Docker, game libraries, cloud folders, and Recycle Bin.
- Browser cookies, history, passwords, sessions, extensions, bookmarks, databases, offline data, and profile configuration.
- Application settings, installed applications, package-manager caches, and arbitrary paths.

## Required sequence

Run the health gate, run Preview, show the measured candidates and side effects, obtain approval for the exact profile and optional Windows actions, then Execute with the exact confirmation phrase. Re-run the health gate and free-space measurement afterward. Skip locked or denied files; never take ownership or weaken permissions.
