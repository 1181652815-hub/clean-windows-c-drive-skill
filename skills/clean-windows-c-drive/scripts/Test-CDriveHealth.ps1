[CmdletBinding()]
param(
    [ValidateRange(1, 90)][int]$EventLookbackDays = 7,
    [ValidateRange(1, 1000)][double]$HealthyFreeGiB = 20,
    [ValidateRange(1, 99)][double]$HealthyFreePercent = 15
)

$ErrorActionPreference = 'Stop'
$checks = [System.Collections.Generic.List[object]]::new()
$recommendations = [System.Collections.Generic.List[string]]::new()

function Add-Check {
    param([string]$Name, [string]$Status, [string]$Summary, [object]$Data = $null)
    $checks.Add([pscustomobject]@{ Name = $Name; Status = $Status; Summary = $Summary; Data = $Data })
}

$logical = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
if (-not $logical) { throw 'C: was not found.' }

$freeGiB = [math]::Round($logical.FreeSpace / 1GB, 2)
$totalGiB = [math]::Round($logical.Size / 1GB, 2)
$freePercent = [math]::Round(($logical.FreeSpace / $logical.Size) * 100, 1)
if ($freeGiB -lt 5 -or $freePercent -lt 3) {
    Add-Check 'FreeSpace' 'Critical' "Only $freeGiB GiB ($freePercent%) is free." @{ FreeGiB = $freeGiB; TotalGiB = $totalGiB; FreePercent = $freePercent }
    $recommendations.Add('Back up important data and reclaim space promptly using approved low-risk actions.')
} elseif ($freeGiB -lt $HealthyFreeGiB -or $freePercent -lt $HealthyFreePercent) {
    Add-Check 'FreeSpace' 'Warning' "$freeGiB GiB ($freePercent%) is free; below the configured healthy buffer." @{ FreeGiB = $freeGiB; TotalGiB = $totalGiB; FreePercent = $freePercent }
    $recommendations.Add('Audit cleanup candidates and preserve at least the configured free-space buffer.')
} else {
    Add-Check 'FreeSpace' 'Pass' "$freeGiB GiB ($freePercent%) is free." @{ FreeGiB = $freeGiB; TotalGiB = $totalGiB; FreePercent = $freePercent }
}

try {
    $volume = Get-Volume -DriveLetter C -ErrorAction Stop
    $volumeHealthy = ($volume.HealthStatus -eq 'Healthy')
    $volumeOperational = (@($volume.OperationalStatus) -contains 'OK')
    $status = if (-not $volumeHealthy) { 'Critical' } elseif (-not $volumeOperational) { 'Warning' } else { 'Pass' }
    Add-Check 'VolumeStatus' $status "Health=$($volume.HealthStatus); Operational=$(@($volume.OperationalStatus) -join ','); FileSystem=$($volume.FileSystem)." @{
        HealthStatus = [string]$volume.HealthStatus; OperationalStatus = @($volume.OperationalStatus); FileSystem = $volume.FileSystem
    }
    if ($status -ne 'Pass') { $recommendations.Add('Investigate the Windows volume status before cleanup or repair.') }
} catch {
    Add-Check 'VolumeStatus' 'Unknown' $_.Exception.Message
}

$diskNumber = $null
try {
    $partition = Get-Partition -DriveLetter C -ErrorAction Stop
    $disk = $partition | Get-Disk -ErrorAction Stop
    $diskNumber = $disk.Number
    $diskHealthy = ($disk.HealthStatus -eq 'Healthy')
    $diskOperational = @($disk.OperationalStatus) -contains 'Online'
    $status = if (-not $diskHealthy) { 'Critical' } elseif (-not $diskOperational) { 'Warning' } else { 'Pass' }
    Add-Check 'DiskStatus' $status "Disk $($disk.Number): Health=$($disk.HealthStatus); Operational=$(@($disk.OperationalStatus) -join ','); Bus=$($disk.BusType)." @{
        Number = $disk.Number; FriendlyName = $disk.FriendlyName
        HealthStatus = [string]$disk.HealthStatus; OperationalStatus = @($disk.OperationalStatus); BusType = [string]$disk.BusType
    }
    if ($status -ne 'Pass') { $recommendations.Add('Back up important data and run the device manufacturer diagnostic.') }
} catch {
    Add-Check 'DiskStatus' 'Unknown' $_.Exception.Message
}

