[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][ValidateSet('Preview', 'Execute')][string]$Mode,
    [string]$ConfirmPhrase = ''
)

$ErrorActionPreference = 'Stop'
if ($Mode -eq 'Execute' -and $ConfirmPhrase -cne 'MOVE APPROVED FILES') {
    throw 'Execution refused. Use the confirmation phrase only after approving the exact manifest.'
}

$allowedExtensions = @('.7z', '.avi', '.gz', '.iso', '.mkv', '.mov', '.mp4', '.msi', '.rar', '.tar', '.tgz', '.wav', '.webm', '.zip')
$manifestFull = [IO.Path]::GetFullPath($ManifestPath)
$manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestFull | ConvertFrom-Json
if ($manifest.Version -ne 1) { throw 'Unsupported manifest version.' }

function Get-DownloadsPath {
    $fallback = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)) 'Downloads'
    try {
        $value = Get-ItemPropertyValue -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -Name '{374DE290-123F-4565-9164-39C4925E467B}' -ErrorAction Stop
        return [Environment]::ExpandEnvironmentVariables($value)
    } catch { return $fallback }
}

function Test-IsChildPath {
    param([string]$Root, [string]$Candidate)
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    return [IO.Path]::GetFullPath($Candidate).StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)
}

$expectedSourceRoot = [IO.Path]::GetFullPath((Get-DownloadsPath))
$sourceRoot = [IO.Path]::GetFullPath([string]$manifest.SourceRoot)
$destinationRoot = [IO.Path]::GetFullPath([string]$manifest.DestinationRoot)
if (-not $sourceRoot.Equals($expectedSourceRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Manifest source is not the current Downloads folder.' }
if ([IO.Path]::GetPathRoot($sourceRoot) -notmatch '^[Cc]:\\$') { throw 'Manifest source is not on C:.' }
$destinationDrive = [IO.Path]::GetPathRoot($destinationRoot)
if ($destinationDrive -notmatch '^[A-Za-z]:\\$' -or $destinationDrive -match '^[Cc]:\\$') { throw 'Manifest destination must be a non-C local drive.' }
$driveId = $destinationDrive.Substring(0, 2)
$destinationVolume = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$driveId'"
if (-not $destinationVolume -or $destinationVolume.DriveType -ne 3) { throw 'Destination is not an available fixed local volume.' }

$results = [System.Collections.Generic.List[object]]::new()
foreach ($entry in @($manifest.Files)) {
    $source = [IO.Path]::GetFullPath([string]$entry.SourcePath)
    $destination = [IO.Path]::GetFullPath([string]$entry.DestinationPath)
    $status = if ($Mode -eq 'Preview') { 'Ready' } else { 'Moved' }
    $reason = ''
    try {
        if (-not (Test-IsChildPath $sourceRoot $source)) { throw 'Source escaped the approved root.' }
        if (-not (Test-IsChildPath $destinationRoot $destination)) { throw 'Destination escaped the approved root.' }
        if ([IO.Path]::GetExtension($source).ToLowerInvariant() -notin $allowedExtensions) { throw 'File extension is not allowlisted.' }
        $sourceItem = Get-Item -LiteralPath $source -Force -ErrorAction Stop
        if ($sourceItem.PSIsContainer) { throw 'Directories are not eligible.' }
        if (($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or ($sourceItem.Attributes -band [IO.FileAttributes]::Offline) -ne 0) { throw 'Reparse points and offline files are refused.' }
        if ($sourceItem.Length -ne [long]$entry.Bytes) { throw 'Source size changed after planning.' }
        if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -cne [string]$entry.SHA256) { throw 'Source hash changed after planning.' }
        if (Test-Path -LiteralPath $destination) { throw 'Destination already exists; overwrite refused.' }

        $stream = $null
        try { $stream = [IO.File]::Open($source, 'Open', 'Read', 'None') } finally { if ($stream) { $stream.Dispose() } }

        if ($Mode -eq 'Execute') {
            $parent = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item -LiteralPath $source -Destination $destination -ErrorAction Stop
            $destinationItem = Get-Item -LiteralPath $destination -Force
            $destinationHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
            if ($destinationItem.Length -ne $sourceItem.Length -or $destinationHash -cne [string]$entry.SHA256) {
                Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
                throw 'Destination verification failed; unverified copy removed and source preserved.'
            }
            try {
                Remove-Item -LiteralPath $source -Force -ErrorAction Stop
            } catch {
                $status = 'CopiedSourceRetained'
                $reason = $_.Exception.Message
            }
        }
    } catch {
        $status = 'Skipped'
        $reason = $_.Exception.Message
    }
    $results.Add([pscustomobject]@{ SourcePath = $source; DestinationPath = $destination; Bytes = [long]$entry.Bytes; Status = $status; Reason = $reason })
}

$moved = @($results | Where-Object Status -eq 'Moved')
$copiedRetained = @($results | Where-Object Status -eq 'CopiedSourceRetained')
$skipped = @($results | Where-Object Status -eq 'Skipped')
[pscustomobject]@{
    Mode = $Mode
    ReadyOrMovedCount = @($results | Where-Object Status -in @('Ready', 'Moved')).Count
    ReclaimedGiB = if ($Mode -eq 'Execute') { [math]::Round((($moved | Measure-Object Bytes -Sum).Sum) / 1GB, 3) } else { 0 }
    CopiedSourceRetainedCount = $copiedRetained.Count
    SkippedCount = $skipped.Count
    Results = @($results)
} | ConvertTo-Json -Depth 5
