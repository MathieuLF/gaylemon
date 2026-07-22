param(
    [string]$TaskName = ""
)

$ErrorActionPreference = "Continue"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot
if (-not $TaskName) { $TaskName = $config.StartupTaskName }

$StartupFolder = [Environment]::GetFolderPath("Startup")
$StartupLauncher = Join-Path $StartupFolder "$TaskName.cmd"
$RunKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$RunValue = Get-ItemPropertyValue -Path $RunKey -Name $TaskName -ErrorAction SilentlyContinue

$task = if ($RunValue) {
    $null
}
else {
    Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
}
if ($task) {
    $info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
    Write-Host "✅ Tâche planifiée: installée" -ForegroundColor Green
    Write-Host "État: $($task.State)"
    if ($info) {
        Write-Host "Dernière exécution: $($info.LastRunTime)"
        Write-Host "Dernier résultat: $($info.LastTaskResult)"
        Write-Host "Prochaine exécution: $($info.NextRunTime)"
    }
}
else {
    Write-Host "ℹ️  Tâche planifiée: non installée" -ForegroundColor DarkGray
}

if ($RunValue) {
    Write-Host "✅ Démarrage utilisateur: installé" -ForegroundColor Green
    Write-Host "Entrée: $TaskName"
}
else {
    Write-Host "ℹ️  Démarrage utilisateur: non installé" -ForegroundColor DarkGray
}

if (Test-Path -LiteralPath $StartupLauncher) {
    Write-Host "✅ Lanceur Startup: installé" -ForegroundColor Green
    Write-Host "Chemin du lanceur: $StartupLauncher"
}
else {
    $launcherColor = if ($task -or $RunValue) { "DarkGray" } else { "Yellow" }
    $launcherPrefix = if ($task -or $RunValue) { "ℹ️ " } else { "⚠️ " }
    Write-Host "$launcherPrefix Lanceur Startup: non installé" -ForegroundColor $launcherColor
}

Write-Host ""
& (Join-Path $PSScriptRoot "palworld-api-tunnel.ps1") status

Write-Host ""
$originUrl = $config.MicrositeOriginUrl
$publicUrl = $config.MicrositePublicUrl
try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $originUrl -TimeoutSec 2
    Write-Host "✅ Microsite origine locale: HTTP $($response.StatusCode) sur $originUrl" -ForegroundColor Green
}
catch {
    Write-Host "⚠️  Microsite origine locale: non joignable sur $originUrl" -ForegroundColor Yellow
}

try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $publicUrl -TimeoutSec 8
    Write-Host "✅ Microsite public: HTTP $($response.StatusCode) sur $publicUrl" -ForegroundColor Green
}
catch {
    Write-Host "⚠️  Microsite public: non joignable sur $publicUrl" -ForegroundColor Yellow
}

Write-Host ""
if (Get-Command docker -ErrorAction SilentlyContinue) {
    try {
        $container = & docker ps --filter "name=$($config.DockerMicrositeContainer)" --format "{{.Names}}|{{.Status}}|{{.Ports}}" 2>$null | Select-Object -First 1
        if ($container) {
            $parts = $container -split "\|", 3
            Write-Host "✅ Docker microsite: $($parts[0])" -ForegroundColor Green
            Write-Host "État: $($parts[1])"
            if ($parts.Count -gt 2) {
                Write-Host "Ports: $($parts[2])"
            }
        }
        else {
            Write-Host "⚠️  Docker microsite: conteneur non démarré" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "⚠️  Docker microsite: vérification impossible ($($_.Exception.Message))" -ForegroundColor Yellow
    }
}
else {
    Write-Host "⚠️  Docker CLI: introuvable" -ForegroundColor Yellow
}

Write-Host ""
$watcherPidPath = Join-Path $PSScriptRoot "..\portal\data\metrics-watcher.pid"
$watcherLogPath = Join-Path $PSScriptRoot "..\portal\data\metrics-watcher.log"
$watcherProcess = $null
$watcherPid = $null

if (Test-Path -LiteralPath $watcherPidPath) {
    $pidValue = Get-Content -LiteralPath $watcherPidPath -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pidValue -as [int]) {
        $watcherPid = [int]$pidValue
        $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $watcherPid" -ErrorAction SilentlyContinue
        if ($processInfo -and $processInfo.CommandLine -and $processInfo.CommandLine.Contains("watch-microsite-metrics.ps1")) {
            $watcherProcess = $processInfo
        }
    }
}

if (-not $watcherProcess) {
    $watcherProcess = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains("watch-microsite-metrics.ps1") } |
        Select-Object -First 1
}

if ($watcherProcess) {
    Write-Host "✅ Rafraîchisseur microsite: actif" -ForegroundColor Green
    Write-Host "PID: $($watcherProcess.ProcessId)"
}
elseif ($watcherPid) {
    Write-Host "⚠️  Rafraîchisseur microsite: PID stale ($watcherPid), processus absent" -ForegroundColor Yellow
}
else {
    Write-Host "⚠️  Rafraîchisseur microsite: non actif" -ForegroundColor Yellow
}

$publicMetricsPath = Join-Path $PSScriptRoot "..\portal\data\public-metrics.json"
if (Test-Path -LiteralPath $publicMetricsPath) {
    $metricsItem = Get-Item -LiteralPath $publicMetricsPath
    $ageSeconds = [int][Math]::Max(0, ((Get-Date).ToUniversalTime() - $metricsItem.LastWriteTimeUtc).TotalSeconds)
    $freshLimitSeconds = [Math]::Max(90, $config.MetricUpdateTimeoutSeconds + ($config.MetricIntervalSeconds * 2))
    $freshnessColor = if ($ageSeconds -le $freshLimitSeconds) { "Green" } else { "Yellow" }
    Write-Host "Dernier export public-metrics: ${ageSeconds}s" -ForegroundColor $freshnessColor
}

