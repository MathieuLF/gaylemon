param(
    [string]$DataDirectory = (Join-Path $PSScriptRoot "..\portal\data"),
    [string]$OutputPath = "",
    [string]$HistoryOutputPath = "",
    [string]$AvailabilityOutputPath = "",
    [string]$SampleStorePath = "",
    [int]$HistoryDays = 0,
    [int]$MaxBars = 96,
    [int]$MaxSamples = 25000
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot

if (-not $OutputPath) { $OutputPath = Join-Path $DataDirectory "public-uptime.json" }
if (-not $HistoryOutputPath) { $HistoryOutputPath = Join-Path $DataDirectory "public-uptime-history.json" }
if (-not $AvailabilityOutputPath) { $AvailabilityOutputPath = Join-Path $DataDirectory "public-availability.json" }
if (-not $SampleStorePath) { $SampleStorePath = Join-Path $ProjectRoot "runtime\uptime\palworld-rest-samples.jsonl" }
if ($HistoryDays -le 0) { $HistoryDays = $config.UptimeHistoryDays }
if ($MaxBars -lt 1) { $MaxBars = 96 }
if ($MaxSamples -lt 100) { $MaxSamples = 100 }

try {
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    $OutputEncoding = [Console]::OutputEncoding
}
catch {
    # Best effort for older PowerShell hosts.
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] $Payload
    )

    $directory = Split-Path -Parent $Path
    if ($directory) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $temporary = "$resolved.tmp"
    $json = $Payload | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($temporary, $json.TrimEnd() + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $resolved -Force
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

function Convert-ToLocalString {
    param($Value)

    $parsed = Convert-ToDate $Value
    if (-not $parsed) { return $null }
    return [TimeZoneInfo]::ConvertTime($parsed, [TimeZoneInfo]::Local).ToString("yyyy-MM-dd HH:mm:ss zzz")
}

function Convert-Uptime {
    param([int]$Seconds)

    $span = [TimeSpan]::FromSeconds([Math]::Max(0, $Seconds))
    if ($span.Days -gt 0) { return "{0}j {1}h" -f $span.Days, $span.Hours }
    if ($span.Hours -gt 0) { return "{0}h {1}m" -f $span.Hours, $span.Minutes }
    return "{0}m" -f $span.Minutes
}

function Convert-ToPercent {
    param(
        [int]$UpSeconds,
        [int]$UnavailableSeconds,
        [int]$DegradedSeconds
    )

    $denominator = $UpSeconds + $UnavailableSeconds + $DegradedSeconds
    if ($denominator -le 0) { return $null }
    return [Math]::Round(($UpSeconds / $denominator) * 100, 4)
}

function Invoke-PalworldEndpoint {
    param([ValidateSet("info", "metrics", "players")] [string]$Endpoint)

    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = & (Join-Path $PSScriptRoot "palworld-api.ps1") $Endpoint 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        $stopwatch.Stop()
    }

    $text = (($output | Out-String).Trim())
    if ($exitCode -ne 0) {
        return [pscustomobject]@{
            endpoint = $Endpoint
            ok = $false
            latencyMs = [Math]::Round($stopwatch.Elapsed.TotalMilliseconds, 1)
            payload = $null
            error = if ($text) { $text } else { "endpoint failed with exit code $exitCode" }
        }
    }

    try {
        $payload = $text | ConvertFrom-Json
        return [pscustomobject]@{
            endpoint = $Endpoint
            ok = $true
            latencyMs = [Math]::Round($stopwatch.Elapsed.TotalMilliseconds, 1)
            payload = $payload
            error = $null
        }
    }
    catch {
        return [pscustomobject]@{
            endpoint = $Endpoint
            ok = $false
            latencyMs = [Math]::Round($stopwatch.Elapsed.TotalMilliseconds, 1)
            payload = $null
            error = "invalid JSON returned by $Endpoint"
        }
    }
}

