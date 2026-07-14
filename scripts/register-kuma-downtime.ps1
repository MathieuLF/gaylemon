param(
    [string]$HistoryPath = (Join-Path $PSScriptRoot "..\portal\data\public-uptime-history.json"),
    [string]$ReportPath = (Join-Path $PSScriptRoot "..\runtime\recovery\kuma-downtime-registration-latest.json"),
    [int]$ExpectedIntervalSeconds = 30,
    [int]$MinimumGapSeconds = 90,
    [switch]$Apply
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot

try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $OutputEncoding = [Console]::OutputEncoding
}
catch {
    # Best effort for older PowerShell hosts.
}

function Read-JsonFile {
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Fichier JSON introuvable: $Path"
    }
    return (Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json)
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] $Payload
    )

    $directory = Split-Path -Parent $Path
    if ($directory) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $json = $Payload | ConvertTo-Json -Depth 18
    [IO.File]::WriteAllText($resolved, $json.TrimEnd() + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}

function Convert-ToDate {
    param($Value)

    if ($null -eq $Value -or -not [string]$Value) { return $null }
    if ($Value -is [DateTimeOffset]) {
        return $Value.ToUniversalTime()
    }
    if ($Value -is [DateTime]) {
        $dateTime = [DateTime]$Value
        if ($dateTime.Kind -eq [DateTimeKind]::Utc) {
            return [DateTimeOffset]::new($dateTime)
        }
        if ($dateTime.Kind -eq [DateTimeKind]::Local) {
            return [DateTimeOffset]::new($dateTime).ToUniversalTime()
        }
        return ([DateTimeOffset]::new($dateTime, [TimeZoneInfo]::Local.GetUtcOffset($dateTime))).ToUniversalTime()
    }

    $parsed = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse([string]$Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) {
        return $parsed.ToUniversalTime()
    }
    if ([DateTimeOffset]::TryParse([string]$Value, [ref]$parsed)) {
        return $parsed.ToUniversalTime()
    }
    return $null
}

function Convert-ToUnixSeconds {
    param([DateTimeOffset]$Value)

    return [int64][Math]::Floor(($Value.ToUniversalTime() - [DateTimeOffset]::FromUnixTimeSeconds(0)).TotalSeconds)
}

function Convert-ToDbTime {
    param([DateTimeOffset]$Value)

    return $Value.ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss.fff", [Globalization.CultureInfo]::InvariantCulture)
}

function Convert-ToLocalString {
    param([DateTimeOffset]$Value)

    return [TimeZoneInfo]::ConvertTime($Value, [TimeZoneInfo]::Local).ToString("yyyy-MM-dd HH:mm:ss zzz")
}

function Escape-SqliteString {
    param([AllowNull()] [string]$Value)

    if ($null -eq $Value) { return "" }
    return $Value.Replace("'", "''")
}

function New-CorrectionId {
    param(
        [string]$StartedAt,
        [string]$EndedAt
    )

    $inputText = "$StartedAt|$EndedAt"
    $sha1 = [Security.Cryptography.SHA1]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($inputText)
        $hash = [BitConverter]::ToString($sha1.ComputeHash($bytes)).Replace("-", "").ToLowerInvariant()
        return "gaylemon-" + $hash.Substring(0, 12)
    }
    finally {
        $sha1.Dispose()
    }
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

function Get-StatusCount {
    param(
        $StatusCounts,
        [string]$Name
    )

    $value = Get-ObjectPropertyValue -Object $StatusCounts -Name $Name
    if ($null -eq $value) { return 0 }
    return [int]$value
}

function Invoke-KumaSqlite {
    param(
        [Parameter(Mandatory)] [string]$Sql,
        [switch]$Json,
        [switch]$Write
    )

    $docker = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $docker) {
        throw "Docker CLI introuvable; impossible de joindre Uptime Kuma."
    }

    $args = @("exec")
    if ($Write) { $args += "-i" }
    $args += @($config.UptimeKumaContainer, "sqlite3")
    if (-not $Write) { $args += "-readonly" }
    if ($Json) { $args += "-json" }
    $args += @($config.UptimeKumaDbPath)

    if ($Write) {
        $output = $Sql | & $docker.Source @args 2>&1
    }
    else {
        $args += $Sql
        $output = & $docker.Source @args 2>&1
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Commande SQLite Kuma echouee: $($output -join ' ')"
    }

    $text = (($output | Out-String).Trim())
    if (-not $Json) { return $text }
    if (-not $text) { return @() }
    return @($text | ConvertFrom-Json)
}

