param(
    [ValidateSet(
        "Menu",
        "CheckAccess",
        "Status",
        "Metrics",
        "Stats",
        "RefreshStats",
        "Players",
        "Version",
        "Logs",
        "Announce",
        "Backup",
        "ListBackups",
        "Update",
        "Restart",
        "RestartWelcome",
        "ApiTunnelStatus",
        "StartApiTunnel",
        "StopApiTunnel",
        "StartLocalServices",
        "StopLocalServices",
        "StartupStatus",
        "InstallWindowsStartup",
        "UninstallWindowsStartup",
        "OpenMicrosite",
        "RefreshMetrics",
        "TunePerformance",
        "ValidateRepository",
        "DiagnoseIntegrations",
        "PreviewUbuntuDeploy",
        "StageUbuntuDeploy",
        "InstallUbuntuDeploy",
        "AuditUbuntuSource",
        "MaintenanceOverview"
    )]
    [string]$Action = "Menu",

    [ValidateSet("service", "game", "update", "backup", "welcome")]
    [string]$LogMode = "service",

    [int]$Lines = 120,

    [switch]$Follow,

    [switch]$NoEmoji,

    [string]$Message
)

$ErrorActionPreference = "Stop"

try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $OutputEncoding = [Console]::OutputEncoding
}
catch {
    # Best effort: older hosts may not support changing the encoding.
}

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot
$SshHost = $config.SshAlias
$SshTimeoutSeconds = 6
$LastActionExitCode = 0
$UseEmoji = -not $NoEmoji

function Get-Icon {
    param([string]$Name)

    if (-not $script:UseEmoji) {
        switch ($Name) {
            "Brand" { "[OPS]" }
            "Ok" { "[OK]" }
            "Warn" { "[!]" }
            "Error" { "[X]" }
            "Info" { "[i]" }
            "Server" { "[SRV]" }
            "Api" { "[API]" }
            "Logs" { "[LOG]" }
            "Backup" { "[BAK]" }
            "Update" { "[UPD]" }
            "Restart" { "[RST]" }
            "Windows" { "[WIN]" }
            "Web" { "[WEB]" }
            "Players" { "[PLY]" }
            "Announce" { "[MSG]" }
            "Shield" { "[SEC]" }
            "Tools" { "[TLS]" }
            "Quit" { "[Q]" }
            default { "" }
        }
        return
    }

    switch ($Name) {
        "Brand" { "🌴" }
        "Ok" { "✅" }
        "Warn" { "⚠️" }
        "Error" { "⛔" }
        "Info" { "ℹ️" }
        "Server" { "🖥️" }
        "Api" { "🔌" }
        "Logs" { "📜" }
        "Backup" { "💾" }
        "Update" { "⬆️" }
        "Restart" { "🔄" }
        "Windows" { "🪟" }
        "Web" { "🌐" }
        "Players" { "🧑‍🤝‍🧑" }
        "Announce" { "📣" }
        "Shield" { "🛡️" }
        "Tools" { "🧰" }
        "Quit" { "🚪" }
        default { "" }
    }
}

function Write-StatusLine {
    param(
        [ValidateSet("Ok", "Warn", "Error", "Info")]
        [string]$Kind,

        [string]$Text
    )

    $color = switch ($Kind) {
        "Ok" { "Green" }
        "Warn" { "Yellow" }
        "Error" { "Red" }
        "Info" { "Cyan" }
    }

    Write-Host ("{0}  {1}" -f (Get-Icon $Kind), $Text) -ForegroundColor $color
}

function Write-MenuItem {
    param(
        [string]$Number,
        [string]$Icon,
        [string]$Label,
        [string]$Hint,
        [string]$Color = "White"
    )

    Write-Host (" {0,2}. " -f $Number) -NoNewline -ForegroundColor DarkGray
    Write-Host ("{0}  {1}" -f $Icon, $Label) -NoNewline -ForegroundColor $Color
    if (-not [string]::IsNullOrWhiteSpace($Hint)) {
        Write-Host ("  - {0}" -f $Hint) -ForegroundColor DarkGray
    }
    else {
        Write-Host ""
    }
}

function Convert-Uptime {
    param([int]$Seconds)

    $span = [TimeSpan]::FromSeconds([Math]::Max(0, $Seconds))
    if ($span.Days -gt 0) {
        return "{0}j {1}h" -f $span.Days, $span.Hours
    }
    if ($span.Hours -gt 0) {
        return "{0}h {1}m" -f $span.Hours, $span.Minutes
    }
    return "{0}m" -f $span.Minutes
}

