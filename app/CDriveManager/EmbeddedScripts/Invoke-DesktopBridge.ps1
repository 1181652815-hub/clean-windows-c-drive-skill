[CmdletBinding()]
param([Parameter(Mandatory)][string]$PayloadPath)

$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8

try {
    if (-not (Test-Path -LiteralPath $PayloadPath -PathType Leaf)) { throw 'Request payload was not found.' }
    $request = Get-Content -LiteralPath $PayloadPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $scriptRoot = $PSScriptRoot

    switch ([string]$request.Action) {
        'Health' {
            & (Join-Path $scriptRoot 'Test-CDriveHealth.ps1')
        }
        'JunkPreview' {
            $parameters = @{ Mode = 'Preview'; Categories = @($request.Categories) }
            if ($request.IncludeComponentStore) { $parameters.IncludeComponentStore = $true }
            if ($request.IncludeDeliveryOptimization) { $parameters.IncludeDeliveryOptimization = $true }
            & (Join-Path $scriptRoot 'Invoke-DeepCDriveCleanup.ps1') @parameters
        }
        'JunkExecute' {
            $parameters = @{
                Mode = 'Execute'
                Categories = @($request.Categories)
                ConfirmPhrase = 'DEEP CLEAN APPROVED CATEGORIES'
            }
            if ($request.IncludeComponentStore) { $parameters.IncludeComponentStore = $true }
            if ($request.IncludeDeliveryOptimization) { $parameters.IncludeDeliveryOptimization = $true }
            & (Join-Path $scriptRoot 'Invoke-DeepCDriveCleanup.ps1') @parameters
        }
        'LargeScan' {
            & (Join-Path $scriptRoot 'Find-CDriveLargeFiles.ps1') -MinimumSizeMB ([int]$request.MinimumSizeMB)
        }
        'DuplicateScan' {
            & (Join-Path $scriptRoot 'Find-CDriveDuplicateFiles.ps1') -MinimumSizeMB ([int]$request.MinimumSizeMB)
        }
        'UserCleanupPreview' {
            & (Join-Path $scriptRoot 'Invoke-SafeUserFileCleanup.ps1') -ManifestPath ([string]$request.ManifestPath) -Mode Preview
        }
        'UserCleanupExecute' {
            & (Join-Path $scriptRoot 'Invoke-SafeUserFileCleanup.ps1') -ManifestPath ([string]$request.ManifestPath) -Mode Execute -ConfirmPhrase 'RECYCLE APPROVED USER FILES'
        }
        default { throw 'Unsupported bridge action.' }
    }
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
