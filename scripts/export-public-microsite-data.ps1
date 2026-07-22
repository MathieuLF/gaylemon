param(
    [string]$DataDirectory = (Join-Path $PSScriptRoot "..\portal\data")
)

$ErrorActionPreference = "Stop"
$PublicSettingsFields = @(
    "Difficulty", "DayTimeSpeedRate", "NightTimeSpeedRate", "ExpRate", "PalCaptureRate",
    "PalSpawnNumRate", "PalDamageRateAttack", "PalDamageRateDefense", "PlayerDamageRateAttack",
    "PlayerDamageRateDefense", "CollectionDropRate", "CollectionObjectHpRate",
    "CollectionObjectRespawnSpeedRate", "EnemyDropItemRate", "DeathPenalty", "BaseCampMaxNum",
    "BaseCampWorkerMaxNum", "GuildPlayerMaxNum", "PalEggDefaultHatchingTime", "WorkSpeedRate",
    "AutoSaveSpan", "bIsPvP", "bEnablePlayerToPlayerDamage", "bEnableFriendlyFire",
    "bEnableInvaderEnemy", "bEnableFastTravel", "bUseBackupSaveData", "CrossplayPlatforms"
)

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

function Convert-PublicSettings {
    param($Settings)

    $result = [ordered]@{}
    foreach ($field in $PublicSettingsFields | Sort-Object) {
        $value = Get-ObjectPropertyValue -InputObject $Settings -Name $field
        if ($null -ne $value) { $result[$field] = $value }
    }
    return $result
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
    $displayName = if ($null -ne $name) { ([string]$name).Trim() } else { "" }
    $placeholderNames = @("joueur", "player", "unknown", "inconnu", "joueur inconnu")
    if (
        -not [string]::IsNullOrWhiteSpace($displayName) -and
        $placeholderNames -notcontains $displayName.ToLowerInvariant()
    ) {
        return $displayName
    }

    return $null
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
    if ([string]::IsNullOrWhiteSpace([string]$displayName)) {
        return $null
    }
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
$statsProvenance = if ($stats) { Get-ObjectPropertyValue -InputObject $stats -Name "provenance" } else { $null }
$metrics = Read-JsonFile -Path $metricsPath
if ($metrics) {
    $metricsOk = [bool](Get-ObjectPropertyValue -InputObject $metrics -Name "ok")
    $metricsInfo = Get-ObjectPropertyValue -InputObject $metrics -Name "info"
    $publicMetrics = [ordered]@{
        version = 2
        schemaVersion = 2
        ok = $metricsOk
        updatedAt = Get-ObjectPropertyValue -InputObject $metrics -Name "updatedAt"
        updatedAtLocal = Get-ObjectPropertyValue -InputObject $metrics -Name "updatedAtLocal"
        provenance = [ordered]@{
            observedAt = Get-ObjectPropertyValue -InputObject $metrics -Name "updatedAt"
            sourceUpdatedAt = Get-ObjectPropertyValue -InputObject $metrics -Name "updatedAt"
            gameVersion = Get-ObjectPropertyValue -InputObject $metricsInfo -Name "version"
            steamBuildId = Get-ObjectPropertyValue -InputObject $statsProvenance -Name "steamBuildId"
            parserCommit = Get-ObjectPropertyValue -InputObject $statsProvenance -Name "parserCommit"
            catalogCommit = Get-ObjectPropertyValue -InputObject $statsProvenance -Name "catalogCommit"
            schemaVersion = 2
            freshness = "current"
            sourceStatus = if ($metricsOk) { "available" } else { "transient-error" }
        }
        server = [ordered]@{
            name = Get-ObjectPropertyValue -InputObject $metricsInfo -Name "serverName"
            description = Get-ObjectPropertyValue -InputObject $metricsInfo -Name "description"
            version = Get-ObjectPropertyValue -InputObject $metricsInfo -Name "version"
        }
        metrics = Get-ObjectPropertyValue -InputObject $metrics -Name "metrics"
        players = @(Convert-ToObjectArray -Value (Get-ObjectPropertyValue -InputObject $metrics -Name "players") | ForEach-Object {
            $displayName = Get-PublicDisplayName -Player $_
            if (-not [string]::IsNullOrWhiteSpace([string]$displayName)) {
                $statsPlayer = Find-PlayerLookupRecord -Player $_ -Lookup $statsPlayerLookup
                $isOnline = $statsPlayer -and [bool](Get-ObjectPropertyValue -InputObject $statsPlayer -Name "isOnline")
                $currentSessionStartedAt = if ($isOnline) { Get-ObjectPropertyValue -InputObject $statsPlayer -Name "currentSessionStartedAt" } else { $null }
                [ordered]@{
                    name = $displayName
                    currentSessionStartedAt = $currentSessionStartedAt
                    onlineSinceAt = $currentSessionStartedAt
                    lastOnlineAt = if ($statsPlayer) { Get-ObjectPropertyValue -InputObject $statsPlayer -Name "lastOnlineAt" } else { $null }
                }
            }
        })
    }

    if (-not $metricsOk) {
        $publicMetrics["error"] = "Les métriques du serveur sont temporairement indisponibles."
    }

    Write-JsonFile -Path $publicMetricsPath -Payload $publicMetrics
}

if ($stats) {
    $rawPlayers = $rawStatsPlayers
    $rawGuilds = Convert-ToObjectArray -Value (Get-ObjectPropertyValue -InputObject $stats -Name "guilds")
    $statsOk = [bool](Get-ObjectPropertyValue -InputObject $stats -Name "ok")
    $statsCollection = Get-ObjectPropertyValue -InputObject $stats -Name "collection"
    $statsSettings = Get-ObjectPropertyValue -InputObject $stats -Name "settings"
    $statsSources = Get-ObjectPropertyValue -InputObject $stats -Name "sources"
    $publicSources = [ordered]@{}
    foreach ($sourceName in @("info", "metrics", "players", "settings", "game-data")) {
        $source = Get-ObjectPropertyValue -InputObject $statsSources -Name $sourceName
        if (-not $source) { continue }
        $sourceStatus = Get-ObjectPropertyValue -InputObject $source -Name "status"
        if ($sourceName -eq "game-data") {
            $gameDataStatus = Get-ObjectPropertyValue -InputObject $statsCollection -Name "gameDataStatus"
            if ($gameDataStatus) {
                $sourceStatus = $gameDataStatus
            }
        }
        $publicSources[$sourceName] = [ordered]@{
            status = $sourceStatus
            lastObservedAt = Get-ObjectPropertyValue -InputObject $source -Name "lastObservedAt"
            lastSuccessAt = Get-ObjectPropertyValue -InputObject $source -Name "lastSuccessAt"
            latencyMs = Get-ObjectPropertyValue -InputObject $source -Name "latencyMs"
            latencyP95Ms = Get-ObjectPropertyValue -InputObject $source -Name "latencyP95Ms"
            responseBytes = Get-ObjectPropertyValue -InputObject $source -Name "responseBytes"
            consecutiveFailures = Get-ObjectPropertyValue -InputObject $source -Name "consecutiveFailures"
        }
    }

    $publicStats = [ordered]@{
        version = 2
        schemaVersion = 2
        ok = $statsOk
        updatedAt = Get-ObjectPropertyValue -InputObject $stats -Name "updatedAt"
        updatedAtLocal = Get-ObjectPropertyValue -InputObject $stats -Name "updatedAtLocal"
        provenance = [ordered]@{
            observedAt = Get-ObjectPropertyValue -InputObject $statsProvenance -Name "observedAt"
            sourceUpdatedAt = Get-ObjectPropertyValue -InputObject $statsProvenance -Name "sourceUpdatedAt"
            gameVersion = Get-ObjectPropertyValue -InputObject $statsProvenance -Name "gameVersion"
            steamBuildId = Get-ObjectPropertyValue -InputObject $statsProvenance -Name "steamBuildId"
            parserCommit = Get-ObjectPropertyValue -InputObject $statsProvenance -Name "parserCommit"
            catalogCommit = Get-ObjectPropertyValue -InputObject $statsProvenance -Name "catalogCommit"
            schemaVersion = 2
            freshness = Get-ObjectPropertyValue -InputObject $statsProvenance -Name "freshness"
            sourceStatus = Get-ObjectPropertyValue -InputObject $statsProvenance -Name "sourceStatus"
        }
        collection = [ordered]@{
            source = Get-ObjectPropertyValue -InputObject $statsCollection -Name "source"
            firstSampleAt = Get-ObjectPropertyValue -InputObject $statsCollection -Name "firstSampleAt"
            lastSampleAt = Get-ObjectPropertyValue -InputObject $statsCollection -Name "lastSampleAt"
            sampleCount = Get-ObjectPropertyValue -InputObject $statsCollection -Name "sampleCount"
            gameDataAvailable = [bool](Get-ObjectPropertyValue -InputObject $statsCollection -Name "gameDataAvailable")
            gameDataStatus = Get-ObjectPropertyValue -InputObject $statsCollection -Name "gameDataStatus"
            lastGameDataAt = Get-ObjectPropertyValue -InputObject $statsCollection -Name "lastGameDataAt"
            nextGameDataAttemptAt = Get-ObjectPropertyValue -InputObject $statsCollection -Name "nextGameDataAttemptAt"
            settingsStatus = Get-ObjectPropertyValue -InputObject $statsSettings -Name "status"
            lastSettingsAt = Get-ObjectPropertyValue -InputObject $statsSettings -Name "updatedAt"
            note = $null
        }
        settings = [ordered]@{
            status = Get-ObjectPropertyValue -InputObject $statsSettings -Name "status"
            updatedAt = Get-ObjectPropertyValue -InputObject $statsSettings -Name "updatedAt"
            current = Convert-PublicSettings -Settings (Get-ObjectPropertyValue -InputObject $statsSettings -Name "current")
        }
        sources = $publicSources
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
        players = @($rawPlayers | ForEach-Object {
            $publicPlayer = Convert-PublicPlayer -Player $_
            if ($null -ne $publicPlayer) {
                $publicPlayer
            }
        })
    }

    if (-not $statsOk) {
        $publicStats["error"] = "Les statistiques du serveur sont temporairement indisponibles."
    }

    Write-JsonFile -Path $publicStatsPath -Payload $publicStats
}

Write-Host "Public microsite data exported to $DataDirectory"