function New-ProbeSample {
    $checkedAt = Get-Date
    $info = Invoke-PalworldEndpoint -Endpoint info
    $metrics = Invoke-PalworldEndpoint -Endpoint metrics
    $players = Invoke-PalworldEndpoint -Endpoint players
    $endpointResults = @($info, $metrics, $players)
    $okEndpoints = @($endpointResults | Where-Object { $_.ok }).Count
    $latencies = @($endpointResults | Where-Object { $_.ok } | ForEach-Object { [double]$_.latencyMs })
    $latencyMs = if ($latencies.Count -gt 0) {
        [Math]::Round((($latencies | Measure-Object -Average).Average), 1)
    }
    else {
        $null
    }

    $metricsPayload = $metrics.payload
    $infoPayload = $info.payload
    $playersPayload = $players.payload
    $fps = if ($metrics.ok -and $null -ne $metricsPayload.serverfps) { [int]$metricsPayload.serverfps } else { $null }
    $fpsAverage = if ($metrics.ok -and $null -ne $metricsPayload.serverfpsaverage) { [Math]::Round([double]$metricsPayload.serverfpsaverage, 1) } else { $null }
    $frameMs = if ($metrics.ok -and $null -ne $metricsPayload.serverframetime) { [Math]::Round([double]$metricsPayload.serverframetime, 1) } else { $null }
    $playerCount = if ($metrics.ok -and $null -ne $metricsPayload.currentplayernum) { [int]$metricsPayload.currentplayernum } else { $null }
    $maxPlayers = if ($metrics.ok -and $null -ne $metricsPayload.maxplayernum) { [int]$metricsPayload.maxplayernum } else { $null }
    $uptimeSeconds = if ($metrics.ok -and $null -ne $metricsPayload.uptime) { [int]$metricsPayload.uptime } else { $null }
    $playerListCount = if ($players.ok -and $playersPayload.players) { @($playersPayload.players).Count } else { $null }

    $status = "down"
    $statusClass = "unavailable"
    $message = "API REST Palworld indisponible."
    if ($metrics.ok -and $null -ne $fps -and $fps -gt 0) {
        $status = "up"
        $statusClass = "nominal"
        $message = "Palworld OK"
    }
    elseif ($okEndpoints -gt 0) {
        $status = "degraded"
        $statusClass = "degraded"
        $message = "API REST Palworld partiellement disponible."
    }

    return [ordered]@{
        version = 1
        checkedAt = $checkedAt.ToString("o")
        checkedAtLocal = $checkedAt.ToString("yyyy-MM-dd HH:mm:ss")
        ok = $status -eq "up"
        status = $status
        statusClass = $statusClass
        message = $message
        latencyMs = $latencyMs
        endpoints = [ordered]@{
            info = [ordered]@{ ok = [bool]$info.ok; latencyMs = $info.latencyMs }
            metrics = [ordered]@{ ok = [bool]$metrics.ok; latencyMs = $metrics.latencyMs }
            players = [ordered]@{ ok = [bool]$players.ok; latencyMs = $players.latencyMs }
        }
        server = [ordered]@{
            name = if ($info.ok) { [string]$infoPayload.servername } else { $null }
            description = if ($info.ok) { [string]$infoPayload.description } else { $null }
            version = if ($info.ok) { [string]$infoPayload.version } else { $null }
            worldGuid = if ($info.ok) { [string]$infoPayload.worldguid } else { $null }
        }
        metrics = [ordered]@{
            players = $playerCount
            playerListCount = $playerListCount
            maxPlayers = $maxPlayers
            fps = $fps
            fpsAverage = $fpsAverage
            frameMs = $frameMs
            days = if ($metrics.ok -and $null -ne $metricsPayload.days) { [int]$metricsPayload.days } else { $null }
            baseCamps = if ($metrics.ok -and $null -ne $metricsPayload.basecampnum) { [int]$metricsPayload.basecampnum } else { $null }
            uptimeSeconds = $uptimeSeconds
            uptime = if ($null -ne $uptimeSeconds) { Convert-Uptime -Seconds $uptimeSeconds } else { $null }
        }
    }
}

function Read-Samples {
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $samples = [Collections.Generic.List[object]]::new()
    foreach ($line in [IO.File]::ReadLines($Path, [Text.Encoding]::UTF8)) {
        if (-not $line.Trim()) { continue }
        try {
            $sample = $line | ConvertFrom-Json
            if (Convert-ToDate $sample.checkedAt) { $samples.Add($sample) | Out-Null }
        }
        catch {
            # Ignore damaged local history lines.
        }
    }
    return @($samples)
}

