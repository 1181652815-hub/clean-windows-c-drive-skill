# C: Drive Health Policy

## Meaning of results

- **Healthy**: all available core checks pass and free-space thresholds are comfortable. Optional unavailable checks reduce coverage but do not by themselves fail the drive.
- **Attention**: cleanup or investigation is advisable, but no definite critical storage failure was detected.
- **Critical**: the volume or physical disk reports unhealthy status, free space is critically low, or critical storage events were observed. Stop cleanup and protect data first.
- **Unknown**: one or more core checks could not be performed. Do not translate an unknown core check into healthy.

No result guarantees future health. SMART and Windows status can miss sudden failures. Maintain backups independently of this skill.

## Default thresholds

- Healthy free space: at least 20 GiB and at least 15%.
- Attention: below either healthy threshold.
- Critical: below 5 GiB or below 3%.

These are operational guardrails, not universal hardware specifications. Explain when large updates, VMs, games, or professional workloads need a larger buffer.

## Cleanup gate

- Continue normally on Healthy.
- On Attention caused only by low space, present low-risk cleanup candidates and require approval.
- On Attention caused by storage events, filesystem status, or disk status, investigate before deleting data.
- On Critical, stop cleanup. Recommend backing up irreplaceable data and using the appropriate Windows or hardware diagnostic path.
- On Unknown, disclose which checks failed. Continue only with read-only analysis unless the user explicitly accepts the uncertainty.

## Checks included

- C: capacity and free-space thresholds.
- Windows volume health and operational status.
- Backing disk health and operational status when Windows exposes them.
- SMART-style failure prediction when WMI exposes it.
- Recent critical/error events from common Windows storage providers.
- NTFS dirty-bit and TRIM status as diagnostic information when available.

Do not run repair-mode CHKDSK, firmware updates, secure erase, optimization, defragmentation, BitLocker changes, or driver changes automatically.
