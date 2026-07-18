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

function Get-ObjectPropertyValue {
    param(
        $InputObject,
        [Parameter(Mandatory)] [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary] -and $InputObject.Contains($Name)) {
        return $InputObject[$Name]
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }

    return $null
}

function Get-NormalizedLookupKey {
    param($Value)

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    return $text.Trim().ToLowerInvariant()
}

function New-PlayerLookup {
    param([object[]]$Players)

    $lookup = @{}
    foreach ($player in @($Players)) {
        foreach ($field in @("name", "accountName", "playerId", "userId", "id")) {
            $key = Get-NormalizedLookupKey -Value (Get-ObjectPropertyValue -InputObject $player -Name $field)
            if ($key -and -not $lookup.ContainsKey($key)) {
                $lookup[$key] = $player
            }
        }
    }

    return $lookup
}

function Find-PlayerLookupRecord {
    param(
        $Player,
        [hashtable]$Lookup
    )

    foreach ($field in @("name", "accountName", "playerId", "userId", "id")) {
        $key = Get-NormalizedLookupKey -Value (Get-ObjectPropertyValue -InputObject $Player -Name $field)
        if ($key -and $Lookup.ContainsKey($key)) {
            return $Lookup[$key]
        }
    }

    return $null
}

function Convert-PublicPosition {
    param($Location)

    if ($null -eq $Location) {
        return $null
    }

    $xValue = Get-ObjectPropertyValue -InputObject $Location -Name "x"
    $yValue = Get-ObjectPropertyValue -InputObject $Location -Name "y"
    $hasX = $null -ne $xValue
    $hasY = $null -ne $yValue
    if (-not $hasX -and -not $hasY) {
        return $null
    }

    $rounding = 1000
    $x = if ($hasX) { [Math]::Round(([double]$xValue) / $rounding, 0) * $rounding } else { $null }
    $y = if ($hasY) { [Math]::Round(([double]$yValue) / $rounding, 0) * $rounding } else { $null }
    $xLabel = Format-Coordinate -Value $x
    $yLabel = Format-Coordinate -Value $y

    return [ordered]@{
        x = $x
        y = $y
        label = "X {0} / Y {1}" -f (Get-ValueOrDefault -Value $xLabel -Default "--"), (Get-ValueOrDefault -Value $yLabel -Default "--")
        precision = "approximate"
    }
}

function Get-PublicDisplayName {
    param($Player)

    $name = Get-ObjectPropertyValue -InputObject $Player -Name "name"
    if (-not [string]::IsNullOrWhiteSpace([string]$name)) {
        return [string]$name
    }

    return "Joueur"
}

function Convert-PublicSessionHistory {
    param($Player)

    return @(Convert-ToObjectArray -Value (Get-ObjectPropertyValue -InputObject $Player -Name "sessionHistory") |
        Select-Object -Last 40 |
        ForEach-Object {
            $startedAt = Get-ObjectPropertyValue -InputObject $_ -Name "startedAt"
            if (-not [string]::IsNullOrWhiteSpace([string]$startedAt)) {
                [ordered]@{
                    startedAt = $startedAt
                    endedAt = Get-ObjectPropertyValue -InputObject $_ -Name "endedAt"
                }
            }
        })
}

function Convert-PublicPlayer {
    param($Player)

    $displayName = Get-PublicDisplayName -Player $Player
    $isOnline = [bool](Get-ObjectPropertyValue -InputObject $Player -Name "isOnline")
    $currentSessionStartedAt = if ($isOnline) { Get-ObjectPropertyValue -InputObject $Player -Name "currentSessionStartedAt" } else { $null }

    return [ordered]@{
        name = $displayName
        isOnline = $isOnline
        sessionCount = [int](Get-ValueOrDefault -Value (Get-ObjectPropertyValue -InputObject $Player -Name "sessionCount") -Default 0)
        currentSessionStartedAt = $currentSessionStartedAt
        onlineSinceAt = $currentSessionStartedAt
        lastSessionEndedAt = Get-ObjectPropertyValue -InputObject $Player -Name "lastSessionEndedAt"
        sessionHistory = @(Convert-PublicSessionHistory -Player $Player)
        totalOnlineSeconds = [int](Get-ValueOrDefault -Value (Get-ObjectPropertyValue -InputObject $Player -Name "totalOnlineSeconds") -Default 0)
        totalOnline = if (Get-ObjectPropertyValue -InputObject $Player -Name "totalOnline") { [string](Get-ObjectPropertyValue -InputObject $Player -Name "totalOnline") } else { $null }
        level = Get-ObjectPropertyValue -InputObject $Player -Name "level"
        buildingCount = Get-ObjectPropertyValue -InputObject $Player -Name "buildingCount"
        ping = Get-ObjectPropertyValue -InputObject $Player -Name "ping"
        position = Convert-PublicPosition -Location (Get-ObjectPropertyValue -InputObject $Player -Name "location")
        guildName = Get-ObjectPropertyValue -InputObject $Player -Name "guildName"
        activePalCount = [int](Get-ValueOrDefault -Value (Get-ObjectPropertyValue -InputObject $Player -Name "activePalCount") -Default 0)
        basePalCount = [int](Get-ValueOrDefault -Value (Get-ObjectPropertyValue -InputObject $Player -Name "basePalCount") -Default 0)
        lastSeenAt = Get-ObjectPropertyValue -InputObject $Player -Name "lastSeenAt"
        lastOnlineAt = Get-ObjectPropertyValue -InputObject $Player -Name "lastOnlineAt"
    }
}

