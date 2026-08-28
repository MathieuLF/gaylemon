[CmdletBinding()]
param(
    [ValidateSet('Quick','Full')][string]$Mode = 'Quick',
    [switch]$AllowDirty,
    [string]$CosignKey = "$env:USERPROFILE\.gaylemon\cosign.key",
    [string]$CosignPublicKey = "$env:USERPROFILE\.gaylemon\cosign.pub"
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$startedAt = [DateTimeOffset]::UtcNow
$fullSecurity = $null
$initialStatus = @(& git -C $root status --porcelain)
if ($Mode -eq 'Full' -and $initialStatus.Count -gt 0 -and -not $AllowDirty) {
    throw 'La validation Full exige un commit propre. Utiliser -AllowDirty uniquement avant le commit final.'
}
$checks = [Collections.Generic.List[object]]::new()
function Invoke-Check([string]$Name, [scriptblock]$Action) {
    & $Action
    if ($LASTEXITCODE -ne 0) { throw "$Name a échoué." }
    $checks.Add([ordered]@{ name = $Name; status = 'passed' })
}
function Get-VersionCapture([string]$Text, [string]$Pattern, [string]$Tool) {
    $match = [regex]::Match($Text, $Pattern, [Text.RegularExpressions.RegexOptions]::Multiline)
    if (-not $match.Success -or -not $match.Groups[1].Value.Trim()) {
        throw "Version de $Tool indétectable."
    }
    return $match.Groups[1].Value.Trim()
}

$inventory = & (Join-Path $PSScriptRoot 'upgrade-preflight.ps1') -Mode Inventory | ConvertFrom-Json
$routeInventory = & (Join-Path $PSScriptRoot 'inventory-routes.ps1') -Check | ConvertFrom-Json
$canonicalRoutes = ConvertTo-Json @($routeInventory.routes) -Depth 5 -Compress
$routeHashBytes = [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($canonicalRoutes))
$routeHash = [Convert]::ToHexString($routeHashBytes).ToLowerInvariant()
$env:GOFLAGS = '-mod=readonly'
try {
    Invoke-Check 'go-test' { go test ./... }
    Invoke-Check 'go-vet' { go vet ./... }
    Invoke-Check 'validation-receipt-contracts' { python -m unittest discover -s scripts/tests -p 'test_*.py' }
    Invoke-Check 'season-agent-contracts' { python -m unittest discover -s server/tests -p 'test_security_controls.py' }
    Invoke-Check 'portal-contracts' { node --test portal/tests/portal-v6-static.test.mjs }
    if ($Mode -eq 'Full') {
		foreach ($requiredTool in 'govulncheck','docker','python','bash','tar') {
			if (-not (Get-Command $requiredTool -ErrorAction SilentlyContinue)) { throw "Outil Full absent: $requiredTool" }
		}
		Invoke-Check 'npm-ci' { npm ci --ignore-scripts }
		Invoke-Check 'playwright-install' { npx playwright install chromium }
		Invoke-Check 'playwright-axe' { npm run test:browser }
		if ($IsWindows) {
			$raceImage = "gaylemon-race-validation:$((& git -C $root rev-parse --short=12 HEAD).Trim())"
			Invoke-Check 'go-race-image' { docker build --target build --tag $raceImage $root }
			Invoke-Check 'go-race' { docker run --rm --entrypoint /bin/sh $raceImage -c 'CGO_ENABLED=1 go test -mod=readonly -race ./...' }
		} else {
			Invoke-Check 'go-race' { $env:CGO_ENABLED='1'; try { go test -race ./... } finally { Remove-Item Env:CGO_ENABLED -ErrorAction SilentlyContinue } }
		}
        Invoke-Check 'deadcode' { go tool deadcode -test ./... }
		Invoke-Check 'govulncheck' { govulncheck ./... }
        Invoke-Check 'full-security-gates' {
            $securityJson = & python -B (Join-Path $PSScriptRoot 'run-full-security.py') --repository $root
            if ($LASTEXITCODE -eq 0) { $script:fullSecurity = $securityJson | ConvertFrom-Json }
        }
        Invoke-Check 'repository-contracts' { & (Join-Path $PSScriptRoot 'valider-depot.ps1') -SansDocker }
        Invoke-Check 'server-contracts' { python -m unittest discover -s server/tests -p 'test_*.py' }
        Invoke-Check 'postgresql-multi-season' { & (Join-Path $PSScriptRoot 'test-postgres-seasons.ps1') }
        $version = (Get-Content -Raw -LiteralPath (Join-Path $root 'VERSION')).Trim()
    }
    Invoke-Check 'git-diff-check' { git -C $root diff --check }
    Invoke-Check 'git-diff-base-check' { git -C $root diff --check origin/main...HEAD }
}
finally { Remove-Item Env:GOFLAGS -ErrorAction SilentlyContinue }

$finalStatus = @(& git -C $root status --porcelain)
if ($initialStatus.Count -eq 0 -and $finalStatus.Count -gt 0) {
    throw 'La validation a modifié le dépôt.'
}

$receiptDirectory = Join-Path $root 'release'
New-Item -ItemType Directory -Force -Path $receiptDirectory | Out-Null
$artifacts = @()
$sbomArtifacts = @()
if ($Mode -eq 'Full') {
    foreach ($artifactPath in @(
        'config/full-security-policy-v1.json',
        'scripts/run-full-security.py',
        'scripts/suite_security.py',
        'release/evidence/gitleaks.json',
        'release/evidence/trivy-fs.json',
        'release/evidence/full-security.json',
        'release/sbom/source.spdx.json',
        'release/sbom/source.cyclonedx.json'
    )) {
        $file = Get-Item -LiteralPath (Join-Path $root $artifactPath)
        $artifacts += [ordered]@{
            path = $artifactPath
            bytes = $file.Length
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    $sbomArtifacts += "release/gaylemon-$version.spdx.json"
    $sbomArtifacts += "release/gaylemon-$version.cdx.json"
}
$toolVersions = [ordered]@{
    go = (& go env GOVERSION).Trim()
    node = (& node --version).Trim()
    powershell = $PSVersionTable.PSVersion.ToString()
    python = (& python --version 2>&1 | Out-String).Trim()
    git = (& git --version).Trim()
}
if ($Mode -eq 'Full') {
    $packages = Get-Content -Raw -LiteralPath (Join-Path $root 'package.json') | ConvertFrom-Json
    $toolVersions['npm'] = (& npm --version).Trim()
    $toolVersions['docker'] = (& docker version --format '{{.Client.Version}}').Trim()
    $toolVersions['playwright'] = $packages.devDependencies.'@playwright/test'
    $toolVersions['axe'] = $packages.devDependencies.'@axe-core/playwright'
    $toolVersions['deadcode'] = (& go list -m -f '{{.Version}}' golang.org/x/tools).Trim()
    $toolVersions['govulncheck'] = Get-VersionCapture ((& govulncheck -version 2>&1 | Out-String)) '^Scanner:\s+govulncheck@(\S+)' 'govulncheck'
    $toolVersions['gitleaks'] = $fullSecurity.tools.gitleaks
    $toolVersions['syft'] = $fullSecurity.tools.syft
    $toolVersions['trivy'] = $fullSecurity.tools.trivy
    $toolVersions['cosign'] = '3.1.3-container'
    $toolVersions['bash'] = Get-VersionCapture ((& bash --version 2>&1 | Out-String)) '^GNU bash, version\s+(\S+)' 'Bash'
}
$branch = (& git -C $root branch --show-current).Trim()
$upstream = (& git -C $root rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>$null)
if ($LASTEXITCODE -ne 0) { $upstream = $null } else { $upstream = $upstream.Trim() }
$ahead = $null
$behind = $null
if ($upstream) {
    $divergence = ((& git -C $root rev-list --left-right --count "HEAD...$upstream").Trim() -split '\s+')
    if ($LASTEXITCODE -eq 0 -and $divergence.Count -eq 2) {
        $ahead = [int]$divergence[0]
        $behind = [int]$divergence[1]
    }
}
$checkReceipts = @($checks)
$security = [ordered]@{ schema='suite.full-security-evidence.v1'; requiredInFull=$true; result='not-run' }
if ($Mode -eq 'Full') {
    $checkReceipts += @(
        [ordered]@{ name='gitleaks'; status='passed' },
        [ordered]@{ name='trivy-filesystem'; status='passed' },
        [ordered]@{ name='sbom-spdx'; status='passed' },
        [ordered]@{ name='sbom-cyclonedx'; status='passed' }
    )
    $security = $fullSecurity
}
$receipt = [ordered]@{
    schema = 'suite.local-validation.v2'
    contract = 'suite-foundation-v2'
    contractRevision = '2.2.0'
    profile = 'seasonal-go-microsite'
    application = 'gaylemon'
    version = (Get-Content -Raw -LiteralPath (Join-Path $root 'VERSION')).Trim()
    mode = $Mode.ToLowerInvariant()
    startedAt = $startedAt.ToString('o')
    completedAt = [DateTimeOffset]::UtcNow.ToString('o')
    git = [ordered]@{
        commit = (& git -C $root rev-parse HEAD).Trim()
        branch = $branch
        upstream = $upstream
        ahead = $ahead
        behind = $behind
        cleanAtStart = ($initialStatus.Count -eq 0)
        cleanAtEnd = ($finalStatus.Count -eq 0)
    }
    routes = [ordered]@{
        count = [int]$routeInventory.count
        sha256 = $routeHash
        inventory = @($routeInventory.routes)
    }
    tools = $toolVersions
    checks = $checkReceipts
    artifacts = [ordered]@{ files = @($artifacts); sbom = @($sbomArtifacts) }
    security = $security
    lifecycle = [ordered]@{
        palworldRestartForbidden = $true
        agentContracts = [ordered]@{ status='passed'; check='season-agent-contracts' }
        multiSeasonDatabase = if ($Mode -eq 'Full') { [ordered]@{ status='passed'; check='postgresql-multi-season' } } else { [ordered]@{ status='not-applicable'; reason='Quick couvre les contrats purs; Full exécute les migrations et la concurrence PostgreSQL.' } }
    }
    result = 'passed'
}
$receiptPath = Join-Path $receiptDirectory 'local-validation.json'
[IO.File]::WriteAllText($receiptPath, ($receipt | ConvertTo-Json -Depth 8) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
& python (Join-Path $PSScriptRoot 'check_local_validation_receipt.py') $receiptPath
if ($LASTEXITCODE -ne 0) { throw 'Le reçu de validation locale ne respecte pas suite.local-validation.v2.' }
if ($Mode -eq 'Full') {
    & (Join-Path $PSScriptRoot 'release.ps1') -Version $version -Image 'gaylemon-local' -CosignKey $CosignKey -CosignPublicKey $CosignPublicKey
    if ($LASTEXITCODE -ne 0) { throw "La chaîne de release locale n'a pas produit son reçu canonique." }
}
Write-Host "Validation locale $Mode réussie."
