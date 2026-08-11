[CmdletBinding()]
param(
    [uri]$ProductionUrl = "https://gaylemon.nethercore.dev",
    [ValidatePattern("^[A-Za-z0-9][A-Za-z0-9._/-]*$")]
    [string]$Remote = "origin",
    [ValidatePattern("^[A-Za-z0-9][A-Za-z0-9._/-]*$")]
    [string]$Branch = "main",
    [switch]$Json,
    [switch]$Strict
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$versionPattern = "^[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[1-9][0-9]*$"

function Invoke-ProjectGit {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = @(& git -C $ProjectRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') a échoué: $($output -join ' ')"
    }
    return ($output -join "`n").Trim()
}

function Get-ShortCommit {
    param([string]$Commit)

    if ([string]::IsNullOrWhiteSpace($Commit) -or $Commit -eq "unknown") { return "—" }
    return $Commit.Substring(0, [Math]::Min(7, $Commit.Length))
}

if (-not $ProductionUrl.IsAbsoluteUri -or $ProductionUrl.Scheme -notin @("http", "https")) {
    throw "ProductionUrl doit être une URL HTTP ou HTTPS absolue."
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git est requis pour comparer les versions."
}

$localVersion = (Get-Content -LiteralPath (Join-Path $ProjectRoot "VERSION") -Raw -Encoding UTF8).Trim()
if ($localVersion -notmatch $versionPattern) {
    throw "VERSION doit respecter AAAA.MM.JJ.REVISION."
}
$localCommit = Invoke-ProjectGit -Arguments @("rev-parse", "HEAD")
$localBranch = Invoke-ProjectGit -Arguments @("branch", "--show-current")
$localDirty = -not [string]::IsNullOrWhiteSpace((Invoke-ProjectGit -Arguments @("status", "--porcelain")))

$remoteVersion = ""
$remoteCommit = ""
$remoteError = ""
try {
    Invoke-ProjectGit -Arguments @("fetch", "--quiet", "--no-tags", $Remote, "refs/heads/$Branch") | Out-Null
    $remoteCommit = Invoke-ProjectGit -Arguments @("rev-parse", "FETCH_HEAD")
    $remoteVersion = Invoke-ProjectGit -Arguments @("show", "$remoteCommit`:VERSION")
    if ($remoteVersion -notmatch $versionPattern) {
        throw "VERSION distante invalide: $remoteVersion"
    }
}
catch {
    $remoteError = $_.Exception.Message
}

$productionVersion = ""
$productionCommit = ""
$productionChannel = ""
$productionError = ""
try {
    $versionUri = [uri]::new($ProductionUrl.AbsoluteUri.TrimEnd('/') + "/version")
    $production = Invoke-RestMethod -Uri $versionUri -Headers @{ Accept = "application/json" } -TimeoutSec 10
    $productionVersion = [string]$production.version
    $productionCommit = [string]$production.commit
    $productionChannel = [string]$production.channel
    if ($productionVersion -notmatch $versionPattern) {
        throw "La VPS annonce une version invalide: $productionVersion"
    }
    if ($productionCommit -notmatch "^[0-9a-f]{40}$") {
        throw "La VPS n'annonce pas un commit Git complet."
    }
}
catch {
    $productionError = $_.Exception.Message
}

$localMatchesGitHub = -not $localDirty -and -not $remoteError -and $localVersion -eq $remoteVersion -and $localCommit -eq $remoteCommit
$gitHubMatchesProduction = -not $remoteError -and -not $productionError -and $remoteVersion -eq $productionVersion -and $remoteCommit -eq $productionCommit
$allMatch = $localMatchesGitHub -and $gitHubMatchesProduction

$result = [pscustomobject]@{
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    allMatch = $allMatch
    localMatchesGitHub = $localMatchesGitHub
    gitHubMatchesProduction = $gitHubMatchesProduction
    local = [pscustomobject]@{
        version = $localVersion
        commit = $localCommit
        branch = $localBranch
        dirty = $localDirty
    }
    github = [pscustomobject]@{
        version = $remoteVersion
        commit = $remoteCommit
        remote = $Remote
        branch = $Branch
        error = $remoteError
    }
    production = [pscustomobject]@{
        version = $productionVersion
        commit = $productionCommit
        channel = $productionChannel
        url = $ProductionUrl.AbsoluteUri.TrimEnd('/')
        error = $productionError
    }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 5
}
else {
    $rows = @(
        [pscustomobject]@{ Source = "Local"; Version = $localVersion; Commit = Get-ShortCommit $localCommit; État = $(if ($localDirty) { "$localBranch, modifié" } else { "$localBranch, propre" }) }
        [pscustomobject]@{ Source = "GitHub"; Version = $(if ($remoteVersion) { $remoteVersion } else { "—" }); Commit = Get-ShortCommit $remoteCommit; État = $(if ($remoteError) { "indisponible" } else { "$Remote/$Branch" }) }
        [pscustomobject]@{ Source = "VPS"; Version = $(if ($productionVersion) { $productionVersion } else { "—" }); Commit = Get-ShortCommit $productionCommit; État = $(if ($productionError) { "indisponible" } else { $productionChannel }) }
    )
    $rows | Format-Table -AutoSize
    if ($allMatch) {
        Write-Host "Les trois versions correspondent." -ForegroundColor Green
    }
    else {
        Write-Host "Les versions ne correspondent pas encore." -ForegroundColor Yellow
        if ($remoteError) { Write-Warning "GitHub: $remoteError" }
        if ($productionError) { Write-Warning "VPS: $productionError" }
    }
}

if ($Strict -and -not $allMatch) {
    exit 1
}
