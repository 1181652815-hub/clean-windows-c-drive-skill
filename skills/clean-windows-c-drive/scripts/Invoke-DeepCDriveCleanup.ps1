[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Preview', 'Execute')]
    [string]$Mode,

    [string]$ConfirmPhrase = '',

    [switch]$IncludeComponentStore,

    [switch]$IncludeDeliveryOptimization,

    [switch]$IncludeDetails
)

$ErrorActionPreference = 'Stop'

if ($Mode -eq 'Execute' -and $ConfirmPhrase -cne 'DEEP CLEAN APPROVED CATEGORIES') {
    throw 'Execution refused. Pass -ConfirmPhrase "DEEP CLEAN APPROVED CATEGORIES" only after explicit user approval of the preview.'
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-IsChildPath {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Candidate)
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $candidateFull = [IO.Path]::GetFullPath($Candidate)
    return $candidateFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$healthScript = Join-Path $scriptDir 'Test-CDriveHealth.ps1'
$health = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $healthScript | ConvertFrom-Json
if ($health.Overall -eq 'Critical') {
    throw 'Deep cleanup stopped because the C: health gate returned Critical.'
}

$localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
if ([string]::IsNullOrWhiteSpace($localAppData)) { throw 'Windows LocalApplicationData path is unavailable.' }

$targets = [System.Collections.Generic.List[object]]::new()
function Add-Target {
    param([string]$Category, [string]$Root, [int]$MinimumAgeDays, [string]$Description)
    if (-not [string]::IsNullOrWhiteSpace($Root)) {
        $targets.Add([pscustomobject]@{
            Category = $Category
            Root = $Root
            MinimumAgeDays = $MinimumAgeDays
            Description = $Description
        })
    }
}

Add-Target 'UserTemp' (Join-Path $localAppData 'Temp') 7 'Current-user temporary files'
Add-Target 'DirectXShaderCache' (Join-Path $localAppData 'D3DSCache') 0 'Regenerable DirectX shader cache'
Add-Target 'CrashDumps' (Join-Path $localAppData 'CrashDumps') 30 'Old application crash dumps'
Add-Target 'WindowsErrorReports' (Join-Path $localAppData 'Microsoft\Windows\WER') 30 'Old per-user Windows error reports'
Add-Target 'InstallerTemp' (Join-Path $localAppData 'SquirrelTemp') 14 'Old Squirrel installer temporary files'

$browserRoots = @(
    @{ Category = 'ChromeCache'; Base = Join-Path $localAppData 'Google\Chrome\User Data' },
    @{ Category = 'EdgeCache'; Base = Join-Path $localAppData 'Microsoft\Edge\User Data' }
)
foreach ($browser in $browserRoots) {
    if (-not (Test-Path -LiteralPath $browser.Base -PathType Container)) { continue }
    $profiles = @(Get-ChildItem -LiteralPath $browser.Base -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'Default' -or $_.Name -match '^Profile \d+$' })
    foreach ($profile in $profiles) {
        Add-Target $browser.Category (Join-Path $profile.FullName 'Cache') 0 'HTTP resource cache only'
        Add-Target $browser.Category (Join-Path $profile.FullName 'Code Cache') 0 'Regenerable JavaScript code cache only'
        Add-Target $browser.Category (Join-Path $profile.FullName 'GPUCache') 0 'Regenerable GPU cache only'
    }
}

$before = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$results = [System.Collections.Generic.List[object]]::new()

foreach ($target in $targets) {
    $root = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($target.Root))
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        $results.Add([pscustomobject]@{ Category = $target.Category; Status = 'Unavailable'; Path = $root; Bytes = 0L; Reason = 'Directory does not exist' })
        continue
    }

    $rootItem = Get-Item -LiteralPath $root -Force
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        $results.Add([pscustomobject]@{ Category = $target.Category; Status = 'Skipped'; Path = $root; Bytes = 0L; Reason = 'Root is a reparse point' })
        continue
    }

    $cutoff = (Get-Date).AddDays(-1 * $target.MinimumAgeDays)
    $scanErrors = @()
    Get-ChildItem -LiteralPath $root -File -Force -Recurse -ErrorAction SilentlyContinue -ErrorVariable +scanErrors |
        ForEach-Object {
            $file = $_
            if ($file.LastWriteTime -gt $cutoff) { return }
            $status = if ($Mode -eq 'Preview') { 'WouldDelete' } else { 'Deleted' }
            $reason = ''
            [long]$bytes = $file.Length
            try {
                if (-not (Test-IsChildPath -Root $root -Candidate $file.FullName)) { throw 'Resolved path escaped the approved root' }
                if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Reparse point refused' }
                if ($Mode -eq 'Execute') { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop }
            } catch {
                $status = 'Skipped'
                $reason = $_.Exception.Message
                $bytes = 0L
            }
            $results.Add([pscustomobject]@{
                Category = $target.Category; Status = $status; Path = $file.FullName
                Bytes = $bytes; Reason = $reason
            })
        }

    foreach ($scanError in @($scanErrors)) {
        $results.Add([pscustomobject]@{ Category = $target.Category; Status = 'Skipped'; Path = $root; Bytes = 0L; Reason = $scanError.Exception.Message })
    }
}

