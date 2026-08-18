[CmdletBinding()]
param(
    [ValidateRange(1, 102400)][int]$MinimumSizeMB = 10,
    [ValidateRange(100, 50000)][int]$MaximumFiles = 10000,
    [ValidateRange(1, 500)][int]$MaximumHashGiB = 50
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UserFileSafety.ps1')

$minimumBytes = [long]$MinimumSizeMB * 1MB
$candidates = @(Get-SafeCDriveUserFiles -MaximumFiles $MaximumFiles | Where-Object Length -ge $minimumBytes)
$sameSize = @($candidates | Group-Object Length | Where-Object Count -gt 1)
$hashedBytes = 0L
$hashLimit = [long]$MaximumHashGiB * 1GB
$hashRows = [System.Collections.Generic.List[object]]::new()

foreach ($sizeGroup in $sameSize) {
    foreach ($file in $sizeGroup.Group) {
        if (($hashedBytes + $file.Length) -gt $hashLimit) { break }
        try {
            $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
            $hashedBytes += $file.Length
            $hashRows.Add([pscustomobject]@{ File = $file; Hash = $hash })
        } catch { }
    }
    if ($hashedBytes -ge $hashLimit) { break }
}

$duplicateGroups = @($hashRows | Group-Object Hash | Where-Object Count -gt 1)
$items = [System.Collections.Generic.List[object]]::new()
$groupNumber = 0
foreach ($group in $duplicateGroups) {
    $groupNumber++
    $groupId = ('D{0:0000}' -f $groupNumber)
    foreach ($row in $group.Group | Sort-Object { $_.File.FullName }) {
        $items.Add([pscustomobject]@{
            Selected = $false
            Group = $groupId
            Category = Get-CDriveUserFileCategory -Path $row.File.FullName
            SizeGiB = [math]::Round($row.File.Length / 1GB, 3)
            Size = [long]$row.File.Length
            Sha256 = $row.Hash
            LastWriteTime = $row.File.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
            Path = $row.File.FullName
        })
    }
}

$reclaimable = @($duplicateGroups | ForEach-Object {
    $rows = @($_.Group)
    if ($rows.Count -gt 1) { ($rows.Count - 1) * [long]$rows[0].File.Length }
} | Measure-Object -Sum).Sum

[pscustomobject]@{
    GeneratedAt = (Get-Date).ToString('o')
    Scope = 'Current user known folders on C: only'
    MinimumSizeMB = $MinimumSizeMB
    DuplicateGroupCount = $duplicateGroups.Count
    DuplicateFileCount = $items.Count
    PotentialReclaimGiB = [math]::Round($reclaimable / 1GB, 3)
    HashedGiB = [math]::Round($hashedBytes / 1GB, 3)
    HashLimitReached = ($hashedBytes -ge $hashLimit)
    Items = @($items)
} | ConvertTo-Json -Depth 5