function Write-Samples {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [object[]]$Samples
    )

    $directory = Split-Path -Parent $Path
    if ($directory) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $temporary = "$resolved.tmp"
    $lines = @($Samples | ForEach-Object { $_ | ConvertTo-Json -Depth 12 -Compress })
    [IO.File]::WriteAllLines($temporary, $lines, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $resolved -Force
}

function Get-SampleStatusClass {
    param($Sample)

    try {
        if (
            $Sample.endpoints -and
            $Sample.endpoints.metrics -and
            [bool]$Sample.endpoints.metrics.ok -and
            $Sample.metrics -and
            $null -ne $Sample.metrics.fps -and
            [int]$Sample.metrics.fps -gt 0
        ) {
            return "nominal"
        }
    }
    catch {
        # Older samples may not have the full probe shape.
    }

    $value = [string]$Sample.statusClass
    if ($value -in @("nominal", "unavailable", "degraded", "maintenance")) { return $value }
    switch ([string]$Sample.status) {
        "up" { return "nominal" }
        "down" { return "unavailable" }
        "maintenance" { return "maintenance" }
        "degraded" { return "degraded" }
        default { return "unavailable" }
    }
}

function Add-DurationToTotals {
    param(
        [hashtable]$Totals,
        [string]$StatusClass,
        [int]$Seconds
    )

    if ($Seconds -le 0) { return }
    switch ($StatusClass) {
        "nominal" { $Totals.upSeconds += $Seconds }
        "maintenance" { $Totals.maintenanceSeconds += $Seconds }
        "degraded" { $Totals.degradedSeconds += $Seconds }
        "unavailable" { $Totals.unavailableSeconds += $Seconds }
        default { $Totals.unknownSeconds += $Seconds }
    }
}

function New-Totals {
    return @{
        upSeconds = 0
        unavailableSeconds = 0
        degradedSeconds = 0
        maintenanceSeconds = 0
        unknownSeconds = 0
    }
}

function Convert-Totals {
    param([hashtable]$Totals)

    $observed = $Totals.upSeconds + $Totals.unavailableSeconds + $Totals.degradedSeconds + $Totals.maintenanceSeconds + $Totals.unknownSeconds
    return [ordered]@{
        upSeconds = [int]$Totals.upSeconds
        unavailableSeconds = [int]$Totals.unavailableSeconds
        degradedSeconds = [int]$Totals.degradedSeconds
        maintenanceSeconds = [int]$Totals.maintenanceSeconds
        unknownSeconds = [int]$Totals.unknownSeconds
        observedSeconds = [int]$observed
        uptimePercent = Convert-ToPercent -UpSeconds $Totals.upSeconds -UnavailableSeconds $Totals.unavailableSeconds -DegradedSeconds $Totals.degradedSeconds
    }
}

function Measure-Samples {
    param(
        [object[]]$Samples,
        $Since,
        $NowUtc,
        [int]$FreshThresholdSeconds
    )

    $totals = New-Totals
    $ordered = @($Samples | Sort-Object { (Convert-ToDate $_.checkedAt).UtcDateTime })
    for ($i = 0; $i -lt $ordered.Count; $i++) {
        $sample = $ordered[$i]
        $start = (Convert-ToDate $sample.checkedAt).ToUniversalTime()
        $end = if ($i + 1 -lt $ordered.Count) {
            (Convert-ToDate $ordered[$i + 1].checkedAt).ToUniversalTime()
        }
        else {
            $NowUtc
        }
        if ($Since -and $end -le $Since) { continue }
        if ($Since -and $start -lt $Since) { $start = $Since }
        if ($end -le $start) { continue }

        $duration = [int][Math]::Round(($end - $start).TotalSeconds, 0)
        $statusClass = Get-SampleStatusClass -Sample $sample
        if ($duration -gt $FreshThresholdSeconds) {
            Add-DurationToTotals -Totals $totals -StatusClass $statusClass -Seconds $FreshThresholdSeconds
            Add-DurationToTotals -Totals $totals -StatusClass "unavailable" -Seconds ($duration - $FreshThresholdSeconds)
        }
        else {
            Add-DurationToTotals -Totals $totals -StatusClass $statusClass -Seconds $duration
        }
    }

    return Convert-Totals -Totals $totals
}