function Backup-KumaDatabase {
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
    $backupPath = "/app/data/gaylemon-kuma-backup-$stamp.db"
    $sql = ".backup '$backupPath'"
    Invoke-KumaSqlite -Sql $sql | Out-Null
    return $backupPath
}

function Add-BucketSlot {
    param(
        [hashtable]$Buckets,
        [DateTimeOffset]$Cursor,
        [int]$WidthSeconds
    )

    $unix = Convert-ToUnixSeconds $Cursor
    $bucket = $unix - ($unix % $WidthSeconds)
    $key = [string]$bucket
    if (-not $Buckets.ContainsKey($key)) { $Buckets[$key] = 0 }
    $Buckets[$key] = [int]$Buckets[$key] + 1
}

function Get-StatBuckets {
    param(
        [DateTimeOffset]$StartedAt,
        [DateTimeOffset]$EndedAt
    )

    $minutely = @{}
    $hourly = @{}
    $daily = @{}
    $cursor = $StartedAt
    while ($cursor -lt $EndedAt) {
        Add-BucketSlot -Buckets $minutely -Cursor $cursor -WidthSeconds 60
        Add-BucketSlot -Buckets $hourly -Cursor $cursor -WidthSeconds 3600
        Add-BucketSlot -Buckets $daily -Cursor $cursor -WidthSeconds 86400
        $cursor = $cursor.AddSeconds($ExpectedIntervalSeconds)
    }

    return [pscustomobject]@{
        minutely = $minutely
        hourly = $hourly
        daily = $daily
    }
}

function New-StatUpsertSql {
    param(
        [string]$Table,
        [hashtable]$Buckets
    )

    $lines = [Collections.Generic.List[string]]::new()
    foreach ($key in @($Buckets.Keys | Sort-Object {[int64]$_})) {
        $timestamp = [int64]$key
        $down = [int]$Buckets[$key]
        $lines.Add("insert into $Table (monitor_id, timestamp, ping, up, down, ping_min, ping_max, extras) values ($($config.UptimeKumaMonitorId), $timestamp, 0, 0, $down, 0, 0, 'gaylemon-correction') on conflict(monitor_id, timestamp) do update set down = down + excluded.down;") | Out-Null
    }
    return @($lines)
}

function New-CorrectionSql {
    param($Candidate)

    $startedAt = Convert-ToDate $Candidate.startedAt
    $endedAt = Convert-ToDate $Candidate.endedAt
    $duration = [int][Math]::Round(($endedAt - $startedAt).TotalSeconds, 0)
    $message = Escape-SqliteString ("Gaylemon outage correction {0}: absence de heartbeat Kuma entre dernier nominal et reprise fonctionnelle." -f $Candidate.correctionId)
    $dbTime = Convert-ToDbTime $endedAt
    $buckets = Get-StatBuckets -StartedAt $startedAt -EndedAt $endedAt
    $sql = [Collections.Generic.List[string]]::new()
    $sql.Add("insert into heartbeat (important, monitor_id, status, msg, time, ping, duration, down_count, end_time, retries, response) values (1, $($config.UptimeKumaMonitorId), 0, '$message', '$dbTime', null, $duration, 0, '$dbTime', 0, null);") | Out-Null
    foreach ($line in New-StatUpsertSql -Table "stat_minutely" -Buckets $buckets.minutely) { $sql.Add($line) | Out-Null }
    foreach ($line in New-StatUpsertSql -Table "stat_hourly" -Buckets $buckets.hourly) { $sql.Add($line) | Out-Null }
    foreach ($line in New-StatUpsertSql -Table "stat_daily" -Buckets $buckets.daily) { $sql.Add($line) | Out-Null }
    return @($sql)
}

