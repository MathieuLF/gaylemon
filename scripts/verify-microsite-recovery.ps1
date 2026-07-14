param(
    [ValidateSet("manual", "microsite-startup", "watcher-retry")]
    [string]$Trigger = "manual",
    [string]$ReportRoot = (Join-Path $PSScriptRoot "..\runtime\recovery"),
    [switch]$SkipRepair
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot
$LocalEventsPath = Join-Path $ProjectRoot "portal\data\public-events.json"
$LocalSnapshotPath = Join-Path $ProjectRoot "portal\data\public-save-snapshot.json"
$RemoteEventsPath = "$($config.RemoteProjectRoot)/runtime/public-events.json"
$RemoteRecoveryPath = "$($config.RemoteProjectRoot)/runtime/events/palworld-events-recovery.json"
$LatestReportPath = Join-Path $ReportRoot "microsite-recovery-latest.json"
$HistoryReportPath = Join-Path $ReportRoot "microsite-recovery-history.jsonl"

function Read-JsonFile {
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Fichier JSON introuvable: $Path"
    }
    return (Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json)
}

function Read-RemoteJson {
    param([Parameter(Mandatory)] [string]$Path)

    $raw = & ssh.exe $config.SshAlias "test -s '$Path' && gzip -c '$Path' | base64 -w0" 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Fichier distant indisponible: $Path"
    }
    $base64 = (($raw | Out-String).Trim())
    if (-not $base64) {
        throw "Fichier distant vide: $Path"
    }
    $compressed = [Convert]::FromBase64String($base64)
    $input = [IO.MemoryStream]::new($compressed, $false)
    $gzip = [IO.Compression.GZipStream]::new($input, [IO.Compression.CompressionMode]::Decompress)
    $reader = [IO.StreamReader]::new($gzip, [Text.Encoding]::UTF8, $true)
    try {
        return ($reader.ReadToEnd() | ConvertFrom-Json)
    }
    finally {
        $reader.Dispose()
        $gzip.Dispose()
        $input.Dispose()
    }
}

function Convert-ToDate {
    param($Value)

    if (-not $Value) { return $null }
    $parsed = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse([string]$Value, [ref]$parsed)) { return $parsed }
    return $null
}

function Convert-ToIsoString {
    param($Value)

    $parsed = Convert-ToDate $Value
    if ($parsed) { return $parsed.ToString("o") }
    if ($null -eq $Value -or -not [string]$Value) { return $null }
    return [string]$Value
}

function Convert-ToStringArray {
    param($Values)

    return @($Values | Where-Object { $null -ne $_ -and [string]$_ } | ForEach-Object { [string]$_ })
}

function Convert-ToIsoArray {
    param($Values)

    return @($Values | Where-Object { $null -ne $_ } | ForEach-Object { Convert-ToIsoString $_ })
}

function Get-RecoveryState {
    $remoteEvents = Read-RemoteJson -Path $RemoteEventsPath
    $remoteRecovery = Read-RemoteJson -Path $RemoteRecoveryPath
    $localEvents = Read-JsonFile -Path $LocalEventsPath
    $localSnapshot = Read-JsonFile -Path $LocalSnapshotPath

    $remoteEventCount = [long]$remoteEvents.summary.events
    $localEventCount = [long]$localEvents.summary.events
    $remoteLastEventAt = Convert-ToDate $remoteEvents.summary.lastAt
    $localLastEventAt = Convert-ToDate $localEvents.summary.lastAt
    $remoteSnapshotAt = Convert-ToDate $remoteRecovery.currentSnapshotAt
    if ($null -eq $remoteSnapshotAt) {
        $remoteSnapshotAt = Convert-ToDate $remoteRecovery.lastSaveAt
    }
    $localSnapshotAt = Convert-ToDate $localSnapshot.updatedAt

    $eventsCaughtUp = $localEventCount -ge $remoteEventCount
    if ($remoteLastEventAt) {
        $eventsCaughtUp = $eventsCaughtUp -and $localLastEventAt -and $localLastEventAt -ge $remoteLastEventAt
    }
    $snapshotCaughtUp = $localSnapshotAt -and $remoteSnapshotAt -and $localSnapshotAt -ge $remoteSnapshotAt

    return [pscustomobject]@{
        RemoteEvents = $remoteEvents
        RemoteRecovery = $remoteRecovery
        LocalEvents = $localEvents
        LocalSnapshot = $localSnapshot
        RemoteEventCount = $remoteEventCount
        LocalEventCount = $localEventCount
        RemoteLastEventAt = $remoteLastEventAt
        LocalLastEventAt = $localLastEventAt
        RemoteSnapshotAt = $remoteSnapshotAt
        LocalSnapshotAt = $localSnapshotAt
        EventsCaughtUp = [bool]$eventsCaughtUp
        SnapshotCaughtUp = [bool]$snapshotCaughtUp
    }
}

function Repair-RecoveryState {
    & (Join-Path $PSScriptRoot "sync-palworld-save-snapshot.ps1") | Out-Null
    & (Join-Path $PSScriptRoot "sync-palworld-events.ps1") | Out-Null
}

function Write-RecoveryReport {
    param([Parameter(Mandatory)] $Report)

    New-Item -ItemType Directory -Force -Path $ReportRoot | Out-Null
    $resolvedLatest = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LatestReportPath)
    $temporary = "$resolvedLatest.tmp"
    $prettyJson = $Report | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText($temporary, $prettyJson.TrimEnd() + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $resolvedLatest -Force

    $compactJson = $Report | ConvertTo-Json -Depth 12 -Compress
    [IO.File]::AppendAllText(
        $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($HistoryReportPath),
        $compactJson + [Environment]::NewLine,
        [Text.UTF8Encoding]::new($false)
    )

    $history = Get-Item -LiteralPath $HistoryReportPath -ErrorAction SilentlyContinue
    if ($history -and $history.Length -gt 2MB) {
        $tail = @(Get-Content -LiteralPath $HistoryReportPath -Tail 500)
        [IO.File]::WriteAllLines($history.FullName, $tail, [Text.UTF8Encoding]::new($false))
    }
}

