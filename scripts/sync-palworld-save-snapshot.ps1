param(
    [string]$OutputPath = (Join-Path $PSScriptRoot "..\portal\data\public-save-snapshot.json"),
    [string]$DiagnosticsOutputPath = (Join-Path $PSScriptRoot "..\portal\data\public-save-diagnostics.json"),
    [string]$BasesOutputPath = (Join-Path $PSScriptRoot "..\portal\data\public-save-bases.json"),
    [string]$PlayerDataRoot = (Join-Path $PSScriptRoot "..\portal\data\players"),
    [string]$PlayerPagesRoot = (Join-Path $PSScriptRoot "..\portal\joueur"),
    [string]$RemoteSnapshotPath = "",
    [string]$RemoteDiagnosticsPath = "",
    [string]$RemoteBasesPath = "",
    [int]$DiagnosticsRefreshHour = 4,
    [switch]$ForceDiagnostics
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot
if (-not $RemoteSnapshotPath) { $RemoteSnapshotPath = "$($config.RemoteProjectRoot)/runtime/public-save-snapshot.json" }
if (-not $RemoteDiagnosticsPath) { $RemoteDiagnosticsPath = "$($config.RemoteProjectRoot)/runtime/public-save-diagnostics.json" }
if (-not $RemoteBasesPath) { $RemoteBasesPath = "$($config.RemoteProjectRoot)/runtime/public-save-bases.json" }

function Test-DiagnosticsRefreshDue {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [int]$RefreshHour,
        [switch]$Force
    )

    if ($Force) { return $true }
    if (-not (Test-Path -LiteralPath $Path)) { return $true }

    $now = Get-Date
    $dueAt = [datetime]::new($now.Year, $now.Month, $now.Day, $RefreshHour, 0, 0, $now.Kind)
    if ($now -lt $dueAt) { return $false }

    $item = Get-Item -LiteralPath $Path
    return $item.LastWriteTime -lt $dueAt
}

function Expand-GzipBase64 {
    param([Parameter(Mandatory)] [string]$Value)

    $compressed = [Convert]::FromBase64String($Value)
    $input = [IO.MemoryStream]::new($compressed, $false)
    $gzip = [IO.Compression.GZipStream]::new($input, [IO.Compression.CompressionMode]::Decompress)
    $reader = [IO.StreamReader]::new($gzip, [Text.Encoding]::UTF8, $true)
    try {
        return $reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
        $gzip.Dispose()
        $input.Dispose()
    }
}

function Read-RemoteJson {
    param(
        [Parameter(Mandatory)] [string]$RemotePath,
        [switch]$Optional
    )

    $raw = & ssh.exe $config.SshAlias "test -s '$RemotePath' && gzip -c '$RemotePath' | base64 -w0" 2>$null
    if ($LASTEXITCODE -ne 0) {
        if ($Optional) { return $null }
        throw "Le fichier public distant n'est pas disponible: $RemotePath"
    }
    $base64 = (($raw | Out-String).Trim())
    if (-not $base64) {
        if ($Optional) { return $null }
        throw "Le fichier public distant est vide: $RemotePath"
    }
    $text = Expand-GzipBase64 -Value $base64
    return ($text | ConvertFrom-Json)
}

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] $Value,
        [int]$Depth = 20
    )

    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $directory = Split-Path -Parent $resolved
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $temporary = "$resolved.tmp"
    $json = $Value | ConvertTo-Json -Depth $Depth
    [IO.File]::WriteAllText($temporary, $json.TrimEnd() + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $resolved -Force
}

function Read-LocalJson {
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    return ($text | ConvertFrom-Json)
}

function Get-NullableInt($Value) {
    if ($null -eq $Value) { return $null }
    return [int]$Value
}

function Get-OptionalInt($Value, [string]$Name, [int]$Default = 0) {
    $property = Get-OptionalProperty $Value $Name
    if ($null -eq $property) { return $Default }
    return [int]$property
}

function Get-NullableDouble($Value) {
    if ($null -eq $Value) { return $null }
    return [double]$Value
}

