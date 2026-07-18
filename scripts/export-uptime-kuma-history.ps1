param(
    [string]$DataDirectory = (Join-Path $PSScriptRoot "..\portal\data"),
    [string]$OutputPath = "",
    [string]$AvailabilityOutputPath = "",
    [int]$HistoryDays = 0,
    [int]$MonitorId = 0,
    [string]$ContainerName = "",
    [string]$DatabasePath = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot

if (-not $OutputPath) { $OutputPath = Join-Path $DataDirectory "public-uptime-history.json" }
if (-not $AvailabilityOutputPath) { $AvailabilityOutputPath = Join-Path $DataDirectory "public-availability.json" }
if ($HistoryDays -le 0) { $HistoryDays = $config.UptimeHistoryDays }
if ($MonitorId -le 0) { $MonitorId = $config.UptimeKumaMonitorId }
if (-not $ContainerName) { $ContainerName = $config.UptimeKumaContainer }
if (-not $DatabasePath) { $DatabasePath = $config.UptimeKumaDbPath }

try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
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

function Get-PublicUptime24hSnapshot {
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }

    try {
        $payload = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    }
    catch {
        return $null
    }

    if (-not $payload -or -not $payload.ok) { return $null }

    $values = @()
    foreach ($monitor in @($payload.monitors)) {
        if ($null -ne $monitor.uptime24h -and [string]$monitor.uptime24h -ne "") {
            $values += [double]$monitor.uptime24h
        }
    }

    $uptimePercent = $null
    if ($values.Count -gt 0) {
        $uptimePercent = [Math]::Round((($values | Measure-Object -Average).Average), 2)
    }
    elseif ($payload.summary -and $null -ne $payload.summary.uptime24hAverage -and [string]$payload.summary.uptime24hAverage -ne "") {
        $uptimePercent = [Math]::Round([double]$payload.summary.uptime24hAverage, 2)
    }

    if ($null -eq $uptimePercent) { return $null }

    return [ordered]@{
        uptimePercent = $uptimePercent
        unavailableSeconds = [int][Math]::Round(86400 * (100 - [double]$uptimePercent) / 100, 0)
        updatedAt = if ($payload.updatedAt) { [string]$payload.updatedAt } else { $null }
        source = "uptime-kuma-status-page"
    }
}

function Invoke-KumaSqliteJson {
    param([Parameter(Mandatory)] [string]$Query)

    $docker = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $docker) {
        throw "Docker CLI introuvable; impossible de lire Uptime Kuma."
    }

    $raw = & $docker.Source exec $ContainerName sqlite3 -readonly -json $DatabasePath $Query 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Lecture SQLite Kuma échouée: $($raw -join ' ')"
    }

    $text = (($raw | Out-String).Trim())
    if (-not $text) { return @() }

    $parsed = $text | ConvertFrom-Json
    if ($null -eq $parsed) { return @() }
    return @($parsed)
}

function Convert-KumaStatus {
    param($Status)

    $statusCode = -1
    if ($null -ne $Status) { $statusCode = [int]$Status }

    switch ($statusCode) {
        0 { return "down" }
        1 { return "up" }
        2 { return "pending" }
        3 { return "maintenance" }
        default { return "unknown" }
    }
}

function Get-StatusClass {
    param([string]$Status)

    if ($Status -eq "up") { return "nominal" }
    if ($Status -eq "down" -or $Status -eq "pending") { return "unavailable" }
    if ($Status -eq "maintenance") { return "maintenance" }
    return "unknown"
}

function Convert-ToInt {
    param(
        $Value,
        [int]$Default = 0
    )

    if ($null -eq $Value) { return $Default }
    $parsed = 0
    if ([int]::TryParse([string]$Value, [ref]$parsed)) { return $parsed }
    return $Default
}

