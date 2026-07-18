param(
    [string]$StatsPath = (Join-Path $PSScriptRoot "..\portal\data\stats.json"),
    [int]$MaxIntervalSeconds = 300,
    [int]$GameDataIntervalMinutes = 5
)

$ErrorActionPreference = "Stop"
$MaxSessionHistory = 200

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
    param([ValidateSet("info", "players", "metrics", "game-data")] [string]$Endpoint)

    $raw = & (Join-Path $PSScriptRoot "palworld-api.ps1") $Endpoint 2>&1
    $text = ($raw | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "palworld-api.ps1 $Endpoint failed with exit code $LASTEXITCODE. $text"
    }

    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    return ($text | ConvertFrom-Json)
}

function ConvertTo-Hashtable {
    param($InputObject)

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $hash = [ordered]@{}
        foreach ($key in $InputObject.Keys) {
            $hash[$key] = ConvertTo-Hashtable $InputObject[$key]
        }
        return $hash
    }

    if ($InputObject -is [pscustomobject]) {
        $hash = [ordered]@{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $hash[$property.Name] = ConvertTo-Hashtable $property.Value
        }
        return $hash
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        return @($InputObject | ForEach-Object { ConvertTo-Hashtable $_ })
    }

    return $InputObject
}

function New-StatsDocument {
    param([datetime]$Now)

    return [ordered]@{
        version = 1
        ok = $true
        updatedAt = $Now.ToString("o")
        updatedAtLocal = $Now.ToString("yyyy-MM-dd HH:mm:ss")
        collection = [ordered]@{
            firstSampleAt = $Now.ToString("o")
            lastSampleAt = $null
            lastGameDataAt = $null
            nextGameDataAttemptAt = $null
            sampleCount = 0
            gameDataStatus = "unknown"
            gameDataDisabledAt = $null
            gameDataAvailable = $false
            gameDataError = $null
            note = "Les temps et connexions sont estimés par échantillonnage local."
        }
        server = [ordered]@{
            totalObservedSeconds = 0
            totalObserved = "0m"
            peakPlayers = 0
            peakPlayersAt = $null
            playerSamples = 0
            playerTotal = 0
            averagePlayers = 0
            fpsSamples = 0
            fpsTotal = 0
            averageFps = 0
            lastPlayers = 0
            maxPlayers = 0
            lastFps = 0
            lastFrameMs = 0
            lastBaseCamps = 0
            lastDays = 0
            lastUptimeSeconds = 0
            lastUptime = "0m"
        }
        players = [ordered]@{}
        guilds = [ordered]@{}
        actors = [ordered]@{
            lastSnapshotAt = $null
            total = 0
            players = 0
            palBoxes = 0
            baseCampPals = 0
            otomoPals = 0
            wildPals = 0
            npcs = 0
        }
    }
}

function Test-GameDataDisabledError {
    param([string]$Message)

    return $Message -match "HTTP 40[45]" -or
        $Message -match "\b40[45]\b" -or
        $Message -match "GameData API is not enabled" -or
        $Message -match "not enabled"
}

function Ensure-CollectionDefaults {
    param(
        [hashtable]$Stats,
        [datetime]$Now
    )

    if (-not $Stats.Contains("collection") -or -not $Stats.collection) {
        $Stats.collection = [ordered]@{}
    }

    if (-not $Stats.collection.Contains("lastGameDataAt")) { $Stats.collection.lastGameDataAt = $null }
    if (-not $Stats.collection.Contains("nextGameDataAttemptAt")) { $Stats.collection.nextGameDataAttemptAt = $null }
    if (-not $Stats.collection.Contains("gameDataStatus")) { $Stats.collection.gameDataStatus = "unknown" }
    if (-not $Stats.collection.Contains("gameDataDisabledAt")) { $Stats.collection.gameDataDisabledAt = $null }
    if (-not $Stats.collection.Contains("gameDataAvailable")) { $Stats.collection.gameDataAvailable = $false }
    if (-not $Stats.collection.Contains("gameDataError")) { $Stats.collection.gameDataError = $null }

    if ($Stats.collection.gameDataStatus -ne "disabled" -and (Test-GameDataDisabledError -Message ([string]$Stats.collection.gameDataError))) {
        $Stats.collection.gameDataStatus = "disabled"
        $Stats.collection.gameDataDisabledAt = if ($Stats.collection.lastGameDataAt) { $Stats.collection.lastGameDataAt } else { $Now.ToString("o") }
        $Stats.collection.nextGameDataAttemptAt = $null
    }
}

