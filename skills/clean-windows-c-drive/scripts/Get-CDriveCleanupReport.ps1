[CmdletBinding()]
param([switch]$IncludePersonalFolders)

$ErrorActionPreference = 'Stop'

function Get-DirectorySize {
    param([Parameter(Mandatory)][string]$LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Container)) {
        return [pscustomobject]@{ Bytes = 0L; Files = 0L; Errors = 0L }
    }
    [long]$bytes = 0; [long]$files = 0; [long]$errors = 0
    try {
        Get-ChildItem -LiteralPath $LiteralPath -File -Force -Recurse -ErrorAction SilentlyContinue -ErrorVariable scanErrors |
            ForEach-Object { $bytes += $_.Length; $files++ }
        $errors += @($scanErrors).Count
    } catch { $errors++ }
    [pscustomobject]@{ Bytes = $bytes; Files = $files; Errors = $errors }
}

function New-Candidate {
    param([string]$Category, [string]$Path, [string]$Classification, [string]$PreferredAction)
    $resolved = [Environment]::ExpandEnvironmentVariables($Path)
    $measurement = Get-DirectorySize -LiteralPath $resolved
    [pscustomobject]@{
        Category = $Category; Path = $resolved
        SizeGiB = [math]::Round($measurement.Bytes / 1GB, 2)
        FileCount = $measurement.Files; ScanErrors = $measurement.Errors
        Classification = $Classification; PreferredAction = $PreferredAction
    }
}

$volume = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
if (-not $volume) { throw 'C: was not found.' }

$candidates = @(
    New-Candidate 'Current-user temporary files' '%TEMP%' 'Low risk through Windows controls' 'Windows Storage > Temporary files'
    New-Candidate 'Windows temporary files' '%SystemRoot%\Temp' 'Low risk through Windows controls' 'Windows Storage > Temporary files'
    New-Candidate 'Windows Update download cache' '%SystemRoot%\SoftwareDistribution\Download' 'Conditional' 'Use Windows controls; do not manually delete'
    New-Candidate 'Delivery Optimization cache' '%ProgramData%\Microsoft\Windows\DeliveryOptimization\Cache' 'Low risk through Windows controls' 'Windows Storage > Temporary files'
    New-Candidate 'Windows error reports' '%ProgramData%\Microsoft\Windows\WER' 'Conditional' 'Keep if troubleshooting; otherwise use Windows controls'
    New-Candidate 'Application crash dumps' '%LOCALAPPDATA%\CrashDumps' 'Conditional' 'Keep if troubleshooting; otherwise review'
)

if ($IncludePersonalFolders) {
    $candidates += @(
        New-Candidate 'Downloads' '%USERPROFILE%\Downloads' 'User review only' 'Select exact files'
        New-Candidate 'Desktop' '%USERPROFILE%\Desktop' 'User review only' 'Select exact files'
        New-Candidate 'Documents' '%USERPROFILE%\Documents' 'User review only' 'Select exact files'
        New-Candidate 'Pictures' '%USERPROFILE%\Pictures' 'User review only' 'Select exact files'
        New-Candidate 'Videos' '%USERPROFILE%\Videos' 'User review only' 'Select exact files'
    )
}

$fixedFiles = foreach ($name in 'hiberfil.sys', 'pagefile.sys', 'swapfile.sys', 'MEMORY.DMP') {
    $path = Join-Path 'C:\' $name
    $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    if ($item) {
        [pscustomobject]@{
            Category = $name; Path = $path; SizeGiB = [math]::Round($item.Length / 1GB, 2)
            Classification = if ($name -eq 'hiberfil.sys') { 'Conditional' } else { 'Protected or diagnostic' }
            PreferredAction = if ($name -eq 'hiberfil.sys') { 'Explain tradeoff and require separate approval' } else { 'Do not manually delete' }
        }
    }
}

[pscustomobject]@{
    GeneratedAt = (Get-Date).ToString('o'); ComputerName = $env:COMPUTERNAME
    Volume = [pscustomobject]@{
        Drive = 'C:'; TotalGiB = [math]::Round($volume.Size / 1GB, 2)
        FreeGiB = [math]::Round($volume.FreeSpace / 1GB, 2)
        FreePercent = [math]::Round(($volume.FreeSpace / $volume.Size) * 100, 1)
    }
    Candidates = @($candidates | Sort-Object SizeGiB -Descending)
    FixedSystemFiles = @($fixedFiles | Sort-Object SizeGiB -Descending)
    Notice = 'Read-only estimate. No files were changed. Apparent size is not safely reclaimable space.'
} | ConvertTo-Json -Depth 5