function Get-DisplayWidth {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return 0
    }

    $width = 0
    $enumerator = [System.Globalization.StringInfo]::GetTextElementEnumerator($Value)
    while ($enumerator.MoveNext()) {
        $element = [string]$enumerator.Current
        if ([string]::IsNullOrEmpty($element)) {
            continue
        }

        $category = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($element, 0)
        if ($category -in @(
            [System.Globalization.UnicodeCategory]::NonSpacingMark,
            [System.Globalization.UnicodeCategory]::SpacingCombiningMark,
            [System.Globalization.UnicodeCategory]::EnclosingMark,
            [System.Globalization.UnicodeCategory]::Control,
            [System.Globalization.UnicodeCategory]::Format
        )) {
            continue
        }

        $codePoint = [int][char]$element[0]
        $isSurrogateEmoji = $element.Length -gt 1 -and [char]::IsSurrogate($element[0])
        $isSymbolEmoji = $category -eq [System.Globalization.UnicodeCategory]::OtherSymbol
        $isWideText = (
            ($codePoint -ge 0x1100 -and $codePoint -le 0x115F) -or
            ($codePoint -ge 0x2E80 -and $codePoint -le 0xA4CF) -or
            ($codePoint -ge 0xAC00 -and $codePoint -le 0xD7A3) -or
            ($codePoint -ge 0xF900 -and $codePoint -le 0xFAFF) -or
            ($codePoint -ge 0xFE10 -and $codePoint -le 0xFE6F) -or
            ($codePoint -ge 0xFF00 -and $codePoint -le 0xFFE6)
        )

        if ($isSurrogateEmoji -or $isSymbolEmoji -or $isWideText) {
            $width += 2
        }
        else {
            $width += 1
        }
    }

    return $width
}

function Write-Title {
    param([string]$Text)

    $innerWidth = 58
    $content = " {0}  {1}" -f (Get-Icon "Brand"), $Text
    $padding = [Math]::Max(0, $innerWidth - (Get-DisplayWidth $content))

    Write-Host ""
    Write-Host ("╭{0}╮" -f ("─" * $innerWidth)) -ForegroundColor DarkCyan
    Write-Host "│" -NoNewline -ForegroundColor DarkCyan
    Write-Host $content -NoNewline -ForegroundColor Cyan
    Write-Host (" " * $padding) -NoNewline
    Write-Host "│" -ForegroundColor DarkCyan
    Write-Host ("╰{0}╯" -f ("─" * $innerWidth)) -ForegroundColor DarkCyan
}

function Pause-Menu {
    Write-Host ""
    [void](Read-Host "Entrée pour continuer")
}

function Invoke-ProjectScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptName,

        [object[]]$ArgumentList = @()
    )

    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    & $scriptPath @ArgumentList
    $script:LastActionExitCode = $LASTEXITCODE
}

function Invoke-Remote {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [switch]$Tty
    )

    $args = @()
    if ($Tty) {
        $args += "-tt"
    }

    $args += $SshHost
    $args += $Command

    & ssh.exe @args
    $script:LastActionExitCode = $LASTEXITCODE
}

function Invoke-RemoteSystemctl {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("start", "restart")]
        [string]$Verb,

        [Parameter(Mandatory = $true)]
        [string]$Unit
    )

    Invoke-Remote -Command ("sudo -n /usr/bin/systemctl {0} {1}" -f $Verb, $Unit)
}

function Test-CommandAvailable {
    param([string]$CommandName)

    return [bool](Get-Command $CommandName -ErrorAction SilentlyContinue)
}

function Test-SshAlias {
    $null = & ssh.exe -G $SshHost 2>$null
    return $LASTEXITCODE -eq 0
}

function Test-RemoteAccess {
    $null = & ssh.exe -o "BatchMode=yes" -o "ConnectTimeout=$SshTimeoutSeconds" $SshHost "hostname >/dev/null" 2>$null
    return $LASTEXITCODE -eq 0
}

function Get-RemotePalworldState {
    $output = & ssh.exe -o "BatchMode=yes" -o "ConnectTimeout=$SshTimeoutSeconds" $SshHost "systemctl is-active palworld.service 2>/dev/null || true" 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    return (($output | Out-String).Trim())
}

