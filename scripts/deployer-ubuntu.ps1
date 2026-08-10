param(
    [Alias("Apply")]
    [switch]$Stage,

    [switch]$Install,

    [string[]]$RestartUnit = @(),

    [switch]$AllowPalworldRestart,

    [string]$Confirmation = "",

    [string]$Cible,

    [string]$RepertoireDistant = "/tmp/gaylemon-staging",

    [switch]$SansValidationLocale
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
. (Join-Path $PSScriptRoot "lib\Gaylemon.Deployment.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot
if (-not $Cible) { $Cible = $config.SshAlias }

if ($Install) { $Stage = $true }
if ($RepertoireDistant -notmatch '^/tmp/[A-Za-z0-9._/-]+$' -or $RepertoireDistant.Contains("..")) {
    throw "Le répertoire distant doit rester sous /tmp et ne peut pas contenir '..'."
}
foreach ($unit in $RestartUnit) {
    if ($unit -notmatch '^(palworld|gaylemon|cloudflare-update-dns)[A-Za-z0-9_.@-]*\.(service|timer)$') {
        throw "Unité systemd non autorisée: $unit"
    }
}
if ($RestartUnit -contains "palworld.service" -and -not $AllowPalworldRestart) {
    throw "Le redémarrage de palworld.service exige -AllowPalworldRestart."
}

[void](Build-GaylemonLinuxAgent -ProjectRoot $ProjectRoot)

$manifest = Get-GaylemonDeploymentManifest -ProjectRoot $ProjectRoot -Config $config
$serverRoot = Join-Path $ProjectRoot "server"
$files = @(Get-ChildItem -LiteralPath $serverRoot -File -Recurse | Where-Object {
    $_.FullName -notmatch '(__pycache__|\.py[co]$)'
})

Write-Host "Livraison Ubuntu Gaylémon" -ForegroundColor Cyan
Write-Host "Cible SSH: $Cible"
Write-Host "Zone distante: $RepertoireDistant"
Write-Host "Fichiers actifs déclarés: $($manifest.Entries.Count)"
Write-Host "Fichiers livrés: $($files.Count)"
Write-Host ""

foreach ($entry in $manifest.Entries) {
    $restart = if ($entry.RestartPolicy -eq "none") { "" } else { " [$($entry.RestartPolicy): $($entry.RestartUnit)]" }
    Write-Host "- $($entry.Source) -> $($entry.Destination)$restart"
}

Write-Host ""
Write-Host "Garde-fous:" -ForegroundColor Yellow
Write-Host "- le manifeste limite strictement les destinations actives;"
Write-Host "- toutes les sources sont validées avant installation;"
Write-Host "- chaque fichier remplacé est sauvegardé sous $($manifest.BackupRoot);"
Write-Host "- aucune configuration secrète n'est livrée;"
Write-Host "- aucun service n'est redémarré par défaut;"
Write-Host "- palworld.service exige une autorisation et une confirmation distinctes."

if (-not $Stage) {
    Write-Host ""
    Write-Host "Aperçu seulement. Utiliser -Stage (ou l'ancien alias -Apply) pour mettre en scène." -ForegroundColor Green
    Write-Host "Utiliser -Install pour mettre en scène puis installer avec une seule élévation sudo." -ForegroundColor Green
    exit 0
}

if (-not $SansValidationLocale) {
    Write-Host ""
    Write-Host "Validation locale avant livraison..." -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot "valider-depot.ps1") -SansDocker
    if ($LASTEXITCODE -ne 0) {
        throw "La validation locale a échoué; livraison annulée."
    }
}

$tar = Get-Command tar -ErrorAction Stop
$scp = Get-Command scp -ErrorAction Stop
$ssh = Get-Command ssh -ErrorAction Stop
$deployRoot = Join-Path $ProjectRoot "runtime\deploy"
New-Item -ItemType Directory -Path $deployRoot -Force | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$packageRoot = Join-Path $deployRoot "package-$stamp"
$packageServerRoot = Join-Path $packageRoot "server"
$archiveName = "gaylemon-server-$stamp.tar.gz"
$archivePath = Join-Path $deployRoot $archiveName
$remoteArchive = "/tmp/$archiveName"
$remoteStage = "$($RepertoireDistant.TrimEnd('/'))/$stamp"

New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
Copy-Item -LiteralPath $serverRoot -Destination $packageServerRoot -Recurse
New-GaylemonResolvedDeploymentManifest `
    -Manifest $manifest `
    -OutputPath (Join-Path $packageServerRoot "deployment-manifest.resolved.json")
$resolvedManifestPath = Join-Path $packageServerRoot "deployment-manifest.resolved.json"
$manifestSha256 = (Get-FileHash -LiteralPath $resolvedManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
$engineSha256 = (Get-FileHash -LiteralPath (Join-Path $packageServerRoot "deploy\gaylemon_deploy.py") -Algorithm SHA256).Hash.ToLowerInvariant()
$wrapperSha256 = (Get-FileHash -LiteralPath (Join-Path $packageServerRoot "sbin\gaylemon-deploy-install") -Algorithm SHA256).Hash.ToLowerInvariant()

& $tar.Source -czf $archivePath --exclude="__pycache__" --exclude="*.pyc" -C $packageRoot server
if ($LASTEXITCODE -ne 0) { throw "Création de l'archive impossible." }

& $scp.Source $archivePath "${Cible}:$remoteArchive"
if ($LASTEXITCODE -ne 0) { throw "Téléversement de l'archive impossible." }

$remoteCommand = "set -eu; mkdir -p '$remoteStage'; tar -xzf '$remoteArchive' -C '$remoteStage'; rm -f '$remoteArchive'; printf '%s  %s\n' '$manifestSha256' '$remoteStage/server/deployment-manifest.resolved.json' | sha256sum -c - >/dev/null; /usr/bin/python3 '$remoteStage/server/deploy/gaylemon_deploy.py' plan --stage '$remoteStage' --manifest-sha256 '$manifestSha256' --json"
$planJson = (& $ssh.Source -o BatchMode=yes $Cible $remoteCommand 2>&1) -join "`n"
if ($LASTEXITCODE -ne 0) { throw "Validation de la zone distante impossible: $planJson" }

try {
    $plan = $planJson | ConvertFrom-Json
}
catch {
    throw "Le plan distant n'est pas un JSON valide: $planJson"
}

$changed = @($plan.entries | Where-Object { $_.changed -eq $true })
$removed = @($plan.removals | Where-Object { $_.changed -eq $true })
$protected = @($plan.entries | Where-Object { $null -eq $_.changed })
$recommendedUnits = @($changed | Where-Object restartPolicy -eq "recommended" | Select-Object -ExpandProperty restartUnit -Unique)
$gameChanges = @($changed | Where-Object restartPolicy -eq "game")

Write-Host ""
Write-Host "Zone validée: ${Cible}:$remoteStage" -ForegroundColor Green
Write-Host "Changements visibles: $($changed.Count)"
Write-Host "Suppressions visibles: $($removed.Count)"
Write-Host "Fichiers protégés à revérifier sous sudo: $($protected.Count)"
if ($recommendedUnits.Count -gt 0) {
    Write-Host "Redémarrages auxiliaires suggérés: $($recommendedUnits -join ', ')" -ForegroundColor Yellow
}
if ($gameChanges.Count -gt 0) {
    Write-Host "Un changement touchera Palworld au prochain redémarrage; le jeu ne sera pas redémarré automatiquement." -ForegroundColor Yellow
}

if (-not $Install) {
    Write-Host "Aucun fichier actif du serveur n'a été remplacé." -ForegroundColor Green
    exit 0
}

if (-not $Confirmation) {
    $Confirmation = Read-Host "Taper INSTALLER $stamp pour confirmer l'installation sans redémarrage implicite"
}
if ($Confirmation -cne "INSTALLER $stamp") {
    throw "Confirmation invalide; installation annulée."
}
if ($RestartUnit -contains "palworld.service") {
    $gameConfirmation = Read-Host "Taper REDEMARRER PALWORLD pour confirmer l'interruption du jeu"
    if ($gameConfirmation -cne "REDEMARRER PALWORLD") {
        throw "Confirmation du redémarrage Palworld invalide; installation annulée."
    }
}

Write-Host ""
Write-Host "Installation distante avec le moteur root-owned. Une élévation sudo interactive est requise." -ForegroundColor Cyan
$wrapperArguments = "'$remoteStage' --manifest-sha256 '$manifestSha256'"
foreach ($unit in $RestartUnit) {
    $wrapperArguments += " --restart-unit '$unit'"
}
if ($AllowPalworldRestart) {
    $wrapperArguments += " --allow-game-restart"
}
$rootInstallLines = @(
    'set -euo pipefail',
    "stage='$remoteStage'",
    'fixed_engine=/usr/local/libexec/gaylemon/gaylemon-deploy',
    'fixed_wrapper=/usr/local/sbin/gaylemon-deploy-install',
    'secure_tools=true',
    '[[ -f "$fixed_engine" && ! -L "$fixed_engine" && "$(/usr/bin/stat -c ''%U:%G:%a'' "$fixed_engine")" == root:root:755 ]] || secure_tools=false',
    '[[ -f "$fixed_wrapper" && ! -L "$fixed_wrapper" && "$(/usr/bin/stat -c ''%U:%G:%a'' "$fixed_wrapper")" == root:root:755 ]] || secure_tools=false',
    '/usr/bin/grep -Fq ''/usr/local/libexec/gaylemon/gaylemon-deploy'' "$fixed_wrapper" 2>/dev/null || secure_tools=false',
    '/usr/bin/grep -Fq -- ''--manifest-sha256'' "$fixed_wrapper" 2>/dev/null || secure_tools=false',
    'if [[ "$secure_tools" != true ]]; then',
    '  bootstrap_tmp="$(/usr/bin/mktemp -d /var/tmp/gaylemon-bootstrap.XXXXXX)"',
    '  /usr/bin/chmod 0700 "$bootstrap_tmp"',
    '  trap ''/usr/bin/rm -rf -- "$bootstrap_tmp"'' EXIT',
    '  /usr/bin/install -m 0600 "$stage/server/deploy/gaylemon_deploy.py" "$bootstrap_tmp/gaylemon-deploy"',
    '  /usr/bin/install -m 0600 "$stage/server/sbin/gaylemon-deploy-install" "$bootstrap_tmp/gaylemon-deploy-install"',
    ("  printf '%s  %s\n' '$engineSha256' ""`$bootstrap_tmp/gaylemon-deploy"" | /usr/bin/sha256sum -c - >/dev/null"),
    ("  printf '%s  %s\n' '$wrapperSha256' ""`$bootstrap_tmp/gaylemon-deploy-install"" | /usr/bin/sha256sum -c - >/dev/null"),
    '  bootstrap_backup="/var/backups/gaylemon-deploy/bootstrap-$(/usr/bin/date -u +%Y%m%dT%H%M%SZ)"',
    '  /usr/bin/install -d -o root -g root -m 0700 "$bootstrap_backup"',
    '  for current in "$fixed_engine" "$fixed_wrapper"; do',
    '    if [[ -e "$current" || -L "$current" ]]; then',
    '      [[ -f "$current" || -L "$current" ]] || { echo "Chemin de bootstrap non ordinaire: $current" >&2; exit 1; }',
    '      /usr/bin/cp -a --no-dereference "$current" "$bootstrap_backup/"',
    '    fi',
    '  done',
    '  /usr/bin/install -d -o root -g root -m 0755 /usr/local/libexec/gaylemon',
    '  /usr/bin/rm -f -- "$fixed_engine" "$fixed_wrapper"',
    '  /usr/bin/install -o root -g root -m 0755 "$bootstrap_tmp/gaylemon-deploy" "$fixed_engine"',
    '  /usr/bin/install -o root -g root -m 0755 "$bootstrap_tmp/gaylemon-deploy-install" "$fixed_wrapper"',
    'fi',
    "exec /usr/local/sbin/gaylemon-deploy-install $wrapperArguments"
)
$rootInstallScript = $rootInstallLines -join "`n"
$encodedRootInstall = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($rootInstallScript))
$installCommand = "printf '%s' '$encodedRootInstall' | /usr/bin/base64 -d | sudo /usr/bin/bash -s --"
& $ssh.Source -tt $Cible $installCommand
if ($LASTEXITCODE -ne 0) {
    throw "Installation distante en échec. Les services non demandés n'ont pas été redémarrés."
}

Write-Host ""
Write-Host "Audit post-installation..." -ForegroundColor Cyan
& (Join-Path $PSScriptRoot "auditer-source-ubuntu.ps1")
if ($LASTEXITCODE -ne 0) {
    throw "Installation terminée, mais l'audit de source signale encore une dérive."
}

Write-Host "Livraison Ubuntu terminée." -ForegroundColor Green
