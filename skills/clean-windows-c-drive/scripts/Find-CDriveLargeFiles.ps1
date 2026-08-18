[CmdletBinding()]
param(
    [ValidateRange(10, 102400)][int]$MinimumSizeMB = 500,
    [ValidateRange(1, 2000)][int]$MaximumResults = 300
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UserFileSafety.ps1')

$minimumBytes = [long]$MinimumSizeMB * 1MB
$files = @(Get-SafeCDriveUserFiles | Where-Object Length -ge $minimumBytes |
    Sort-Object Length -Descending | Select-Object -First $MaximumResults)

$items = @($files | ForEach-Object {
    [pscustomobject]@{
        Selected = $false
        Category = Get-CDriveUserFileCategory -Path $_.FullName
        SizeGiB = [math]::Round($_.Length / 1GB, 3)
        Size = [long]$_.Length
        LastWriteTime = $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
        Path = $_.FullName
    }
})
$totalBytes = 0L
if ($items.Count -gt 0) { $totalBytes = [long](($items | Measure-Object Size -Sum).Sum) }

[pscustomobject]@{
    GeneratedAt = (Get-Date).ToString('o')
    Scope = 'Current user known folders on C: only'
    MinimumSizeMB = $MinimumSizeMB
    Count = $items.Count
    TotalGiB = [math]::Round($totalBytes / 1GB, 3)
    Items = $items
} | ConvertTo-Json -Depth 5