function Show-AccessCheck {
    Write-Title "Prévol local et SSH"

    if (Test-CommandAvailable -CommandName "ssh.exe") {
        Write-StatusLine Ok "ssh.exe: disponible"
    }
    else {
        Write-StatusLine Error "ssh.exe: introuvable dans le PATH Windows"
        Write-StatusLine Info "Installe OpenSSH Client dans Windows ou utilise PowerShell avec ssh.exe disponible."
        $script:LastActionExitCode = 1
        return
    }

    if (Test-SshAlias) {
        Write-StatusLine Ok "Alias SSH '$SshHost': configuré"
    }
    else {
        Write-StatusLine Error "Alias SSH '$SshHost': non résolu par ssh -G"
        Write-StatusLine Info "Vérifie le fichier $HOME\.ssh\config et l'entrée Host $SshHost."
        $script:LastActionExitCode = 1
        return
    }

    if (Test-RemoteAccess) {
        Write-StatusLine Ok "Connexion SSH sans invite: OK"
        $state = Get-RemotePalworldState
        if ($state -eq "active") {
            Write-StatusLine Ok "Service Palworld: actif"
        }
        elseif ($state) {
            Write-StatusLine Warn "Service Palworld: $state"
        }
        else {
            Write-StatusLine Warn "Service Palworld: état non lu"
        }
        $script:LastActionExitCode = 0
        return
    }

    Write-StatusLine Warn "Connexion SSH automatique: échec ou clé non chargée"
    Write-StatusLine Info "Essai manuel recommandé depuis ce dossier: ssh $SshHost"
    Write-StatusLine Info "Si une phrase secrète ou un mot de passe est demandé, complète-le une fois puis relance la console."
    $script:LastActionExitCode = 2
}

function Confirm-DangerousAction {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ActionName,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedText
    )

    Write-Host ""
    Write-StatusLine Warn "Action sensible: $ActionName"
    Write-StatusLine Info "Cette action peut interrompre ou affecter les joueurs connectés."
    Show-ConnectedPlayers
    Write-StatusLine Warn "Tape exactement '$ExpectedText' pour confirmer, ou laisse vide pour annuler."
    $answer = Read-Host "Confirmation"
    return $answer -eq $ExpectedText
}

function Get-ConnectedPlayers {
    try {
        $raw = & (Join-Path $PSScriptRoot "palworld-api.ps1") players 2>$null
        if ($LASTEXITCODE -ne 0) {
            return @()
        }

        $json = (($raw | Out-String).Trim() | ConvertFrom-Json)
        return @($json.players)
    }
    catch {
        return @()
    }
}

function Show-ConnectedPlayers {
    $players = Get-ConnectedPlayers
    if ($players.Count -eq 0) {
        Write-StatusLine Info "Joueurs connectés: aucun joueur listé."
        return
    }

    $names = $players | ForEach-Object {
        if ($_.name) { $_.name } elseif ($_.accountName) { $_.accountName } else { "Joueur" }
    }

    Write-StatusLine Warn ("Joueurs connectés: {0}" -f ($names -join ", "))
}

function Show-Status {
    Write-Title "État rapide"
    Invoke-ProjectScript -ScriptName "palworld-status.ps1"
}

function Show-Metrics {
    Write-Title "Métriques"
    Invoke-ProjectScript -ScriptName "palworld-api.ps1" -ArgumentList @("metrics")
}

