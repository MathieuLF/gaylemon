param(
    [string]$OutputPath = (Join-Path $PSScriptRoot "..\portal\data\metrics.json")
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
    Write-Warning "Remote stats sync failed, using local fallback: $($_.Exception.Message)"
    try {
        & (Join-Path $PSScriptRoot "update-palworld-stats.ps1") | Out-Null
    }
    catch {
        Write-Warning "Stats update failed: $($_.Exception.Message)"
    }
}

try {
    & (Join-Path $PSScriptRoot "export-public-microsite-data.ps1") | Out-Null
}
catch {
    Write-Warning "Public microsite export failed: $($_.Exception.Message)"
}

try {
    & (Join-Path $PSScriptRoot "export-public-uptime.ps1") | Out-Null
}
catch {
    Write-Warning "Public uptime export failed: $($_.Exception.Message)"
}

try {
    & (Join-Path $PSScriptRoot "sync-palworld-save-snapshot.ps1") | Out-Null
}
catch {
    Write-Warning "Public save snapshot sync failed: $($_.Exception.Message)"
}

try {
    & (Join-Path $PSScriptRoot "sync-palworld-events.ps1") | Out-Null
}
catch {
    Write-Warning "Public event history sync failed: $($_.Exception.Message)"
}

$assetMarker = Join-Path $PSScriptRoot "..\portal\assets\game\.source-commit"
$assetAuditDue = -not (Test-Path -LiteralPath $assetMarker) -or
    (Get-Item -LiteralPath $assetMarker).LastWriteTimeUtc -lt (Get-Date).ToUniversalTime().AddHours(-6)
if ($assetAuditDue) {
    try {
        & (Join-Path $PSScriptRoot "sync-palworld-game-assets.ps1") | Out-Null
    }
    catch {
        Write-Warning "Palworld visual asset sync failed: $($_.Exception.Message)"
    }
}
