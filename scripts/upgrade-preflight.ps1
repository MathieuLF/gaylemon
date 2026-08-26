[CmdletBinding()]
param(
    [ValidateSet('Inventory')][string]$Mode = 'Inventory',
    [string]$ContractPath
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$profilePath = Join-Path $root 'config\suite-profile-v2.json'
$profile = Get-Content -Raw -LiteralPath $profilePath | ConvertFrom-Json
if ($profile.schema -ne 'suite.profile.v2' -or $profile.contract -ne 'suite-foundation-v2' -or $profile.application -ne 'gaylemon') {
    throw 'Le profil Gaylémon ne respecte pas suite-foundation-v2.'
}
if ($ContractPath) {
    $resolvedContract = (Resolve-Path -LiteralPath $ContractPath).Path
    $contract = Get-Content -Raw -LiteralPath $resolvedContract | ConvertFrom-Json
    $entry = @($contract.applications | Where-Object { $_.id -eq 'gaylemon' })
    if ($entry.Count -ne 1 -or $entry[0].profile -ne $profile.profile) { throw 'Le profil local diverge du contrat central.' }
}
$routes = & (Join-Path $PSScriptRoot 'inventory-routes.ps1') -Check | ConvertFrom-Json
$goVersion = (& go env GOVERSION).Trim()
$commit = (& git -C $root rev-parse HEAD).Trim()
$status = @(& git -C $root status --porcelain)
[ordered]@{
    schema = 'suite.upgrade-inventory.v2'
    contract = $profile.contract
    application = $profile.application
    profile = $profile.profile
    commit = $commit
    clean = ($status.Count -eq 0)
    go = $goVersion
    routes = $routes.count
    image = $profile.update.artifact
    palworldRestartForbidden = $true
} | ConvertTo-Json -Depth 5