function Convert-SampleToBeat {
    param($Sample)

    $statusClass = Get-SampleStatusClass -Sample $Sample
    $status = switch ($statusClass) {
        "nominal" { "up" }
        "unavailable" { "down" }
        "degraded" { "degraded" }
        "maintenance" { "maintenance" }
        default { [string]$Sample.status }
    }

    return [ordered]@{
        status = $status
        statusCode = if ($status -eq "up") { 1 } elseif ($status -eq "down") { 0 } elseif ($status -eq "degraded") { 2 } else { -1 }
        time = [string]$Sample.checkedAt
        ping = $Sample.latencyMs
        message = [string]$Sample.message
    }
}

function New-DowntimeWindows {
    param(
        [object[]]$Samples,
        $NowUtc,
        [int]$FreshThresholdSeconds
    )

    $windows = [Collections.Generic.List[object]]::new()
    $ordered = @($Samples | Sort-Object { (Convert-ToDate $_.checkedAt).UtcDateTime })
    $current = $null
    $sequence = 1

    for ($i = 0; $i -lt $ordered.Count; $i++) {
        $sample = $ordered[$i]
        $start = (Convert-ToDate $sample.checkedAt).ToUniversalTime()
        $end = if ($i + 1 -lt $ordered.Count) {
            (Convert-ToDate $ordered[$i + 1].checkedAt).ToUniversalTime()
        }
        else {
            $NowUtc
        }
        if ($end -le $start) { continue }
        $duration = [int][Math]::Round(($end - $start).TotalSeconds, 0)
        $statusClass = Get-SampleStatusClass -Sample $sample
        $windowStatus = if ($statusClass -eq "nominal" -and $duration -le $FreshThresholdSeconds) { "nominal" } else { "unavailable" }

        if ($windowStatus -eq "nominal") {
            if ($current) {
                $current.status = "resolved"
                $current.endedAt = $start.ToString("o")
                $current.endedAtLocal = Convert-ToLocalString $start
                $current.firstFunctionalAt = $start.ToString("o")
                $current.firstFunctionalAtLocal = Convert-ToLocalString $start
                $current.durationSeconds = [int][Math]::Round(($start - (Convert-ToDate $current.startedAt).ToUniversalTime()).TotalSeconds, 0)
                $windows.Add($current) | Out-Null
                $sequence++
                $current = $null
            }
            continue
        }

        $downStart = if ($statusClass -eq "nominal" -and $duration -gt $FreshThresholdSeconds) {
            $start.AddSeconds($FreshThresholdSeconds)
        }
        else {
            $start
        }
        if (-not $current) {
            $current = [ordered]@{
                id = "palworld-api-window-{0:0000}" -f $sequence
                status = "open"
                startedAt = $downStart.ToString("o")
                startedAtLocal = Convert-ToLocalString $downStart
                endedAt = $null
                endedAtLocal = $null
                durationSeconds = 0
                measuredUnavailableSeconds = 0
                firstFunctionalAt = $null
                firstFunctionalAtLocal = $null
                statusCounts = [ordered]@{}
                messages = @()
            }
        }
        $current.measuredUnavailableSeconds = [int]$current.measuredUnavailableSeconds + [Math]::Max(0, [int][Math]::Round(($end - $downStart).TotalSeconds, 0))
        $statusKey = [string]$sample.status
        if (-not $current.statusCounts.Contains($statusKey)) {
            $current.statusCounts[$statusKey] = 0
        }
        $current.statusCounts[$statusKey] = [int]$current.statusCounts[$statusKey] + 1
        if ($sample.message -and $sample.message -notin $current.messages) {
            $current.messages = @($current.messages + [string]$sample.message)
        }
    }

    if ($current) {
        $started = (Convert-ToDate $current.startedAt).ToUniversalTime()
        $current.durationSeconds = [int][Math]::Round(($NowUtc - $started).TotalSeconds, 0)
        $windows.Add($current) | Out-Null
    }

    return @($windows)
}