function Get-PlayerKey {
    param($Player)

    foreach ($field in @("userId", "userid", "playerId", "accountName", "name")) {
        if ($Player.PSObject.Properties.Name -contains $field -and -not [string]::IsNullOrWhiteSpace([string]$Player.$field)) {
            return [string]$Player.$field
        }
    }

    return $null
}

function Ensure-PlayerRecord {
    param(
        [hashtable]$Stats,
        [string]$Key,
        [datetime]$Now
    )

    if (-not $Stats.players.Contains($Key)) {
        $Stats.players[$Key] = [ordered]@{
            id = $Key
            name = $Key
            accountName = $null
            playerId = $null
            userId = $null
            firstSeenAt = $Now.ToString("o")
            lastSeenAt = $Now.ToString("o")
            lastOnlineAt = $Now.ToString("o")
            isOnline = $false
            sessionCount = 0
            currentSessionStartedAt = $null
            lastSessionEndedAt = $null
            sessionHistory = @()
            totalOnlineSeconds = 0
            totalOnline = "0m"
            level = $null
            buildingCount = $null
            ping = $null
            location = $null
            guildId = $null
            guildName = $null
            hp = $null
            maxHp = $null
            activePalCount = 0
            basePalCount = 0
            lastSeenSource = "players"
        }
    }

    $record = $Stats.players[$Key]
    if (-not $record.Contains("sessionHistory") -or $null -eq $record.sessionHistory) {
        $record.sessionHistory = @()
    }

    if ($record.currentSessionStartedAt) {
        $history = @($record.sessionHistory)
        $knownOpenSession = @($history | Where-Object { $_.startedAt -eq $record.currentSessionStartedAt }).Count -gt 0
        if (-not $knownOpenSession) {
            $history += [ordered]@{
                startedAt = $record.currentSessionStartedAt
                endedAt = $null
            }
            $record.sessionHistory = @($history | Select-Object -Last $MaxSessionHistory)
        }
    }

    return $record
}

function Start-PlayerSession {
    param(
        [hashtable]$Record,
        [Parameter(Mandatory)] [string]$StartedAt
    )

    $history = @($Record.sessionHistory)
    if ($history.Count -eq 0 -or $history[-1].endedAt) {
        $history += [ordered]@{
            startedAt = $StartedAt
            endedAt = $null
        }
    }
    elseif (-not $history[-1].startedAt) {
        $history[-1].startedAt = $StartedAt
    }

    $Record.sessionHistory = @($history | Select-Object -Last $MaxSessionHistory)
}

function Stop-PlayerSession {
    param(
        [hashtable]$Record,
        [Parameter(Mandatory)] [string]$EndedAt
    )

    $history = @($Record.sessionHistory)
    for ($index = $history.Count - 1; $index -ge 0; $index--) {
        if ($history[$index].startedAt -and -not $history[$index].endedAt) {
            $history[$index].endedAt = $EndedAt
            break
        }
    }

    $Record.sessionHistory = @($history | Select-Object -Last $MaxSessionHistory)
}