function Get-OptionalProperty($Value, [string]$Name) {
    if ($null -eq $Value) { return $null }
    if ($Value.PSObject.Properties.Name -notcontains $Name) { return $null }
    return $Value.$Name
}

function Convert-PublicPosition($Position) {
    if ($null -eq $Position) { return $null }
    $mapVisible = Get-OptionalProperty $Position "mapVisible"
    return [ordered]@{
        mapX = [int]$Position.mapX
        mapY = [int]$Position.mapY
        leftPercent = [double]$Position.leftPercent
        topPercent = [double]$Position.topPercent
        mapVisible = if ($null -eq $mapVisible) { $true } else { [bool]$mapVisible }
    }
}

function Convert-PublicSkill($Skill) {
    return [ordered]@{
        name = [string]$Skill.name
        description = if ($Skill.description) { [string]$Skill.description } else { $null }
        rank = [int]$Skill.rank
        power = Get-NullableInt $Skill.power
        cooldown = Get-NullableDouble $Skill.cooldown
        element = if ($Skill.element) { [string]$Skill.element } else { $null }
    }
}

function Convert-PublicPal($Pal) {
    $result = [ordered]@{
        name = [string]$Pal.name
        species = [string]$Pal.species
        icon = if ($Pal.icon) { [string]$Pal.icon } else { $null }
        level = [int]$Pal.level
        experience = [long]$Pal.experience
        gender = if ($Pal.gender) { [string]$Pal.gender } else { $null }
        container = [string]$Pal.container
        hp = [double]$Pal.hp
        maxHp = Get-NullableInt $Pal.maxHp
        hunger = [double]$Pal.hunger
        sanity = Get-NullableDouble $Pal.sanity
        friendship = [int]$Pal.friendship
        rank = Get-NullableInt $Pal.rank
        lucky = [bool]$Pal.lucky
        boss = [bool]$Pal.boss
        awakening = [bool]$Pal.awakening
        favorite = [bool]$Pal.favorite
        imported = [bool]$Pal.imported
        talents = [ordered]@{
            hp = [int]$Pal.talents.hp
            attack = [int]$Pal.talents.attack
            defense = [int]$Pal.talents.defense
        }
        souls = [ordered]@{
            hp = [int]$Pal.souls.hp
            attack = [int]$Pal.souls.attack
            defense = [int]$Pal.souls.defense
            workSpeed = [int]$Pal.souls.workSpeed
        }
        computedStats = [ordered]@{
            attack = Get-NullableInt $Pal.computedStats.attack
            defense = Get-NullableInt $Pal.computedStats.defense
            workSpeed = Get-NullableInt $Pal.computedStats.workSpeed
        }
        passives = @($Pal.passives | ForEach-Object { Convert-PublicSkill $_ })
        activeSkills = @($Pal.activeSkills | ForEach-Object { Convert-PublicSkill $_ })
        learnedSkills = @($Pal.learnedSkills | ForEach-Object { Convert-PublicSkill $_ })
        workSuitabilityBonuses = @($Pal.workSuitabilityBonuses | ForEach-Object {
            [ordered]@{ name = [string]$_.name; level = [int]$_.level; bonus = [int]$_.bonus }
        })
        healthStatus = if ($Pal.healthStatus) { [string]$Pal.healthStatus } else { $null }
        ownedAt = if ($Pal.ownedAt) { [string]$Pal.ownedAt } else { $null }
        position = Convert-PublicPosition $Pal.position
    }
    $task = Get-OptionalProperty $Pal "task"
    if ($task) { $result.task = [string]$task }
    return $result
}

function Convert-PublicCountRows($Rows) {
    return @($Rows | ForEach-Object {
        [ordered]@{ name = [string]$_.name; count = [long]$_.count }
    })
}

function Convert-PublicTopItems($Rows) {
    return @($Rows | ForEach-Object {
        [ordered]@{
            name = [string]$_.name
            count = [long]$_.count
            icon = if ($_.icon) { [string]$_.icon } else { $null }
            category = if ($_.category) { [string]$_.category } else { $null }
        }
    })
}