function Get-DataProbe {
    param(
        [string]$Name,
        [string]$Path,
        [int]$MaxAgeSeconds,
        $NowUtc,
        [switch]$PreferFileTimestamp
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [ordered]@{
            name = $Name
            status = "missing"
            updatedAt = $null
            ageSeconds = $null
            maxAgeSeconds = $MaxAgeSeconds
            ok = $false
            error = "missing"
        }
    }

    $item = Get-Item -LiteralPath $Path
    $payload = $null
    try { $payload = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json } catch { }
    $contentUpdatedValue = $payload.updatedAt
    if (-not $contentUpdatedValue) { $contentUpdatedValue = $payload.generatedAt }
    if (-not $contentUpdatedValue) { $contentUpdatedValue = $payload.checkedAt }
    $contentUpdatedAt = Convert-ToDate $contentUpdatedValue
    $updatedAt = if ($PreferFileTimestamp) { [DateTimeOffset]$item.LastWriteTimeUtc } else { $contentUpdatedAt }
    if (-not $updatedAt) { $updatedAt = [DateTimeOffset]$item.LastWriteTimeUtc }
    $ageSeconds = [int][Math]::Round(($NowUtc - $updatedAt.ToUniversalTime()).TotalSeconds, 0)
    if ($ageSeconds -lt 0) { $ageSeconds = 0 }
    $payloadOk = if ($null -eq $payload -or $null -eq $payload.ok) { $true } else { [bool]$payload.ok }
    $status = if (-not $payloadOk) { "degraded" } elseif ($ageSeconds -gt $MaxAgeSeconds) { "stale" } else { "fresh" }

    return [ordered]@{
        name = $Name
        status = $status
        updatedAt = $updatedAt.ToString("o")
        contentUpdatedAt = if ($contentUpdatedAt) { $contentUpdatedAt.ToString("o") } else { $null }
        fileUpdatedAt = ([DateTimeOffset]$item.LastWriteTimeUtc).ToString("o")
        ageSeconds = $ageSeconds
        maxAgeSeconds = $MaxAgeSeconds
        ok = $payloadOk
        error = if ($payloadOk) { $null } else { [string]$payload.error }
    }
}

$sample = New-ProbeSample
$sampleDate = (Convert-ToDate $sample.checkedAt).ToUniversalTime()
$historyFloor = [DateTimeOffset]::UtcNow.AddDays(-1 * [Math]::Max(1, $HistoryDays))
$samples = @(Read-Samples -Path $SampleStorePath)
$samples += ([pscustomobject]$sample)
$samples = @(
    $samples |
        Where-Object {
            $date = Convert-ToDate $_.checkedAt
            $date -and $date.ToUniversalTime() -ge $historyFloor
        } |
        Sort-Object { (Convert-ToDate $_.checkedAt).UtcDateTime } |
        Select-Object -Last $MaxSamples
)
Write-Samples -Path $SampleStorePath -Samples $samples

$now = Get-Date
$nowUtc = [DateTimeOffset]::UtcNow
$freshThresholdSeconds = [Math]::Max($config.RecoveryStaleSeconds, $config.MetricIntervalSeconds * 4)
$last24h = Measure-Samples -Samples $samples -Since $nowUtc.AddHours(-24) -NowUtc $nowUtc -FreshThresholdSeconds $freshThresholdSeconds
$last7d = Measure-Samples -Samples $samples -Since $nowUtc.AddDays(-7) -NowUtc $nowUtc -FreshThresholdSeconds $freshThresholdSeconds
$all = Measure-Samples -Samples $samples -Since $null -NowUtc $nowUtc -FreshThresholdSeconds $freshThresholdSeconds
$windows = New-DowntimeWindows -Samples $samples -NowUtc $nowUtc -FreshThresholdSeconds $freshThresholdSeconds
$beats = @($samples | Select-Object -Last $MaxBars | ForEach-Object { Convert-SampleToBeat -Sample $_ })
$latest = $samples[-1]
$latestDate = Convert-ToDate $latest.checkedAt
$probeAgeSeconds = if ($latestDate) { [int][Math]::Max(0, [Math]::Round(($nowUtc - $latestDate.ToUniversalTime()).TotalSeconds, 0)) } else { $null }
$probeFresh = $null -ne $probeAgeSeconds -and $probeAgeSeconds -le $freshThresholdSeconds
$latestStatusClass = Get-SampleStatusClass -Sample $latest
$latestStatus = switch ($latestStatusClass) {
    "nominal" { "up" }
    "unavailable" { "down" }
    "degraded" { "degraded" }
    "maintenance" { "maintenance" }
    default { [string]$latest.status }
}
$currentAvailability = if ($latestStatusClass -eq "nominal" -and $probeFresh) { "up" } elseif ($latestStatusClass -eq "unavailable") { "down" } else { "degraded" }

