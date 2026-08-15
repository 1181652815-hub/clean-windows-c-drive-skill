# Safe Relocation Policy

## Automatically eligible

The bundled planner may consider only regular files inside the current user's Downloads folder that:

- are on C:;
- meet the configured size and age thresholds;
- have an allowlisted archive, disk-image, installer, or media extension;
- are not reparse points, offline placeholders, shortcuts, encrypted profile data, or in use;
- are copied to a non-C fixed local volume with enough reserve space.

The default thresholds are 250 MiB and 30 days. Age and size identify candidates, not permission. The user must approve the exact manifest.

## Copy-verify-delete requirement

For each approved file:

1. Revalidate the source and destination against the manifest.
2. Refuse destination overwrite.
3. Verify the source size and SHA-256 hash have not changed.
4. Copy to the destination.
5. Verify destination size and SHA-256.
6. Delete the source only after verification.
7. If any step fails, preserve the source and report the outcome.

## Never use generic relocation

Do not generically move Windows, Program Files, ProgramData, AppData, package caches, browser/mail profiles, OneDrive or other sync roots, Desktop, Documents, repositories, WSL, Docker, virtual machines, game libraries, shortcuts, system files, or application configuration.

Use the application's supported feature instead:

- Installed app: Settings > Apps > Installed apps > Move, only when offered.
- Game: the launcher's library move feature.
- OneDrive: verify sync, then use Files On-Demand “Free up space.”
- Documents/Pictures/Videos: Windows folder Properties > Location, with separate approval and a backup.

Do not create junctions or symbolic links to disguise manual moves. They can break updates, uninstallers, backup tools, permissions, and recovery.
