param(
    [string]$OutputPath = (Join-Path $PSScriptRoot "..\portal\data\metrics.json"),
    [int]$UptimeHistoryIntervalMinutes = 10,
    [int]$SaveSnapshotIntervalMinutes = 15,
    [int]$DiagnosticsRefreshIntervalHours = 2,
    [int]$DiagnosticsRefreshAnchorHour = 1,
    [int]$DiagnosticsRefreshWindowMinutes = 15,
    [int]$EventsIntervalMinutes = 1,
    [int]$AssetAuditIntervalHours = 6,
    [switch]$FastOnly,
    [switch]$ForceHeavy
)

$ErrorActionPreference = "Stop"

try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $OutputEncoding = [Console]::OutputEncoding
}
catch {
    # Best effort for older PowerShell hosts.
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

function Read-PalworldJson {
    param([ValidateSet("info", "players", "metrics")] [string]$Endpoint)

    $raw = & (Join-Path $PSScriptRoot "palworld-api.ps1") $Endpoint
    if ($LASTEXITCODE -ne 0) {
        throw "palworld-api.ps1 $Endpoint failed with exit code $LASTEXITCODE."
    }

    return (($raw | Out-String).Trim() | ConvertFrom-Json)
}

$outputItem = Get-Item -LiteralPath $OutputPath -ErrorAction SilentlyContinue
$outputDirectory = if ($outputItem -and $outputItem.PSIsContainer) {
    $outputItem.FullName
}
else {
    Split-Path -Parent $OutputPath
}

New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$warningLogPath = Join-Path $outputDirectory "metrics-update-warnings.log"

function Write-UpdateWarning {
    param([Parameter(Mandatory)] [string]$Message)

    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    try {
        Add-Content -LiteralPath $warningLogPath -Value $line -Encoding UTF8
    }
    catch {
        # Logging should never block the public metrics refresh.
    }
    Write-Warning $Message
}

function Test-RefreshDue {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [int]$IntervalMinutes = 0,
        [int]$IntervalHours = 0,
        [switch]$Force
    )

    if ($Force) { return $true }
    if ($FastOnly) { return $false }
    if (-not (Test-Path -LiteralPath $Path)) { return $true }

    $interval = if ($IntervalHours -gt 0) {
        [TimeSpan]::FromHours($IntervalHours)
    }
    else {
        [TimeSpan]::FromMinutes([Math]::Max(1, $IntervalMinutes))
    }

    $item = Get-Item -LiteralPath $Path
    return $item.LastWriteTimeUtc -lt (Get-Date).ToUniversalTime().Subtract($interval)
}

function Get-ScheduledRefreshSlot {
    param(
        [Parameter(Mandatory)] [int]$IntervalHours,
        [Parameter(Mandatory)] [int]$AnchorHour,
        [datetime]$Now = (Get-Date)
    )

    $safeInterval = [Math]::Max(1, $IntervalHours)
    $safeAnchor = (($AnchorHour % 24) + 24) % 24
    $slot = [datetime]::new($Now.Year, $Now.Month, $Now.Day, $safeAnchor, 0, 0, $Now.Kind)
    while ($slot -gt $Now) { $slot = $slot.AddHours(-$safeInterval) }
    while ($slot.AddHours($safeInterval) -le $Now) { $slot = $slot.AddHours($safeInterval) }
    return $slot
}

function Test-ScheduledRefreshDue {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [int]$IntervalHours,
        [Parameter(Mandatory)] [int]$AnchorHour,
        [Parameter(Mandatory)] [int]$WindowMinutes,
        [switch]$Force
    )

    if ($Force) { return $true }
    if ($FastOnly) { return $false }
    if (-not (Test-Path -LiteralPath $Path)) { return $true }

    $now = Get-Date
    $slot = Get-ScheduledRefreshSlot -IntervalHours $IntervalHours -AnchorHour $AnchorHour -Now $now
    if ($now -ge $slot.AddMinutes([Math]::Max(1, $WindowMinutes))) {
        return $false
    }

    $item = Get-Item -LiteralPath $Path
    return $item.LastWriteTime -lt $slot
}

function Invoke-OptionalRefresh {
    param(
        [Parameter(Mandatory)] [string]$Label,
        [Parameter(Mandatory)] [scriptblock]$ScriptBlock,
        [Parameter(Mandatory)] [string]$DuePath,
        [int]$IntervalMinutes = 0,
        [int]$IntervalHours = 0
    )

    if (-not (Test-RefreshDue -Path $DuePath -IntervalMinutes $IntervalMinutes -IntervalHours $IntervalHours -Force:$ForceHeavy)) {
        Write-Host "$Label ignoré: dernière synchronisation encore fraîche."
        return
    }

    & $ScriptBlock
}