$checkedAt = (Get-Date).ToString("o")
$repairAttempted = $false
$messages = [Collections.Generic.List[string]]::new()
$state = $null
$failure = $null

try {
    $state = Get-RecoveryState
    if ((-not $state.EventsCaughtUp -or -not $state.SnapshotCaughtUp) -and -not $SkipRepair) {
        $repairAttempted = $true
        $messages.Add("La copie locale était en retard; une resynchronisation ciblée a été exécutée.")
        Repair-RecoveryState
        $state = Get-RecoveryState
    }
}
catch {
    $failure = $_.Exception.Message
    $messages.Add("Audit interrompu: $failure")
}

$hardFailure = $failure -or -not $state -or -not $state.EventsCaughtUp -or -not $state.SnapshotCaughtUp
$lastBackfill = if ($state) { $state.RemoteRecovery.lastBackfill } else { $null }
$missingHours = @()
if ($lastBackfill -and $lastBackfill.missingHours) {
    $missingHours = Convert-ToIsoArray $lastBackfill.missingHours
}
elseif ($state -and $state.RemoteRecovery.archives.missingHours) {
    $missingHours = Convert-ToIsoArray $state.RemoteRecovery.archives.missingHours
}
$lastBackfillReport = $null
if ($lastBackfill) {
    $lastBackfillReport = [ordered]@{
        completedAt = Convert-ToIsoString $lastBackfill.completedAt
        fromSaveAt = Convert-ToIsoString $lastBackfill.fromSaveAt
        toSaveAt = Convert-ToIsoString $lastBackfill.toSaveAt
        gapSeconds = $lastBackfill.gapSeconds
        archivesImported = $lastBackfill.archivesImported
        importedHours = [object[]]@(Convert-ToStringArray $lastBackfill.importedHours)
        missingHours = [object[]]@(Convert-ToIsoArray $lastBackfill.missingHours)
        eventsAdded = $lastBackfill.eventsAdded
    }
}
$currentImportedHours = [object[]]@()
if ($state) {
    $currentImportedHours = [object[]]@(Convert-ToStringArray $state.RemoteRecovery.archives.importedHours)
}

if (-not $hardFailure) {
    $messages.Add("Le snapshot public et le journal local couvrent les dernières données Ubuntu.")
}
if ($missingHours.Count) {
    $messages.Add("Des archives horaires historiques sont absentes: $($missingHours -join ', ').")
}

$status = if ($hardFailure) { "error" } elseif ($missingHours.Count) { "warning" } else { "complete" }
$report = [ordered]@{
    version = 1
    ok = -not [bool]$hardFailure
    status = $status
    checkedAt = $checkedAt
    trigger = $Trigger
    repairAttempted = $repairAttempted
    synchronization = [ordered]@{
        eventsCaughtUp = if ($state) { $state.EventsCaughtUp } else { $false }
        snapshotCaughtUp = if ($state) { $state.SnapshotCaughtUp } else { $false }
        remoteEventRevision = if ($state) { [string]$state.RemoteEvents.revision } else { $null }
        localEventRevision = if ($state) { [string]$state.LocalEvents.revision } else { $null }
        remoteEventCount = if ($state) { $state.RemoteEventCount } else { $null }
        localEventCount = if ($state) { $state.LocalEventCount } else { $null }
        lastEventSynchronizedAt = if ($state) { Convert-ToIsoString $state.LocalEvents.summary.lastAt } else { $null }
        remoteSnapshotAt = if ($state -and $state.RemoteSnapshotAt) { $state.RemoteSnapshotAt.ToString("o") } else { $null }
        localSnapshotAt = if ($state -and $state.LocalSnapshotAt) { $state.LocalSnapshotAt.ToString("o") } else { $null }
    }
    continuity = [ordered]@{
        currentStatus = if ($state) { [string]$state.RemoteRecovery.status } else { "unknown" }
        previousLastSaveAt = if ($state) { Convert-ToIsoString $state.RemoteRecovery.previousLastSaveAt } else { $null }
        lastSaveAt = if ($state) { Convert-ToIsoString $state.RemoteRecovery.lastSaveAt } else { $null }
        currentGapSeconds = if ($state) { $state.RemoteRecovery.gapSeconds } else { $null }
        archivesScanned = if ($state) { $state.RemoteRecovery.archives.scanned } else { $null }
        archivesImported = if ($state) { $state.RemoteRecovery.archives.imported } else { $null }
        importedHours = $currentImportedHours
        missingHours = [object[]]$missingHours
        lastBackfill = $lastBackfillReport
    }
    messages = @($messages)
}

Write-RecoveryReport -Report $report

$color = if ($status -eq "complete") { "Green" } elseif ($status -eq "warning") { "Yellow" } else { "Red" }
Write-Host "Audit de reprise: $status" -ForegroundColor $color
Write-Host "Rapport: $LatestReportPath"
if ($report.synchronization.lastEventSynchronizedAt) {
    Write-Host "Dernier événement synchronisé: $($report.synchronization.lastEventSynchronizedAt)"
}
if ($lastBackfill) {
    Write-Host "Dernier backfill: $($lastBackfill.archivesImported) archive(s), $($lastBackfill.eventsAdded) événement(s) ajouté(s)."
}

if ($hardFailure) {
    throw "L'audit de reprise n'est pas sain. Consulte $LatestReportPath."
}
