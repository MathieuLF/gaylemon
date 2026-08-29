[CmdletBinding()]
param(
    [switch]$SansDocker,
    [switch]$SansTestsPython,
    [switch]$SansBash,
    [switch]$SansGo
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$failures = [Collections.Generic.List[string]]::new()

function Assert-Contract([bool]$Condition, [string]$Message) {
    if ($Condition) { Write-Host "[OK] $Message" -ForegroundColor Green; return }
    Write-Host "[ÉCHEC] $Message" -ForegroundColor Red
    $script:failures.Add($Message)
}

Write-Host 'Validation locale publique de Gaylémon' -ForegroundColor Cyan
Write-Host 'Aucun hôte, service distant ou déploiement ne sera contacté.' -ForegroundColor DarkGray

$required = @(
    '.env.example', 'CHANGELOG.md', 'README.md', 'VERSION', 'go.mod', 'go.sum',
    'config/suite-profile-v2.json', 'db/migrations/embed.go', 'docs/ARCHITECTURE.md',
    'docs/PUBLIC-REPOSITORY.md', 'docs/SAISONS.md', 'portal/index.html',
    'portal/assets/app.js', 'portal/assets/styles.css', 'portal/sw.js',
    'scripts/upgrade-preflight.ps1', 'scripts/verify-local.ps1', 'scripts/release.ps1',
    'security/cosign.pub'
)
foreach ($relative in $required) {
    Assert-Contract (Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf) "Fichier requis: $relative"
}

$profile = Get-Content -Raw -LiteralPath (Join-Path $root 'config/suite-profile-v2.json') | ConvertFrom-Json
$version = (Get-Content -Raw -LiteralPath (Join-Path $root 'VERSION')).Trim()
Assert-Contract ($profile.contractRevision -eq '2.3.0') 'Contrat Suite 2.3.0'
Assert-Contract (@($profile.capabilities) -contains 'cache-safe-assets') 'Capacité cache-safe-assets déclarée'
Assert-Contract ($profile.release.releasePredicate -eq 'urn:gaylemon:attestation:release-manifest:v1') 'Prédicat de release indépendant du déploiement'
Assert-Contract ($version -match '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$') 'VERSION respecte SemVer'

$tracked = @(& git -C $root ls-files)
$forbiddenPaths = @($tracked | Where-Object {
    $_ -match '^(?:server|vps)/' -or
    $_ -in @('compose.production.yaml', '.env.production.example', 'Gaylemon Ops Console.ps1') -or
    $_ -match '^docs/(?:OPERATIONS|DEPLOIEMENT|hébergement-|LAN-ACCESS|SECURITE-EXPLOITATION|SOURCE-DE-VERITE)\.md$'
})
$forbiddenPathDetails = if ($forbiddenPaths.Count) { ': ' + ($forbiddenPaths -join ', ') } else { '' }
Assert-Contract ($forbiddenPaths.Count -eq 0) "Aucun adaptateur ou runbook d’instance suivi$forbiddenPathDetails"

$textExtensions = @('.css', '.env', '.example', '.go', '.html', '.js', '.json', '.md', '.mjs', '.ps1', '.py', '.sh', '.svg', '.txt', '.yaml', '.yml')
$privateSurfaceErrors = [Collections.Generic.List[string]]::new()
$privateHostA = -join @(110,101,116,104,101,114,99,111,114,101 | ForEach-Object { [char]$_ })
$privateHostB = -join @(100,111,99,107,112,97,110,101,108 | ForEach-Object { [char]$_ })
$providerA = -join @(71,111,111,103,108,101,32,68,114,105,118,101 | ForEach-Object { [char]$_ })
$providerB = -join @(67,108,111,117,100,102,108,97,114,101,32,82,50 | ForEach-Object { [char]$_ })
foreach ($relative in $tracked) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $extension = [IO.Path]::GetExtension($relative).ToLowerInvariant()
    if ($extension -notin $textExtensions -and [IO.Path]::GetFileName($relative) -notin @('LICENSE', '.gitignore', '.gitattributes')) { continue }
    $content = Get-Content -Raw -LiteralPath $path -Encoding UTF8
    if ($content.IndexOf($privateHostA, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $content.IndexOf($privateHostB, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $content.Contains($providerA) -or $content.Contains($providerB) -or
        $content -match '(?i)/home/[A-Za-z0-9._-]+/Gaylemon|gaylemon\.mathieu\.pro') {
        $privateSurfaceErrors.Add($relative)
    }
}
$privateSurfaceDetails = if ($privateSurfaceErrors.Count) { ': ' + (($privateSurfaceErrors | Sort-Object -Unique) -join ', ') } else { '' }
Assert-Contract ($privateSurfaceErrors.Count -eq 0) "Aucun détail privé dans les fichiers suivis$privateSurfaceDetails"

$portalPages = @(Get-ChildItem -LiteralPath (Join-Path $root 'portal') -Filter '*.html' -File)
$assetErrors = [Collections.Generic.List[string]]::new()
foreach ($page in $portalPages) {
    $source = Get-Content -Raw -LiteralPath $page.FullName -Encoding UTF8
    if ($page.Name -eq 'offline.html' -and $source -notmatch '/assets/(?:styles\.css|app\.js)') { continue }
    if ($source -notmatch '/assets/styles\.css' -or $source -notmatch '/assets/app\.js' -or $source -match '(?:styles\.css|app\.js)\?v=') {
        $assetErrors.Add($page.Name)
    }
}
$worker = Get-Content -Raw -LiteralPath (Join-Path $root 'portal/sw.js') -Encoding UTF8
$assetDetails = if ($assetErrors.Count) { ': ' + ($assetErrors -join ', ') } else { '' }
Assert-Contract ($assetErrors.Count -eq 0) "Pages prêtes pour les actifs hachés$assetDetails"
Assert-Contract ($worker -match '__GAYLEMON_ASSET_RELEASE__' -and $worker -match 'slice\(0, 2\)' -and $worker -match 'caches\.match\(request\)' -and $worker -notmatch 'ignoreSearch') 'Service worker exact avec release précédente'

$jsonErrors = [Collections.Generic.List[string]]::new()
foreach ($relative in @($tracked | Where-Object { $_ -like '*.json' })) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    try { [void](Get-Content -Raw -LiteralPath $path -Encoding UTF8 | ConvertFrom-Json -AsHashtable) }
    catch { $jsonErrors.Add($relative) }
}
$jsonDetails = if ($jsonErrors.Count) { ': ' + ($jsonErrors -join ', ') } else { '' }
Assert-Contract ($jsonErrors.Count -eq 0) "JSON valides$jsonDetails"

if (-not $SansGo) {
    & go test ./...
    Assert-Contract ($LASTEXITCODE -eq 0) 'Tests Go'
    & go vet ./...
    Assert-Contract ($LASTEXITCODE -eq 0) 'Analyse Go'
}

& node --check (Join-Path $root 'portal/assets/app.js')
Assert-Contract ($LASTEXITCODE -eq 0) 'Syntaxe JavaScript'
& node --test (Join-Path $root 'portal/tests/portal-v6-static.test.mjs')
Assert-Contract ($LASTEXITCODE -eq 0) 'Contrats du portail'

if (-not $SansTestsPython) {
    & python -m unittest discover -s (Join-Path $root 'scripts/tests') -p 'test_*.py'
    Assert-Contract ($LASTEXITCODE -eq 0) 'Contrats Python locaux'
}

& git -C $root diff --check
Assert-Contract ($LASTEXITCODE -eq 0) 'Diff Git sans erreur de format'

if ($failures.Count -gt 0) {
    Write-Host "`n$($failures.Count) validation(s) en échec." -ForegroundColor Red
    exit 1
}
Write-Host "`nDépôt public valide. Aucun service distant n’a été modifié." -ForegroundColor Green