function Convert-PublicStorage($Storage) {
    return [ordered]@{
        units = [int]$Storage.units
        capacity = [int]$Storage.capacity
        used = [int]$Storage.used
        fillPercent = Get-NullableDouble $Storage.fillPercent
        itemTypes = [int]$Storage.itemTypes
        categories = @(Convert-PublicCountRows $Storage.categories)
        topItems = @(Convert-PublicTopItems $Storage.topItems)
    }
}

function Convert-PublicBase($Base) {
    return [ordered]@{
        name = [string]$Base.name
        guild = [string]$Base.guild
        players = @($Base.players | ForEach-Object { [string]$_ })
        campLevel = [int]$Base.campLevel
        position = Convert-PublicPosition $Base.position
        areaRange = [double]$Base.areaRange
        state = [string]$Base.state
        workers = [ordered]@{
            assigned = [int]$Base.workers.assigned
            busy = [int]$Base.workers.busy
            healthy = [int]$Base.workers.healthy
            unwell = [int]$Base.workers.unwell
            list = @($Base.workers.list | ForEach-Object { Convert-PublicPal $_ })
        }
        structures = [ordered]@{
            total = [int]$Base.structures.total
            damaged = [int]$Base.structures.damaged
            unfinished = [int]$Base.structures.unfinished
            categories = @(Convert-PublicCountRows $Base.structures.categories)
            highlights = @(Convert-PublicCountRows $Base.structures.highlights)
        }
        storage = Convert-PublicStorage $Base.storage
        production = Convert-PublicStorage $Base.production
        work = [ordered]@{
            total = [int]$Base.work.total
            active = [int]$Base.work.active
            assignedWorkers = [int]$Base.work.assignedWorkers
            bufferedItems = [int]$Base.work.bufferedItems
            jobs = @($Base.work.jobs | ForEach-Object {
                [ordered]@{
                    name = [string]$_.name
                    type = [string]$_.type
                    progressPercent = Get-NullableDouble $_.progressPercent
                }
            })
        }
        research = [ordered]@{
            current = if ($Base.research.current) { [string]$Base.research.current } else { $null }
            completed = [int]$Base.research.completed
        }
    }
}

function Convert-PublicInventory($Sections) {
    return @($Sections | ForEach-Object {
        [ordered]@{
            key = [string]$_.key
            label = [string]$_.label
            items = @($_.items | ForEach-Object {
                [ordered]@{
                    name = [string]$_.name
                    count = [int]$_.count
                    slot = [int]$_.slot
                    icon = if ($_.icon) { [string]$_.icon } else { $null }
                    rarity = [int]$_.rarity
                    category = if ($_.category) { [string]$_.category } else { $null }
                }
            })
        }
    })
}

