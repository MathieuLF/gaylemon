param(
    [string]$DataDirectory = (Join-Path $PSScriptRoot "..\portal\data")
)

$ErrorActionPreference = "Stop"

try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $OutputEncoding = [Console]::OutputEncoding
}
catch {
    # Best effort for older PowerShell hosts.
}

function Read-JsonFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    return $text | ConvertFrom-Json
}

function Write-JsonFile {
    param(
        [string]$Path,
        $Payload
    )

    $json = $Payload | ConvertTo-Json -Depth 16
    [System.IO.File]::WriteAllText($Path, ($json.TrimEnd() + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
}

function Format-Coordinate {
    param($Value)

    if ($null -eq $Value) {
        return $null
    }

    $number = [double]$Value
    $sign = if ($number -lt 0) { "-" } else { "" }
    $absolute = [Math]::Abs($number)

    if ($absolute -ge 1000) {
        return "{0}{1}k" -f $sign, [Math]::Round($absolute / 1000, 0)
    }

    return "{0}{1}" -f $sign, [Math]::Round($absolute, 0)
}

function Get-ValueOrDefault {
    param(
        $Value,
        $Default
    )

    if ($null -ne $Value) {
        return $Value
    }

    return $Default
}

function Convert-ToObjectArray {
    param($Value)

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [array]) {
        return @($Value | Where-Object { $null -ne $_ })
    }

    $properties = @($Value.PSObject.Properties)
    if ($properties.Count -gt 0) {
        return @($properties | ForEach-Object { $_.Value } | Where-Object { $null -ne $_ })
    }

    return @($Value)
}

function Convert-PublicPosition {
    param($Location)

    if ($null -eq $Location) {
        return $null
    }

    $hasX = $Location.PSObject.Properties.Name -contains "x" -and $null -ne $Location.x
    $hasY = $Location.PSObject.Properties.Name -contains "y" -and $null -ne $Location.y
    if (-not $hasX -and -not $hasY) {
        return $null
    }

    $rounding = 1000
    $x = if ($hasX) { [Math]::Round(([double]$Location.x) / $rounding, 0) * $rounding } else { $null }
    $y = if ($hasY) { [Math]::Round(([double]$Location.y) / $rounding, 0) * $rounding } else { $null }
    $xLabel = Format-Coordinate -Value $x
    $yLabel = Format-Coordinate -Value $y

    return [ordered]@{
        x = $x
        y = $y
        label = "X {0} / Y {1}" -f (Get-ValueOrDefault -Value $xLabel -Default "--"), (Get-ValueOrDefault -Value $yLabel -Default "--")
        precision = "approximate"
    }
}

function Convert-PublicPlayer {
    param($Player)

    $displayName = if (-not [string]::IsNullOrWhiteSpace([string]$Player.name)) {
        [string]$Player.name
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$Player.accountName)) {
        [string]$Player.accountName
    }
    else {
        "Joueur"
    }

    return [ordered]@{
        name = $displayName
        isOnline = [bool]$Player.isOnline
        sessionCount = [int](Get-ValueOrDefault -Value $Player.sessionCount -Default 0)
        totalOnlineSeconds = [int](Get-ValueOrDefault -Value $Player.totalOnlineSeconds -Default 0)
        totalOnline = if ($Player.totalOnline) { [string]$Player.totalOnline } else { $null }
        level = $Player.level
        buildingCount = $Player.buildingCount
        ping = $Player.ping
        position = Convert-PublicPosition -Location $Player.location
        guildName = $Player.guildName
        activePalCount = [int](Get-ValueOrDefault -Value $Player.activePalCount -Default 0)
        basePalCount = [int](Get-ValueOrDefault -Value $Player.basePalCount -Default 0)
        lastSeenAt = $Player.lastSeenAt
        lastOnlineAt = $Player.lastOnlineAt
    }
}

New-Item -ItemType Directory -Force -Path $DataDirectory | Out-Null

$metricsPath = Join-Path $DataDirectory "metrics.json"
$statsPath = Join-Path $DataDirectory "stats.json"
$publicMetricsPath = Join-Path $DataDirectory "public-metrics.json"
$publicStatsPath = Join-Path $DataDirectory "public-stats.json"

$metrics = Read-JsonFile -Path $metricsPath
if ($metrics) {
    $publicMetrics = [ordered]@{
        version = 1
        ok = [bool]$metrics.ok
        updatedAt = $metrics.updatedAt
        updatedAtLocal = $metrics.updatedAtLocal
        server = [ordered]@{
            name = $metrics.info.serverName
            description = $metrics.info.description
            version = $metrics.info.version
        }
        metrics = $metrics.metrics
        players = @($metrics.players | ForEach-Object {
            [ordered]@{
                name = if ($_.name) { [string]$_.name } elseif ($_.accountName) { [string]$_.accountName } else { "Joueur" }
            }
        })
    }

    if (-not $metrics.ok) {
        $publicMetrics["error"] = $metrics.error
    }

    Write-JsonFile -Path $publicMetricsPath -Payload $publicMetrics
}

$stats = Read-JsonFile -Path $statsPath
if ($stats) {
    $rawPlayers = Convert-ToObjectArray -Value $stats.players
    $rawGuilds = Convert-ToObjectArray -Value $stats.guilds

    $publicStats = [ordered]@{
        version = 1
        ok = [bool]$stats.ok
        updatedAt = $stats.updatedAt
        updatedAtLocal = $stats.updatedAtLocal
        collection = [ordered]@{
            source = $stats.collection.source
            firstSampleAt = $stats.collection.firstSampleAt
            lastSampleAt = $stats.collection.lastSampleAt
            sampleCount = $stats.collection.sampleCount
            gameDataAvailable = [bool]$stats.collection.gameDataAvailable
            gameDataStatus = $stats.collection.gameDataStatus
            note = $null
        }
        server = $stats.server
        actors = $stats.actors
        guilds = @($rawGuilds | ForEach-Object {
            [ordered]@{
                name = if ($_.name) { [string]$_.name } else { "Guilde" }
                baseCount = [int](Get-ValueOrDefault -Value $_.baseCount -Default 0)
                playerCount = [int](Get-ValueOrDefault -Value $_.playerCount -Default 0)
                activePlayerCount = [int](Get-ValueOrDefault -Value $_.activePlayerCount -Default 0)
            }
        })
        players = @($rawPlayers | ForEach-Object { Convert-PublicPlayer -Player $_ })
    }

    if (-not $stats.ok) {
        $publicStats["error"] = $stats.error
    }

    Write-JsonFile -Path $publicStatsPath -Payload $publicStats
}

Write-Host "Public microsite data exported to $DataDirectory"
