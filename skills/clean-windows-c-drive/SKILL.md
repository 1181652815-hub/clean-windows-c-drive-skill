---
name: clean-windows-c-drive
description: "Automatically assess Windows C: drive health, safely reclaim space, and relocate approved ordinary user files to another fixed drive without breaking Windows or installed applications. Use when a user asks whether C: is healthy, wants automatic C: checks, asks what is filling C:, how to clean C:, whether files are safe to remove, or wants large files moved off C:. Always run the read-only health gate and audit, use manifest-based copy-verify-delete relocation, stop on storage-health warnings, and require explicit approval before changing anything."
---

# Clean Windows C Drive

## Objective

Assess C: health, diagnose usage, separate safe cleanup from review-only data, and preserve normal Windows operation. Prefer Windows-supported cleanup mechanisms and reversible actions. Never claim that a single check guarantees future hardware or filesystem health.

## Safety rules

- Start read-only. Do not change anything during the audit.
- Run the health gate on every invocation before measuring cleanup candidates.
- Stop cleanup on a `Critical` result. On `Attention`, explain the failed checks and clean only if the warning is solely low free space and the proposed action is low risk.
- Read [references/safety-catalog.md](references/safety-catalog.md) before recommending or performing cleanup.
- Never manually delete from Windows, Program Files, ProgramData, System Volume Information, Recovery, Boot, WinSxS, DriverStore, EFI/recovery partitions, registry hives, page files, or restore-point storage.
- Never bulk-clean a user profile, Downloads, Desktop, Documents, cloud folders, browser profiles, mail, projects, VMs, or game libraries.
- Never use registry cleaners, broad wildcards, recursive deletion from a drive root, `DISM /ResetBase`, ownership changes, ACL changes, or unresolved environment variables.
- Do not disable hibernation, System Restore, Windows Update, antivirus, indexing, reserved storage, or OneDrive Files On-Demand merely to gain space.
- Prefer Windows-supported cleanup and reversible actions. State when recovery is impossible.
- Verify exact resolved targets stay inside each user-approved location before a destructive operation.
- Never move installed-program directories, AppData, ProgramData, game libraries, cloud placeholders, shortcuts, profile configuration, WSL/Docker/VM data, or any folder tree with the generic relocation script.

## Workflow

### 1. Establish scope

Confirm Windows and C: are the intended targets. Determine whether the request is audit-only, recommendations, or cleanup after approval. A general "clean C:" request authorizes an audit and plan, not unspecified deletion.

### 2. Run the automatic health gate

Run the bundled read-only health check on every invocation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\Test-CDriveHealth.ps1"
```

Read [references/health-policy.md](references/health-policy.md) when interpreting the result. Report `Healthy`, `Attention`, `Critical`, or `Unknown` with the individual checks. Treat inaccessible checks as unknown, not healthy. Do not repair filesystems, change BitLocker, run offline CHKDSK, update firmware, or modify storage settings without separate approval.

This health gate is automatic when the skill is invoked. Do not create a scheduled task, reminder, or background monitor unless the user explicitly requests recurring monitoring.

### 3. Audit before recommending

Run the bundled read-only report:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\Get-CDriveCleanupReport.ps1"
```

Use `-IncludePersonalFolders` only when the user requests measurement of major personal folders. It still changes nothing.

For deeper read-only checks, use:

```powershell
Get-Volume -DriveLetter C
Dism.exe /Online /Cleanup-Image /AnalyzeComponentStore
powercfg.exe /a
```

Treat all sizes as estimates. Apparent directory size is not safely reclaimable size.

### 4. Classify findings

Classify every candidate as:

1. **Low risk through Windows controls**: temporary files, thumbnails, Delivery Optimization cache, DirectX shader cache, and error reports exposed in Windows Storage settings.
2. **Conditional**: Recycle Bin, Windows.old, update cleanup, driver packages, languages, hibernation, restore points, app caches, dumps, and uninstalling apps. Explain consequences first.
3. **User review only**: downloads, media, archives, installers, ISOs, VMs, projects, cloud files, browser/mail profiles, and game data.
4. **Protected**: system and application locations listed in the safety rules.

### 5. Present the plan

Before changing anything, list each exact category or path, measured size, supported action, side effects, recoverability, administrator need, and restart need. Order lowest risk first. Do not promise all measured bytes are reclaimable.

### 6. Obtain explicit approval

Ask for approval of exact cleanup groups. Approval for one group applies only to that group. Obtain separate approval for Recycle Bin, personal files, uninstalling apps, hibernation, restore points, or rollback data.

### 7. Use supported cleanup

- For approved low-risk file cleanup, preview with the bundled allowlist cleaner. It only considers files older than the category threshold and changes nothing in Preview mode:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\Invoke-SafeCDriveCleanup.ps1" -Mode Preview -Category UserTemp,CrashDumps
```

- Show the preview and obtain explicit approval. Execute only the exact approved categories with the required confirmation phrase:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\Invoke-SafeCDriveCleanup.ps1" -Mode Execute -Category UserTemp -ConfirmPhrase "DELETE APPROVED ITEMS"
```

- Never pass unapproved categories. The cleaner intentionally does not accept arbitrary paths, Windows directories, browser profiles, Downloads, or Recycle Bin.
- Prefer Settings > System > Storage > Temporary files or Storage Sense for Windows-managed categories.
- Prefer an application's own cache or uninstall control.
- For OneDrive, verify sync health and use "Free up space"; do not delete synced files.
- Use `Dism.exe /Online /Cleanup-Image /StartComponentCleanup` only when analysis recommends it, the user approves, and elevation is available. Never add `/ResetBase`.
- For user files, operate only on an explicit item list and prefer Recycle Bin or a verified destination on another drive.
- Skip locked or denied files. Do not take ownership or weaken permissions.

### 8. Relocate ordinary files safely

Read [references/relocation-policy.md](references/relocation-policy.md) before proposing relocation.

Use the manifest planner only for large, old, ordinary files in the current user's Downloads folder. It is read-only except for writing the manifest:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\New-SafeRelocationPlan.ps1" -DestinationRoot "D:\CDriveArchive" -OutputPath "<manifest-path>"
```

Show the exact manifest and obtain approval. Preview it before execution:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\Invoke-SafeFileRelocation.ps1" -ManifestPath "<manifest-path>" -Mode Preview
```

Execute only after approval of that unchanged manifest:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\Invoke-SafeFileRelocation.ps1" -ManifestPath "<manifest-path>" -Mode Execute -ConfirmPhrase "MOVE APPROVED FILES"
```

The executor must copy, verify SHA-256 and size, then delete the original. Never overwrite a destination. If verification or source deletion fails, preserve the source and report the duplicate or partial result.

Move installed apps only through Settings > Apps when the app exposes Move. Move game libraries only through the launcher's supported library feature. Move known folders only through Windows Location properties after separate approval. Never simulate these operations with filesystem moves or junctions.

### 9. Verify

Re-run `Test-CDriveHealth.ps1`, re-measure C: free space, report the before/after difference and all skips/failures, confirm Windows Update and Windows Security were not disabled, and report whether restart is pending. Recommend keeping a practical 15-20 GB free buffer without presenting it as a universal requirement.

## Response format

For a health or audit request, return overall health, failed/unknown checks, current free space, largest relevant candidates, safe-now recommendations, conditional choices, protected areas, and the exact approval needed next.

For cleanup or relocation, return approved actions performed, free space before and after, copied/verified/deleted counts, duplicates or retained originals, skips/failures, restart requirements, and remaining optional actions. Never claim space was reclaimed after only an estimate, preview, or copy that left the source intact.