function Convert-PublicProgress($Progress, [switch]$SummaryOnly) {
    $paldex = $Progress.paldex
    $bosses = $Progress.bosses
    $exploration = $Progress.exploration
    $relics = $Progress.relics
    $quests = Get-OptionalProperty $Progress "quests"
    $challenges = Get-OptionalProperty $Progress "challenges"
    $records = Get-OptionalProperty $Progress "records"
    $technologies = Get-OptionalProperty $Progress "technologies"
    $result = [ordered]@{
        technologyPoints = [int]$Progress.technologyPoints
        bossTechnologyPoints = [int]$Progress.bossTechnologyPoints
        unlockedTechnologies = [int]$Progress.unlockedTechnologies
        completedQuests = [int]$Progress.completedQuests
    }
    if ($null -eq $paldex) { return $result }

    $result.paldex = [ordered]@{
        encounteredSpecies = [int]$paldex.encounteredSpecies
        capturedSpecies = [int]$paldex.capturedSpecies
        totalSpecies = [int]$paldex.totalSpecies
        totalCaptures = [int]$paldex.totalCaptures
        captureChallengesCompleted = Get-OptionalInt $paldex "captureChallengesCompleted"
        completionPercent = Get-NullableDouble $paldex.completionPercent
    }
    $result.bosses = [ordered]@{
        defeated = [int]$bosses.defeated
        normalDefeated = [int]$bosses.normalDefeated
        normalKnownTotal = [int]$bosses.normalKnownTotal
        towerDefeated = [int]$bosses.towerDefeated
    }
    $result.exploration = [ordered]@{
        fastTravelUnlocked = [int]$exploration.fastTravelUnlocked
        fastTravelTotal = [int]$exploration.fastTravelTotal
        areasDiscovered = [int]$exploration.areasDiscovered
        areasTotal = [int]$exploration.areasTotal
        worldMapsUnlocked = [int]$exploration.worldMapsUnlocked
        completionPercent = Get-NullableDouble $exploration.completionPercent
    }
    $result.relics = [ordered]@{
        totalRanks = [int]$relics.totalRanks
        maximumRanks = Get-NullableInt $relics.maximumRanks
        completionPercent = Get-NullableDouble $relics.completionPercent
    }
    if (-not $SummaryOnly) {
        $paldexSpecies = Get-OptionalProperty $paldex "species"
        $result.paldex.species = @($paldexSpecies | Where-Object { $null -ne $_ } | ForEach-Object {
            [ordered]@{
                index = [int]$_.index
                name = [string]$_.name
                icon = if ($_.icon) { [string]$_.icon } else { $null }
                encountered = [bool]$_.encountered
                captured = [bool]$_.captured
                captureCount = [int]$_.captureCount
                challengeCount = Get-OptionalInt $_ "challengeCount"
                challengeTarget = Get-OptionalInt $_ "challengeTarget" 5
                challengeComplete = [bool](Get-OptionalProperty $_ "challengeComplete")
            }
        })
        $result.quests = [ordered]@{
            completedCount = Get-OptionalInt $quests "completedCount"
            completed = @((Get-OptionalProperty $quests "completed") | Where-Object { $null -ne $_ } | ForEach-Object {
                [ordered]@{ name = [string]$_.name }
            })
            activeCount = Get-OptionalInt $quests "activeCount"
            active = @((Get-OptionalProperty $quests "active") | Where-Object { $null -ne $_ } | ForEach-Object {
                [ordered]@{ name = [string]$_.name }
            })
        }
        $result.challenges = [ordered]@{
            completedCount = Get-OptionalInt $challenges "completedCount"
            completed = @((Get-OptionalProperty $challenges "completed") | Where-Object { $null -ne $_ } | ForEach-Object {
                [ordered]@{
                    name = [string]$_.name
                    category = [string]$_.category
                    tier = [int]$_.tier
                }
            })
        }
        $result.records = [ordered]@{
            treasuresFound = Get-OptionalInt $records "treasuresFound"
            normalDungeonsCleared = Get-OptionalInt $records "normalDungeonsCleared"
            fixedDungeonsCleared = Get-OptionalInt $records "fixedDungeonsCleared"
            oilRigsCleared = Get-OptionalInt $records "oilRigsCleared"
            campsConquered = Get-OptionalInt $records "campsConquered"
            fishCaught = Get-OptionalInt $records "fishCaught"
            fishSpecies = Get-OptionalInt $records "fishSpecies"
            itemsCrafted = [long](Get-OptionalInt $records "itemsCrafted")
            craftedItemTypes = Get-OptionalInt $records "craftedItemTypes"
            uniqueItemsPickedUp = Get-OptionalInt $records "uniqueItemsPickedUp"
        }
        $result.bosses.known = @((Get-OptionalProperty $bosses "known") | Where-Object { $null -ne $_ } | ForEach-Object {
            [ordered]@{ name = [string]$_.name; icon = if ($_.icon) { [string]$_.icon } else { $null } }
        })
        $result.exploration.fastTravelPoints = @((Get-OptionalProperty $exploration "fastTravelPoints") | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
        $result.technologies = @($technologies | Where-Object { $null -ne $_ } | ForEach-Object {
            [ordered]@{
                name = [string]$_.name
                icon = if ($_.icon) { [string]$_.icon } else { $null }
                level = [int]$_.level
                tier = [int]$_.tier
                type = [string]$_.type
            }
        })
        $result.relics.categories = @($relics.categories | ForEach-Object {
            [ordered]@{ name = [string]$_.name; rank = [int]$_.rank; maxRank = Get-NullableInt $_.maxRank }
        })
    }
    return $result
}

function Assert-PublicPayload($Value, [string]$Path = "$") {
    $forbidden = "uid|guid|instance|container|account|steam|password|token|dynamic_id"
    if ($Value -is [Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            if ($key -ne "container" -and [string]$key -match $forbidden) {
                throw "Clé technique interdite dans la projection publique: $Path.$key"
            }
            Assert-PublicPayload $Value[$key] "$Path.$key"
        }
    }
    elseif ($Value -is [pscustomobject]) {
        foreach ($property in $Value.PSObject.Properties) {
            if ($property.Name -ne "container" -and $property.Name -match $forbidden) {
                throw "Clé technique interdite dans la projection publique: $Path.$($property.Name)"
            }
            Assert-PublicPayload $property.Value "$Path.$($property.Name)"
        }
    }
    elseif ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
        $index = 0
        foreach ($item in $Value) {
            Assert-PublicPayload $item "$Path[$index]"
            $index++
        }
    }
}

