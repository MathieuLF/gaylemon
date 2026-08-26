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

$inventory = & (Join-Path $PSScriptRoot 'upgrade-preflight.ps1') -Mode Inventory | ConvertFrom-Json
$env:GOFLAGS = '-mod=readonly'
try {
    Invoke-Check 'go-test' { go test ./... }
    Invoke-Check 'go-vet' { go vet ./... }
    Invoke-Check 'portal-contracts' { node --test portal/tests/portal-v6-static.test.mjs }
    if ($Mode -eq 'Full') {
		foreach ($requiredTool in 'govulncheck','gitleaks','docker','syft','trivy','cosign','python','bash') {
			if (-not (Get-Command $requiredTool -ErrorAction SilentlyContinue)) { throw "Outil Full absent: $requiredTool" }
		}
		Invoke-Check 'npm-ci' { npm ci --ignore-scripts }
		Invoke-Check 'playwright-install' { npx playwright install chromium }
		Invoke-Check 'playwright-axe' { npm run test:browser }
        Invoke-Check 'go-race' { go test -race ./... }
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

$receiptDirectory = Join-Path $root 'release'
New-Item -ItemType Directory -Force -Path $receiptDirectory | Out-Null
$artifacts = @()
if ($Mode -eq 'Full') { $artifacts += "gaylemon-local:$version" }
$receipt = [ordered]@{
    schema = 'suite.local-validation.v2'
    suiteContract = 'suite-foundation-v2'
    profile = 'seasonal-go-microsite'
    application = 'gaylemon'
    result = 'success'
    mode = $Mode.ToLowerInvariant()
    commit = (& git -C $root rev-parse HEAD).Trim()
    branch = (& git -C $root branch --show-current).Trim()
    cleanAtStart = ($initialStatus.Count -eq 0)
    routes = $inventory.routes
    tools = [ordered]@{ go = (& go env GOVERSION).Trim(); node = (& node --version).Trim() }
    checks = $checks
    artifacts = $artifacts
    sbom = if ($Mode -eq 'Full') { @("release/gaylemon-$version.spdx.json", "release/gaylemon-$version.cdx.json") } else { @() }
	scan = if ($Mode -eq 'Full') { [ordered]@{ tool='trivy'; blocking=$true; result='success' } } else { $null }
	signature = if ($Mode -eq 'Full') { [ordered]@{ tool='cosign'; imageDescriptor="release/gaylemon-$version-local-image.json.sig"; agent="release/gaylemon-agent-$version-linux-amd64.sig"; verified=$true } } else { $null }
    validatedAt = [DateTimeOffset]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText((Join-Path $receiptDirectory 'local-validation.json'), ($receipt | ConvertTo-Json -Depth 8) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
Write-Host "Validation locale $Mode réussie."