function Convert-ToDoubleOrNull {
    param($Value)

    if ($null -eq $Value -or [string]$Value -eq "") { return $null }
    $parsed = 0.0
    if ([double]::TryParse([string]$Value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
        return [Math]::Round($parsed, 1)
    }
    return $null
}

function Convert-ToKumaDate {
    param($Value)

    if ($null -eq $Value -or -not [string]$Value) { return $null }

    $text = ([string]$Value).Trim()
    $parsed = [DateTimeOffset]::MinValue
    $styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
    $formats = @(
        "yyyy-MM-dd HH:mm:ss.FFFFFFF",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-ddTHH:mm:ss.FFFFFFFK",
        "o"
    )

    foreach ($format in $formats) {
        if ([DateTimeOffset]::TryParseExact($text, $format, [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
            return $parsed
        }
    }
    if ([DateTimeOffset]::TryParse($text, [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
        return $parsed
    }
    if ([DateTimeOffset]::TryParse($text, [ref]$parsed)) {
        return $parsed.ToUniversalTime()
    }
    return $null
}

function Convert-ToIsoString {
    param($Value)

    $parsed = Convert-ToKumaDate $Value
    if ($parsed) { return $parsed.ToString("o") }
    if ($null -eq $Value -or -not [string]$Value) { return $null }
    return [string]$Value
}

function Convert-ToLocalIsoString {
    param($Value)

    if ($null -eq $Value) { return $null }
    $parsed = if ($Value -is [DateTimeOffset]) { $Value } else { Convert-ToKumaDate $Value }
    if ($parsed) {
        return [TimeZoneInfo]::ConvertTime($parsed, [TimeZoneInfo]::Local).ToString("yyyy-MM-dd HH:mm:ss zzz")
    }
    return $null
}

function Convert-ToPublicDate {
    param($Value)

    if ($null -eq $Value -or -not [string]$Value) { return $null }

    $text = ([string]$Value).Trim()
    $parsed = [DateTimeOffset]::MinValue
    $hasExplicitOffset = $text -match '(Z|[+-]\d{2}:?\d{2})$'
    $styles = if ($hasExplicitOffset) {
        [Globalization.DateTimeStyles]::AdjustToUniversal
    }
    else {
        [Globalization.DateTimeStyles]::AssumeLocal
    }

    $formats = @(
        "yyyy-MM-dd HH:mm:ss.FFFFFFF",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-ddTHH:mm:ss.FFFFFFFK",
        "MM/dd/yyyy HH:mm:ss",
        "M/d/yyyy HH:mm:ss",
        "o"
    )
    foreach ($format in $formats) {
        if ([DateTimeOffset]::TryParseExact($text, $format, [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
            return $parsed
        }
    }
    if ([DateTimeOffset]::TryParse($text, [Globalization.CultureInfo]::CurrentCulture, $styles, [ref]$parsed)) {
        return $parsed
    }
    if ([DateTimeOffset]::TryParse($text, [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
        return $parsed
    }
    return $null
}

function Convert-ToKumaHeartbeat {
    param($Row)

    $time = Convert-ToKumaDate $Row.time
    $durationSeconds = Convert-ToInt $Row.duration 0
    if ($durationSeconds -lt 0) { $durationSeconds = 0 }

    $endTime = Convert-ToKumaDate $Row.end_time
    if ($null -eq $endTime) { $endTime = $time }
    if ($time -and $endTime -and $endTime -lt $time) { $endTime = $time }

    $intervalEnd = $endTime
    if ($time -and $endTime -and $endTime -eq $time) {
        $intervalEnd = $time
    }
    $intervalStart = $intervalEnd
    if ($intervalEnd) {
        $intervalStart = $intervalEnd.AddSeconds(-1 * $durationSeconds)
    }
    elseif ($time) {
        $intervalStart = $time
        $intervalEnd = $time.AddSeconds($durationSeconds)
    }

    $status = Convert-KumaStatus $Row.status
    $message = if ($Row.msg) { [string]$Row.msg } else { $null }
    if ($message -and $message.Length -gt 240) { $message = $message.Substring(0, 240) }

    return [ordered]@{
        id = Convert-ToInt $Row.id 0
        status = $status
        statusCode = Convert-ToInt $Row.status -1
        statusClass = Get-StatusClass $status
        startedAt = if ($intervalStart) { $intervalStart.ToString("o") } else { $null }
        startedAtLocal = Convert-ToLocalIsoString $intervalStart
        endedAt = if ($intervalEnd) { $intervalEnd.ToString("o") } else { $null }
        endedAtLocal = Convert-ToLocalIsoString $intervalEnd
        heartbeatAt = if ($time) { $time.ToString("o") } else { $null }
        heartbeatAtLocal = Convert-ToLocalIsoString $time
        durationSeconds = $durationSeconds
        ping = Convert-ToDoubleOrNull $Row.ping
        message = $message
        important = [bool](Convert-ToInt $Row.important 0)
        downCount = Convert-ToInt $Row.down_count 0
        retries = Convert-ToInt $Row.retries 0
    }
}

function Add-WindowMessage {
    param(
        [hashtable]$Window,
        [string]$Message
    )

    if (-not $Message) { return }
    if (-not $Window.MessageSet.ContainsKey($Message)) {
        $Window.MessageSet[$Message] = $true
        $Window.Messages.Add($Message) | Out-Null
    }
}

function New-DowntimeWindow {
    param(
        [hashtable]$Heartbeat,
        $LastNominalEndedAt
    )

    $startedAt = Convert-ToKumaDate $Heartbeat.startedAt
    $endedAt = Convert-ToKumaDate $Heartbeat.endedAt
    $window = @{
        LastNominalEndedAt = $LastNominalEndedAt
        UnavailableStartedAt = $startedAt
        UnavailableEndedAt = $endedAt
        FirstFunctionalAt = $null
        LastHeartbeatId = $Heartbeat.id
        MeasuredUnavailableSeconds = [int]$Heartbeat.durationSeconds
        StatusCounts = @{}
        Messages = [Collections.Generic.List[string]]::new()
        MessageSet = @{}
    }
    $window.StatusCounts[$Heartbeat.status] = 1
    Add-WindowMessage -Window $window -Message $Heartbeat.message
    return $window
}

function Update-DowntimeWindow {
    param(
        [hashtable]$Window,
        [hashtable]$Heartbeat
    )

    $startedAt = Convert-ToKumaDate $Heartbeat.startedAt
    $endedAt = Convert-ToKumaDate $Heartbeat.endedAt
    if ($startedAt -and ((-not $Window.UnavailableStartedAt) -or $startedAt -lt $Window.UnavailableStartedAt)) {
        $Window.UnavailableStartedAt = $startedAt
    }
    if ($endedAt -and ((-not $Window.UnavailableEndedAt) -or $endedAt -gt $Window.UnavailableEndedAt)) {
        $Window.UnavailableEndedAt = $endedAt
    }
    $Window.LastHeartbeatId = $Heartbeat.id
    $Window.MeasuredUnavailableSeconds = [int]$Window.MeasuredUnavailableSeconds + [int]$Heartbeat.durationSeconds
    if (-not $Window.StatusCounts.ContainsKey($Heartbeat.status)) { $Window.StatusCounts[$Heartbeat.status] = 0 }
    $Window.StatusCounts[$Heartbeat.status] = [int]$Window.StatusCounts[$Heartbeat.status] + 1
    Add-WindowMessage -Window $Window -Message $Heartbeat.message
}

function New-GapDowntimeWindow {
    param(
        $GapStartedAt,
        $GapEndedAt,
        [int]$GapSeconds,
        $LastNominalEndedAt
    )

    $window = @{
        LastNominalEndedAt = if ($LastNominalEndedAt) { $LastNominalEndedAt } else { $GapStartedAt }
        UnavailableStartedAt = $GapStartedAt
        UnavailableEndedAt = $GapEndedAt
        FirstFunctionalAt = $null
        LastHeartbeatId = 0
        MeasuredUnavailableSeconds = $GapSeconds
        StatusCounts = @{ gap = 1 }
        Messages = [Collections.Generic.List[string]]::new()
        MessageSet = @{}
    }
    Add-WindowMessage -Window $window -Message ("Aucun heartbeat Uptime Kuma pendant {0} secondes." -f $GapSeconds)
    return $window
}

function Update-DowntimeWindowWithGap {
    param(
        [hashtable]$Window,
        $GapStartedAt,
        $GapEndedAt,
        [int]$GapSeconds
    )

    if ($GapStartedAt -and ((-not $Window.UnavailableStartedAt) -or $GapStartedAt -lt $Window.UnavailableStartedAt)) {
        $Window.UnavailableStartedAt = $GapStartedAt
    }
    if ($GapEndedAt -and ((-not $Window.UnavailableEndedAt) -or $GapEndedAt -gt $Window.UnavailableEndedAt)) {
        $Window.UnavailableEndedAt = $GapEndedAt
    }
    $Window.MeasuredUnavailableSeconds = [int]$Window.MeasuredUnavailableSeconds + $GapSeconds
    if (-not $Window.StatusCounts.ContainsKey("gap")) { $Window.StatusCounts["gap"] = 0 }
    $Window.StatusCounts["gap"] = [int]$Window.StatusCounts["gap"] + 1
    Add-WindowMessage -Window $Window -Message ("Aucun heartbeat Uptime Kuma pendant {0} secondes." -f $GapSeconds)
}

function Convert-WindowStatusCounts {
    param([hashtable]$StatusCounts)

    $result = [ordered]@{}
    foreach ($key in @($StatusCounts.Keys | Sort-Object)) {
        $result[$key] = [int]$StatusCounts[$key]
    }
    return $result
}

function Close-DowntimeWindow {
    param(
        [hashtable]$Window,
        $FirstFunctionalAt,
        [int]$Sequence
    )

    if ($FirstFunctionalAt) { $Window.FirstFunctionalAt = $FirstFunctionalAt }

    $windowStart = $Window.UnavailableStartedAt
    if (-not $windowStart -and $Window.LastNominalEndedAt) { $windowStart = $Window.LastNominalEndedAt }
    $windowEnd = $Window.UnavailableEndedAt
    if (-not $windowEnd -and $Window.FirstFunctionalAt) { $windowEnd = $Window.FirstFunctionalAt }

    $spanSeconds = [int]$Window.MeasuredUnavailableSeconds
    if ($windowStart -and $windowEnd -and $windowEnd -gt $windowStart) {
        $spanSeconds = [int][Math]::Round(($windowEnd - $windowStart).TotalSeconds, 0)
    }
    if ($spanSeconds -lt [int]$Window.MeasuredUnavailableSeconds) {
        $spanSeconds = [int]$Window.MeasuredUnavailableSeconds
    }

    return [ordered]@{
        id = "kuma-window-{0:0000}" -f $Sequence
        status = if ($Window.FirstFunctionalAt) { "resolved" } else { "open" }
        startedAt = if ($windowStart) { $windowStart.ToString("o") } else { $null }
        startedAtLocal = Convert-ToLocalIsoString $windowStart
        endedAt = if ($windowEnd) { $windowEnd.ToString("o") } else { $null }
        endedAtLocal = Convert-ToLocalIsoString $windowEnd
        durationSeconds = $spanSeconds
        measuredUnavailableSeconds = [int]$Window.MeasuredUnavailableSeconds
        lastNominalAt = if ($Window.LastNominalEndedAt) { $Window.LastNominalEndedAt.ToString("o") } else { $null }
        lastNominalAtLocal = Convert-ToLocalIsoString $Window.LastNominalEndedAt
        unavailableStartedAt = if ($Window.UnavailableStartedAt) { $Window.UnavailableStartedAt.ToString("o") } else { $null }
        unavailableStartedAtLocal = Convert-ToLocalIsoString $Window.UnavailableStartedAt
        unavailableEndedAt = if ($Window.UnavailableEndedAt) { $Window.UnavailableEndedAt.ToString("o") } else { $null }
        unavailableEndedAtLocal = Convert-ToLocalIsoString $Window.UnavailableEndedAt
        firstFunctionalAt = if ($Window.FirstFunctionalAt) { $Window.FirstFunctionalAt.ToString("o") } else { $null }
        firstFunctionalAtLocal = Convert-ToLocalIsoString $Window.FirstFunctionalAt
        lastHeartbeatId = [int]$Window.LastHeartbeatId
        statusCounts = Convert-WindowStatusCounts $Window.StatusCounts
        messages = [object[]]@($Window.Messages)
    }
}

function Measure-HeartbeatTotals {
    param(
        [object[]]$Heartbeats,
        $Since
    )

    $up = 0
    $down = 0
    $maintenance = 0
    $unknown = 0
    foreach ($beat in $Heartbeats) {
        $endedAt = Convert-ToKumaDate $beat.endedAt
        if ($Since -and $endedAt -and $endedAt -lt $Since) { continue }
        $duration = [int]$beat.durationSeconds
        switch ($beat.statusClass) {
            "nominal" { $up += $duration }
            "unavailable" { $down += $duration }
            "maintenance" { $maintenance += $duration }
            default { $unknown += $duration }
        }
    }

    $denominator = $up + $down
    $uptimePercent = $null
    if ($denominator -gt 0) {
        $uptimePercent = [Math]::Round(($up / $denominator) * 100, 4)
    }

    return [ordered]@{
        upSeconds = $up
        unavailableSeconds = $down
        maintenanceSeconds = $maintenance
        unknownSeconds = $unknown
        observedSeconds = $up + $down + $maintenance + $unknown
        uptimePercent = $uptimePercent
    }
}

function Measure-HeartbeatGapSeconds {
    param(
        [object[]]$Heartbeats,
        $Since
    )

    $gapThresholdSeconds = [Math]::Max($config.RecoveryStaleSeconds, $config.MetricIntervalSeconds * 4)
    $previousEndedAt = $null
    $total = 0

    foreach ($beat in $Heartbeats) {
        $startedAt = Convert-ToKumaDate $beat.startedAt
        $endedAt = Convert-ToKumaDate $beat.endedAt
        if ($previousEndedAt -and $startedAt) {
            $gapSeconds = [int][Math]::Round(($startedAt - $previousEndedAt).TotalSeconds, 0)
            if ($gapSeconds -gt $gapThresholdSeconds) {
                $gapStart = $previousEndedAt
                $gapEnd = $startedAt
                if ($Since) {
                    if ($gapEnd -le $Since) {
                        $previousEndedAt = $endedAt
                        continue
                    }
                    if ($gapStart -lt $Since) { $gapStart = $Since }
                }
                if ($gapEnd -gt $gapStart) {
                    $total += [int][Math]::Round(($gapEnd - $gapStart).TotalSeconds, 0)
                }
            }
        }
        if ($endedAt) { $previousEndedAt = $endedAt }
    }

    return $total
}

function Add-GapSecondsToTotals {
    param(
        $Totals,
        [int]$GapSeconds
    )

    if ($GapSeconds -le 0) { return $Totals }
    $Totals.unavailableSeconds = [int]$Totals.unavailableSeconds + $GapSeconds
    $Totals.observedSeconds = [int]$Totals.observedSeconds + $GapSeconds
    $denominator = [int]$Totals.upSeconds + [int]$Totals.unavailableSeconds
    if ($denominator -gt 0) {
        $Totals.uptimePercent = [Math]::Round(([int]$Totals.upSeconds / $denominator) * 100, 4)
    }
    return $Totals
}

function Get-DowntimeWindows {
    param([object[]]$Heartbeats)

    $windows = [Collections.Generic.List[object]]::new()
    $current = $null
    $lastNominalEndedAt = $null
    $previousBeatEndedAt = $null
    $sequence = 1
    $mergeGapSeconds = [Math]::Max(120, $config.MetricIntervalSeconds * 4)
    $missingHeartbeatThresholdSeconds = [Math]::Max($config.RecoveryStaleSeconds, $config.MetricIntervalSeconds * 4)

    foreach ($beatObject in $Heartbeats) {
        $beat = @{}
        foreach ($property in $beatObject.GetEnumerator()) {
            $beat[$property.Key] = $property.Value
        }

        $startedAt = Convert-ToKumaDate $beat.startedAt
        $endedAt = Convert-ToKumaDate $beat.endedAt
        if ($previousBeatEndedAt -and $startedAt) {
            $missingSeconds = [int][Math]::Round(($startedAt - $previousBeatEndedAt).TotalSeconds, 0)
            if ($missingSeconds -gt $missingHeartbeatThresholdSeconds) {
                if ($current) {
                    Update-DowntimeWindowWithGap -Window $current -GapStartedAt $previousBeatEndedAt -GapEndedAt $startedAt -GapSeconds $missingSeconds
                }
                else {
                    $current = New-GapDowntimeWindow -GapStartedAt $previousBeatEndedAt -GapEndedAt $startedAt -GapSeconds $missingSeconds -LastNominalEndedAt $lastNominalEndedAt
                }
            }
        }

        if ($beat.statusClass -eq "nominal") {
            if ($current) {
                $recoveredAt = $startedAt
                if (-not $recoveredAt) { $recoveredAt = $endedAt }
                $windows.Add((Close-DowntimeWindow -Window $current -FirstFunctionalAt $recoveredAt -Sequence $sequence)) | Out-Null
                $sequence++
                $current = $null
            }
            if ($endedAt) { $lastNominalEndedAt = $endedAt }
            if ($endedAt) { $previousBeatEndedAt = $endedAt }
            continue
        }

        if ($beat.statusClass -ne "unavailable") {
            if ($endedAt) { $previousBeatEndedAt = $endedAt }
            continue
        }

        if ($current) {
            $gapSeconds = 0
            if ($startedAt -and $current.UnavailableEndedAt) {
                $gapSeconds = [int][Math]::Round(($startedAt - $current.UnavailableEndedAt).TotalSeconds, 0)
            }
            if ($gapSeconds -le $mergeGapSeconds) {
                Update-DowntimeWindow -Window $current -Heartbeat $beat
                if ($endedAt) { $previousBeatEndedAt = $endedAt }
                continue
            }

            $windows.Add((Close-DowntimeWindow -Window $current -FirstFunctionalAt $null -Sequence $sequence)) | Out-Null
            $sequence++
        }

        $current = New-DowntimeWindow -Heartbeat $beat -LastNominalEndedAt $lastNominalEndedAt
        if ($endedAt) { $previousBeatEndedAt = $endedAt }
    }

    if ($current) {
        $windows.Add((Close-DowntimeWindow -Window $current -FirstFunctionalAt $null -Sequence $sequence)) | Out-Null
    }

    return @($windows)
}

function Get-ObjectPropertyValue {
    param(
        $Object,
        [string]$Name
    )

    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if ($property) { return $property.Value }
    return $null
}

function Read-JsonFileOrNull {
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return (Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json)
    }
    catch {
        return [pscustomobject]@{
            __invalid = $true
            __error = $_.Exception.Message
        }
    }
}

function Get-PublicDataProbe {
    param(
        [string]$Name,
        [string]$Path,
        [int]$MaxAgeSeconds,
        $NowUtc,
        [switch]$PreferFileTimestamp
    )

    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if (-not (Test-Path -LiteralPath $resolved)) {
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

    $item = Get-Item -LiteralPath $resolved
    $payload = Read-JsonFileOrNull -Path $resolved
    if ($payload -and (Get-ObjectPropertyValue $payload "__invalid")) {
        return [ordered]@{
            name = $Name
            status = "invalid"
            updatedAt = $item.LastWriteTimeUtc.ToString("o")
            ageSeconds = [int][Math]::Round(($NowUtc - [DateTimeOffset]$item.LastWriteTimeUtc).TotalSeconds, 0)
            maxAgeSeconds = $MaxAgeSeconds
            ok = $false
            error = [string](Get-ObjectPropertyValue $payload "__error")
        }
    }

    $contentUpdatedValue = Get-ObjectPropertyValue $payload "updatedAt"
    if (-not $contentUpdatedValue) { $contentUpdatedValue = Get-ObjectPropertyValue $payload "generatedAt" }
    if (-not $contentUpdatedValue) { $contentUpdatedValue = Get-ObjectPropertyValue $payload "checkedAt" }
    $contentUpdatedAt = Convert-ToPublicDate $contentUpdatedValue
    $updatedAt = if ($PreferFileTimestamp) { [DateTimeOffset]$item.LastWriteTimeUtc } else { $contentUpdatedAt }
    if (-not $updatedAt) { $updatedAt = [DateTimeOffset]$item.LastWriteTimeUtc }

    $ageSeconds = [int][Math]::Round(($NowUtc - $updatedAt.ToUniversalTime()).TotalSeconds, 0)
    if ($ageSeconds -lt 0) { $ageSeconds = 0 }
    $payloadOk = Get-ObjectPropertyValue $payload "ok"
    $isOk = if ($null -eq $payloadOk) { $true } else { [bool]$payloadOk }
    $status = if (-not $isOk) { "degraded" } elseif ($ageSeconds -gt $MaxAgeSeconds) { "stale" } else { "fresh" }

    return [ordered]@{
        name = $Name
        status = $status
        updatedAt = $updatedAt.ToString("o")
        contentUpdatedAt = if ($contentUpdatedAt) { $contentUpdatedAt.ToString("o") } else { $null }
        fileUpdatedAt = ([DateTimeOffset]$item.LastWriteTimeUtc).ToString("o")
        ageSeconds = $ageSeconds
        maxAgeSeconds = $MaxAgeSeconds
        ok = $isOk
        error = if ($isOk) { $null } else { [string](Get-ObjectPropertyValue $payload "error") }
    }
}

function New-ErrorPayload {
    param(
        [string]$Source,
        [string]$ErrorMessage
    )

    $now = Get-Date
    return [ordered]@{
        version = 1
        ok = $false
        source = $Source
        updatedAt = $now.ToString("o")
        updatedAtLocal = $now.ToString("yyyy-MM-dd HH:mm:ss")
        error = $ErrorMessage
    }
}

New-Item -ItemType Directory -Force -Path $DataDirectory | Out-Null
$now = Get-Date
$nowUtc = [DateTimeOffset]::UtcNow

try {
    $monitorQuery = "select id, name, type, active from monitor where id = $MonitorId limit 1;"
    $monitorRows = @(Invoke-KumaSqliteJson -Query $monitorQuery)
    if ($monitorRows.Count -eq 0) {
        throw "Monitor Uptime Kuma introuvable: id=$MonitorId."
    }
    $monitor = $monitorRows[0]

    $heartbeatQuery = @"
select
  id,
  monitor_id,
  status,
  coalesce(msg, '') as msg,
  time,
  ping,
  duration,
  end_time,
  important,
  down_count,
  retries
from heartbeat
where monitor_id = $MonitorId
  and time >= datetime('now', '-$HistoryDays days')
order by time asc;
"@
    $heartbeatRows = @(Invoke-KumaSqliteJson -Query $heartbeatQuery)
    $heartbeats = @($heartbeatRows | ForEach-Object { Convert-ToKumaHeartbeat $_ })
    $latestHeartbeat = if ($heartbeats.Count -gt 0) { $heartbeats[-1] } else { $null }
    $windows = Get-DowntimeWindows -Heartbeats $heartbeats

    $totals = Measure-HeartbeatTotals -Heartbeats $heartbeats -Since $null
    $last24h = Measure-HeartbeatTotals -Heartbeats $heartbeats -Since $nowUtc.AddHours(-24)
    $last7d = Measure-HeartbeatTotals -Heartbeats $heartbeats -Since $nowUtc.AddDays(-7)
    $gapSecondsAll = Measure-HeartbeatGapSeconds -Heartbeats $heartbeats -Since $null
    $gapSeconds24h = Measure-HeartbeatGapSeconds -Heartbeats $heartbeats -Since $nowUtc.AddHours(-24)
    $gapSeconds7d = Measure-HeartbeatGapSeconds -Heartbeats $heartbeats -Since $nowUtc.AddDays(-7)
    $totals = Add-GapSecondsToTotals -Totals $totals -GapSeconds $gapSecondsAll
    $last24h = Add-GapSecondsToTotals -Totals $last24h -GapSeconds $gapSeconds24h
    $last7d = Add-GapSecondsToTotals -Totals $last7d -GapSeconds $gapSeconds7d
    $uptimeDataPath = Join-Path $DataDirectory "public-uptime.json"
    $statusPage24h = Get-PublicUptime24hSnapshot -Path $uptimeDataPath
    $publishedLast24hUptime = if ($statusPage24h) { $statusPage24h.uptimePercent } else { $last24h.uptimePercent }
    $publishedLast24hUnavailableSeconds = if ($statusPage24h) { $statusPage24h.unavailableSeconds } else { $last24h.unavailableSeconds }
    $publishedLast24hSource = if ($statusPage24h) { $statusPage24h.source } else { "uptime-kuma-sqlite-reconstruction" }
    $publishedLast24hTotals = if ($statusPage24h) {
        [ordered]@{
            upSeconds = [int](86400 - [int]$statusPage24h.unavailableSeconds)
            unavailableSeconds = [int]$statusPage24h.unavailableSeconds
            maintenanceSeconds = 0
            unknownSeconds = 0
            observedSeconds = 86400
            uptimePercent = $statusPage24h.uptimePercent
            source = $statusPage24h.source
            statusPageUpdatedAt = $statusPage24h.updatedAt
        }
    }
    else {
        $last24h
    }

    $latestStatus = if ($latestHeartbeat) { $latestHeartbeat.status } else { "unknown" }
    $latestHeartbeatAt = if ($latestHeartbeat) { $latestHeartbeat.heartbeatAt } else { $null }
    $latestHeartbeatDate = Convert-ToKumaDate $latestHeartbeatAt
    $heartbeatAgeSeconds = $null
    if ($latestHeartbeatDate) {
        $heartbeatAgeSeconds = [int][Math]::Round(($nowUtc - $latestHeartbeatDate.ToUniversalTime()).TotalSeconds, 0)
        if ($heartbeatAgeSeconds -lt 0) { $heartbeatAgeSeconds = 0 }
    }

    $fresh = $true
    if ($null -eq $heartbeatAgeSeconds -or $heartbeatAgeSeconds -gt $config.RecoveryStaleSeconds) { $fresh = $false }

    $historyPayload = [ordered]@{
        version = 1
        ok = $true
        source = "uptime-kuma-sqlite"
        updatedAt = $now.ToString("o")
        updatedAtLocal = $now.ToString("yyyy-MM-dd HH:mm:ss")
        localTimeZone = [ordered]@{
            id = [TimeZoneInfo]::Local.Id
            displayName = [TimeZoneInfo]::Local.DisplayName
        }
        historyDays = $HistoryDays
        monitor = [ordered]@{
            id = [int]$monitor.id
            name = [string]$monitor.name
            type = [string]$monitor.type
            active = [bool]$monitor.active
        }
        latest = [ordered]@{
            status = $latestStatus
            statusClass = if ($latestHeartbeat) { $latestHeartbeat.statusClass } else { "unknown" }
            heartbeatAt = $latestHeartbeatAt
            heartbeatAgeSeconds = $heartbeatAgeSeconds
            fresh = $fresh
            ping = if ($latestHeartbeat) { $latestHeartbeat.ping } else { $null }
            message = if ($latestHeartbeat) { $latestHeartbeat.message } else { $null }
        }
        summary = [ordered]@{
            all = $totals
            last24h = $publishedLast24hTotals
            last24hObserved = $last24h
            last24hStatusPage = $statusPage24h
            last7d = $last7d
            missingHeartbeatGapSeconds = $gapSecondsAll
            missingHeartbeatGapSecondsLast24h = $gapSeconds24h
            missingHeartbeatGapSecondsLast7d = $gapSeconds7d
            heartbeatCount = $heartbeats.Count
            downtimeWindowCount = $windows.Count
            resolvedDowntimeWindowCount = @($windows | Where-Object { $_.status -eq "resolved" }).Count
            openDowntimeWindowCount = @($windows | Where-Object { $_.status -eq "open" }).Count
        }
        windows = [object[]]@($windows | Select-Object -Last 200)
        recentHeartbeats = [object[]]@($heartbeats | Select-Object -Last 500)
    }

    Write-JsonFile -Path $OutputPath -Payload $historyPayload

    $publicMetricMaxAgeSeconds = [Math]::Max(90, $config.MetricIntervalSeconds * 4)
    $publicEventsMaxAgeSeconds = [Math]::Max(60, $config.EventSyncIntervalSeconds * 4)
    $publicDiagnosticsMaxAgeSeconds = 26 * 60 * 60
    $dataChecks = @(
        Get-PublicDataProbe -Name "metrics" -Path (Join-Path $DataDirectory "public-metrics.json") -MaxAgeSeconds $publicMetricMaxAgeSeconds -NowUtc $nowUtc
        Get-PublicDataProbe -Name "stats" -Path (Join-Path $DataDirectory "public-stats.json") -MaxAgeSeconds 900 -NowUtc $nowUtc
        Get-PublicDataProbe -Name "uptime" -Path $uptimeDataPath -MaxAgeSeconds 300 -NowUtc $nowUtc
        Get-PublicDataProbe -Name "uptimeHistory" -Path $OutputPath -MaxAgeSeconds 300 -NowUtc $nowUtc
        Get-PublicDataProbe -Name "saveIndex" -Path (Join-Path $DataDirectory "public-save-index.json") -MaxAgeSeconds 900 -NowUtc $nowUtc -PreferFileTimestamp
        Get-PublicDataProbe -Name "saveSnapshot" -Path (Join-Path $DataDirectory "public-save-snapshot.json") -MaxAgeSeconds 900 -NowUtc $nowUtc -PreferFileTimestamp
        Get-PublicDataProbe -Name "saveBases" -Path (Join-Path $DataDirectory "public-save-bases.json") -MaxAgeSeconds 900 -NowUtc $nowUtc -PreferFileTimestamp
        Get-PublicDataProbe -Name "saveDiagnostics" -Path (Join-Path $DataDirectory "public-save-diagnostics.json") -MaxAgeSeconds $publicDiagnosticsMaxAgeSeconds -NowUtc $nowUtc -PreferFileTimestamp
        Get-PublicDataProbe -Name "events" -Path (Join-Path $DataDirectory "public-events.json") -MaxAgeSeconds $publicEventsMaxAgeSeconds -NowUtc $nowUtc
        Get-PublicDataProbe -Name "recentEvents" -Path (Join-Path $DataDirectory "public-events-recent.json") -MaxAgeSeconds $publicEventsMaxAgeSeconds -NowUtc $nowUtc
    )
    $badChecks = @($dataChecks | Where-Object { $_.status -ne "fresh" })
    $currentAvailability = if ($latestHeartbeat -and $latestHeartbeat.statusClass -eq "nominal" -and $fresh -and $badChecks.Count -eq 0) {
        "up"
    }
    elseif ($latestHeartbeat -and $latestHeartbeat.statusClass -eq "unavailable") {
        "down"
    }
    else {
        "degraded"
    }

    $availabilityPayload = [ordered]@{
        version = 1
        ok = $badChecks.Count -eq 0 -and $currentAvailability -eq "up"
        source = "gaylemon-local-recovery"
        updatedAt = $now.ToString("o")
        updatedAtLocal = $now.ToString("yyyy-MM-dd HH:mm:ss")
        localTimeZone = [ordered]@{
            id = [TimeZoneInfo]::Local.Id
            displayName = [TimeZoneInfo]::Local.DisplayName
        }
        status = $currentAvailability
        summary = [ordered]@{
            monitorStatus = $latestStatus
            monitorFresh = $fresh
            heartbeatAgeSeconds = $heartbeatAgeSeconds
            staleOrMissingDataSets = $badChecks.Count
            downtimeWindowCount = $windows.Count
            uptimeLast24h = $publishedLast24hUptime
            unavailableSecondsLast24h = $publishedLast24hUnavailableSeconds
            uptimeLast24hSource = $publishedLast24hSource
            uptimeLast24hStatusPageUpdatedAt = if ($statusPage24h) { $statusPage24h.updatedAt } else { $null }
            uptimeLast24hObserved = $last24h.uptimePercent
            unavailableSecondsLast24hObserved = $last24h.unavailableSeconds
            uptimeLast24hObservedSource = "uptime-kuma-sqlite-duration-sum"
            uptimeAll = $totals.uptimePercent
            unavailableSecondsAll = $totals.unavailableSeconds
        }
        dataFreshness = [object[]]$dataChecks
        downtimeWindows = [object[]]@($windows | Select-Object -Last 20)
    }

    Write-JsonFile -Path $AvailabilityOutputPath -Payload $availabilityPayload
    Write-Host "Uptime Kuma history exported to $OutputPath"
    Write-Host "Availability ledger exported to $AvailabilityOutputPath"
}
catch {
    $message = $_.Exception.Message
    Write-JsonFile -Path $OutputPath -Payload (New-ErrorPayload -Source "uptime-kuma-sqlite" -ErrorMessage $message)
    Write-JsonFile -Path $AvailabilityOutputPath -Payload (New-ErrorPayload -Source "gaylemon-local-recovery" -ErrorMessage $message)
    throw
}