function ConvertTo-PlayerSlug([string]$Name) {
    $normalized = $Name.Normalize([Text.NormalizationForm]::FormD)
    $letters = [Text.StringBuilder]::new()
    foreach ($character in $normalized.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($character) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$letters.Append($character)
        }
    }
    $slug = [regex]::Replace($letters.ToString().ToLowerInvariant(), "[^a-z0-9]+", "-").Trim("-")
    if ($slug) { return $slug }
    return "joueur"
}

function Write-PlayerSharePages($Players, [string]$DestinationRoot) {
    $resolvedRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationRoot)
    if (Test-Path -LiteralPath $resolvedRoot) { Remove-Item -LiteralPath $resolvedRoot -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $resolvedRoot | Out-Null
    $sectionTitles = [ordered]@{
        profile = "Progression et statistiques"
        paldex = "Paldex personnel"
        pals = "Collection de Pals"
        inventory = "Inventaire"
        bases = "Bases et campements"
    }
    foreach ($player in $Players) {
        $slug = ConvertTo-PlayerSlug ([string]$player.name)
        $name = [Net.WebUtility]::HtmlEncode([string]$player.name)
        $description = [Net.WebUtility]::HtmlEncode("Suis la progression de $($player.name), ses Pals et ses découvertes sur Palpagos.")
        foreach ($tab in $sectionTitles.Keys) {
            $section = [Net.WebUtility]::HtmlEncode($sectionTitles[$tab])
            $title = "$name | $section | Gaylémon Palworld"
            $publicUrl = "$($config.MicrositePublicUrl.TrimEnd('/'))/joueur/$slug/$tab/"
            $appRoute = "/#joueur/$slug/$tab"
            $directory = Join-Path $resolvedRoot "$slug\$tab"
            New-Item -ItemType Directory -Force -Path $directory | Out-Null
            $html = @"
<!doctype html>
<html lang="fr-CA">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>$title</title>
    <meta name="description" content="$description">
    <meta name="robots" content="noindex, follow, max-image-preview:large">
    <link rel="canonical" href="$publicUrl">
    <meta property="og:type" content="profile">
    <meta property="og:locale" content="fr_CA">
    <meta property="og:site_name" content="Gaylémon Palworld">
    <meta property="og:title" content="$title">
    <meta property="og:description" content="$description">
    <meta property="og:url" content="$publicUrl">
    <meta property="og:image" content="$($config.MicrositePublicUrl.TrimEnd('/'))/assets/social/gaylemon-social-card.png">
    <meta name="twitter:card" content="summary_large_image">
    <meta http-equiv="refresh" content="0; url=$appRoute">
    <script>location.replace("$appRoute");</script>
  </head>
  <body><p>Ouverture de la fiche de ${name}... <a href="$appRoute">Continuer</a></p></body>
</html>
"@
            [IO.File]::WriteAllText((Join-Path $directory "index.html"), $html.Trim() + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        }
    }
}

function Write-PlayerDataFiles($Players, [string]$DestinationRoot, [string]$UpdatedAt, [int]$Version) {
    $resolvedRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationRoot)
    New-Item -ItemType Directory -Force -Path $resolvedRoot | Out-Null
    $expectedFiles = @()
    foreach ($player in $Players) {
        $slug = ConvertTo-PlayerSlug ([string]$player.name)
        $expectedFiles += "$slug.json"
        $payload = [ordered]@{
            version = $Version
            ok = $true
            updatedAt = $UpdatedAt
            player = $player
        }
        Assert-PublicPayload $payload
        Write-JsonAtomic -Path (Join-Path $resolvedRoot "$slug.json") -Value $payload -Depth 24
    }
    Get-ChildItem -LiteralPath $resolvedRoot -File -Filter "*.json" -ErrorAction SilentlyContinue |
        Where-Object { $expectedFiles -notcontains $_.Name } |
        Remove-Item -Force
}

