[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][ValidateSet('Preview','Execute')][string]$Mode,
    [string]$ConfirmPhrase = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UserFileSafety.ps1')

if ($Mode -eq 'Execute' -and $ConfirmPhrase -cne 'RECYCLE APPROVED USER FILES') {
    throw 'Execution refused. Use the exact confirmation phrase after reviewing the manifest.'
}
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw 'Manifest was not found.' }
$manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.Type -notin @('LargeFiles','Duplicates')) { throw 'Unsupported manifest type.' }

$items = @($manifest.Items)
if ($items.Count -eq 0) { throw 'Manifest contains no selected files.' }
$selectedPaths = @($items.Path)
if (@($selectedPaths | Select-Object -Unique).Count -ne $selectedPaths.Count) { throw 'Manifest contains duplicate paths.' }

if ($manifest.Type -eq 'Duplicates') {
    foreach ($group in @($manifest.Groups)) {
        $members = @($group.MemberPaths)
        if ($members.Count -lt 2) { throw "Duplicate group $($group.Group) is incomplete." }
        $remaining = @($members | Where-Object { $_ -notin $selectedPaths -and (Test-Path -LiteralPath $_ -PathType Leaf) })
        if ($remaining.Count -lt 1) { throw "At least one file must remain in duplicate group $($group.Group)." }
    }
}

if ($Mode -eq 'Execute') { Add-Type -AssemblyName Microsoft.VisualBasic }
$results = [System.Collections.Generic.List[object]]::new()
foreach ($entry in $items) {
    $status = if ($Mode -eq 'Preview') { 'WouldRecycle' } else { 'Recycled' }
    $reason = ''
    try {
        if (-not (Test-IsApprovedCDriveUserFile -Path $entry.Path)) { throw 'File is outside the approved C: user folders or has blocked attributes.' }
        $file = Get-Item -LiteralPath $entry.Path -Force -ErrorAction Stop
        if ([long]$file.Length -ne [long]$entry.Size) { throw 'File size changed after the scan.' }
        $actualHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
        if ($actualHash -cne [string]$entry.Sha256) { throw 'File hash changed after the scan.' }
        if ($Mode -eq 'Execute') {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                $file.FullName,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
            )
        }
    } catch {
        $status = 'Skipped'
        $reason = $_.Exception.Message
    }
    $results.Add([pscustomobject]@{ Path = $entry.Path; Status = $status; Size = [long]$entry.Size; Reason = $reason })
}

$accepted = @($results | Where-Object Status -in @('WouldRecycle','Recycled'))
[pscustomobject]@{
    Mode = $Mode
    ManifestType = $manifest.Type
    AcceptedCount = $accepted.Count
    AcceptedGiB = [math]::Round((($accepted | Measure-Object Size -Sum).Sum) / 1GB, 3)
    SkippedCount = @($results | Where-Object Status -eq 'Skipped').Count
    Recoverability = 'Sent to the Windows Recycle Bin; recovery is possible until it is emptied.'
    Results = @($results)
} | ConvertTo-Json -Depth 6
