# Windows C: Cleanup Safety Catalog

## Low risk through Windows controls

| Category | Preferred mechanism | Note |
|---|---|---|
| Temporary files | Settings > System > Storage > Temporary files | Review every selected category. |
| Thumbnails | Temporary files | Windows regenerates them; previews may load slowly once. |
| DirectX shader cache | Temporary files | Apps regenerate it; first launch may briefly stutter. |
| Delivery Optimization files | Temporary files | Windows can download required content again. |
| Windows error reports | Temporary files | Keep when troubleshooting a current failure. |

## Conditional

| Category | Consequence or required check |
|---|---|
| Recycle Bin | Emptying removes the normal restore path; inspect it first. |
| Downloads in Temporary files | Personal data, not cache. Keep unchecked unless exact items are approved. |
| Windows.old | Removal can prevent rollback. Use Windows Temporary files, never manual deletion. |
| Windows Update cleanup | Use Windows controls; restart may be required. |
| WinSxS | Analyze with DISM; use only StartComponentCleanup and never manual deletion or ResetBase. |
| Driver packages | Removal reduces rollback options. Use supported Windows controls. |
| Hibernation file | Disabling hibernation may also disable Fast Startup. Require separate approval. |
| Restore points | Removal reduces recovery options. Confirm backups and recovery needs. |
| App/browser caches | Close the app and prefer its cleanup UI; caches may include offline data. |
| Installed apps | Uninstall through Settings after checking saved data, licenses, and reinstallability. |
| OneDrive local copies | Verify healthy sync, then use “Free up space”; do not delete synced files. |
| Memory dumps | Keep while diagnosing crashes; review before removal. |

## User review only

Treat Downloads, Desktop, Documents, media, archives, ISOs, installers, repositories, build artifacts, WSL, Docker, VMs, game libraries, mail, browser profiles, and cloud-sync roots as user data. Never infer deletion permission from age, size, type, duplication, or apparent inactivity.

## Protected

Do not manually remove content from Windows, WinSxS, Installer, System32, SysWOW64, DriverStore, Program Files, Program Files (x86), ProgramData, System Volume Information, Recovery, Boot, EFI/recovery partitions, registry hives, pagefile.sys, or swapfile.sys.

Do not use ownership or ACL changes, service disabling, registry cleaning, Windows-folder compression, or third-party cleanup tools as shortcuts.

## Stop and diagnose first

Stop cleanup when storage health or filesystem errors appear; free space repeatedly collapses due to logs, dumps, updates, malware, or a runaway app; Windows Update, antivirus, servicing, or backup is active; the device is organization-managed; or only protected/irreplaceable data remains.
