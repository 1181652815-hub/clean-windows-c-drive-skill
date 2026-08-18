# C: user-file cleanup policy

## Scan scope

Large-file and duplicate-file modules scan only existing current-user folders located on C:: Downloads, Desktop, Documents, Pictures, Videos, and Music. They do not scan the whole drive and never include AppData, Windows, Program Files, ProgramData, browser profiles, cloud roots, repositories, WSL, Docker, virtual machines, game libraries, or reparse/offline/system files.

## Large files

Size identifies review candidates, not permission. Classify results as images, videos, audio, documents, archives/installers, or other. Default every row to unselected. Never infer that a large file is disposable.

## Duplicate files

Treat files as duplicates only after matching byte size and SHA-256. Default every row to unselected. Before execution, require at least one existing unselected member in every selected duplicate group. Similar names, dates, perceptual similarity, or extensions are not sufficient.

## File handling

Revalidate the exact path, approved root, attributes, size, and SHA-256 after selection. Send approved files to the Windows Recycle Bin instead of permanent deletion. Do not empty the Recycle Bin. If validation fails, skip the file. The user must approve the exact selected list after preview.