$isAdmin = Test-IsAdministrator
$componentStore = [ordered]@{ Requested = [bool]$IncludeComponentStore; Status = 'NotRequested'; ExitCode = $null; Output = $null }
if ($IncludeComponentStore) {
    if (-not $isAdmin) {
        $componentStore.Status = 'SkippedNeedsAdministrator'
    } elseif ($Mode -eq 'Preview') {
        $componentOutput = (& Dism.exe /Online /Cleanup-Image /AnalyzeComponentStore /English 2>&1 | Out-String).Trim()
        $componentStore.Status = if ($LASTEXITCODE -eq 0) { 'Analyzed' } else { 'AnalysisFailed' }
        $componentStore.ExitCode = $LASTEXITCODE
        $componentStore.Output = $componentOutput
    } else {
        $componentOutput = (& Dism.exe /Online /Cleanup-Image /StartComponentCleanup /English 2>&1 | Out-String).Trim()
        $componentStore.Status = if ($LASTEXITCODE -eq 0) { 'Completed' } else { 'Failed' }
        $componentStore.ExitCode = $LASTEXITCODE
        $componentStore.Output = $componentOutput
    }
}

$deliveryOptimization = [ordered]@{ Requested = [bool]$IncludeDeliveryOptimization; Status = 'NotRequested'; Output = $null }
if ($IncludeDeliveryOptimization) {
    $doCommand = Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue
    if (-not $doCommand) {
        $deliveryOptimization.Status = 'UnsupportedOnThisWindowsBuild'
    } elseif ($Mode -eq 'Preview') {
        $deliveryOptimization.Status = 'AvailableForExecute'
    } elseif (-not $isAdmin) {
        $deliveryOptimization.Status = 'SkippedNeedsAdministrator'
    } else {
        try {
            $deliveryOptimization.Output = (Delete-DeliveryOptimizationCache -Force -ErrorAction Stop | Out-String).Trim()
            $deliveryOptimization.Status = 'Completed'
        } catch {
            $deliveryOptimization.Status = 'Failed'
            $deliveryOptimization.Output = $_.Exception.Message
        }
    }
}

$after = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$eligible = @($results | Where-Object Status -in @('WouldDelete', 'Deleted'))
$skipped = @($results | Where-Object Status -eq 'Skipped')

[pscustomobject]@{
    Mode = $Mode
    SafetyProfile = 'DeepSafeV1'
    HealthGate = @{ Overall = $health.Overall; Coverage = $health.Coverage }
    Administrator = $isAdmin
    Categories = @($targets.Category | Select-Object -Unique)
    EligibleFileCount = $eligible.Count
    EligibleGiB = [math]::Round((($eligible | Measure-Object Bytes -Sum).Sum) / 1GB, 3)
    SkippedCount = $skipped.Count
    FreeGiBBefore = [math]::Round($before.FreeSpace / 1GB, 3)
    FreeGiBAfter = [math]::Round($after.FreeSpace / 1GB, 3)
    ActualFreeSpaceChangeGiB = [math]::Round(($after.FreeSpace - $before.FreeSpace) / 1GB, 3)
    ComponentStore = $componentStore
    DeliveryOptimization = $deliveryOptimization
    ProtectedByDesign = @('Windows system files', 'Personal files', 'Browser cookies and profiles', 'Application settings', 'Rollback and restore data')
    Details = if ($IncludeDetails) { @($results) } else { $null }
} | ConvertTo-Json -Depth 7