$uptimePayload = [ordered]@{
    version = 2
    ok = [bool]($currentAvailability -eq "up")
    source = "palworld-rest-api"
    updatedAt = $now.ToString("o")
    updatedAtLocal = $now.ToString("yyyy-MM-dd HH:mm:ss")
    title = "Palworld"
    monitors = @(
        [ordered]@{
            id = "palworld-rest-api"
            name = "Serveur Palworld"
            type = "rest-api"
            status = $latestStatus
            statusCode = if ($latestStatus -eq "up") { 1 } elseif ($latestStatus -eq "down") { 0 } elseif ($latestStatus -eq "degraded") { 2 } else { -1 }
            lastHeartbeatAt = [string]$latest.checkedAt
            lastProbeAt = [string]$latest.checkedAt
            ping = $latest.latencyMs
            uptime24h = $last24h.uptimePercent
            beats = [object[]]$beats
        }
    )
    summary = [ordered]@{
        total = 1
        up = if ($currentAvailability -eq "up") { 1 } else { 0 }
        down = if ($currentAvailability -eq "down") { 1 } else { 0 }
        maintenance = 0
        status = $currentAvailability
        monitorStatus = $latestStatus
        probeFresh = $probeFresh
        probeAgeSeconds = $probeAgeSeconds
        heartbeatAgeSeconds = $probeAgeSeconds
        uptime24hAverage = $last24h.uptimePercent
        uptimeLast24h = $last24h.uptimePercent
        unavailableSecondsLast24h = $last24h.unavailableSeconds + $last24h.degradedSeconds
        averagePing = $latest.latencyMs
        players = $latest.metrics.players
        maxPlayers = $latest.metrics.maxPlayers
        fps = $latest.metrics.fps
        fpsAverage = $latest.metrics.fpsAverage
        frameMs = $latest.metrics.frameMs
        gameUptimeSeconds = $latest.metrics.uptimeSeconds
    }
}
if (-not $uptimePayload.ok) {
    $uptimePayload["error"] = [string]$latest.message
}

$historyPayload = [ordered]@{
    version = 2
    ok = $true
    source = "palworld-rest-api-history"
    updatedAt = $now.ToString("o")
    updatedAtLocal = $now.ToString("yyyy-MM-dd HH:mm:ss")
    localTimeZone = [ordered]@{
        id = [TimeZoneInfo]::Local.Id
        displayName = [TimeZoneInfo]::Local.DisplayName
    }
    historyDays = $HistoryDays
    monitor = [ordered]@{
        id = "palworld-rest-api"
        name = "Serveur Palworld"
        type = "rest-api"
        active = $true
    }
    latest = [ordered]@{
        status = $latestStatus
        statusClass = $latestStatusClass
        heartbeatAt = [string]$latest.checkedAt
        heartbeatAtLocal = Convert-ToLocalString $latest.checkedAt
        probeAt = [string]$latest.checkedAt
        probeAgeSeconds = $probeAgeSeconds
        heartbeatAgeSeconds = $probeAgeSeconds
        fresh = $probeFresh
        ping = $latest.latencyMs
        message = [string]$latest.message
        metrics = $latest.metrics
    }
    summary = [ordered]@{
        all = $all
        last24h = $last24h
        last7d = $last7d
        sampleCount = $samples.Count
        downtimeWindowCount = $windows.Count
        resolvedDowntimeWindowCount = @($windows | Where-Object { $_.status -eq "resolved" }).Count
        openDowntimeWindowCount = @($windows | Where-Object { $_.status -eq "open" }).Count
    }
    windows = [object[]]@($windows | Select-Object -Last 200)
    recentHeartbeats = [object[]]@($beats)
    recentProbes = [object[]]@($samples | Select-Object -Last 500)
}

Write-JsonFile -Path $OutputPath -Payload $uptimePayload
Write-JsonFile -Path $HistoryOutputPath -Payload $historyPayload