$source = Read-RemoteJson -RemotePath $RemoteSnapshotPath
if (-not $source.ok -or [int]$source.version -notin @(2, 3)) {
    throw "Le snapshot public distant est invalide ou incompatible."
}
$shouldSyncDiagnostics = Test-DiagnosticsRefreshDue -Path $DiagnosticsOutputPath -RefreshHour $DiagnosticsRefreshHour -Force:$ForceDiagnostics
$sourceDiagnostics = if ($shouldSyncDiagnostics) { Read-RemoteJson -RemotePath $RemoteDiagnosticsPath -Optional } else { $null }
$sourceBases = Read-RemoteJson -RemotePath $RemoteBasesPath -Optional
$projectionVersion = if (
    $source.PSObject.Properties.Name -contains "projection" -and
    $null -ne $source.projection -and
    $source.projection.PSObject.Properties.Name -contains "version" -and
    $null -ne $source.projection.version
) {
    [int]$source.projection.version
}
else {
    [int]$source.version
}

$public = [ordered]@{
    version = [int]$source.version
    ok = $true
    updatedAt = [string]$source.updatedAt
    source = [ordered]@{ type = [string]$source.source.type; backup = [string]$source.source.backup }
    parser = [ordered]@{ name = "PalworldSaveTools"; commit = [string]$source.parser.commit }
    projection = [ordered]@{ version = $projectionVersion }
    summary = [ordered]@{
        players = [int]$source.summary.players
        pals = [int]$source.summary.pals
        guilds = [int]$source.summary.guilds
        bases = [int]$source.summary.bases
    }
    world = if ($source.world) {
        [ordered]@{
            paldexSpecies = [int]$source.world.paldexSpecies
            fastTravelPoints = [int]$source.world.fastTravelPoints
            discoverableAreas = [int]$source.world.discoverableAreas
            knownBosses = [int]$source.world.knownBosses
        }
    } else { $null }
    bases = @()
    guilds = @($source.guilds | ForEach-Object {
        [ordered]@{
            name = [string]$_.name
            players = [int]$_.players
            bases = [int]$_.bases
            campLevel = [int]$_.campLevel
        }
    })
    players = @($source.players | ForEach-Object {
        [ordered]@{
            name = [string]$_.name
            level = [int]$_.level
            guild = if ($_.guild) { [string]$_.guild } else { $null }
            guildBases = Get-NullableInt $_.guildBases
            campLevel = Get-NullableInt $_.campLevel
            position = Convert-PublicPosition $_.position
            character = [ordered]@{
                experience = [long]$_.character.experience
                hp = [double]$_.character.hp
                shield = [double]$_.character.shield
                hunger = [double]$_.character.hunger
                unusedStatusPoints = [int]$_.character.unusedStatusPoints
                allocations = @($_.character.allocations | ForEach-Object {
                    [ordered]@{ name = [string]$_.name; points = [int]$_.points }
                })
            }
            pals = [ordered]@{
                total = [int]$_.pals.total
                party = [int]$_.pals.party
                palbox = [int]$_.pals.palbox
                uniqueSpecies = [int]$_.pals.uniqueSpecies
                highestLevel = [int]$_.pals.highestLevel
                favorites = @($_.pals.favorites | ForEach-Object {
                    [ordered]@{ name = [string]$_.name; count = [int]$_.count; icon = if ($_.icon) { [string]$_.icon } else { $null } }
                })
                collection = @($_.pals.collection | ForEach-Object { Convert-PublicPal $_ })
            }
            inventory = Convert-PublicInventory $_.inventory
            progress = Convert-PublicProgress $_.progress
        }
    })
}