function Update-PlayerFromOnlineList {
    param(
        [hashtable]$Stats,
        $Player,
        [datetime]$Now,
        [int]$IntervalSeconds
    )

    $key = Get-PlayerKey -Player $Player
    if ([string]::IsNullOrWhiteSpace($key)) {
        return $null
    }

    $record = Ensure-PlayerRecord -Stats $Stats -Key $key -Now $Now

    if (-not $record.isOnline) {
        $record.sessionCount = [int]$record.sessionCount + 1
        $record.currentSessionStartedAt = $Now.ToString("o")
        Start-PlayerSession -Record $record -StartedAt $record.currentSessionStartedAt
    }

    if ($IntervalSeconds -gt 0) {
        $record.totalOnlineSeconds = [int]$record.totalOnlineSeconds + $IntervalSeconds
    }

    $record.name = if ($Player.name) { [string]$Player.name } else { $record.name }
    $record.accountName = if ($Player.accountName) { [string]$Player.accountName } else { $record.accountName }
    $record.playerId = if ($Player.playerId) { [string]$Player.playerId } else { $record.playerId }
    $record.userId = if ($Player.userId) { [string]$Player.userId } else { $record.userId }
    $record.lastSeenAt = $Now.ToString("o")
    $record.lastOnlineAt = $Now.ToString("o")
    $record.isOnline = $true
    $record.level = if ($null -ne $Player.level) { [int]$Player.level } else { $record.level }
    $record.buildingCount = if ($null -ne $Player.building_count) { [int]$Player.building_count } else { $record.buildingCount }
    $record.ping = if ($null -ne $Player.ping) { [Math]::Round([double]$Player.ping, 1) } else { $record.ping }
    $record.lastSeenSource = "players"

    if ($null -ne $Player.location_x -or $null -ne $Player.location_y) {
        $record.location = [ordered]@{
            x = if ($null -ne $Player.location_x) { [Math]::Round([double]$Player.location_x, 1) } else { $null }
            y = if ($null -ne $Player.location_y) { [Math]::Round([double]$Player.location_y, 1) } else { $null }
        }
    }

    $record.totalOnline = Convert-Uptime -Seconds ([int]$record.totalOnlineSeconds)
    return $key
}

function Update-StatsFromGameData {
    param(
        [hashtable]$Stats,
        $GameData,
        [datetime]$Now
    )

    $actors = @($GameData.ActorData)
    $Stats.collection.gameDataAvailable = $true
    $Stats.collection.gameDataError = $null
    $Stats.collection.lastGameDataAt = $Now.ToString("o")
    $Stats.collection.nextGameDataAttemptAt = $null
    $Stats.collection.gameDataStatus = "available"
    $Stats.collection.gameDataDisabledAt = $null
    $Stats.actors.lastSnapshotAt = $Now.ToString("o")
    $Stats.actors.total = $actors.Count
    $Stats.actors.players = @($actors | Where-Object { $_.Type -eq "Character" -and $_.UnitType -eq "Player" }).Count
    $Stats.actors.palBoxes = @($actors | Where-Object { $_.Type -eq "PalBox" }).Count
    $Stats.actors.baseCampPals = @($actors | Where-Object { $_.UnitType -eq "BaseCampPal" }).Count
    $Stats.actors.otomoPals = @($actors | Where-Object { $_.UnitType -eq "OtomoPal" }).Count
    $Stats.actors.wildPals = @($actors | Where-Object { $_.UnitType -eq "WildPal" }).Count
    $Stats.actors.npcs = @($actors | Where-Object { $_.UnitType -eq "NPC" }).Count

    $guilds = [ordered]@{}
    foreach ($palBox in @($actors | Where-Object { $_.Type -eq "PalBox" })) {
        $guildId = if ($palBox.GuildID) { [string]$palBox.GuildID } else { "unknown" }
        if (-not $guilds.Contains($guildId)) {
            $guilds[$guildId] = [ordered]@{
                id = $guildId
                name = if ($palBox.GuildName) { [string]$palBox.GuildName } else { "Guilde inconnue" }
                baseCount = 0
                playerCount = 0
                activePlayerCount = 0
            }
        }
        $guilds[$guildId].baseCount = [int]$guilds[$guildId].baseCount + 1
    }

    foreach ($actor in @($actors | Where-Object { $_.Type -eq "Character" -and $_.UnitType -eq "Player" })) {
        $key = if ($actor.userid) { [string]$actor.userid } elseif ($actor.InstanceID) { [string]$actor.InstanceID } else { $null }
        if ($key) {
            $record = Ensure-PlayerRecord -Stats $Stats -Key $key -Now $Now
            $record.name = if ($actor.NickName) { [string]$actor.NickName } else { $record.name }
            $record.userId = if ($actor.userid) { [string]$actor.userid } else { $record.userId }
            $record.level = if ($null -ne $actor.level) { [int]$actor.level } else { $record.level }
            $record.hp = if ($null -ne $actor.HP) { [int]$actor.HP } else { $record.hp }
            $record.maxHp = if ($null -ne $actor.MaxHP) { [int]$actor.MaxHP } else { $record.maxHp }
            $record.guildId = if ($actor.GuildID) { [string]$actor.GuildID } else { $record.guildId }
            $record.guildName = if ($actor.GuildName) { [string]$actor.GuildName } else { $record.guildName }
            $record.lastSeenSource = "game-data"

            if ($null -ne $actor.LocationX -or $null -ne $actor.LocationY) {
                $record.location = [ordered]@{
                    x = if ($null -ne $actor.LocationX) { [Math]::Round([double]$actor.LocationX, 1) } else { $null }
                    y = if ($null -ne $actor.LocationY) { [Math]::Round([double]$actor.LocationY, 1) } else { $null }
                }
            }
        }

        if ($actor.GuildID) {
            $guildId = [string]$actor.GuildID
            if (-not $guilds.Contains($guildId)) {
                $guilds[$guildId] = [ordered]@{
                    id = $guildId
                    name = if ($actor.GuildName) { [string]$actor.GuildName } else { "Guilde inconnue" }
                    baseCount = 0
                    playerCount = 0
                    activePlayerCount = 0
                }
            }
            $guilds[$guildId].playerCount = [int]$guilds[$guildId].playerCount + 1
            if ($actor.IsActive -eq "true") {
                $guilds[$guildId].activePlayerCount = [int]$guilds[$guildId].activePlayerCount + 1
            }
        }
    }

    foreach ($pal in @($actors | Where-Object { $_.UnitType -eq "OtomoPal" -or $_.UnitType -eq "BaseCampPal" })) {
        $trainerName = if ($pal.TrainerNickName) { [string]$pal.TrainerNickName } else { $null }
        if (-not $trainerName) {
            continue
        }

        $matchingPlayer = $Stats.players.GetEnumerator() | Where-Object {
            $_.Value.name -eq $trainerName
        } | Select-Object -First 1

        if ($matchingPlayer) {
            if ($pal.UnitType -eq "OtomoPal") {
                $matchingPlayer.Value.activePalCount = [int]$matchingPlayer.Value.activePalCount + 1
            }
            elseif ($pal.UnitType -eq "BaseCampPal") {
                $matchingPlayer.Value.basePalCount = [int]$matchingPlayer.Value.basePalCount + 1
            }
        }
    }

    $Stats.guilds = $guilds
}