New-Item -ItemType Directory -Force -Path $DataDirectory | Out-Null

$metricsPath = Join-Path $DataDirectory "metrics.json"
$statsPath = Join-Path $DataDirectory "stats.json"
$publicMetricsPath = Join-Path $DataDirectory "public-metrics.json"
$publicStatsPath = Join-Path $DataDirectory "public-stats.json"

$stats = Read-JsonFile -Path $statsPath
$rawStatsPlayers = if ($stats) { Convert-ToObjectArray -Value (Get-ObjectPropertyValue -InputObject $stats -Name "players") } else { @() }
$statsPlayerLookup = New-PlayerLookup -Players $rawStatsPlayers
$metrics = Read-JsonFile -Path $metricsPath
if ($metrics) {
    $metricsOk = [bool](Get-ObjectPropertyValue -InputObject $metrics -Name "ok")
    $metricsInfo = Get-ObjectPropertyValue -InputObject $metrics -Name "info"
    $publicMetrics = [ordered]@{
        version = 1
        ok = $metricsOk
        updatedAt = Get-ObjectPropertyValue -InputObject $metrics -Name "updatedAt"
        updatedAtLocal = Get-ObjectPropertyValue -InputObject $metrics -Name "updatedAtLocal"
        server = [ordered]@{
            name = Get-ObjectPropertyValue -InputObject $metricsInfo -Name "serverName"
            description = Get-ObjectPropertyValue -InputObject $metricsInfo -Name "description"
            version = Get-ObjectPropertyValue -InputObject $metricsInfo -Name "version"
        }
        metrics = Get-ObjectPropertyValue -InputObject $metrics -Name "metrics"
        players = @(Convert-ToObjectArray -Value (Get-ObjectPropertyValue -InputObject $metrics -Name "players") | ForEach-Object {
            $statsPlayer = Find-PlayerLookupRecord -Player $_ -Lookup $statsPlayerLookup
            $isOnline = $statsPlayer -and [bool](Get-ObjectPropertyValue -InputObject $statsPlayer -Name "isOnline")
            $currentSessionStartedAt = if ($isOnline) { Get-ObjectPropertyValue -InputObject $statsPlayer -Name "currentSessionStartedAt" } else { $null }
            [ordered]@{
                name = Get-PublicDisplayName -Player $_
                currentSessionStartedAt = $currentSessionStartedAt
                onlineSinceAt = $currentSessionStartedAt
                lastOnlineAt = if ($statsPlayer) { Get-ObjectPropertyValue -InputObject $statsPlayer -Name "lastOnlineAt" } else { $null }
            }
        })
    }

    if (-not $metricsOk) {
        $publicMetrics["error"] = Get-ObjectPropertyValue -InputObject $metrics -Name "error"
    }

    Write-JsonFile -Path $publicMetricsPath -Payload $publicMetrics
}

if ($stats) {
    $rawPlayers = $rawStatsPlayers
    $rawGuilds = Convert-ToObjectArray -Value (Get-ObjectPropertyValue -InputObject $stats -Name "guilds")
    $statsOk = [bool](Get-ObjectPropertyValue -InputObject $stats -Name "ok")
    $statsCollection = Get-ObjectPropertyValue -InputObject $stats -Name "collection"

    $publicStats = [ordered]@{
        version = 1
        ok = $statsOk
        updatedAt = Get-ObjectPropertyValue -InputObject $stats -Name "updatedAt"
        updatedAtLocal = Get-ObjectPropertyValue -InputObject $stats -Name "updatedAtLocal"
        collection = [ordered]@{
            source = Get-ObjectPropertyValue -InputObject $statsCollection -Name "source"
            firstSampleAt = Get-ObjectPropertyValue -InputObject $statsCollection -Name "firstSampleAt"
            lastSampleAt = Get-ObjectPropertyValue -InputObject $statsCollection -Name "lastSampleAt"
            sampleCount = Get-ObjectPropertyValue -InputObject $statsCollection -Name "sampleCount"
            gameDataAvailable = [bool](Get-ObjectPropertyValue -InputObject $statsCollection -Name "gameDataAvailable")
            gameDataStatus = Get-ObjectPropertyValue -InputObject $statsCollection -Name "gameDataStatus"
            note = $null
        }
        server = Get-ObjectPropertyValue -InputObject $stats -Name "server"
        actors = Get-ObjectPropertyValue -InputObject $stats -Name "actors"
        guilds = @($rawGuilds | ForEach-Object {
            [ordered]@{
                name = if (Get-ObjectPropertyValue -InputObject $_ -Name "name") { [string](Get-ObjectPropertyValue -InputObject $_ -Name "name") } else { "Guilde" }
                baseCount = [int](Get-ValueOrDefault -Value (Get-ObjectPropertyValue -InputObject $_ -Name "baseCount") -Default 0)
                playerCount = [int](Get-ValueOrDefault -Value (Get-ObjectPropertyValue -InputObject $_ -Name "playerCount") -Default 0)
                activePlayerCount = [int](Get-ValueOrDefault -Value (Get-ObjectPropertyValue -InputObject $_ -Name "activePlayerCount") -Default 0)
            }
        })
        players = @($rawPlayers | ForEach-Object { Convert-PublicPlayer -Player $_ })
    }

    if (-not $statsOk) {
        $publicStats["error"] = Get-ObjectPropertyValue -InputObject $stats -Name "error"
    }

    Write-JsonFile -Path $publicStatsPath -Payload $publicStats
}

Write-Host "Public microsite data exported to $DataDirectory"
