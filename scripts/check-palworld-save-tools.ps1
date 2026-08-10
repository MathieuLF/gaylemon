param(
    [switch]$SyncFork,
    [switch]$UpdateRemote,
    [string]$ApprovedCommit = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot
$upstream = $config.SaveToolsUpstream
$fork = $config.SaveToolsFork
$lockPath = Join-Path $ProjectRoot "dependencies\palworld-save-tools.lock.json"
$lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
$archiveSha256 = [string]$lock.archiveSha256

function Get-HeadSha([string]$Repository) {
    $sha = (& gh api "repos/$Repository/commits/main" --jq .sha | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($sha)) {
        throw "Impossible de lire la branche main de $Repository."
    }
    return $sha
}

function Get-ActiveRemoteSha {
    $command = "git -C '$($config.RemoteProjectRoot)/vendor/PalworldSaveTools-current' rev-parse HEAD 2>/dev/null || git -C '$($config.RemoteProjectRoot)/vendor/PalworldSaveTools' rev-parse HEAD"
    $sha = (& ssh.exe -o BatchMode=yes -o ConnectTimeout=8 $config.SshAlias $command 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $sha -notmatch '^[a-f0-9]{40}$') {
        return $null
    }
    return $sha
}

if ($UpdateRemote) {
    if ($SyncFork) {
        throw "La synchronisation du fork et l'activation Ubuntu doivent rester deux étapes séparées."
    }
    if ($ApprovedCommit -notmatch '^[a-f0-9]{40}$') {
        throw "-ApprovedCommit doit contenir le commit SHA-1 complet préalablement revu."
    }
    if ($ApprovedCommit -cne [string]$lock.commit) {
        throw "Le commit approuvé doit correspondre au verrou versionné dependencies/palworld-save-tools.lock.json."
    }
    if ($archiveSha256 -notmatch '^[a-f0-9]{64}$') {
        throw "Le verrou versionné doit contenir l'empreinte SHA-256 de l'archive approuvée."
    }
}

$upstreamSha = Get-HeadSha -Repository $upstream
$forkSha = Get-HeadSha -Repository $fork
$wasSynced = $false
$activeBefore = Get-ActiveRemoteSha

if ($upstreamSha -ne $forkSha) {
    Write-Host "Une mise à jour est disponible: $($upstreamSha.Substring(0, 12))"
    if ($SyncFork) {
        & gh repo sync $fork --source $upstream --branch main
        if ($LASTEXITCODE -ne 0) {
            throw "La synchronisation GitHub du fork a échoué."
        }
        $forkSha = Get-HeadSha -Repository $fork
        if ($forkSha -ne $upstreamSha) {
            throw "Le fork ne correspond toujours pas à la révision upstream."
        }
        $wasSynced = $true
        Write-Host "Fork synchronisé: $($forkSha.Substring(0, 12))"
    }
}
else {
    Write-Host "Fork GitHub à jour: $($forkSha.Substring(0, 12))"
}

if ($activeBefore) {
    Write-Host "Parseur Ubuntu actif: $($activeBefore.Substring(0, 12))"
    if ($activeBefore -ne $forkSha) {
        Write-Host "Une version du parseur est disponible pour validation Ubuntu: $($forkSha.Substring(0, 12))" -ForegroundColor Yellow
    }
}
else {
    Write-Warning "La revision active du parseur Ubuntu n'a pas pu etre lue."
}

if ($UpdateRemote) {
    if ($forkSha -cne $ApprovedCommit) {
        throw "Le fork ne pointe pas sur le commit approuvé $ApprovedCommit."
    }
    & ssh.exe $config.SshAlias "$($config.RemoteProjectRoot)/server/bin/palworld-save-tools-update.sh '$ApprovedCommit' '$archiveSha256'"
    if ($LASTEXITCODE -ne 0) {
        throw "La validation ou la mise à jour du parseur Ubuntu a échoué. La version active n'a pas été remplacée."
    }

    $activeAfter = Get-ActiveRemoteSha
    if (-not $activeAfter -or $activeAfter -cne $ApprovedCommit) {
        throw "Le parseur Ubuntu ne correspond pas à la révision approuvée après validation."
    }
    Write-Host "Révision Gaylémon approuvée et activée: $($activeAfter.Substring(0, 12))"
}
else {
    $activeAfter = $activeBefore
}

[pscustomobject]@{
    Upstream = $upstreamSha
    Fork = $forkSha
    Locked = [string]$lock.commit
    LockedArchiveSha256 = $archiveSha256
    ActiveBefore = $activeBefore
    ActiveAfter = $activeAfter
    UpdateAvailableForUbuntu = [bool]($activeBefore -and $activeBefore -ne $forkSha)
    ForkSynchronized = $wasSynced
    RemoteUpdateRequested = [bool]$UpdateRemote
}
