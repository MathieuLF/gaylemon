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
$LocalRecentEventsPath = Join-Path $ProjectRoot "portal\data\public-events-recent.json"
$LocalEventsIndexPath = Join-Path $ProjectRoot "portal\data\public-events-index.json"
$LocalSnapshotPath = Join-Path $ProjectRoot "portal\data\public-save-snapshot.json"
$LocalSnapshotIndexPath = Join-Path $ProjectRoot "portal\data\public-save-index.json"
$LocalAvailabilityPath = Join-Path $ProjectRoot "portal\data\public-availability.json"
$RemoteEventsPath = "$($config.RemoteProjectRoot)/runtime/public-events.json"
$RemoteRecentEventsPath = "$($config.RemoteProjectRoot)/runtime/public-events-recent.json"
$RemoteRecoveryPath = "$($config.RemoteProjectRoot)/runtime/events/palworld-events-recovery.json"
$RemoteSnapshotPath = "$($config.RemoteProjectRoot)/runtime/public-save-snapshot.json"
$LatestReportPath = Join-Path $ReportRoot "microsite-recovery-latest.json"
$HistoryReportPath = Join-Path $ReportRoot "microsite-recovery-history.jsonl"

function Read-JsonFile {
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Fichier JSON introuvable: $Path"
    }
    return (Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json)
}

