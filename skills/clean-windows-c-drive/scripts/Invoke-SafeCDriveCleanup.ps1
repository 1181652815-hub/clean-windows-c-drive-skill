[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Preview', 'Execute')]
    [string]$Mode,

    [string]$Category = 'UserTemp',

    [string]$ConfirmPhrase = '',

    [switch]$IncludeDetails
)

$ErrorActionPreference = 'Stop'

if ($Mode -eq 'Execute' -and $ConfirmPhrase -cne 'DELETE APPROVED ITEMS') {
    throw 'Execution refused. Pass -ConfirmPhrase "DELETE APPROVED ITEMS" only after explicit user approval.'
}

$localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($localAppData)) { throw 'Windows LocalApplicationData path is unavailable.' }

$categories = @($Category -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$allowedCategories = @('UserTemp', 'CrashDumps')
$invalidCategories = @($categories | Where-Object { $_ -notin $allowedCategories })
if ($categories.Count -eq 0 -or $invalidCategories.Count -gt 0) {
    throw "Invalid category. Allowed values: $($allowedCategories -join ', ')."
}

$definitions = @{
    UserTemp = [pscustomobject]@{
        Root = Join-Path $localAppData 'Temp'
        MinimumAgeDays = 7
        Description = 'Current-user temporary files'
    }
    CrashDumps = [pscustomobject]@{
        Root = Join-Path $localAppData 'CrashDumps'
        MinimumAgeDays = 30
        Description = 'Application crash dumps'
    }
}

function Test-IsChildPath {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Candidate)
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $candidateFull = [IO.Path]::GetFullPath($Candidate)
    return $candidateFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)
}

$before = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$results = [System.Collections.Generic.List[object]]::new()

foreach ($categoryName in $categories | Select-Object -Unique) {
    $definition = $definitions[$categoryName]
    if ([string]::IsNullOrWhiteSpace($definition.Root)) {
        $results.Add([pscustomobject]@{ Category = $categoryName; Status = 'Skipped'; Path = ''; Bytes = 0L; Reason = 'Environment path unavailable' })
        continue
    }

    $root = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($definition.Root))
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        $results.Add([pscustomobject]@{ Category = $categoryName; Status = 'Skipped'; Path = $root; Bytes = 0L; Reason = 'Directory does not exist' })
        continue
    }

    $rootItem = Get-Item -LiteralPath $root -Force
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        $results.Add([pscustomobject]@{ Category = $categoryName; Status = 'Skipped'; Path = $root; Bytes = 0L; Reason = 'Root is a reparse point' })
        continue
    }

    $cutoff = (Get-Date).AddDays(-1 * $definition.MinimumAgeDays)
    Get-ChildItem -LiteralPath $root -File -Force -Recurse -ErrorAction SilentlyContinue -ErrorVariable scanErrors |
        ForEach-Object {
            $file = $_
            $status = if ($Mode -eq 'Preview') { 'WouldDelete' } else { 'Deleted' }
            $reason = ''
            [long]$bytes = $file.Length
            try {
                if (-not (Test-IsChildPath -Root $root -Candidate $file.FullName)) { throw 'Resolved path escaped the approved root' }
                if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Reparse point refused' }
                if ($file.LastWriteTime -gt $cutoff) { return }
                if ($Mode -eq 'Execute') { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop }
            } catch {
                $status = 'Skipped'
                $reason = $_.Exception.Message
                $bytes = 0L
            }
            $results.Add([pscustomobject]@{
                Category = $categoryName; Status = $status; Path = $file.FullName
                Bytes = $bytes; Reason = $reason
            })
        }

    foreach ($scanError in @($scanErrors)) {
        $results.Add([pscustomobject]@{ Category = $categoryName; Status = 'Skipped'; Path = $root; Bytes = 0L; Reason = $scanError.Exception.Message })
    }
}

$after = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$eligible = @($results | Where-Object Status -in @('WouldDelete', 'Deleted'))
$skipped = @($results | Where-Object Status -eq 'Skipped')

[pscustomobject]@{
    Mode = $Mode
    Categories = @($categories | Select-Object -Unique)
    EligibleFileCount = $eligible.Count
    EligibleGiB = [math]::Round((($eligible | Measure-Object Bytes -Sum).Sum) / 1GB, 3)
    SkippedCount = $skipped.Count
    FreeGiBBefore = [math]::Round($before.FreeSpace / 1GB, 3)
    FreeGiBAfter = [math]::Round($after.FreeSpace / 1GB, 3)
    ActualFreeSpaceChangeGiB = [math]::Round(($after.FreeSpace - $before.FreeSpace) / 1GB, 3)
    Details = if ($IncludeDetails) { @($results) } else { $null }
} | ConvertTo-Json -Depth 5