$publicIndex = [ordered]@{
    version = 2
    ok = $true
    updatedAt = $public.updatedAt
    summary = $public.summary
    world = $public.world
    guilds = $public.guilds
    players = @($public.players | ForEach-Object {
        [ordered]@{
            name = $_.name
            level = $_.level
            guild = $_.guild
            guildBases = $_.guildBases
            campLevel = $_.campLevel
            position = $_.position
            pals = [ordered]@{
                total = $_.pals.total
                party = $_.pals.party
                palbox = $_.pals.palbox
                uniqueSpecies = $_.pals.uniqueSpecies
                highestLevel = $_.pals.highestLevel
                favorites = $_.pals.favorites
            }
            progress = Convert-PublicProgress $_.progress -SummaryOnly
        }
    })
}

Assert-PublicPayload $public
Assert-PublicPayload $publicIndex
Write-JsonAtomic -Path $OutputPath -Value $public -Depth 24
$indexPath = Join-Path (Split-Path -Parent $OutputPath) "public-save-index.json"
Write-JsonAtomic -Path $indexPath -Value $publicIndex -Depth 14
Write-PlayerDataFiles -Players $public.players -DestinationRoot $PlayerDataRoot -UpdatedAt $public.updatedAt -Version $public.version
Write-PlayerSharePages -Players $public.players -DestinationRoot $PlayerPagesRoot

if ($sourceBases -and $sourceBases.ok -and [int]$sourceBases.version -eq 1) {
    $publicBases = [ordered]@{
        version = 1
        ok = $true
        updatedAt = [string]$sourceBases.updatedAt
        parser = [ordered]@{
            name = "PalworldSaveTools"
            commit = [string]$sourceBases.parser.commit
        }
        summary = [ordered]@{
            bases = [int]$sourceBases.summary.bases
            workers = [int]$sourceBases.summary.workers
            structures = [int]$sourceBases.summary.structures
            storageUnits = [int]$sourceBases.summary.storageUnits
            productionUnits = [int]$sourceBases.summary.productionUnits
            guildStorageUnits = [int]$sourceBases.summary.guildStorageUnits
            activeJobs = [int]$sourceBases.summary.activeJobs
            busyWorkers = [int]$sourceBases.summary.busyWorkers
        }
        bases = @($sourceBases.bases | ForEach-Object { Convert-PublicBase $_ })
        guildStorage = @($sourceBases.guildStorage | ForEach-Object {
            [ordered]@{
                guild = [string]$_.guild
                players = @($_.players | ForEach-Object { [string]$_ })
                units = [int]$_.units
                capacity = [int]$_.capacity
                used = [int]$_.used
                fillPercent = Get-NullableDouble $_.fillPercent
                itemTypes = [int]$_.itemTypes
                categories = @(Convert-PublicCountRows $_.categories)
                topItems = @(Convert-PublicTopItems $_.topItems)
            }
        })
    }
    Assert-PublicPayload $publicBases
    Write-JsonAtomic -Path $BasesOutputPath -Value $publicBases -Depth 24
}

