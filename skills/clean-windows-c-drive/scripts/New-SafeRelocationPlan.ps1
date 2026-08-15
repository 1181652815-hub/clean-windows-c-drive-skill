[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DestinationRoot,
    [ValidateRange(1, 1048576)][int]$MinimumSizeMiB = 250,
    [ValidateRange(1, 3650)][int]$MinimumAgeDays = 30,
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
$allowedExtensions = @('.7z', '.avi', '.gz', '.iso', '.mkv', '.mov', '.mp4', '.msi', '.rar', '.tar', '.tgz', '.wav', '.webm', '.zip')

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

$sourceRoot = [IO.Path]::GetFullPath((Get-DownloadsPath))
if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) { throw "Downloads folder not found: $sourceRoot" }
if ([IO.Path]::GetPathRoot($sourceRoot) -notmatch '^[Cc]:\\$') { throw 'Downloads is not on C:; generic C: relocation is unnecessary.' }

$destinationFull = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($DestinationRoot))
$destinationDrive = [IO.Path]::GetPathRoot($destinationFull)
if ($destinationDrive -notmatch '^[A-Za-z]:\\$' -or $destinationDrive -match '^[Cc]:\\$') { throw 'Destination must be a non-C local drive path.' }
$driveId = $destinationDrive.Substring(0, 2)
$destinationVolume = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$driveId'"
if (-not $destinationVolume -or $destinationVolume.DriveType -ne 3) { throw 'Destination must be an available fixed local volume.' }

$archiveRoot = Join-Path $destinationFull 'Downloads'
$cutoff = (Get-Date).AddDays(-$MinimumAgeDays)
[long]$minimumBytes = $MinimumSizeMiB * 1MB
$files = [System.Collections.Generic.List[object]]::new()

Get-ChildItem -LiteralPath $sourceRoot -File -Force -Recurse -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Length -ge $minimumBytes -and $_.LastWriteTime -le $cutoff -and
        $_.Extension.ToLowerInvariant() -in $allowedExtensions -and
        ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
        ($_.Attributes -band [IO.FileAttributes]::Offline) -eq 0
    } | ForEach-Object {
        if (-not (Test-IsChildPath -Root $sourceRoot -Candidate $_.FullName)) { return }
        $relative = $_.FullName.Substring($sourceRoot.TrimEnd('\').Length).TrimStart('\')
        $destinationPath = Join-Path $archiveRoot $relative
        $files.Add([pscustomobject]@{
            SourcePath = $_.FullName
            RelativePath = $relative
            DestinationPath = $destinationPath
            Bytes = $_.Length
            LastWriteTimeUtc = $_.LastWriteTimeUtc.ToString('o')
            SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        })
    }

[long]$totalBytes = ($files | Measure-Object Bytes -Sum).Sum
[long]$reserveBytes = [math]::Max(10GB, [double]$destinationVolume.Size * 0.05)
if ($totalBytes -gt 0 -and ($destinationVolume.FreeSpace - $totalBytes) -lt $reserveBytes) {
    throw 'Destination lacks sufficient free space after the required reserve.'
}

$manifest = [pscustomobject]@{
    Version = 1
    CreatedAt = (Get-Date).ToString('o')
    SourceRoot = $sourceRoot
    DestinationRoot = $archiveRoot
    Rules = @{ MinimumSizeMiB = $MinimumSizeMiB; MinimumAgeDays = $MinimumAgeDays; AllowedExtensions = $allowedExtensions }
    TotalFiles = $files.Count
    TotalGiB = [math]::Round($totalBytes / 1GB, 3)
    DestinationFreeGiB = [math]::Round($destinationVolume.FreeSpace / 1GB, 3)
    Files = @($files)
}
$json = $manifest | ConvertTo-Json -Depth 6

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $outputFull = [IO.Path]::GetFullPath($OutputPath)
    $parent = Split-Path -Parent $outputFull
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'Manifest parent directory does not exist.' }
    [IO.File]::WriteAllText($outputFull, $json, [Text.UTF8Encoding]::new($false))
}
$json
