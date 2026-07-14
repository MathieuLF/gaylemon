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
    if ($unit -notmatch '^(palworld|cloudflare-update-dns)[A-Za-z0-9_.@-]*\.(service|timer)$') {
        throw "Unité systemd non autorisée: $unit"
    }
}
if ($RestartUnit -contains "palworld.service" -and -not $AllowPalworldRestart) {
    throw "Le redémarrage de palworld.service exige -AllowPalworldRestart."
}

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

& $tar.Source -czf $archivePath --exclude="__pycache__" --exclude="*.pyc" -C $packageRoot server
if ($LASTEXITCODE -ne 0) { throw "Création de l'archive impossible." }

& $scp.Source $archivePath "${Cible}:$remoteArchive"
if ($LASTEXITCODE -ne 0) { throw "Téléversement de l'archive impossible." }

$remoteCommand = "set -eu; mkdir -p '$remoteStage'; tar -xzf '$remoteArchive' -C '$remoteStage'; rm -f '$remoteArchive'; /usr/bin/python3 '$remoteStage/server/deploy/gaylemon_deploy.py' plan --stage '$remoteStage' --json"
$planJson = (& $ssh.Source -o BatchMode=yes $Cible $remoteCommand 2>&1) -join "`n"
if ($LASTEXITCODE -ne 0) { throw "Validation de la zone distante impossible: $planJson" }

try {
    $plan = $planJson | ConvertFrom-Json
}
catch {
    throw "Le plan distant n'est pas un JSON valide: $planJson"
}

$changed = @($plan.entries | Where-Object { $_.changed -eq $true })
$protected = @($plan.entries | Where-Object { $null -eq $_.changed })
$recommendedUnits = @($changed | Where-Object restartPolicy -eq "recommended" | Select-Object -ExpandProperty restartUnit -Unique)
$gameChanges = @($changed | Where-Object restartPolicy -eq "game")

Write-Host ""
Write-Host "Zone validée: ${Cible}:$remoteStage" -ForegroundColor Green
Write-Host "Changements visibles: $($changed.Count)"
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

$installArguments = @(
    "install",
    "--stage", "'$remoteStage'",
    "--confirm", "'$stamp'"
)
foreach ($unit in $RestartUnit) {
    $installArguments += @("--restart-unit", "'$unit'")
}
if ($AllowPalworldRestart) {
    $installArguments += "--allow-game-restart"
}

Write-Host ""
Write-Host "Installation distante. Une seule élévation sudo peut être demandée." -ForegroundColor Cyan
$installCommand = "sudo /usr/bin/python3 '$remoteStage/server/deploy/gaylemon_deploy.py' $($installArguments -join ' ')"
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