$publicSaveIndexPath = Join-Path $PSScriptRoot "..\portal\data\public-save-index.json"
if (Test-Path -LiteralPath $publicSaveIndexPath) {
    try {
        $saveIndex = Get-Content -Raw -Encoding UTF8 -LiteralPath $publicSaveIndexPath | ConvertFrom-Json
        $snapshotSourceAt = $null
        $parsedSnapshotSourceAt = [DateTimeOffset]::MinValue
        $snapshotSourceValue = if ($saveIndex.provenance -and $saveIndex.provenance.sourceUpdatedAt) {
            $saveIndex.provenance.sourceUpdatedAt
        }
        else {
            $saveIndex.updatedAt
        }
        if ($snapshotSourceValue -is [DateTimeOffset]) {
            $snapshotSourceAt = $snapshotSourceValue
        }
        elseif ($snapshotSourceValue -is [datetime]) {
            $snapshotSourceAt = [DateTimeOffset]::new($snapshotSourceValue.ToUniversalTime(), [TimeSpan]::Zero)
        }
        elseif ($snapshotSourceValue -and [DateTimeOffset]::TryParse([string]$snapshotSourceValue, [ref]$parsedSnapshotSourceAt)) {
            $snapshotSourceAt = $parsedSnapshotSourceAt
        }

        $snapshotAgeSeconds = if ($snapshotSourceAt) {
            $nowOffset = [DateTimeOffset]::new((Get-Date).ToUniversalTime(), [TimeSpan]::Zero)
            [int][Math]::Max(0, ($nowOffset - $snapshotSourceAt.ToUniversalTime()).TotalSeconds)
        }
        else {
            [int][Math]::Max(0, ((Get-Date).ToUniversalTime() - (Get-Item -LiteralPath $publicSaveIndexPath).LastWriteTimeUtc).TotalSeconds)
        }
        $snapshotFreshLimitSeconds = [Math]::Max(120, $config.SaveSnapshotSyncTimeoutSeconds + ($config.SaveSnapshotSyncIntervalSeconds * 2))
        $snapshotFreshnessColor = if ($snapshotAgeSeconds -le $snapshotFreshLimitSeconds) { "Green" } else { "Yellow" }
        Write-Host "Dernier snapshot joueurs: ${snapshotAgeSeconds}s, génération $($saveIndex.generationId)" -ForegroundColor $snapshotFreshnessColor
    }
    catch {
        Write-Host "⚠️  Snapshot joueurs local illisible: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

if (Test-Path -LiteralPath $watcherLogPath) {
    $lastWatcherLine = Get-Content -LiteralPath $watcherLogPath -Tail 120 -ErrorAction SilentlyContinue |
        Where-Object { $_ -match "Metrics update (completed|skipped)|(?:Metrics|Microsite) watcher (started|stopped)|Save snapshot sync (started|completed|skipped)" } |
        Select-Object -Last 1
    if ($lastWatcherLine) {
        Write-Host "Dernier log watcher: $lastWatcherLine"
    }
}

Write-Host ""
$recoveryReportPath = Join-Path $PSScriptRoot "..\runtime\recovery\microsite-recovery-latest.json"
if (Test-Path -LiteralPath $recoveryReportPath) {
    try {
        $recovery = Get-Content -Raw -Encoding UTF8 -LiteralPath $recoveryReportPath | ConvertFrom-Json
        $recoveryColor = if ($recovery.status -eq "complete") { "Green" } elseif ($recovery.status -eq "warning") { "Yellow" } else { "Red" }
        Write-Host "Audit de reprise: $($recovery.status)" -ForegroundColor $recoveryColor
        Write-Host "Vérifié: $($recovery.checkedAt)"
        Write-Host "Dernier événement synchronisé: $($recovery.synchronization.lastEventSynchronizedAt)"
        Write-Host "Archives réimportées: $($recovery.continuity.archivesImported)"
        Write-Host "Heures manquantes: $(@($recovery.continuity.missingHours).Count)"
        Write-Host "Rapport: $recoveryReportPath"
    }
    catch {
        Write-Host "⚠️  Rapport de reprise illisible: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
else {
    Write-Host "ℹ️  Aucun audit de reprise local n'a encore été exécuté." -ForegroundColor DarkGray
}

Write-Host ""
$availabilityPath = Join-Path $PSScriptRoot "..\portal\data\public-availability.json"
if (Test-Path -LiteralPath $availabilityPath) {
    try {
        $availability = Get-Content -Raw -Encoding UTF8 -LiteralPath $availabilityPath | ConvertFrom-Json
        $availabilityColor = if ($availability.status -eq "up") { "Green" } elseif ($availability.status -eq "down") { "Red" } else { "Yellow" }
        Write-Host "Disponibilité locale: $($availability.status)" -ForegroundColor $availabilityColor
        Write-Host "Moniteur Kuma: $($availability.summary.monitorStatus)"
        Write-Host "Dernier heartbeat: $($availability.summary.heartbeatAgeSeconds)s"
        Write-Host "Exports stale/manquants: $($availability.summary.staleOrMissingDataSets)"
    }
    catch {
        Write-Host "⚠️  Disponibilité locale illisible: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
else {
    Write-Host "ℹ️  Aucun ledger de disponibilité local n'a encore été généré." -ForegroundColor DarkGray
}