if ($sourceDiagnostics) {
    $worldMap = Join-Path $PSScriptRoot "..\portal\assets\game\maps\T_WorldMap.webp"
    $treeMap = Join-Path $PSScriptRoot "..\portal\assets\game\maps\T_TreeMap.webp"
    $eventsPath = Join-Path (Split-Path -Parent $OutputPath) "public-events.json"
    $eventsPayload = Read-LocalJson -Path $eventsPath
    $eventsCount = if ($eventsPayload -and $eventsPayload.summary) {
        [int]$eventsPayload.summary.events
    }
    elseif ($eventsPayload -and $eventsPayload.events) {
        @($eventsPayload.events).Count
    }
    else {
        0
    }
    $publicDiagnostics = [ordered]@{
        version = 1
        ok = [bool]$sourceDiagnostics.ok
        updatedAt = [string]$sourceDiagnostics.updatedAt
        save = [ordered]@{
            levelBytes = [long]$sourceDiagnostics.save.levelBytes
            playerFiles = [int]$sourceDiagnostics.save.playerFiles
            playersBytes = [long]$sourceDiagnostics.save.playersBytes
            generationBytes = [long]$sourceDiagnostics.save.generationBytes
            backupAgeSeconds = [int]$sourceDiagnostics.save.backupAgeSeconds
        }
        parse = [ordered]@{
            durationMs = Get-NullableInt $sourceDiagnostics.parse.durationMs
            decodeDurationMs = Get-NullableInt $sourceDiagnostics.parse.decodeDurationMs
            projectionDurationMs = Get-NullableInt $sourceDiagnostics.parse.projectionDurationMs
            status = [string]$sourceDiagnostics.parse.status
            warnings = [int]$sourceDiagnostics.parse.warnings
            playersParsed = [int]$sourceDiagnostics.parse.playersParsed
            palsParsed = [int]$sourceDiagnostics.parse.palsParsed
            basesParsed = [int]$sourceDiagnostics.parse.basesParsed
        }
        output = [ordered]@{
            snapshotBytes = Get-NullableInt $sourceDiagnostics.output.snapshotBytes
            snapshotGzipBytes = Get-NullableInt $sourceDiagnostics.output.snapshotGzipBytes
            basesBytes = Get-NullableInt $sourceDiagnostics.output.basesBytes
            basesGzipBytes = Get-NullableInt $sourceDiagnostics.output.basesGzipBytes
            privateBasesBytes = Get-NullableInt $sourceDiagnostics.output.privateBasesBytes
            historyArchiveBytes = Get-NullableInt $sourceDiagnostics.output.historyArchiveBytes
        }
        parser = [ordered]@{ name = "PalworldSaveTools"; commit = [string]$sourceDiagnostics.parser.commit }
        events = [ordered]@{
            version = if ($eventsPayload -and $eventsPayload.version) { [int]$eventsPayload.version } else { $null }
            updatedAt = if ($eventsPayload -and $eventsPayload.updatedAt) { [string]$eventsPayload.updatedAt } else { $null }
            revision = if ($eventsPayload -and $eventsPayload.revision) { [string]$eventsPayload.revision } else { $null }
            count = $eventsCount
            firstAt = if ($eventsPayload -and $eventsPayload.summary -and $eventsPayload.summary.firstAt) { [string]$eventsPayload.summary.firstAt } else { $null }
            lastAt = if ($eventsPayload -and $eventsPayload.summary -and $eventsPayload.summary.lastAt) { [string]$eventsPayload.summary.lastAt } else { $null }
        }
        publicOutput = [ordered]@{
            indexBytes = (Get-Item -LiteralPath $indexPath).Length
            snapshotBytes = (Get-Item -LiteralPath $OutputPath).Length
            basesBytes = if (Test-Path -LiteralPath $BasesOutputPath) { (Get-Item -LiteralPath $BasesOutputPath).Length } else { $null }
        }
        assets = [ordered]@{
            worldMapBytes = if (Test-Path $worldMap) { (Get-Item $worldMap).Length } else { $null }
            worldMapWidth = 8192
            worldMapHeight = 8192
            treeMapBytes = if (Test-Path $treeMap) { (Get-Item $treeMap).Length } else { $null }
        }
    }
    Assert-PublicPayload $publicDiagnostics
    Write-JsonAtomic -Path $DiagnosticsOutputPath -Value $publicDiagnostics -Depth 10
}

Write-Host "Snapshot v$($public.version) synchronisé vers $OutputPath"
Write-Host "Index léger synchronisé vers $indexPath"
if ($sourceDiagnostics) { Write-Host "Diagnostics publics synchronisés vers $DiagnosticsOutputPath" }
elseif (-not $shouldSyncDiagnostics) { Write-Host "Diagnostics publics conservés jusqu'au prochain passage quotidien de 04:00." }
Write-Host "Pages de partage joueurs générées dans $PlayerPagesRoot"