function Read-JsonFileIfPresent {
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    try {
        return (Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Read-RemoteJson {
    param([Parameter(Mandatory)] [string]$Path)

    $raw = & ssh.exe -n -T -o BatchMode=yes -o ConnectTimeout=8 $config.SshAlias "test -s '$Path' && gzip -c '$Path' | base64 -w0" 2>$null
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

function Read-RemoteJsonIfPresent {
    param([Parameter(Mandatory)] [string]$Path)

    try {
        return Read-RemoteJson -Path $Path
    }
    catch {
        return $null
    }
}

function Convert-ToDate {
    param($Value)

    if (-not $Value) { return $null }
    if ($Value -is [DateTimeOffset]) { return $Value }
    if ($Value -is [datetime]) {
        return [DateTimeOffset]::new($Value.ToUniversalTime(), [TimeSpan]::Zero)
    }
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

function Get-JsonProperty {
    param(
        $Object,
        [Parameter(Mandatory)] [string]$Name
    )

    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Get-EventRevisionLastId {
    param($Revision)

    if ($null -eq $Revision -or -not [string]$Revision) { return $null }
    $parts = ([string]$Revision).Split(":")
    if ($parts.Count -lt 3) { return $null }
    $parsed = 0L
    if ([long]::TryParse($parts[2], [ref]$parsed)) { return $parsed }
    for ($index = $parts.Count - 1; $index -ge 1; $index--) {
        if ([long]::TryParse($parts[$index], [ref]$parsed)) { return $parsed }
    }
    return $null
}

function Get-EventSummaryCount {
    param($Payload)

    if (-not $Payload -or -not $Payload.summary) { return 0L }
    if ($Payload.summary.PSObject.Properties.Name -contains "totalEchoes" -and $null -ne $Payload.summary.totalEchoes) {
        return [long]$Payload.summary.totalEchoes
    }
    if ($Payload.summary.PSObject.Properties.Name -contains "echoes" -and $null -ne $Payload.summary.echoes) {
        return [long]$Payload.summary.echoes
    }
    if ($Payload.summary.PSObject.Properties.Name -contains "totalEvents" -and $null -ne $Payload.summary.totalEvents) {
        return [long]$Payload.summary.totalEvents
    }
    if ($Payload.summary.PSObject.Properties.Name -contains "events" -and $null -ne $Payload.summary.events) {
        return [long]$Payload.summary.events
    }
    return 0L
}

function Select-FreshestLocalEvents {
    param(
        [Parameter(Mandatory)] $FullEvents,
        $IndexEvents
    )

    if (-not $IndexEvents -or -not $IndexEvents.summary) {
        return $FullEvents
    }

    $fullLastAt = Convert-ToDate $FullEvents.summary.lastAt
    $indexLastAt = Convert-ToDate $IndexEvents.summary.lastAt
    if ($indexLastAt -and (-not $fullLastAt -or $indexLastAt -gt $fullLastAt)) {
        return $IndexEvents
    }

    $fullCount = Get-EventSummaryCount -Payload $FullEvents
    $indexCount = Get-EventSummaryCount -Payload $IndexEvents
    if ($indexCount -gt $fullCount) {
        return $IndexEvents
    }

    return $FullEvents
}

function Get-DateLagSeconds {
    param(
        $LocalValue,
        $RemoteValue
    )

    if (-not $LocalValue -or -not $RemoteValue) { return $null }
    $lag = [int][Math]::Round(($RemoteValue.ToUniversalTime() - $LocalValue.ToUniversalTime()).TotalSeconds, 0)
    if ($lag -lt 0) { return 0 }
    return $lag
}

function Get-RecoveryState {
    $remoteFullEvents = Read-RemoteJson -Path $RemoteEventsPath
    $remoteRecentEvents = Read-RemoteJsonIfPresent -Path $RemoteRecentEventsPath
    $remoteEvents = if ($remoteRecentEvents) { $remoteRecentEvents } else { $remoteFullEvents }
    $remoteEventsSource = if ($remoteRecentEvents) { "recent" } else { "full" }
    $remoteRecovery = Read-RemoteJson -Path $RemoteRecoveryPath
    $remoteSnapshot = Read-RemoteJsonIfPresent -Path $RemoteSnapshotPath
    $localFullEvents = Read-JsonFile -Path $LocalEventsPath
    $localIndexEvents = Read-JsonFileIfPresent -Path $LocalEventsIndexPath
    $localRecentEvents = Read-JsonFileIfPresent -Path $LocalRecentEventsPath
    $localEvents = Select-FreshestLocalEvents -FullEvents $localFullEvents -IndexEvents $localIndexEvents
    $localEventsSource = if ($localEvents -eq $localIndexEvents) { "index" } else { "full" }
    if ($localRecentEvents) {
        $freshestLocalEvents = Select-FreshestLocalEvents -FullEvents $localEvents -IndexEvents $localRecentEvents
        if ($freshestLocalEvents -eq $localRecentEvents) {
            $localEventsSource = "recent"
        }
        $localEvents = $freshestLocalEvents
    }
    $localSnapshot = Read-JsonFileIfPresent -Path $LocalSnapshotIndexPath
    $localSnapshotSource = if ($localSnapshot) { "public-save-index" } else { "public-save-snapshot" }
    if (-not $localSnapshot) {
        $localSnapshot = Read-JsonFile -Path $LocalSnapshotPath
    }
    $catchUpToleranceSeconds = [Math]::Max($config.RecoveryStaleSeconds, $config.MetricIntervalSeconds * 6)

    $remoteEventCount = Get-EventSummaryCount -Payload $remoteEvents
    $localEventCount = Get-EventSummaryCount -Payload $localEvents
    $remoteLastEventAt = Convert-ToDate $remoteEvents.summary.lastAt
    $localLastEventAt = Convert-ToDate $localEvents.summary.lastAt
    $remoteSnapshotSource = "recovery"
    $remoteSnapshotAt = $null
    if ($remoteSnapshot) {
        $remoteSnapshotAt = Convert-ToDate $remoteSnapshot.provenance.sourceUpdatedAt
        if ($null -eq $remoteSnapshotAt) {
            $remoteSnapshotAt = Convert-ToDate $remoteSnapshot.updatedAt
        }
        if ($null -ne $remoteSnapshotAt) {
            $remoteSnapshotSource = "public-save-snapshot"
        }
    }
    if ($null -eq $remoteSnapshotAt) {
        $remoteSnapshotAt = Convert-ToDate $remoteRecovery.currentSnapshotAt
    }
    if ($null -eq $remoteSnapshotAt) {
        $remoteSnapshotAt = Convert-ToDate $remoteRecovery.lastSaveAt
    }
    $localSnapshotAt = Convert-ToDate $localSnapshot.provenance.sourceUpdatedAt
    if ($null -eq $localSnapshotAt) {
        $localSnapshotAt = Convert-ToDate $localSnapshot.updatedAt
    }
    $remoteRevisionLastId = Get-EventRevisionLastId $remoteEvents.revision
    $localRevisionLastId = Get-EventRevisionLastId $localEvents.revision
    $eventLagSeconds = Get-DateLagSeconds -LocalValue $localLastEventAt -RemoteValue $remoteLastEventAt
    $snapshotLagSeconds = Get-DateLagSeconds -LocalValue $localSnapshotAt -RemoteValue $remoteSnapshotAt

    $eventsStrictCaughtUp = ($localEventCount -ge $remoteEventCount) -or (
        $null -ne $remoteRevisionLastId -and
        $null -ne $localRevisionLastId -and
        $localRevisionLastId -ge $remoteRevisionLastId
    )
    if ($remoteLastEventAt) {
        $eventsStrictCaughtUp = $eventsStrictCaughtUp -and $localLastEventAt -and $localLastEventAt -ge $remoteLastEventAt
    }
    $eventsRecentEnough = $null -ne $eventLagSeconds -and $eventLagSeconds -le $catchUpToleranceSeconds
    $eventsCaughtUp = $eventsStrictCaughtUp -or $eventsRecentEnough
    $snapshotCaughtUp = ($localSnapshotAt -and $remoteSnapshotAt -and $localSnapshotAt -ge $remoteSnapshotAt) -or (
        $null -ne $snapshotLagSeconds -and $snapshotLagSeconds -le $catchUpToleranceSeconds
    )

    return [pscustomobject]@{
        RemoteEvents = $remoteEvents
        RemoteFullEvents = $remoteFullEvents
        RemoteRecentEvents = $remoteRecentEvents
        RemoteEventsSource = $remoteEventsSource
        RemoteRecovery = $remoteRecovery
        RemoteSnapshot = $remoteSnapshot
        RemoteSnapshotSource = $remoteSnapshotSource
        LocalEvents = $localEvents
        LocalFullEvents = $localFullEvents
        LocalIndexEvents = $localIndexEvents
        LocalRecentEvents = $localRecentEvents
        LocalEventsSource = $localEventsSource
        LocalSnapshot = $localSnapshot
        LocalSnapshotSource = $localSnapshotSource
        RemoteEventCount = $remoteEventCount
        LocalEventCount = $localEventCount
        RemoteRevisionLastId = $remoteRevisionLastId
        LocalRevisionLastId = $localRevisionLastId
        RemoteLastEventAt = $remoteLastEventAt
        LocalLastEventAt = $localLastEventAt
        RemoteSnapshotAt = $remoteSnapshotAt
        LocalSnapshotAt = $localSnapshotAt
        EventLagSeconds = $eventLagSeconds
        SnapshotLagSeconds = $snapshotLagSeconds
        CatchUpToleranceSeconds = $catchUpToleranceSeconds
        EventsCaughtUp = [bool]$eventsCaughtUp
        SnapshotCaughtUp = [bool]$snapshotCaughtUp
    }
}

function Repair-RecoveryState {
    & (Join-Path $PSScriptRoot "sync-palworld-save-snapshot.ps1") | Out-Null
    & (Join-Path $PSScriptRoot "sync-palworld-events.ps1") | Out-Null
}

function Refresh-AvailabilityState {
    & (Join-Path $PSScriptRoot "update-microsite-metrics.ps1") -FastOnly -SkipEvents | Out-Null
    & (Join-Path $PSScriptRoot "export-uptime-kuma-history.ps1") | Out-Null
    return (Read-JsonFile -Path $LocalAvailabilityPath)
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
$availability = $null
$availabilityFailure = $null
$availabilityRefreshed = $false

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

try {
    $availability = Refresh-AvailabilityState
    $availabilityRefreshed = $true
}
catch {
    $availabilityFailure = $_.Exception.Message
    $messages.Add("Disponibilité Kuma non rafraîchie: $availabilityFailure")
    if (Test-Path -LiteralPath $LocalAvailabilityPath) {
        try {
            $availability = Read-JsonFile -Path $LocalAvailabilityPath
        }
        catch {
            $messages.Add("Rapport de disponibilité local illisible: $($_.Exception.Message)")
        }
    }
}

$availabilityStatus = if ($availability -and $availability.status) { [string]$availability.status } else { "unknown" }
$availabilityOk = $availability -and [bool]$availability.ok
$availabilityHardFailure = $availabilityStatus -eq "down"
$availabilityWarning = -not $availabilityOk -and -not $availabilityHardFailure
$hardFailure = $failure -or -not $state -or -not $state.EventsCaughtUp -or -not $state.SnapshotCaughtUp -or $availabilityHardFailure
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
    if ($state -and (($state.EventLagSeconds -and $state.EventLagSeconds -gt 0) -or ($state.SnapshotLagSeconds -and $state.SnapshotLagSeconds -gt 0))) {
        $messages.Add("La copie locale reste dans la tolérance de reprise ($($state.CatchUpToleranceSeconds)s): échos $($state.EventLagSeconds)s, snapshot $($state.SnapshotLagSeconds)s.")
    }
}
if ($availabilityHardFailure) {
    $messages.Add("Uptime Kuma indique une indisponibilité active.")
}
elseif ($availabilityWarning) {
    $messages.Add("La disponibilité publique est dégradée ou incomplète; consulter public-availability.json.")
}
if ($missingHours.Count) {
    $messages.Add("Des archives horaires historiques sont absentes: $($missingHours -join ', ').")
}

$status = if ($hardFailure) { "error" } elseif ($missingHours.Count -or $availabilityWarning) { "warning" } else { "complete" }
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
        remoteEventsSource = if ($state) { [string]$state.RemoteEventsSource } else { $null }
        localEventsSource = if ($state) { [string]$state.LocalEventsSource } else { $null }
        remoteSnapshotSource = if ($state) { [string]$state.RemoteSnapshotSource } else { $null }
        localSnapshotSource = if ($state) { [string]$state.LocalSnapshotSource } else { $null }
        remoteSnapshotGenerationId = if ($state) { [string](Get-JsonProperty -Object $state.RemoteSnapshot -Name "generationId") } else { $null }
        localSnapshotGenerationId = if ($state) { [string](Get-JsonProperty -Object $state.LocalSnapshot -Name "generationId") } else { $null }
        remoteEventCount = if ($state) { $state.RemoteEventCount } else { $null }
        localEventCount = if ($state) { $state.LocalEventCount } else { $null }
        remoteRevisionLastId = if ($state) { $state.RemoteRevisionLastId } else { $null }
        localRevisionLastId = if ($state) { $state.LocalRevisionLastId } else { $null }
        lastEventSynchronizedAt = if ($state) { Convert-ToIsoString $state.LocalEvents.summary.lastAt } else { $null }
        remoteSnapshotAt = if ($state -and $state.RemoteSnapshotAt) { $state.RemoteSnapshotAt.ToString("o") } else { $null }
        localSnapshotAt = if ($state -and $state.LocalSnapshotAt) { $state.LocalSnapshotAt.ToString("o") } else { $null }
        eventLagSeconds = if ($state) { $state.EventLagSeconds } else { $null }
        snapshotLagSeconds = if ($state) { $state.SnapshotLagSeconds } else { $null }
        catchUpToleranceSeconds = if ($state) { $state.CatchUpToleranceSeconds } else { $null }
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
    availability = [ordered]@{
        refreshed = $availabilityRefreshed
        ok = if ($availability) { [bool]$availability.ok } else { $false }
        status = $availabilityStatus
        monitorStatus = if ($availability -and $availability.summary) { $availability.summary.monitorStatus } else { $null }
        monitorFresh = if ($availability -and $availability.summary) { $availability.summary.monitorFresh } else { $null }
        heartbeatAgeSeconds = if ($availability -and $availability.summary) { $availability.summary.heartbeatAgeSeconds } else { $null }
        staleOrMissingDataSets = if ($availability -and $availability.summary) { $availability.summary.staleOrMissingDataSets } else { $null }
        downtimeWindowCount = if ($availability -and $availability.summary) { $availability.summary.downtimeWindowCount } else { $null }
        uptimeLast24h = if ($availability -and $availability.summary) { $availability.summary.uptimeLast24h } else { $null }
        unavailableSecondsLast24h = if ($availability -and $availability.summary) { $availability.summary.unavailableSecondsLast24h } else { $null }
        latestDowntimeWindow = if ($availability -and $availability.downtimeWindows) { @($availability.downtimeWindows)[-1] } else { $null }
        error = $availabilityFailure
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
if ($report.availability.status) {
    Write-Host "Disponibilité locale: $($report.availability.status)"
}

if ($hardFailure) {
    throw "L'audit de reprise n'est pas sain. Consulte $LatestReportPath."
}