function Show-Stats {
    Write-Title "Stats historiques"
    $statsPath = Join-Path $ProjectRoot "portal\data\stats.json"
    if (-not (Test-Path -LiteralPath $statsPath)) {
        Write-StatusLine Warn "Aucun fichier stats.json pour l’instant. Rafraîchissement en cours."
        Refresh-Stats
    }

    if (-not (Test-Path -LiteralPath $statsPath)) {
        Write-StatusLine Error "Impossible de créer ou lire portal\data\stats.json."
        return
    }

    $stats = (Get-Content -LiteralPath $statsPath -Raw) | ConvertFrom-Json
    $players = @($stats.players.PSObject.Properties | ForEach-Object { $_.Value })
    $totalSessions = ($players | Measure-Object -Property sessionCount -Sum).Sum
    $totalSeconds = ($players | Measure-Object -Property totalOnlineSeconds -Sum).Sum

    Write-StatusLine Ok ("Joueurs uniques: {0}" -f $players.Count)
    Write-StatusLine Info ("Connexions observées: {0}" -f ([int]$totalSessions))
    Write-StatusLine Info ("Temps cumulé: {0}" -f (Convert-Uptime -Seconds ([int]$totalSeconds)))
    Write-StatusLine Info ("Pic joueurs: {0}" -f $stats.server.peakPlayers)
    Write-StatusLine Info ("Échantillons collectés: {0}" -f $stats.collection.sampleCount)

    if (-not $stats.collection.gameDataAvailable) {
        Write-StatusLine Warn "Snapshot avancé /game-data non disponible actuellement. Les bases par guilde peuvent rester vides."
    }

    $topPlayers = $players |
        Sort-Object -Property @{ Expression = { [int]$_.totalOnlineSeconds }; Descending = $true } |
        Select-Object -First 10

    if ($topPlayers.Count -eq 0) {
        Write-StatusLine Info "Aucun joueur observé pour l’instant."
        return
    }

    Write-Host ""
    Write-Host "Top joueurs observés" -ForegroundColor DarkCyan
    foreach ($player in $topPlayers) {
        $status = if ($player.isOnline) { "en ligne" } else { "hors ligne" }
        Write-Host (" - {0}: {1}, {2} connexion(s), {3}" -f $player.name, $player.totalOnline, $player.sessionCount, $status)
    }
}

function Refresh-Stats {
    Write-Title "Rafraîchir les statistiques"
    try {
        Invoke-RemoteSystemctl -Verb "start" -Unit "palworld-stats.service"
        if ($script:LastActionExitCode -eq 0) {
            Start-Sleep -Seconds 1
        }
        else {
            Write-StatusLine Warn "Déclenchement serveur immédiat refusé sans sudo interactif; synchronisation du dernier snapshot disponible."
        }
        Invoke-ProjectScript -ScriptName "sync-palworld-stats.ps1"
        return
    }
    catch {
        Write-StatusLine Warn "Collecte serveur indisponible, fallback local via SSH."
        Invoke-ProjectScript -ScriptName "update-palworld-stats.ps1"
    }
}

function Show-Players {
    Write-Title "Joueurs connectés"
    Invoke-ProjectScript -ScriptName "palworld-api.ps1" -ArgumentList @("players")
}

function Show-Version {
    Write-Title "Version Palworld"
    Invoke-ProjectScript -ScriptName "palworld-version.ps1"
}

function Show-Logs {
    param(
        [string]$Mode,
        [int]$LineCount,
        [bool]$ShouldFollow
    )

    Write-Title "Logs: $Mode"

    $scriptPath = Join-Path $PSScriptRoot "palworld-logs.ps1"
    if ($ShouldFollow) {
        & $scriptPath -Mode $Mode -Lines $LineCount -Follow
    }
    else {
        & $scriptPath -Mode $Mode -Lines $LineCount
    }
}

function Send-Announcement {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        $Text = Read-Host "Message à annoncer en jeu"
    }

    if ([string]::IsNullOrWhiteSpace($Text)) {
        Write-StatusLine Warn "Annonce annulée: message vide."
        return
    }

    Write-Host ""
    Write-StatusLine Info "Annonce proposée:"
    Write-Host $Text -ForegroundColor White
    $answer = Read-Host "Envoyer cette annonce? (oui/non)"
    if ($answer -ne "oui") {
        Write-StatusLine Warn "Annonce annulée."
        return
    }

    Invoke-ProjectScript -ScriptName "palworld-announce.ps1" -ArgumentList @($Text)
}

function Start-Backup {
    Write-Title "Backup manuel"
    Write-StatusLine Info "Un backup est sûr et recommandé avant update/redémarrage."
    $answer = Read-Host "Lancer le backup maintenant? (oui/non)"
    if ($answer -ne "oui") {
        Write-StatusLine Warn "Backup annulé."
        return
    }

    Invoke-RemoteSystemctl -Verb "start" -Unit "palworld-backup.service"
    Write-StatusLine Ok "Backup demandé. Derniers logs:"
    Show-Logs -Mode "backup" -LineCount 40 -ShouldFollow:$false
}

function Show-Backups {
    Write-Title "Backups disponibles"
    Invoke-Remote -Command "ls -lh '$($config.RemotePalworldRoot)/backups'"
}