$publicMetricMaxAgeSeconds = [Math]::Max(90, $config.MetricIntervalSeconds * 4)
$publicRecentEventsMaxAgeSeconds = [Math]::Max(120, $config.EventSyncIntervalSeconds * 6)
$publicFullEventsMaxAgeSeconds = 30 * 60
$publicDiagnosticsMaxAgeSeconds = 26 * 60 * 60
$dataChecks = @(
    Get-DataProbe -Name "metrics" -Path (Join-Path $DataDirectory "public-metrics.json") -MaxAgeSeconds $publicMetricMaxAgeSeconds -NowUtc $nowUtc
    Get-DataProbe -Name "stats" -Path (Join-Path $DataDirectory "public-stats.json") -MaxAgeSeconds 900 -NowUtc $nowUtc
    Get-DataProbe -Name "uptime" -Path $OutputPath -MaxAgeSeconds $publicMetricMaxAgeSeconds -NowUtc $nowUtc
    Get-DataProbe -Name "uptimeHistory" -Path $HistoryOutputPath -MaxAgeSeconds 300 -NowUtc $nowUtc
    Get-DataProbe -Name "saveIndex" -Path (Join-Path $DataDirectory "public-save-index.json") -MaxAgeSeconds 900 -NowUtc $nowUtc -PreferFileTimestamp
    Get-DataProbe -Name "saveSnapshot" -Path (Join-Path $DataDirectory "public-save-snapshot.json") -MaxAgeSeconds 900 -NowUtc $nowUtc -PreferFileTimestamp
    Get-DataProbe -Name "saveBases" -Path (Join-Path $DataDirectory "public-save-bases.json") -MaxAgeSeconds 900 -NowUtc $nowUtc -PreferFileTimestamp
    Get-DataProbe -Name "saveDiagnostics" -Path (Join-Path $DataDirectory "public-save-diagnostics.json") -MaxAgeSeconds $publicDiagnosticsMaxAgeSeconds -NowUtc $nowUtc -PreferFileTimestamp
    Get-DataProbe -Name "events" -Path (Join-Path $DataDirectory "public-events.json") -MaxAgeSeconds $publicFullEventsMaxAgeSeconds -NowUtc $nowUtc
    Get-DataProbe -Name "recentEvents" -Path (Join-Path $DataDirectory "public-events-recent.json") -MaxAgeSeconds $publicRecentEventsMaxAgeSeconds -NowUtc $nowUtc
)
$badChecks = @($dataChecks | Where-Object { $_.status -ne "fresh" })
$availabilityStatus = if ($currentAvailability -eq "down") { "down" } elseif ($badChecks.Count -gt 0 -or $currentAvailability -ne "up") { "degraded" } else { "up" }

$availabilityPayload = [ordered]@{
    version = 2
    ok = [bool]($availabilityStatus -eq "up")
    source = "palworld-rest-api"
    updatedAt = $now.ToString("o")
    updatedAtLocal = $now.ToString("yyyy-MM-dd HH:mm:ss")
    localTimeZone = [ordered]@{
        id = [TimeZoneInfo]::Local.Id
        displayName = [TimeZoneInfo]::Local.DisplayName
    }
    status = $availabilityStatus
    summary = [ordered]@{
        monitorStatus = $latestStatus
        probeFresh = $probeFresh
        monitorFresh = $probeFresh
        probeAgeSeconds = $probeAgeSeconds
        heartbeatAgeSeconds = $probeAgeSeconds
        staleOrMissingDataSets = $badChecks.Count
        downtimeWindowCount = $windows.Count
        uptimeLast24h = $last24h.uptimePercent
        unavailableSecondsLast24h = $last24h.unavailableSeconds + $last24h.degradedSeconds
        uptimeLast24hSource = "palworld-rest-api-history"
        uptimeLast24hObserved = $last24h.uptimePercent
        unavailableSecondsLast24hObserved = $last24h.unavailableSeconds + $last24h.degradedSeconds
        uptimeLast24hObservedSource = "palworld-rest-api-history"
        uptimeAll = $all.uptimePercent
        unavailableSecondsAll = $all.unavailableSeconds + $all.degradedSeconds
        players = $latest.metrics.players
        maxPlayers = $latest.metrics.maxPlayers
        fps = $latest.metrics.fps
        fpsAverage = $latest.metrics.fpsAverage
        frameMs = $latest.metrics.frameMs
    }
    dataFreshness = [object[]]$dataChecks
    downtimeWindows = [object[]]@($windows | Select-Object -Last 20)
}

Write-JsonFile -Path $AvailabilityOutputPath -Payload $availabilityPayload
Write-Host "Palworld REST uptime exported to $OutputPath"
Write-Host "Palworld REST uptime history exported to $HistoryOutputPath"
Write-Host "Availability ledger exported to $AvailabilityOutputPath"
