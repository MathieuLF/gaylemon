[CmdletBinding()]
param(
    [ValidateSet('Quick','Full')][string]$Mode = 'Quick',
    [switch]$AllowDirty,
    [string]$CosignKey = "$env:USERPROFILE\.gaylemon\cosign.key",
    [string]$CosignPublicKey = "$env:USERPROFILE\.gaylemon\cosign.pub"
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$initialStatus = @(& git -C $root status --porcelain)
if ($Mode -eq 'Full' -and $initialStatus.Count -gt 0 -and -not $AllowDirty) {
    throw 'La validation Full exige un commit propre. Utiliser -AllowDirty uniquement avant le commit final.'
}
$checks = [Collections.Generic.List[object]]::new()
function Invoke-Check([string]$Name, [scriptblock]$Action) {
    & $Action
    if ($LASTEXITCODE -ne 0) { throw "$Name a échoué." }
    $checks.Add([ordered]@{ name = $Name; result = 'success' })
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
    Invoke-Check 'portal-contracts' { node --test portal/tests/portal-v6-static.test.mjs }
    if ($Mode -eq 'Full') {
		foreach ($requiredTool in 'govulncheck','gitleaks','docker','syft','trivy','cosign','python','bash') {
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
		Invoke-Check 'gitleaks' { gitleaks detect --source $root --no-banner --redact }
		Invoke-Check 'repository-contracts' { & (Join-Path $PSScriptRoot 'valider-depot.ps1') -SansDocker }
        $version = (Get-Content -Raw -LiteralPath (Join-Path $root 'VERSION')).Trim()
        Invoke-Check 'release-chain' { & (Join-Path $PSScriptRoot 'release.ps1') -Version $version -Image 'gaylemon-local' -CosignKey $CosignKey -CosignPublicKey $CosignPublicKey }
    }
    Invoke-Check 'git-diff-check' { git -C $root diff --check }
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
    $artifacts += "gaylemon-local:$version"
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
    $toolVersions['gitleaks'] = (& gitleaks version).Trim()
    $toolVersions['syft'] = Get-VersionCapture ((& syft version 2>&1 | Out-String)) '^Version:\s+(\S+)' 'Syft'
    $toolVersions['trivy'] = Get-VersionCapture ((& trivy version 2>&1 | Out-String)) '^Version:\s+(\S+)' 'Trivy'
    $toolVersions['cosign'] = Get-VersionCapture ((& cosign version 2>&1 | Out-String)) '^GitVersion:\s+v?(\S+)' 'Cosign'
    $toolVersions['bash'] = Get-VersionCapture ((& bash --version 2>&1 | Out-String)) '^GNU bash, version\s+(\S+)' 'Bash'
}
$receipt = [ordered]@{
    schema = 'suite.local-validation.v2'
    contract = 'suite-foundation-v2'
    profile = 'seasonal-go-microsite'
    application = 'gaylemon'
    result = 'success'
    mode = $Mode.ToLowerInvariant()
    commit = (& git -C $root rev-parse HEAD).Trim()
    branch = (& git -C $root branch --show-current).Trim()
    cleanAtStart = ($initialStatus.Count -eq 0)
    cleanAtEnd = ($finalStatus.Count -eq 0)
    routes = [ordered]@{
        count = [int]$routeInventory.count
        sha256 = $routeHash
        inventory = @($routeInventory.routes)
    }
    tools = $toolVersions
    checks = $checks
    artifacts = @($artifacts)
    sbom = @($sbomArtifacts)
	scan = if ($Mode -eq 'Full') { [ordered]@{ tool='trivy'; blocking=$true; result='success' } } else { $null }
	signature = if ($Mode -eq 'Full') { [ordered]@{ tool='cosign'; imageDescriptor="release/gaylemon-$version-local-image.json.cosign-bundle.json"; agent="release/gaylemon-agent-$version-linux-amd64.cosign-bundle.json"; verified=$true } } else { $null }
    validatedAt = [DateTimeOffset]::UtcNow.ToString('o')
}
$receiptPath = Join-Path $receiptDirectory 'local-validation.json'
[IO.File]::WriteAllText($receiptPath, ($receipt | ConvertTo-Json -Depth 8) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
& python (Join-Path $PSScriptRoot 'check_local_validation_receipt.py') $receiptPath
if ($LASTEXITCODE -ne 0) { throw 'Le reçu de validation locale ne respecte pas suite.local-validation.v2.' }
Write-Host "Validation locale $Mode réussie."