function Start-Update {
    Write-Title "Update Palworld"
    Write-StatusLine Info "Routine recommandée: annoncer aux joueurs, backup, puis update."
    $doAnnounce = Read-Host "Envoyer une annonce aux joueurs avant? (oui/non)"
    if ($doAnnounce -eq "oui") {
        Send-Announcement -Text "Maintenance Palworld à venir: sauvegarde et mise à jour du serveur."
    }

    $doBackup = Read-Host "Lancer un backup avant l'update? (oui/non)"
    if ($doBackup -eq "oui") {
        Invoke-RemoteSystemctl -Verb "start" -Unit "palworld-backup.service"
    }

    if (-not (Confirm-DangerousAction -ActionName "Mise à jour Palworld" -ExpectedText "UPDATE")) {
        Write-StatusLine Warn "Update annulée."
        return
    }

    Invoke-RemoteSystemctl -Verb "start" -Unit "palworld-update.service"
    Write-StatusLine Ok "Update demandée. Derniers logs:"
    Show-Logs -Mode "update" -LineCount 80 -ShouldFollow:$false
}

function Restart-Palworld {
    Write-Title "Redémarrage Palworld"
    $doAnnounce = Read-Host "Envoyer une annonce aux joueurs avant? (oui/non)"
    if ($doAnnounce -eq "oui") {
        Send-Announcement -Text "Redémarrage du serveur Palworld dans quelques instants."
    }

    $doBackup = Read-Host "Lancer un backup avant le redémarrage? (oui/non)"
    if ($doBackup -eq "oui") {
        Invoke-RemoteSystemctl -Verb "start" -Unit "palworld-backup.service"
    }

    if (-not (Confirm-DangerousAction -ActionName "Redémarrage du serveur Palworld" -ExpectedText "RESTART")) {
        Write-StatusLine Warn "Redémarrage annulé."
        return
    }

    Write-StatusLine Info "Application du profil serveur avant le redémarrage."
    Invoke-Remote -Command "sudo -n '$($config.RemoteSteamRoot)/bin/palworld-configure-balanced.sh'"
    if ($script:LastActionExitCode -ne 0) {
        Write-StatusLine Error "Configuration serveur refusée ou échouée; redémarrage annulé."
        return
    }

    Invoke-RemoteSystemctl -Verb "restart" -Unit "palworld.service"
    Write-StatusLine Ok "Redémarrage demandé. État actuel:"
    Invoke-Remote -Command "systemctl status palworld.service --no-pager -l"
}

function Restart-WelcomeWatcher {
    Write-Title "Redémarrage du watcher de bienvenue"
    $answer = Read-Host "Redémarrer palworld-welcome.service? (oui/non)"
    if ($answer -ne "oui") {
        Write-StatusLine Warn "Action annulée."
        return
    }

    Invoke-RemoteSystemctl -Verb "restart" -Unit "palworld-welcome.service"
    Invoke-Remote -Command "systemctl status palworld-welcome.service --no-pager -l"
}

function Tune-Performance {
    Write-Title "Priorité Palworld"
    Write-StatusLine Info "Application du profil performance sans redémarrage du serveur de jeu."
    Invoke-RemoteSystemctl -Verb "start" -Unit "palworld-performance.service"
    if ($script:LastActionExitCode -eq 0) {
        Write-StatusLine Ok "Profil performance appliqué."
    }
}

function Show-ApiTunnelStatus {
    Invoke-ProjectScript -ScriptName "palworld-api-tunnel.ps1" -ArgumentList @("status")
}

function Start-ApiTunnel {
    Invoke-ProjectScript -ScriptName "palworld-api-tunnel.ps1" -ArgumentList @("start")
}

function Stop-ApiTunnel {
    Invoke-ProjectScript -ScriptName "palworld-api-tunnel.ps1" -ArgumentList @("stop")
}

function Start-LocalServices {
    Invoke-ProjectScript -ScriptName "start-local-services.ps1"
}

function Stop-LocalServices {
    Invoke-ProjectScript -ScriptName "stop-local-services.ps1"
}

function Show-StartupStatus {
    Invoke-ProjectScript -ScriptName "windows-startup-status.ps1"
}

function Install-WindowsStartup {
    Invoke-ProjectScript -ScriptName "install-windows-startup.ps1"
}

