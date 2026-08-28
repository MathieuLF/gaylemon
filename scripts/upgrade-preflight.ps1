[CmdletBinding()]
param(
    [ValidateSet('Inventory','Quick','Full')][string]$Mode = 'Inventory',
    [string]$ContractPath,
    [switch]$AllowDirty,
    [string]$CosignKey = "$env:USERPROFILE\.gaylemon\cosign.key",
    [string]$CosignPublicKey = "$env:USERPROFILE\.gaylemon\cosign.pub"
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$profilePath = Join-Path $root 'config\suite-profile-v2.json'
$profile = Get-Content -Raw -LiteralPath $profilePath | ConvertFrom-Json

if ($profile.schema -ne 'suite.profile.v2' -or $profile.contract -ne 'suite-foundation-v2' -or $profile.application -ne 'gaylemon') {
    throw 'Le profil Gaylémon ne respecte pas suite-foundation-v2.'
}

$requiredCapabilities = @(
    'fr-ca', 'accessibility', 'command-palette', 'safe-offline', 'changelog',
    'information-page', 'version-contract', 'privacy-link', 'season-lifecycle',
    'signed-agent', 'signed-oci', 'sbom-spdx', 'sbom-cyclonedx', 'trivy',
    'release-receipts', 'operations-contract'
)
$missingCapabilities = @($requiredCapabilities | Where-Object { $_ -notin @($profile.capabilities) })
if ($missingCapabilities.Count -gt 0) {
    throw "Capacités Suite manquantes: $($missingCapabilities -join ', ')."
}
foreach ($dependency in 'go','postgresql') {
    if (-not $profile.dependencies.PSObject.Properties.Name.Contains($dependency) -or -not $profile.dependencies.$dependency) {
        throw "Dépendance de profil manquante: $dependency."
    }
}

$version = (Get-Content -Raw -LiteralPath (Join-Path $root 'VERSION')).Trim()
if ($profile.contractRevision -ne '2.2.0' -or $profile.version.source -ne 'VERSION' -or
    $version -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$') {
    throw 'Le contrat et la version Gaylémon doivent respecter la révision 2.2.0 et SemVer.'
}
if ($profile.update.backup -ne 'restic-offsite-postgresql-spool-and-palworld-final') {
    throw 'Le profil Gaylémon doit utiliser le contrat Restic hors site prévu.'
}
if ($profile.release.receiptSchema -ne 'suite.release.v1' -or $profile.release.requiresImmutableSource -ne $true) {
    throw 'Le profil Gaylémon doit exiger un reçu suite.release.v1 et une source immuable.'
}

$requiredPaths = @(
    'CHANGELOG.md', 'VERSION', 'portal/release-notes.json', 'portal/informations.html',
    'portal/confidentialite.html', 'portal/offline.html', 'security/cosign.pub',
    'scripts/inventory-routes.ps1', 'scripts/verify-local.ps1', 'scripts/release.ps1',
    'scripts/test-postgres-seasons.ps1', 'docs/SAISONS.md'
)
$missingPaths = @($requiredPaths | Where-Object { -not (Test-Path -LiteralPath (Join-Path $root $_)) })
if ($missingPaths.Count -gt 0) {
    throw "Éléments du socle absents: $($missingPaths -join ', ')."
}

if ($ContractPath) {
    $resolvedContract = (Resolve-Path -LiteralPath $ContractPath).Path
    $contract = Get-Content -Raw -LiteralPath $resolvedContract | ConvertFrom-Json
    $entry = @($contract.applications | Where-Object { $_.id -eq 'gaylemon' })
    $centralProfile = $contract.profiles.PSObject.Properties[$profile.profile].Value
    $centralRequiredCapabilities = @($centralProfile.required_capabilities)
    $centralRequiredDependencies = @($centralProfile.required_dependencies)
    $centralMissingCapabilities = @($centralRequiredCapabilities | Where-Object { $_ -notin @($profile.capabilities) })
    $centralMissingDependencies = @($centralRequiredDependencies | Where-Object { -not $profile.dependencies.PSObject.Properties.Name.Contains($_) })
    if ($entry.Count -ne 1 -or $entry[0].profile -ne $profile.profile -or
        $entry[0].backup -ne $profile.update.backup -or
        $contract.contract_revision -ne $profile.contractRevision -or
        $centralMissingCapabilities.Count -gt 0 -or $centralMissingDependencies.Count -gt 0) {
        throw 'Le profil local diverge du contrat central.'
    }
}

$routes = & (Join-Path $PSScriptRoot 'inventory-routes.ps1') -Check | ConvertFrom-Json
$goVersion = (& go env GOVERSION).Trim()
$commit = (& git -C $root rev-parse HEAD).Trim()
$status = @(& git -C $root status --porcelain)
$inventory = [ordered]@{
    schema = 'suite.upgrade-inventory.v2'
    contract = $profile.contract
    contractRevision = $profile.contractRevision
    application = $profile.application
    profile = $profile.profile
    version = $version
    commit = $commit
    clean = ($status.Count -eq 0)
    go = $goVersion
    routes = $routes.count
    image = $profile.update.artifact
    backup = $profile.update.backup
    releaseReceipt = $profile.release.receiptSchema
    seasonLifecycle = $true
    palworldRestartForbidden = $true
}

if ($Mode -eq 'Inventory') {
    $inventory | ConvertTo-Json -Depth 5
    exit 0
}

$verifyArguments = @{
    Mode = $Mode
    CosignKey = $CosignKey
    CosignPublicKey = $CosignPublicKey
}
if ($AllowDirty) { $verifyArguments['AllowDirty'] = $true }
& (Join-Path $PSScriptRoot 'verify-local.ps1') @verifyArguments
if ($LASTEXITCODE -ne 0) { throw "La validation $Mode a échoué." }