function Test-CorrectionExists {
    param([string]$CorrectionId)

    $escaped = Escape-SqliteString $CorrectionId
    $rows = Invoke-KumaSqlite -Json -Sql "select id from heartbeat where monitor_id = $($config.UptimeKumaMonitorId) and msg like '%$escaped%' limit 1;"
    return @($rows).Count -gt 0
}

$now = Get-Date
$history = Read-JsonFile -Path $HistoryPath
if (-not $history.ok) {
    throw "Historique Kuma invalide: $($history.error)"
}

$candidates = [Collections.Generic.List[object]]::new()
foreach ($window in @($history.windows)) {
    $gapCount = Get-StatusCount -StatusCounts $window.statusCounts -Name "gap"
    $startedAt = Convert-ToDate $window.startedAt
    $endedAt = Convert-ToDate $window.endedAt
    if ($gapCount -le 0 -or -not $startedAt -or -not $endedAt) { continue }

    $duration = [int][Math]::Round(($endedAt - $startedAt).TotalSeconds, 0)
    if ($duration -lt $MinimumGapSeconds) { continue }

    $correctionId = New-CorrectionId -StartedAt $window.startedAt -EndedAt $window.endedAt
    $exists = Test-CorrectionExists -CorrectionId $correctionId
    $candidates.Add([ordered]@{
        correctionId = $correctionId
        windowId = $window.id
        startedAt = $startedAt.ToString("o")
        startedAtLocal = Convert-ToLocalString $startedAt
        endedAt = $endedAt.ToString("o")
        endedAtLocal = Convert-ToLocalString $endedAt
        durationSeconds = $duration
        measuredUnavailableSeconds = [int]$window.measuredUnavailableSeconds
        gapCount = $gapCount
        alreadyRegistered = $exists
        action = if ($exists) { "skip" } elseif ($Apply) { "apply" } else { "dry-run" }
    }) | Out-Null
}

$backupPath = $null
$applied = 0
$pendingCount = @($candidates | Where-Object { -not $_.alreadyRegistered }).Count
if ($Apply) {
    $toApply = @($candidates | Where-Object { -not $_.alreadyRegistered })
    if ($toApply.Count -gt 0) {
        $backupPath = Backup-KumaDatabase
        $sql = [Collections.Generic.List[string]]::new()
        $sql.Add("begin immediate;") | Out-Null
        foreach ($candidate in $toApply) {
            foreach ($line in New-CorrectionSql -Candidate $candidate) { $sql.Add($line) | Out-Null }
            $applied++
        }
        $sql.Add("commit;") | Out-Null
        Invoke-KumaSqlite -Sql ($sql -join [Environment]::NewLine) -Write | Out-Null
    }
}

$report = [ordered]@{
    version = 1
    ok = $true
    mode = if ($Apply) { "apply" } else { "dry-run" }
    checkedAt = $now.ToString("o")
    historyPath = $HistoryPath
    monitorId = $config.UptimeKumaMonitorId
    container = $config.UptimeKumaContainer
    databasePath = $config.UptimeKumaDbPath
    localTimeZone = [ordered]@{
        id = [TimeZoneInfo]::Local.Id
        displayName = [TimeZoneInfo]::Local.DisplayName
    }
    expectedIntervalSeconds = $ExpectedIntervalSeconds
    minimumGapSeconds = $MinimumGapSeconds
    backupPath = $backupPath
    candidateCount = $candidates.Count
    pendingCount = $pendingCount
    appliedCount = $applied
    candidates = [object[]]$candidates
}

Write-JsonFile -Path $ReportPath -Payload $report

$color = if ($Apply -and $applied -gt 0) { "Green" } elseif ($candidates.Count -gt 0) { "Yellow" } else { "Green" }
Write-Host "Corrections Kuma candidates: $($candidates.Count); appliquees: $applied" -ForegroundColor $color
Write-Host "Rapport: $ReportPath"
if (-not $Apply -and $pendingCount -gt 0) {
    Write-Host "Relancer avec -Apply pour inscrire les corrections dans Uptime Kuma."
}