function Uninstall-WindowsStartup {
    Write-Title "Désinstaller l'autostart Windows"
    $answer = Read-Host "Supprimer la tâche planifiée Gaylemon Ops Local Services? (oui/non)"
    if ($answer -ne "oui") {
        Write-StatusLine Warn "Action annulée."
        return
    }

    Invoke-ProjectScript -ScriptName "uninstall-windows-startup.ps1"
}

function Open-Microsite {
    Write-Title "Microsite"
    Invoke-ProjectScript -ScriptName "open-microsite.ps1"
}

function Refresh-MicrositeMetrics {
    Write-Title "Rafraîchir les métriques du microsite"
    Invoke-ProjectScript -ScriptName "update-microsite-metrics.ps1"
}

function Validate-Repository {
    Write-Title "Validation du dépôt"
    Invoke-ProjectScript -ScriptName "valider-depot.ps1"
}

function Diagnose-Integrations {
    Write-Title "Diagnostic des intégrations"
    Invoke-ProjectScript -ScriptName "diagnostiquer-integrations.ps1"
}

function Preview-UbuntuDeploy {
    Write-Title "Aperçu du déploiement Ubuntu"
    Invoke-ProjectScript -ScriptName "deployer-ubuntu.ps1"
}

function Stage-UbuntuDeploy {
    Write-Title "Mise en scène du déploiement Ubuntu"
    Invoke-ProjectScript -ScriptName "deployer-ubuntu.ps1" -ArgumentList @("-Stage")
}

function Install-UbuntuDeploy {
    Write-Title "Installation contrôlée sur Ubuntu"
    Write-StatusLine Warn "Les fichiers modifiés seront sauvegardés; aucun service ne redémarrera par défaut."
    Invoke-ProjectScript -ScriptName "deployer-ubuntu.ps1" -ArgumentList @("-Install")
}

function Audit-UbuntuSource {
    Write-Title "Audit de la source Ubuntu"
    Invoke-ProjectScript -ScriptName "auditer-source-ubuntu.ps1"
}

function Show-MaintenanceOverview {
    Write-Title "Bilan général de maintenance"
    Invoke-ProjectScript -ScriptName "auditer-maintenance.ps1"
}

function Show-UbuntuMaintenanceMenu {
    while ($true) {
        Write-Title "Maintenance Ubuntu"
        Write-StatusLine Info "Le serveur de jeu n'est jamais redémarré implicitement."
        Write-Host ""
        Write-MenuItem "1" (Get-Icon "Shield") "Auditer la source active" "lecture seule" "Cyan"
        Write-MenuItem "2" (Get-Icon "Server") "Prévisualiser la livraison" "aucun contact distant" "Yellow"
        Write-MenuItem "3" (Get-Icon "Update") "Mettre en scène sur Ubuntu" "validation puis copie sous /tmp" "Blue"
        Write-MenuItem "4" (Get-Icon "Tools") "Installer les changements" "backup atomique, confirmation et un sudo" "Red"
        Write-MenuItem "0" (Get-Icon "Quit") "Retour" "" "DarkGray"
        $choice = Read-Host "Choix"

        switch ($choice) {
            "1" { Audit-UbuntuSource; Pause-Menu }
            "2" { Preview-UbuntuDeploy; Pause-Menu }
            "3" { Stage-UbuntuDeploy; Pause-Menu }
            "4" { Install-UbuntuDeploy; Pause-Menu }
            "0" { return }
            default { Write-StatusLine Warn "Choix invalide." }
        }
    }
}

function Show-LogsMenu {
    while ($true) {
        Write-Title "Choisir un log"
        Write-MenuItem "1" (Get-Icon "Server") "Service Palworld" "journal systemd principal" "Green"
        Write-MenuItem "2" (Get-Icon "Logs") "Log jeu Pal.log" "événements bruts du serveur" "Cyan"
        Write-MenuItem "3" (Get-Icon "Announce") "Welcome watcher" "messages de bienvenue" "Yellow"
        Write-MenuItem "4" (Get-Icon "Update") "Update" "mises à jour SteamCMD" "Blue"
        Write-MenuItem "5" (Get-Icon "Backup") "Backup" "sauvegardes locales" "DarkGreen"
        Write-MenuItem "0" (Get-Icon "Quit") "Retour" "" "DarkGray"
        $choice = Read-Host "Choix"

        $mode = switch ($choice) {
            "1" { "service" }
            "2" { "game" }
            "3" { "welcome" }
            "4" { "update" }
            "5" { "backup" }
            "0" { return }
            default { $null }
        }

        if (-not $mode) {
            Write-StatusLine Warn "Choix invalide."
            continue
        }

        $followAnswer = Read-Host "Suivre en direct? (oui/non)"
        $lineAnswer = Read-Host "Nombre de lignes [120]"
        $lineCount = if ($lineAnswer -as [int]) { [int]$lineAnswer } else { 120 }
        Show-Logs -Mode $mode -LineCount $lineCount -ShouldFollow:($followAnswer -eq "oui")
        Pause-Menu
    }
}