try {
    $smartRows = @(Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction Stop)
    if ($smartRows.Count -eq 0) {
        Add-Check 'FailurePrediction' 'Unknown' 'Windows did not expose SMART-style failure prediction.'
    } elseif (@($smartRows | Where-Object PredictFailure).Count -gt 0) {
        Add-Check 'FailurePrediction' 'Critical' 'A storage device predicts failure.'
        $recommendations.Add('Back up important data immediately and replace or diagnose the affected drive.')
    } else {
        Add-Check 'FailurePrediction' 'Pass' 'No exposed storage device predicts failure.'
    }
} catch {
    Add-Check 'FailurePrediction' 'Unknown' $_.Exception.Message
}

try {
    $startTime = (Get-Date).AddDays(-$EventLookbackDays)
    $providers = @('disk', 'Ntfs', 'Microsoft-Windows-Ntfs', 'stornvme', 'storahci', 'volmgr', 'volsnap')
    $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $startTime; Level = 1,2,3 } -ErrorAction Stop |
        Where-Object { $_.ProviderName -in $providers } |
        Select-Object -First 50 TimeCreated, Id, LevelDisplayName, ProviderName, Message)
    $criticalEvents = @($events | Where-Object { $_.LevelDisplayName -eq 'Critical' })
    $errorEvents = @($events | Where-Object { $_.LevelDisplayName -eq 'Error' })
    $status = if ($criticalEvents.Count -gt 0) { 'Critical' } elseif ($errorEvents.Count -gt 0 -or $events.Count -gt 0) { 'Warning' } else { 'Pass' }
    Add-Check 'RecentStorageEvents' $status "$($events.Count) relevant storage warning/error event(s) in the last $EventLookbackDays day(s)." @($events)
    if ($events.Count -gt 0) { $recommendations.Add('Review recent storage events before treating the problem as ordinary disk clutter.') }
} catch {
    Add-Check 'RecentStorageEvents' 'Unknown' $_.Exception.Message
}

try {
    $dirtyOutput = (& fsutil.exe dirty query C: 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -eq 0) {
        Add-Check 'NtfsDirtyQuery' 'Info' $dirtyOutput
    } else {
        Add-Check 'NtfsDirtyQuery' 'Unknown' $dirtyOutput
    }
} catch {
    Add-Check 'NtfsDirtyQuery' 'Unknown' $_.Exception.Message
}

try {
    $trimOutput = (& fsutil.exe behavior query DisableDeleteNotify 2>&1 | Out-String).Trim()
    $ntfsTrimDisabled = $trimOutput -match 'NTFS\s+DisableDeleteNotify\s*=\s*1'
    $ntfsTrimEnabled = $trimOutput -match 'NTFS\s+DisableDeleteNotify\s*=\s*0'
    $status = if ($LASTEXITCODE -ne 0) { 'Unknown' } elseif ($ntfsTrimDisabled) { 'Warning' } else { 'Info' }
    $summary = if ($ntfsTrimEnabled) { 'TRIM delete notifications are enabled for NTFS.' } elseif ($ntfsTrimDisabled) { 'TRIM delete notifications appear disabled for NTFS.' } else { $trimOutput }
    Add-Check 'TrimStatus' $status $summary @{ Raw = $trimOutput }
    if ($ntfsTrimDisabled) { $recommendations.Add('TRIM appears disabled for NTFS; investigate the storage configuration before changing it.') }
} catch {
    Add-Check 'TrimStatus' 'Unknown' $_.Exception.Message
}

$criticalCount = @($checks | Where-Object Status -eq 'Critical').Count
$warningCount = @($checks | Where-Object Status -eq 'Warning').Count
$unknownCount = @($checks | Where-Object Status -eq 'Unknown').Count
$coreNames = @('FreeSpace', 'VolumeStatus', 'DiskStatus')
$coreUnknownCount = @($checks | Where-Object { $_.Name -in $coreNames -and $_.Status -eq 'Unknown' }).Count
$overall = if ($criticalCount -gt 0) { 'Critical' } elseif ($warningCount -gt 0) { 'Attention' } elseif ($coreUnknownCount -gt 0) { 'Unknown' } else { 'Healthy' }
$coverage = if ($unknownCount -gt 0) { 'Partial' } else { 'Full' }

[pscustomobject]@{
    GeneratedAt = (Get-Date).ToString('o')
    Overall = $overall
    Coverage = $coverage
    Guarantee = 'Snapshot only. This result cannot guarantee future hardware or filesystem health.'
    Volume = @{ Drive = 'C:'; TotalGiB = $totalGiB; FreeGiB = $freeGiB; FreePercent = $freePercent }
    Counts = @{ Critical = $criticalCount; Warning = $warningCount; Unknown = $unknownCount }
    Checks = @($checks)
    Recommendations = @($recommendations | Select-Object -Unique)
} | ConvertTo-Json -Depth 7