try {
    $metrics = Read-PalworldJson -Endpoint metrics
    $players = Read-PalworldJson -Endpoint players
    $info = Read-PalworldJson -Endpoint info
    $now = Get-Date

    $payload = [ordered]@{
        ok = $true
        updatedAt = $now.ToString("o")
        updatedAtLocal = $now.ToString("yyyy-MM-dd HH:mm:ss")
        info = [ordered]@{
            version = $info.version
            serverName = $info.servername
            description = $info.description
        }
        metrics = [ordered]@{
            players = [int]$metrics.currentplayernum
            maxPlayers = [int]$metrics.maxplayernum
            fps = [int]$metrics.serverfps
            fpsAverage = [Math]::Round([double]$metrics.serverfpsaverage, 1)
            frameMs = [Math]::Round([double]$metrics.serverframetime, 1)
            days = [int]$metrics.days
            baseCamps = [int]$metrics.basecampnum
            uptimeSeconds = [int]$metrics.uptime
            uptime = Convert-Uptime -Seconds ([int]$metrics.uptime)
        }
        players = @($players.players | ForEach-Object {
            [ordered]@{
                name = $_.name
                accountName = $_.accountName
                playerId = $_.playerId
            }
        })
    }
}
catch {
    $now = Get-Date
    $payload = [ordered]@{
        ok = $false
        updatedAt = $now.ToString("o")
        updatedAtLocal = $now.ToString("yyyy-MM-dd HH:mm:ss")
        error = $_.Exception.Message
    }
}

$json = $payload | ConvertTo-Json -Depth 8
$resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
[System.IO.File]::WriteAllText($resolvedOutputPath, ($json.TrimEnd() + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
Write-Host "Metrics written to $OutputPath"

try {
    & (Join-Path $PSScriptRoot "sync-palworld-stats.ps1") | Out-Null
}
catch {
    Write-UpdateWarning "Remote stats sync failed, using local fallback: $($_.Exception.Message)"
    try {
        & (Join-Path $PSScriptRoot "update-palworld-stats.ps1") | Out-Null
    }
    catch {
        Write-UpdateWarning "Stats update failed: $($_.Exception.Message)"
    }
}

try {
    & (Join-Path $PSScriptRoot "export-public-microsite-data.ps1") | Out-Null
}
catch {
    Write-UpdateWarning "Public microsite export failed: $($_.Exception.Message)"
}

try {
    & (Join-Path $PSScriptRoot "export-public-uptime.ps1") | Out-Null
}
catch {
    Write-UpdateWarning "Public uptime export failed: $($_.Exception.Message)"
}

try {
    Invoke-OptionalRefresh `
        -Label "Historique Uptime Kuma" `
        -DuePath (Join-Path $PSScriptRoot "..\portal\data\public-uptime-history.json") `
        -IntervalMinutes $UptimeHistoryIntervalMinutes `
        -ScriptBlock { & (Join-Path $PSScriptRoot "export-uptime-kuma-history.ps1") | Out-Null }
}
catch {
    Write-UpdateWarning "Public uptime history export failed: $($_.Exception.Message)"
}

try {
    Invoke-OptionalRefresh `
        -Label "Snapshot public" `
        -DuePath (Join-Path $PSScriptRoot "..\portal\data\public-save-index.json") `
        -IntervalMinutes $SaveSnapshotIntervalMinutes `
        -ScriptBlock { & (Join-Path $PSScriptRoot "sync-palworld-save-snapshot.ps1") | Out-Null }
}
catch {
    Write-UpdateWarning "Public save snapshot sync failed: $($_.Exception.Message)"
}

try {
    $diagnosticsPath = Join-Path $PSScriptRoot "..\portal\data\public-save-diagnostics.json"
    if (Test-ScheduledRefreshDue `
            -Path $diagnosticsPath `
            -IntervalHours $DiagnosticsRefreshIntervalHours `
            -AnchorHour $DiagnosticsRefreshAnchorHour `
            -WindowMinutes $DiagnosticsRefreshWindowMinutes `
            -Force:$ForceHeavy) {
        & (Join-Path $PSScriptRoot "sync-palworld-save-snapshot.ps1") `
            -DiagnosticsRefreshIntervalHours $DiagnosticsRefreshIntervalHours `
            -DiagnosticsRefreshAnchorHour $DiagnosticsRefreshAnchorHour `
            -DiagnosticsRefreshWindowMinutes $DiagnosticsRefreshWindowMinutes `
            -ForceDiagnostics:$ForceHeavy | Out-Null
    }
    else {
        Write-Host "Diagnostics publics ignorés: prochain créneau planifié non atteint."
    }
}
catch {
    Write-UpdateWarning "Public save diagnostics sync failed: $($_.Exception.Message)"
}

try {
    Invoke-OptionalRefresh `
        -Label "Historique des échos" `
        -DuePath (Join-Path $PSScriptRoot "..\portal\data\public-events-recent.json") `
        -IntervalMinutes $EventsIntervalMinutes `
        -ScriptBlock { & (Join-Path $PSScriptRoot "sync-palworld-events.ps1") | Out-Null }
}
catch {
    Write-UpdateWarning "Public event history sync failed: $($_.Exception.Message)"
}

$assetMarker = Join-Path $PSScriptRoot "..\portal\assets\game\.source-commit"
if (Test-RefreshDue -Path $assetMarker -IntervalHours $AssetAuditIntervalHours -Force:$ForceHeavy) {
    try {
        & (Join-Path $PSScriptRoot "sync-palworld-game-assets.ps1") | Out-Null
    }
    catch {
        Write-UpdateWarning "Palworld visual asset sync failed: $($_.Exception.Message)"
    }
}