function Show-MainMenu {
    while ($true) {
        Write-Title "Gaylémon Ops"
        Write-Host " Serveur" -ForegroundColor DarkCyan
        Write-MenuItem "1" (Get-Icon "Server") "État rapide" "services, timers, ports" "Green"
        Write-MenuItem "2" (Get-Icon "Shield") "Prévol SSH/local" "diagnostic d'accès" "Cyan"
        Write-MenuItem "5" (Get-Icon "Update") "Vérifier la version Steam" "build installée vs publique" "Blue"
        Write-MenuItem "6" (Get-Icon "Logs") "Logs" "suivi en direct ou historique" "DarkYellow"

        Write-Host ""
        Write-Host " Jeu et API" -ForegroundColor DarkCyan
        Write-MenuItem "3" (Get-Icon "Api") "Métriques API" "FPS, uptime, camps" "Cyan"
        Write-MenuItem "4" (Get-Icon "Players") "Joueurs connectés" "liste REST Palworld" "Yellow"
        Write-MenuItem "7" (Get-Icon "Announce") "Envoyer une annonce" "message visible en jeu" "Magenta"
        Write-MenuItem "25" (Get-Icon "Players") "Stats historiques" "connexions, temps, joueurs" "Cyan"
        Write-MenuItem "26" (Get-Icon "Api") "Rafraîchir les stats" "force la collecte locale" "Cyan"

        Write-Host ""
        Write-Host " Maintenance" -ForegroundColor DarkCyan
        Write-MenuItem "8" (Get-Icon "Backup") "Lancer un backup" "confirmation requise" "Green"
        Write-MenuItem "9" (Get-Icon "Backup") "Lister les backups" "archives disponibles" "DarkGreen"
        Write-MenuItem "10" (Get-Icon "Update") "Lancer une update" "annonce, backup, confirmation UPDATE" "Blue"
        Write-MenuItem "11" (Get-Icon "Restart") "Appliquer la config et redémarrer Palworld" "confirmation RESTART" "Red"
        Write-MenuItem "12" (Get-Icon "Restart") "Redémarrer le watcher de bienvenue" "" "Yellow"
        Write-MenuItem "31" (Get-Icon "Server") "Réappliquer la priorité Palworld" "sans redémarrage" "Green"

        Write-Host ""
        Write-Host " Local Windows" -ForegroundColor DarkCyan
        Write-MenuItem "14" (Get-Icon "Web") "Ouvrir le microsite" $config.MicrositePublicUrl "Cyan"
        Write-MenuItem "16" (Get-Icon "Api") "Rafraîchir les métriques du microsite" "" "Cyan"
        Write-MenuItem "17" (Get-Icon "Api") "Statut du tunnel API Docker" "uptime/annonces" "Green"
        Write-MenuItem "18" (Get-Icon "Api") "Démarrer le tunnel API Docker" "" "Green"
        Write-MenuItem "19" (Get-Icon "Api") "Arrêter le tunnel API Docker" "" "Yellow"
        Write-MenuItem "20" (Get-Icon "Windows") "Démarrer les services locaux Windows" "tunnel Docker, microsite, métriques" "Green"
        Write-MenuItem "21" (Get-Icon "Windows") "Arrêter les services locaux Windows" "" "Yellow"
        Write-MenuItem "22" (Get-Icon "Windows") "Statut autostart Windows" "" "Cyan"
        Write-MenuItem "23" (Get-Icon "Windows") "Installer autostart Windows" "" "Green"
        Write-MenuItem "24" (Get-Icon "Windows") "Désinstaller autostart Windows" "" "Red"

        Write-Host ""
        Write-Host " Projet" -ForegroundColor DarkCyan
        Write-MenuItem "27" (Get-Icon "Shield") "Valider le dépôt" "tests locaux sans toucher aux services" "Green"
        Write-MenuItem "28" (Get-Icon "Tools") "Diagnostiquer les intégrations" "lecture seule" "Cyan"
        Write-MenuItem "29" (Get-Icon "Server") "Maintenance Ubuntu guidée" "audit, aperçu, mise en scène et installation" "Yellow"
        Write-MenuItem "30" (Get-Icon "Shield") "Bilan général de maintenance" "dépôt, Ubuntu, Docker et intégrations" "Green"

        Write-Host ""
        Write-MenuItem "0" (Get-Icon "Quit") "Quitter" "" "DarkGray"

        $choice = Read-Host "Choix"
        switch ($choice) {
            "1" { Show-Status; Pause-Menu }
            "2" { Show-AccessCheck; Pause-Menu }
            "3" { Show-Metrics; Pause-Menu }
            "4" { Show-Players; Pause-Menu }
            "5" { Show-Version; Pause-Menu }
            "6" { Show-LogsMenu }
            "7" { Send-Announcement -Text $Message; Pause-Menu }
            "8" { Start-Backup; Pause-Menu }
            "9" { Show-Backups; Pause-Menu }
            "10" { Start-Update; Pause-Menu }
            "11" { Restart-Palworld; Pause-Menu }
            "12" { Restart-WelcomeWatcher; Pause-Menu }
            "14" { Open-Microsite; Pause-Menu }
            "16" { Refresh-MicrositeMetrics; Pause-Menu }
            "17" { Show-ApiTunnelStatus; Pause-Menu }
            "18" { Start-ApiTunnel; Pause-Menu }
            "19" { Stop-ApiTunnel; Pause-Menu }
            "20" { Start-LocalServices; Pause-Menu }
            "21" { Stop-LocalServices; Pause-Menu }
            "22" { Show-StartupStatus; Pause-Menu }
            "23" { Install-WindowsStartup; Pause-Menu }
            "24" { Uninstall-WindowsStartup; Pause-Menu }
            "25" { Show-Stats; Pause-Menu }
            "26" { Refresh-Stats; Pause-Menu }
            "27" { Validate-Repository; Pause-Menu }
            "28" { Diagnose-Integrations; Pause-Menu }
            "29" { Show-UbuntuMaintenanceMenu }
            "30" { Show-MaintenanceOverview; Pause-Menu }
            "31" { Tune-Performance; Pause-Menu }
            "0" { return }
            default { Write-StatusLine Warn "Choix invalide." }
        }
    }
}

