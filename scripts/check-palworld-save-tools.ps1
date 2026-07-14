param(
    [switch]$SyncFork,
    [switch]$UpdateRemote
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot
$upstream = $config.SaveToolsUpstream
$fork = $config.SaveToolsFork
$lockPath = Join-Path $ProjectRoot "dependencies\palworld-save-tools.lock.json"
$lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json

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

function Update-DependencyLock([string]$Commit) {
    $lock.commit = $Commit
    if ($lock.PSObject.Properties.Name -contains "validatedAt") {
        $lock.validatedAt = (Get-Date).ToString("o")
    }
    else {
        $lock | Add-Member -NotePropertyName "validatedAt" -NotePropertyValue (Get-Date).ToString("o")
    }
    $json = $lock | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($lockPath, $json.TrimEnd() + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
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
    & ssh.exe $config.SshAlias "$($config.RemoteProjectRoot)/server/bin/palworld-save-tools-update.sh"
    if ($LASTEXITCODE -ne 0) {
        throw "La validation ou la mise à jour du parseur Ubuntu a échoué. La version active n'a pas été remplacée."
    }

    $activeAfter = Get-ActiveRemoteSha
    if (-not $activeAfter -or $activeAfter -ne $forkSha) {
        throw "Le parseur Ubuntu ne correspond pas a la revision du fork apres validation."
    }
    Update-DependencyLock -Commit $activeAfter
    Write-Host "Verrou Gaylemon actualise: $($activeAfter.Substring(0, 12))"
}
else {
    $activeAfter = $activeBefore
}

$localClone = Join-Path $PSScriptRoot "..\vendor\PalworldSaveTools"
if ((Test-Path -LiteralPath (Join-Path $localClone ".git")) -and ($SyncFork -or $UpdateRemote)) {
    $pullOutput = & git -C $localClone pull --ff-only origin main 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "La copie locale de PalworldSaveTools n'a pas pu être mise à jour en fast-forward."
    }
    $pullText = ($pullOutput | Out-String).Trim()
    if ($pullText -match "Already up to date") {
        Write-Host "Copie locale PalworldSaveTools déjà à jour."
    }
    else {
        Write-Host "Copie locale PalworldSaveTools synchronisée en fast-forward."
    }
    & (Join-Path $PSScriptRoot "sync-palworld-game-assets.ps1") | Out-Null
}

[pscustomobject]@{
    Upstream = $upstreamSha
    Fork = $forkSha
    Locked = [string]$lock.commit
    ActiveBefore = $activeBefore
    ActiveAfter = $activeAfter
    UpdateAvailableForUbuntu = [bool]($activeBefore -and $activeBefore -ne $forkSha)
    ForkSynchronized = $wasSynced
    RemoteUpdateRequested = [bool]$UpdateRemote
}