$statsItem = Get-Item -LiteralPath $StatsPath -ErrorAction SilentlyContinue
$statsDirectory = if ($statsItem -and $statsItem.PSIsContainer) {
    $statsItem.FullName
}
else {
    Split-Path -Parent $StatsPath
}

New-Item -ItemType Directory -Force -Path $statsDirectory | Out-Null

$now = Get-Date
$stats = $null
if (Test-Path -LiteralPath $StatsPath) {
    try {
        $stats = ConvertTo-Hashtable ((Get-Content -LiteralPath $StatsPath -Raw) | ConvertFrom-Json)
    }
    catch {
        $stats = $null
    }
}

if (-not $stats) {
    $stats = New-StatsDocument -Now $now
}
Ensure-CollectionDefaults -Stats $stats -Now $now

try {
    $metrics = Read-PalworldJson -Endpoint metrics
    $playersPayload = Read-PalworldJson -Endpoint players

    $lastSampleAt = $null
    if ($stats.collection.lastSampleAt) {
        $lastSampleAt = [datetime]::Parse($stats.collection.lastSampleAt)
    }

    $intervalSeconds = 0
    if ($lastSampleAt) {
        $elapsed = [int]([Math]::Max(0, ($now - $lastSampleAt).TotalSeconds))
        $intervalSeconds = [Math]::Min($elapsed, $MaxIntervalSeconds)
    }

    foreach ($record in $stats.players.Values) {
        $record.activePalCount = 0
        $record.basePalCount = 0
    }

    $onlineKeys = @{}
    foreach ($player in @($playersPayload.players)) {
        $key = Update-PlayerFromOnlineList -Stats $stats -Player $player -Now $now -IntervalSeconds $intervalSeconds
        if ($key) {
            $onlineKeys[$key] = $true
        }
    }

    foreach ($key in @($stats.players.Keys)) {
        $record = $stats.players[$key]
        if (-not $onlineKeys.Contains($key) -and $record.isOnline) {
            $record.isOnline = $false
            $record.lastSessionEndedAt = $now.ToString("o")
            Stop-PlayerSession -Record $record -EndedAt $record.lastSessionEndedAt
            $record.currentSessionStartedAt = $null
            $record.totalOnline = Convert-Uptime -Seconds ([int]$record.totalOnlineSeconds)
        }
    }

    $currentPlayers = [int]$metrics.currentplayernum
    $stats.server.lastPlayers = $currentPlayers
    $stats.server.maxPlayers = [int]$metrics.maxplayernum
    $stats.server.lastFps = [int]$metrics.serverfps
    $stats.server.lastFrameMs = [Math]::Round([double]$metrics.serverframetime, 1)
    $stats.server.lastBaseCamps = [int]$metrics.basecampnum
    $stats.server.lastDays = [int]$metrics.days
    $stats.server.lastUptimeSeconds = [int]$metrics.uptime
    $stats.server.lastUptime = Convert-Uptime -Seconds ([int]$metrics.uptime)
    $stats.server.totalObservedSeconds = [int]$stats.server.totalObservedSeconds + $intervalSeconds
    $stats.server.totalObserved = Convert-Uptime -Seconds ([int]$stats.server.totalObservedSeconds)
    $stats.server.playerSamples = [int]$stats.server.playerSamples + 1
    $stats.server.playerTotal = [int]$stats.server.playerTotal + $currentPlayers
    $stats.server.averagePlayers = [Math]::Round(([double]$stats.server.playerTotal / [Math]::Max(1, [int]$stats.server.playerSamples)), 2)
    $stats.server.fpsSamples = [int]$stats.server.fpsSamples + 1
    $stats.server.fpsTotal = [double]$stats.server.fpsTotal + [double]$metrics.serverfps
    $stats.server.averageFps = [Math]::Round(([double]$stats.server.fpsTotal / [Math]::Max(1, [int]$stats.server.fpsSamples)), 1)

    if ($currentPlayers -gt [int]$stats.server.peakPlayers) {
        $stats.server.peakPlayers = $currentPlayers
        $stats.server.peakPlayersAt = $now.ToString("o")
    }

    $shouldReadGameData = $false
    if ($stats.collection.gameDataStatus -eq "disabled") {
        $shouldReadGameData = $false
    }
    elseif (-not $stats.collection.lastGameDataAt) {
        $shouldReadGameData = $true
    }
    else {
        $lastGameDataAt = [datetime]::Parse($stats.collection.lastGameDataAt)
        $shouldReadGameData = ($now - $lastGameDataAt).TotalMinutes -ge $GameDataIntervalMinutes
    }

    if ($shouldReadGameData) {
        try {
            $gameData = Read-PalworldJson -Endpoint "game-data"
            if ($gameData) {
                Update-StatsFromGameData -Stats $stats -GameData $gameData -Now $now
            }
        }
        catch {
            $stats.collection.gameDataAvailable = $false
            $stats.collection.gameDataError = $_.Exception.Message
            $stats.collection.lastGameDataAt = $now.ToString("o")
            if (Test-GameDataDisabledError -Message $_.Exception.Message) {
                $stats.collection.gameDataStatus = "disabled"
                $stats.collection.gameDataDisabledAt = $now.ToString("o")
                $stats.collection.nextGameDataAttemptAt = $null
            }
            else {
                $stats.collection.gameDataStatus = "error"
            }
        }
    }

    $stats.ok = $true
    $stats.updatedAt = $now.ToString("o")
    $stats.updatedAtLocal = $now.ToString("yyyy-MM-dd HH:mm:ss")
    $stats.collection.lastSampleAt = $now.ToString("o")
    $stats.collection.sampleCount = [int]$stats.collection.sampleCount + 1

    foreach ($record in $stats.players.Values) {
        $record.totalOnline = Convert-Uptime -Seconds ([int]$record.totalOnlineSeconds)
    }
}
catch {
    $stats.ok = $false
    $stats.updatedAt = $now.ToString("o")
    $stats.updatedAtLocal = $now.ToString("yyyy-MM-dd HH:mm:ss")
    $stats.error = $_.Exception.Message
}

$json = $stats | ConvertTo-Json -Depth 12
$resolvedStatsPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($StatsPath)
[System.IO.File]::WriteAllText($resolvedStatsPath, ($json.TrimEnd() + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
Write-Host "Stats written to $StatsPath"