switch ($Action) {
    "Menu" { Show-MainMenu }
    "CheckAccess" { Show-AccessCheck }
    "Status" { Show-Status }
    "Metrics" { Show-Metrics }
    "Stats" { Show-Stats }
    "RefreshStats" { Refresh-Stats }
    "Players" { Show-Players }
    "Version" { Show-Version }
    "Logs" { Show-Logs -Mode $LogMode -LineCount $Lines -ShouldFollow:$Follow }
    "Announce" { Send-Announcement -Text $Message }
    "Backup" { Start-Backup }
    "ListBackups" { Show-Backups }
    "Update" { Start-Update }
    "Restart" { Restart-Palworld }
    "RestartWelcome" { Restart-WelcomeWatcher }
    "TunePerformance" { Tune-Performance }
    "ApiTunnelStatus" { Show-ApiTunnelStatus }
    "StartApiTunnel" { Start-ApiTunnel }
    "StopApiTunnel" { Stop-ApiTunnel }
    "StartLocalServices" { Start-LocalServices }
    "StopLocalServices" { Stop-LocalServices }
    "StartupStatus" { Show-StartupStatus }
    "InstallWindowsStartup" { Install-WindowsStartup }
    "UninstallWindowsStartup" { Uninstall-WindowsStartup }
    "OpenMicrosite" { Open-Microsite }
    "RefreshMetrics" { Refresh-MicrositeMetrics }
    "ValidateRepository" { Validate-Repository }
    "DiagnoseIntegrations" { Diagnose-Integrations }
    "PreviewUbuntuDeploy" { Preview-UbuntuDeploy }
    "StageUbuntuDeploy" { Stage-UbuntuDeploy }
    "InstallUbuntuDeploy" { Install-UbuntuDeploy }
    "AuditUbuntuSource" { Audit-UbuntuSource }
    "MaintenanceOverview" { Show-MaintenanceOverview }
}

exit $LastActionExitCode
