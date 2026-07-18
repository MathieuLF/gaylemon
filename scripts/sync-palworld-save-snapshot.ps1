param(
    [string]$OutputPath = (Join-Path $PSScriptRoot "..\portal\data\public-save-snapshot.json"),
    [string]$DiagnosticsOutputPath = (Join-Path $PSScriptRoot "..\portal\data\public-save-diagnostics.json"),
    [string]$BasesOutputPath = (Join-Path $PSScriptRoot "..\portal\data\public-save-bases.json"),
    [string]$CatalogsManifestOutputPath = (Join-Path $PSScriptRoot "..\portal\data\public-catalogs-manifest.json"),
    [string]$CatalogsOutputRoot = (Join-Path $PSScriptRoot "..\portal\data\public-catalogs"),
    [string]$PlayerDataRoot = (Join-Path $PSScriptRoot "..\portal\data\players"),
    [string]$PlayerPagesRoot = (Join-Path $PSScriptRoot "..\portal\joueur"),
    [string]$RemoteSnapshotPath = "",
    [string]$RemoteDiagnosticsPath = "",
    [string]$RemoteBasesPath = "",
    [string]$RemoteCatalogsManifestPath = "",
    [string]$SourceBundlePath = "",
    [int]$DiagnosticsRefreshIntervalHours = 2,
    [int]$DiagnosticsRefreshAnchorHour = 1,
    [int]$DiagnosticsRefreshWindowMinutes = 15,
    [switch]$ForceDiagnostics,
    [ValidateSet("", "AfterStage", "AfterFirstPublish")]
    [string]$TestFailurePoint = "",
    [int]$TestHoldLockMilliseconds = 0,
    [int]$TestFileOperationMaxAttempts = 0
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot
if (-not $RemoteSnapshotPath) { $RemoteSnapshotPath = "$($config.RemoteProjectRoot)/runtime/public-save-snapshot.json" }
if (-not $RemoteDiagnosticsPath) { $RemoteDiagnosticsPath = "$($config.RemoteProjectRoot)/runtime/public-save-diagnostics.json" }
if (-not $RemoteBasesPath) { $RemoteBasesPath = "$($config.RemoteProjectRoot)/runtime/public-save-bases.json" }
if (-not $RemoteCatalogsManifestPath) { $RemoteCatalogsManifestPath = "$($config.RemoteProjectRoot)/runtime/public-catalogs-manifest.json" }

$script:SaveSnapshotSyncLock = $null

function Close-SaveSnapshotSyncLock {
    if ($null -ne $script:SaveSnapshotSyncLock) {
        try { $script:SaveSnapshotSyncLock.Dispose() } catch { }
        $script:SaveSnapshotSyncLock = $null
    }
}

$resolvedOutputPathForLock = [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath))
$lockDirectory = Split-Path -Parent $resolvedOutputPathForLock
New-Item -ItemType Directory -Force -Path $lockDirectory | Out-Null
$lockPath = "$resolvedOutputPathForLock.lock"
try {
    $script:SaveSnapshotSyncLock = [IO.File]::Open(
        $lockPath,
        [IO.FileMode]::OpenOrCreate,
        [IO.FileAccess]::ReadWrite,
        [IO.FileShare]::None
    )
}
catch [IO.IOException] {
    Write-Host "Synchronisation des snapshots déjà en cours; cette exécution se termine sans modification."
    return
}

try {
if ($TestHoldLockMilliseconds -gt 0) {
    Start-Sleep -Milliseconds $TestHoldLockMilliseconds
}

function Get-DiagnosticsRefreshSlot {
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

function Test-DiagnosticsRefreshDue {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [int]$IntervalHours,
        [Parameter(Mandatory)] [int]$AnchorHour,
        [Parameter(Mandatory)] [int]$WindowMinutes,
        [switch]$Force
    )

    if ($Force) { return $true }
    if ($IntervalHours -le 0) { return $true }
    if (-not (Test-Path -LiteralPath $Path)) { return $true }

    $now = Get-Date
    $slot = Get-DiagnosticsRefreshSlot -IntervalHours $IntervalHours -AnchorHour $AnchorHour -Now $now
    if ($now -ge $slot.AddMinutes([Math]::Max(1, $WindowMinutes))) {
        return $false
    }

    $item = Get-Item -LiteralPath $Path
    return $item.LastWriteTime -lt $slot
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

    $raw = & ssh.exe -n -T -o BatchMode=yes -o ConnectTimeout=8 $config.SshAlias "test -s '$RemotePath' && gzip -c '$RemotePath' | base64 -w0" 2>$null
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
    $temporary = "$resolved.$([Guid]::NewGuid().ToString('N')).tmp"
    $content = ConvertTo-JsonFileText -Value $Value -Depth $Depth
    if ((Test-Path -LiteralPath $resolved) -and [IO.File]::ReadAllText($resolved, [Text.Encoding]::UTF8) -eq $content) {
        return
    }

    try {
        [IO.File]::WriteAllText($temporary, $content, [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $resolved -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
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

function Get-RemoteFileSha256 {
    param([Parameter(Mandatory)] [string]$RemotePath)

    $raw = & ssh.exe -n -T -o BatchMode=yes -o ConnectTimeout=8 $config.SshAlias "test -s '$RemotePath' && sha256sum -- '$RemotePath'" 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Le fichier public distant n'est pas disponible pour validation: $RemotePath"
    }
    $hash = (($raw | Out-String).Trim() -split '\s+')[0].ToLowerInvariant()
    if ($hash -notmatch '^[a-f0-9]{64}$') {
        throw "L'empreinte distante est invalide: $RemotePath"
    }
    return $hash
}

function ConvertTo-GenerationInstant {
    param(
        [Parameter(Mandatory)] [string]$Value,
        [Parameter(Mandatory)] [string]$Name
    )

    $parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse($Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) {
        throw "L'horodatage de génération '$Name' est invalide."
    }
    return $parsed.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ", [Globalization.CultureInfo]::InvariantCulture)
}

function Assert-SaveSourceBundle {
    param(
        [Parameter(Mandatory)] $Snapshot,
        [Parameter(Mandatory)] $Bases,
        [Parameter(Mandatory)] $Diagnostics
    )

    if (-not $Snapshot.ok -or [int]$Snapshot.version -notin @(2, 3, 4)) {
        throw "Le snapshot public distant est invalide ou incompatible."
    }
    if (-not $Bases.ok -or [int]$Bases.version -ne 1) {
        throw "Le snapshot public distant des bases est invalide ou incompatible."
    }
    if (-not $Diagnostics.ok -or [int]$Diagnostics.version -ne 1 -or [string]$Diagnostics.parse.status -ne "ok") {
        throw "Le diagnostic public distant est invalide ou incomplet."
    }

    $snapshotBackup = [string](Get-OptionalProperty (Get-OptionalProperty $Snapshot "source") "backup")
    $basesBackup = [string](Get-OptionalProperty (Get-OptionalProperty $Bases "source") "backup")
    $diagnosticsBackup = [string](Get-OptionalProperty (Get-OptionalProperty $Diagnostics "save") "backupName")
    if (-not $snapshotBackup -or $basesBackup -ne $snapshotBackup -or $diagnosticsBackup -ne $snapshotBackup) {
        throw "Les artefacts distants ne décrivent pas la même sauvegarde Palworld."
    }

    $snapshotProvenance = Get-OptionalProperty $Snapshot "provenance"
    $basesProvenance = Get-OptionalProperty $Bases "provenance"
    $diagnosticsProvenance = Get-OptionalProperty $Diagnostics "provenance"
    $snapshotUpdatedAt = [string](Get-OptionalProperty $snapshotProvenance "sourceUpdatedAt")
    if (-not $snapshotUpdatedAt) { $snapshotUpdatedAt = [string]$Snapshot.updatedAt }
    $basesUpdatedAt = [string](Get-OptionalProperty $basesProvenance "sourceUpdatedAt")
    if (-not $basesUpdatedAt) { $basesUpdatedAt = [string]$Bases.updatedAt }
    $snapshotInstant = ConvertTo-GenerationInstant -Value $snapshotUpdatedAt -Name "snapshot.provenance.sourceUpdatedAt"
    $basesInstant = ConvertTo-GenerationInstant -Value $basesUpdatedAt -Name "bases.provenance.sourceUpdatedAt"
    if ($basesInstant -ne $snapshotInstant) {
        throw "Le snapshot et les bases distants appartiennent à des captures différentes."
    }

    $projectionVersion = if (Get-OptionalProperty (Get-OptionalProperty $Snapshot "projection") "version") {
        [int]$Snapshot.projection.version
    }
    else {
        [int]$Snapshot.version
    }
    $basesSchemaVersion = Get-OptionalProperty $basesProvenance "schemaVersion"
    $diagnosticsSchemaVersion = Get-OptionalProperty $diagnosticsProvenance "schemaVersion"
    if ($null -eq $basesSchemaVersion -or [int]$basesSchemaVersion -ne $projectionVersion) {
        throw "Le contrat des bases ne correspond pas à celui du snapshot."
    }
    if ($null -eq $diagnosticsSchemaVersion -or [int]$diagnosticsSchemaVersion -ne $projectionVersion) {
        throw "Le contrat du diagnostic ne correspond pas à celui du snapshot."
    }

    $snapshotParser = [string](Get-OptionalProperty (Get-OptionalProperty $Snapshot "parser") "commit")
    $basesParser = [string](Get-OptionalProperty (Get-OptionalProperty $Bases "parser") "commit")
    $diagnosticsParser = [string](Get-OptionalProperty (Get-OptionalProperty $Diagnostics "parser") "commit")
    if (-not $snapshotParser -or $basesParser -ne $snapshotParser -or $diagnosticsParser -ne $snapshotParser) {
        throw "Les artefacts distants n'utilisent pas la même version du parseur."
    }

    $identityText = "$snapshotBackup|$snapshotInstant|$snapshotParser|$projectionVersion"
    $identityHash = (Get-Utf8Sha256 -Text $identityText).Substring(0, 16)
    return [pscustomobject]@{
        generationId = "save-$($snapshotInstant.Substring(0, 19).Replace('-', '').Replace(':', '').Replace('T', '-'))-$identityHash"
        backup = $snapshotBackup
        sourceUpdatedAt = $snapshotInstant
        parserCommit = $snapshotParser
        schemaVersion = $projectionVersion
    }
}

function ConvertTo-JsonFileText {
    param(
        [Parameter(Mandatory)] $Value,
        [int]$Depth = 20
    )

    $json = $Value | ConvertTo-Json -Depth $Depth
    return $json.TrimEnd() + [Environment]::NewLine
}

function Get-JsonFileBytes {
    param(
        [Parameter(Mandatory)] $Value,
        [int]$Depth = 20
    )

    return [Text.UTF8Encoding]::new($false).GetByteCount((ConvertTo-JsonFileText -Value $Value -Depth $Depth))
}

function Read-RemoteText {
    param(
        [Parameter(Mandatory)] [string]$RemotePath,
        [switch]$Optional
    )

    $raw = & ssh.exe -n -T -o BatchMode=yes -o ConnectTimeout=8 $config.SshAlias "test -s '$RemotePath' && gzip -c '$RemotePath' | base64 -w0" 2>$null
    if ($LASTEXITCODE -ne 0) {
        if ($Optional) { return $null }
        throw "Le fichier public distant n'est pas disponible: $RemotePath"
    }
    $base64 = (($raw | Out-String).Trim())
    if (-not $base64) {
        if ($Optional) { return $null }
        throw "Le fichier public distant est vide: $RemotePath"
    }
    return Expand-GzipBase64 -Value $base64
}

function Get-Utf8Sha256 {
    param([Parameter(Mandatory)] [string]$Text)

    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $algorithm.Dispose()
    }
}

function Write-TextAtomic {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Text
    )

    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolved) | Out-Null
    if ((Test-Path -LiteralPath $resolved) -and [IO.File]::ReadAllText($resolved, [Text.Encoding]::UTF8) -eq $Text) {
        return
    }
    $temporary = "$resolved.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary, $Text, [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $resolved -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Convert-PublicProvenance($Value, [string]$UpdatedAt, [int]$SchemaVersion) {
    return [ordered]@{
        observedAt = if (Get-OptionalProperty $Value "observedAt") { [string]$Value.observedAt } else { $UpdatedAt }
        sourceUpdatedAt = if (Get-OptionalProperty $Value "sourceUpdatedAt") { [string]$Value.sourceUpdatedAt } else { $UpdatedAt }
        gameVersion = if (Get-OptionalProperty $Value "gameVersion") { [string]$Value.gameVersion } else { $null }
        steamBuildId = if (Get-OptionalProperty $Value "steamBuildId") { [string]$Value.steamBuildId } else { $null }
        parserCommit = if (Get-OptionalProperty $Value "parserCommit") { [string]$Value.parserCommit } else { $null }
        catalogCommit = if (Get-OptionalProperty $Value "catalogCommit") { [string]$Value.catalogCommit } else { $null }
        schemaVersion = $SchemaVersion
        freshness = if (Get-OptionalProperty $Value "freshness") { [string]$Value.freshness } else { "current" }
        sourceStatus = if (Get-OptionalProperty $Value "sourceStatus") { [string]$Value.sourceStatus } else { "available" }
    }
}

function Convert-PublicExperienceProgress($Progress) {
    if ($null -eq $Progress) { return $null }
    return [ordered]@{
        level = [int]$Progress.level
        nextLevel = [int]$Progress.nextLevel
        gained = [long]$Progress.gained
        required = [long]$Progress.required
        remaining = [long]$Progress.remaining
        percent = Get-NullableDouble $Progress.percent
    }
}

function Convert-PublicFriendshipProgress($Progress) {
    if ($null -eq $Progress) { return $null }
    return [ordered]@{
        points = [long]$Progress.points
        rank = [int]$Progress.rank
        nextRank = Get-NullableInt $Progress.nextRank
        remaining = Get-NullableInt $Progress.remaining
        percent = Get-NullableDouble $Progress.percent
    }
}

function Get-GaylemonPathBytes {
    param(
        [Parameter(Mandatory)] [string[]]$RelativePaths,
        [string[]]$ExcludeRelativeRoots = @()
    )

    $excludeRoots = @($ExcludeRelativeRoots | ForEach-Object {
        $candidate = Join-Path $ProjectRoot $_
        if (Test-Path -LiteralPath $candidate) {
            (Resolve-Path -LiteralPath $candidate).Path.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        }
        else {
            $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($candidate).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        }
    })

    [long]$total = 0
    foreach ($relativePath in $RelativePaths) {
        $candidate = Join-Path $ProjectRoot $relativePath
        if (-not (Test-Path -LiteralPath $candidate)) { continue }
        $item = Get-Item -LiteralPath $candidate
        $files = if ($item.PSIsContainer) {
            Get-ChildItem -LiteralPath $item.FullName -File -Recurse -Force
        }
        else {
            @($item)
        }
        foreach ($file in $files) {
            $fullName = $file.FullName
            $excluded = $false
            foreach ($root in $excludeRoots) {
                if ($fullName -eq $root -or $fullName.StartsWith($root + [IO.Path]::DirectorySeparatorChar) -or $fullName.StartsWith($root + [IO.Path]::AltDirectorySeparatorChar)) {
                    $excluded = $true
                    break
                }
            }
            if (-not $excluded) { $total += [long]$file.Length }
        }
    }
    return $total
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

function Convert-PublicDeathDrop($Drop) {
    $player = Get-OptionalProperty $Drop "player"
    return [ordered]@{
        key = [string]$Drop.key
        type = [string]$Drop.type
        label = [string]$Drop.label
        player = if ($player) { [string]$player } else { $null }
        position = Convert-PublicPosition $Drop.position
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
        experienceProgress = Convert-PublicExperienceProgress (Get-OptionalProperty $Pal "experienceProgress")
        rarity = Get-NullableInt (Get-OptionalProperty $Pal "rarity")
        gender = if ($Pal.gender) { [string]$Pal.gender } else { $null }
        container = [string]$Pal.container
        hp = [double]$Pal.hp
        maxHp = Get-NullableInt $Pal.maxHp
        hunger = [double]$Pal.hunger
        sanity = Get-NullableDouble $Pal.sanity
        friendship = [int]$Pal.friendship
        friendshipProgress = Convert-PublicFriendshipProgress (Get-OptionalProperty $Pal "friendshipProgress")
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
        nextLearnedSkills = @((Get-OptionalProperty $Pal "nextLearnedSkills") | Where-Object { $null -ne $_ } | ForEach-Object {
            [ordered]@{
                level = [int]$_.level
                name = [string]$_.name
                description = if ($_.description) { [string]$_.description } else { $null }
                rank = [int]$_.rank
                power = Get-NullableInt $_.power
                cooldown = Get-NullableDouble $_.cooldown
                element = if ($_.element) { [string]$_.element } else { $null }
            }
        })
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
            weight = Get-NullableDouble (Get-OptionalProperty $_ "weight")
            totalWeight = Get-NullableDouble (Get-OptionalProperty $_ "totalWeight")
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
                    weight = Get-NullableDouble (Get-OptionalProperty $_ "weight")
                    totalWeight = Get-NullableDouble (Get-OptionalProperty $_ "totalWeight")
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
            notesFound = Get-OptionalInt $records "notesFound"
            arenaSoloClears = Get-OptionalInt $records "arenaSoloClears"
            mutations = Get-OptionalInt $records "mutations"
            palRankups = Get-OptionalInt $records "palRankups"
            raidBossDefeats = Get-OptionalInt $records "raidBossDefeats"
            towerBossDefeats = Get-OptionalInt $records "towerBossDefeats"
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
            if ($key -notin @("container", "steamBuildId") -and [string]$key -match $forbidden) {
                throw "Clé technique interdite dans la projection publique: $Path.$key"
            }
            Assert-PublicPayload $Value[$key] "$Path.$key"
        }
    }
    elseif ($Value -is [pscustomobject]) {
        foreach ($property in $Value.PSObject.Properties) {
            if ($property.Name -notin @("container", "steamBuildId") -and $property.Name -match $forbidden) {
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

function Write-PlayerDataFiles($Players, [string]$DestinationRoot, [string]$UpdatedAt, [int]$Version, $Provenance, [string]$GenerationId) {
    $resolvedRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationRoot)
    New-Item -ItemType Directory -Force -Path $resolvedRoot | Out-Null
    $expectedFiles = @()
    foreach ($player in $Players) {
        $slug = ConvertTo-PlayerSlug ([string]$player.name)
        $expectedFiles += "$slug.json"
        $payload = [ordered]@{
            version = $Version
            ok = $true
            generationId = $GenerationId
            updatedAt = $UpdatedAt
            provenance = $Provenance
            player = $player
        }
        Assert-PublicPayload $payload
        Write-JsonAtomic -Path (Join-Path $resolvedRoot "$slug.json") -Value $payload -Depth 24
    }
    Get-ChildItem -LiteralPath $resolvedRoot -File -Filter "*.json" -ErrorAction SilentlyContinue |
        Where-Object { $expectedFiles -notcontains $_.Name } |
        Remove-Item -Force
}

function Invoke-SnapshotFileOperationWithRetry {
    param(
        [Parameter(Mandatory)] [scriptblock]$Operation,
        [Parameter(Mandatory)] [string]$Description,
        [int]$MaxAttempts = 18
    )

    $safeMaxAttempts = [Math]::Max(1, $MaxAttempts)
    for ($attempt = 1; $attempt -le $safeMaxAttempts; $attempt++) {
        try {
            & $Operation
            return
        }
        catch {
            $retryable = $_.Exception -is [IO.IOException] -or $_.Exception -is [UnauthorizedAccessException]
            if (-not $retryable -or $attempt -ge $safeMaxAttempts) {
                throw
            }
            $delayMilliseconds = [Math]::Min(500, [int](40 * [Math]::Pow(1.65, $attempt - 1)))
            Start-Sleep -Milliseconds $delayMilliseconds
        }
    }
    throw "L'opération de fichiers n'a pas abouti: $Description"
}

function Move-SnapshotPathWithRetry {
    param(
        [Parameter(Mandatory)] [string]$Source,
        [Parameter(Mandatory)] [string]$Destination,
        [int]$MaxAttempts = 18
    )

    Invoke-SnapshotFileOperationWithRetry `
        -Description "déplacement de $Source vers $Destination" `
        -MaxAttempts $MaxAttempts `
        -Operation { Move-Item -LiteralPath $Source -Destination $Destination -ErrorAction Stop }
}

function Remove-SnapshotPathWithRetry {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [int]$MaxAttempts = 18
    )

    Invoke-SnapshotFileOperationWithRetry `
        -Description "suppression de $Path" `
        -MaxAttempts $MaxAttempts `
        -Operation {
            if (Test-Path -LiteralPath $Path) {
                Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            }
        }
}

function Publish-PublicSaveGeneration {
    param(
        [Parameter(Mandatory)] $Snapshot,
        [Parameter(Mandatory)] $Index,
        [Parameter(Mandatory)] $Bases,
        [Parameter(Mandatory)] $Diagnostics,
        [Parameter(Mandatory)] [string]$SnapshotPath,
        [Parameter(Mandatory)] [string]$IndexPath,
        [Parameter(Mandatory)] [string]$BasesPath,
        [Parameter(Mandatory)] [string]$DiagnosticsPath,
        [Parameter(Mandatory)] [string]$PlayersRoot,
        [Parameter(Mandatory)] [string]$PlayerPagesRoot,
        [Parameter(Mandatory)] [string]$GenerationId,
        [string]$FailurePoint = "",
        [int]$FileOperationMaxAttempts = 18
    )

    $resolvedSnapshotPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SnapshotPath)
    $transactionParent = Split-Path -Parent $resolvedSnapshotPath
    New-Item -ItemType Directory -Force -Path $transactionParent | Out-Null
    $transactionRoot = Join-Path $transactionParent (".public-save-sync-" + [Guid]::NewGuid().ToString("N"))
    $stageRoot = Join-Path $transactionRoot "staged"
    $backupRoot = Join-Path $transactionRoot "previous"
    New-Item -ItemType Directory -Force -Path $stageRoot, $backupRoot | Out-Null

    $stagedSnapshot = Join-Path $stageRoot "public-save-snapshot.json"
    $stagedIndex = Join-Path $stageRoot "public-save-index.json"
    $stagedBases = Join-Path $stageRoot "public-save-bases.json"
    $stagedDiagnostics = Join-Path $stageRoot "public-save-diagnostics.json"
    $stagedPlayers = Join-Path $stageRoot "players"
    $stagedPages = Join-Path $stageRoot "joueur"

    $items = @(
        [pscustomobject]@{ Type = "file"; Stage = $stagedSnapshot; Destination = $resolvedSnapshotPath; Backup = (Join-Path $backupRoot "public-save-snapshot.json"); HadPrevious = $false; Published = $false },
        [pscustomobject]@{ Type = "file"; Stage = $stagedBases; Destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BasesPath); Backup = (Join-Path $backupRoot "public-save-bases.json"); HadPrevious = $false; Published = $false },
        [pscustomobject]@{ Type = "file"; Stage = $stagedDiagnostics; Destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DiagnosticsPath); Backup = (Join-Path $backupRoot "public-save-diagnostics.json"); HadPrevious = $false; Published = $false },
        [pscustomobject]@{ Type = "directory"; Stage = $stagedPlayers; Destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PlayersRoot); Backup = (Join-Path $backupRoot "players"); HadPrevious = $false; Published = $false },
        [pscustomobject]@{ Type = "directory"; Stage = $stagedPages; Destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PlayerPagesRoot); Backup = (Join-Path $backupRoot "joueur"); HadPrevious = $false; Published = $false },
        [pscustomobject]@{ Type = "file"; Stage = $stagedIndex; Destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($IndexPath); Backup = (Join-Path $backupRoot "public-save-index.json"); HadPrevious = $false; Published = $false }
    )

    try {
        $transactionVolume = [IO.Path]::GetPathRoot($transactionRoot)
        foreach ($item in $items) {
            if ([IO.Path]::GetPathRoot([string]$item.Destination) -ne $transactionVolume) {
                throw "Tous les artefacts d'une génération publique doivent être publiés sur le même volume."
            }
        }

        Write-JsonAtomic -Path $stagedSnapshot -Value $Snapshot -Depth 24
        Write-JsonAtomic -Path $stagedIndex -Value $Index -Depth 14
        Write-JsonAtomic -Path $stagedBases -Value $Bases -Depth 24
        Write-JsonAtomic -Path $stagedDiagnostics -Value $Diagnostics -Depth 10
        Write-PlayerDataFiles -Players $Snapshot.players -DestinationRoot $stagedPlayers -UpdatedAt $Snapshot.updatedAt -Version $Snapshot.version -Provenance $Snapshot.provenance -GenerationId $GenerationId
        Write-PlayerSharePages -Players $Snapshot.players -DestinationRoot $stagedPages

        foreach ($item in $items) {
            if (-not (Test-Path -LiteralPath $item.Stage)) {
                throw "Un artefact de la génération publique n'a pas été préparé: $($item.Stage)"
            }
        }
        if ($FailurePoint -eq "AfterStage") {
            throw "Échec de publication injecté après la préparation."
        }

        $publishedCount = 0
        foreach ($item in $items) {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $item.Destination) | Out-Null
            if ($item.Type -eq "file" -and (Test-Path -LiteralPath $item.Destination -PathType Leaf)) {
                Invoke-SnapshotFileOperationWithRetry `
                    -Description "remplacement atomique de $($item.Destination)" `
                    -MaxAttempts $FileOperationMaxAttempts `
                    -Operation { [IO.File]::Replace($item.Stage, $item.Destination, $item.Backup, $true) }
                $item.HadPrevious = $true
                $item.Published = $true
            }
            else {
                if (Test-Path -LiteralPath $item.Destination) {
                    Move-SnapshotPathWithRetry -Source $item.Destination -Destination $item.Backup -MaxAttempts $FileOperationMaxAttempts
                    $item.HadPrevious = $true
                }
                Move-SnapshotPathWithRetry -Source $item.Stage -Destination $item.Destination -MaxAttempts $FileOperationMaxAttempts
                $item.Published = $true
            }
            $publishedCount++
            if ($FailurePoint -eq "AfterFirstPublish" -and $publishedCount -eq 1) {
                throw "Échec de publication injecté après le premier artefact."
            }
        }
    }
    catch {
        $publicationError = $_
        $rollbackErrors = @()
        for ($index = $items.Count - 1; $index -ge 0; $index--) {
            $item = $items[$index]
            try {
                if ($item.HadPrevious -and (Test-Path -LiteralPath $item.Backup)) {
                    if ($item.Type -eq "file" -and (Test-Path -LiteralPath $item.Destination -PathType Leaf)) {
                        $discardPath = Join-Path $backupRoot ("discard-" + [Guid]::NewGuid().ToString("N") + ".json")
                        Invoke-SnapshotFileOperationWithRetry `
                            -Description "restauration atomique de $($item.Destination)" `
                            -MaxAttempts $FileOperationMaxAttempts `
                            -Operation { [IO.File]::Replace($item.Backup, $item.Destination, $discardPath, $true) }
                        if (Test-Path -LiteralPath $discardPath) {
                            Remove-SnapshotPathWithRetry -Path $discardPath -MaxAttempts $FileOperationMaxAttempts
                        }
                    }
                    else {
                        if ($item.Published -and (Test-Path -LiteralPath $item.Destination)) {
                            Remove-SnapshotPathWithRetry -Path $item.Destination -MaxAttempts $FileOperationMaxAttempts
                        }
                        Move-SnapshotPathWithRetry -Source $item.Backup -Destination $item.Destination -MaxAttempts $FileOperationMaxAttempts
                    }
                }
                elseif ($item.Published -and (Test-Path -LiteralPath $item.Destination)) {
                    Remove-SnapshotPathWithRetry -Path $item.Destination -MaxAttempts $FileOperationMaxAttempts
                }
            }
            catch {
                $rollbackErrors += $_.Exception.Message
            }
        }
        if ($rollbackErrors.Count) {
            throw "La publication a échoué et la restauration est incomplète: $($rollbackErrors -join ' | '). Cause initiale: $($publicationError.Exception.Message)"
        }
        throw $publicationError
    }
    finally {
        if (Test-Path -LiteralPath $transactionRoot) {
            try {
                Remove-SnapshotPathWithRetry -Path $transactionRoot -MaxAttempts $FileOperationMaxAttempts
            }
            catch {
                Write-Warning "Le dossier transactionnel sera nettoyé au prochain passage: $transactionRoot"
            }
        }
    }
}

if ($SourceBundlePath) {
    $sourceBundle = Read-LocalJson -Path $SourceBundlePath
    if (-not $sourceBundle) { throw "Le lot source local est vide ou invalide: $SourceBundlePath" }
    $source = Get-OptionalProperty $sourceBundle "snapshot"
    $sourceBases = Get-OptionalProperty $sourceBundle "bases"
    $sourceDiagnostics = Get-OptionalProperty $sourceBundle "diagnostics"
    $sourceCatalogsManifest = Get-OptionalProperty $sourceBundle "catalogsManifest"
}
else {
    $snapshotHashBefore = Get-RemoteFileSha256 -RemotePath $RemoteSnapshotPath
    $source = Read-RemoteJson -RemotePath $RemoteSnapshotPath
    $sourceBases = Read-RemoteJson -RemotePath $RemoteBasesPath
    $sourceDiagnostics = Read-RemoteJson -RemotePath $RemoteDiagnosticsPath
    $snapshotHashAfter = Get-RemoteFileSha256 -RemotePath $RemoteSnapshotPath
    if ($snapshotHashBefore -ne $snapshotHashAfter) {
        throw "La génération distante a changé pendant le téléchargement; la génération locale précédente est conservée."
    }
    $sourceCatalogsManifest = Read-RemoteJson -RemotePath $RemoteCatalogsManifestPath -Optional
}
$sourceGeneration = Assert-SaveSourceBundle -Snapshot $source -Bases $sourceBases -Diagnostics $sourceDiagnostics
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
$sourceProvenance = Get-OptionalProperty $source "provenance"
$publicProvenance = Convert-PublicProvenance $sourceProvenance ([string]$source.updatedAt) $projectionVersion
$publicProvenance.sourceUpdatedAt = $sourceGeneration.sourceUpdatedAt

$public = [ordered]@{
    version = [int]$source.version
    ok = $true
    generationId = $sourceGeneration.generationId
    updatedAt = [string]$source.updatedAt
    provenance = $publicProvenance
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
            deathDrops = @((Get-OptionalProperty $source.world "deathDrops") | Where-Object { $null -ne $_ } | ForEach-Object {
                Convert-PublicDeathDrop $_
            })
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
                experienceProgress = Convert-PublicExperienceProgress (Get-OptionalProperty $_.character "experienceProgress")
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
                team = @($_.pals.collection |
                    Where-Object { [string]$_.container -eq "party" } |
                    Select-Object -First 5 |
                    ForEach-Object { Convert-PublicPal $_ })
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
    generationId = $sourceGeneration.generationId
    updatedAt = $public.updatedAt
    provenance = $public.provenance
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
                team = @($_.pals.collection |
                    Where-Object { [string]$_.container -eq "party" } |
                    Select-Object -First 5)
            }
            progress = Convert-PublicProgress $_.progress -SummaryOnly
        }
    })
}

Assert-PublicPayload $public
Assert-PublicPayload $publicIndex
$indexPath = Join-Path (Split-Path -Parent $OutputPath) "public-save-index.json"

if ($sourceCatalogsManifest -and $sourceCatalogsManifest.ok) {
    $catalogGenerationId = [string](Get-OptionalProperty $sourceCatalogsManifest "generationId")
    if ($catalogGenerationId -notmatch '^[A-Za-z0-9._-]+$') {
        throw "L'identifiant de génération des catalogues est invalide."
    }
    $catalogFiles = Get-OptionalProperty $sourceCatalogsManifest "files"
    $localCatalogManifest = Read-LocalJson -Path $CatalogsManifestOutputPath
    $sameCatalogContract = $localCatalogManifest -and
        [string](Get-OptionalProperty $localCatalogManifest "generationId") -eq $catalogGenerationId -and
        [string](Get-OptionalProperty $localCatalogManifest "contentRevision") -eq [string](Get-OptionalProperty $sourceCatalogsManifest "contentRevision")
    $expectedCatalogs = @("progression", "learnsets", "breeding")
    foreach ($catalogName in $expectedCatalogs) {
        $entry = Get-OptionalProperty $catalogFiles $catalogName
        $relativePath = [string](Get-OptionalProperty $entry "path")
        $expectedHash = ([string](Get-OptionalProperty $entry "sha256")) -replace '^sha256:', ''
        if (
            $relativePath -notmatch '^public-catalogs/[A-Za-z0-9._-]+/(progression|learnsets|breeding)\.json$' -or
            $relativePath -notmatch ('^public-catalogs/' + [regex]::Escape($catalogGenerationId) + '/') -or
            $expectedHash -notmatch '^[a-fA-F0-9]{64}$'
        ) {
            throw "Le contrat du catalogue $catalogName est invalide."
        }
        $localRelativePath = $relativePath.Substring("public-catalogs/".Length).Replace('/', [IO.Path]::DirectorySeparatorChar)
        $localCatalogPath = Join-Path $CatalogsOutputRoot $localRelativePath
        $expectedBytes = [long](Get-OptionalProperty $entry "bytes")
        $localEntry = if ($sameCatalogContract) { Get-OptionalProperty (Get-OptionalProperty $localCatalogManifest "files") $catalogName } else { $null }
        $localCurrent = $localEntry -and
            [string](Get-OptionalProperty $localEntry "sha256") -eq [string](Get-OptionalProperty $entry "sha256") -and
            (Test-Path -LiteralPath $localCatalogPath -PathType Leaf) -and
            ($expectedBytes -le 0 -or (Get-Item -LiteralPath $localCatalogPath).Length -eq $expectedBytes)
        if (-not $localCurrent -and (Test-Path -LiteralPath $localCatalogPath -PathType Leaf)) {
            $localCurrent = (Get-FileHash -LiteralPath $localCatalogPath -Algorithm SHA256).Hash.ToLowerInvariant() -eq $expectedHash.ToLowerInvariant()
        }
        if (-not $localCurrent) {
            $remoteCatalogPath = "$($config.RemoteProjectRoot)/runtime/$relativePath"
            $catalogText = Read-RemoteText -RemotePath $remoteCatalogPath
            if ((Get-Utf8Sha256 -Text $catalogText) -ne $expectedHash.ToLowerInvariant()) {
                throw "L'empreinte du catalogue $catalogName ne correspond pas au manifeste."
            }
            Write-TextAtomic -Path $localCatalogPath -Text $catalogText
        }
    }
    Write-JsonAtomic -Path $CatalogsManifestOutputPath -Value $sourceCatalogsManifest -Depth 10
}

$publicBases = $null
if ($sourceBases -and $sourceBases.ok -and [int]$sourceBases.version -eq 1) {
    $sourceBasesProvenance = Get-OptionalProperty $sourceBases "provenance"
    $sourceBasesSchemaVersion = if (Get-OptionalProperty $sourceBasesProvenance "schemaVersion") {
        [int]$sourceBasesProvenance.schemaVersion
    }
    else {
        [int]$sourceBases.version
    }
    $publicBasesProvenance = Convert-PublicProvenance $sourceBasesProvenance ([string]$sourceBases.updatedAt) $sourceBasesSchemaVersion
    $publicBasesProvenance.sourceUpdatedAt = $sourceGeneration.sourceUpdatedAt
    $publicBases = [ordered]@{
        version = 1
        ok = $true
        generationId = $sourceGeneration.generationId
        updatedAt = [string]$sourceBases.updatedAt
        provenance = $publicBasesProvenance
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
}

$publicDiagnostics = $null
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
    $footprintDataBytes = Get-GaylemonPathBytes -RelativePaths @("portal\data", "portal\joueur")
    $footprintMicrositeBytes = Get-GaylemonPathBytes -RelativePaths @("portal") -ExcludeRelativeRoots @("portal\assets", "portal\data", "portal\joueur")
    $footprintAssetsBytes = Get-GaylemonPathBytes -RelativePaths @("portal\assets")
    $footprintScriptsBytes = Get-GaylemonPathBytes -RelativePaths @("scripts")
    $footprintServerBytes = Get-GaylemonPathBytes -RelativePaths @("server")
    $footprintDockerBytes = Get-GaylemonPathBytes -RelativePaths @("docker", "compose.yaml", ".env.example", "config")
    $footprintTotalBytes = $footprintDataBytes + $footprintMicrositeBytes + $footprintAssetsBytes + $footprintScriptsBytes + $footprintServerBytes + $footprintDockerBytes
    $unknownStructures = Get-OptionalProperty $sourceDiagnostics.parse "unknownStructures"
    $catalogDrift = Get-OptionalProperty $sourceDiagnostics.parse "catalogDrift"
    $diagnosticSourceProvenance = Get-OptionalProperty $sourceDiagnostics "provenance"
    if (-not $diagnosticSourceProvenance) { $diagnosticSourceProvenance = Get-OptionalProperty $source "provenance" }
    $diagnosticProvenance = Convert-PublicProvenance $diagnosticSourceProvenance ([string]$sourceDiagnostics.updatedAt) 1
    $diagnosticProvenance.observedAt = [string]$sourceDiagnostics.updatedAt
    $diagnosticProvenance.sourceUpdatedAt = $sourceGeneration.sourceUpdatedAt
    $diagnosticProvenance.schemaVersion = $sourceGeneration.schemaVersion
    $publicDiagnostics = [ordered]@{
        version = 1
        ok = [bool]$sourceDiagnostics.ok
        generationId = $sourceGeneration.generationId
        updatedAt = [string]$sourceDiagnostics.updatedAt
        provenance = $diagnosticProvenance
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
            unknownStructures = [ordered]@{
                unknownAreas = Get-OptionalInt $unknownStructures "unknownAreas"
                unknownBossFlags = Get-OptionalInt $unknownStructures "unknownBossFlags"
                unknownFastTravelPoints = Get-OptionalInt $unknownStructures "unknownFastTravelPoints"
                unknownPalCaptureAssets = Get-OptionalInt $unknownStructures "unknownPalCaptureAssets"
                unknownPalChallengeAssets = Get-OptionalInt $unknownStructures "unknownPalChallengeAssets"
                unknownPaldeckAssets = Get-OptionalInt $unknownStructures "unknownPaldeckAssets"
                unknownPalProperties = Get-OptionalInt $unknownStructures "unknownPalProperties"
                unknownTechnologies = Get-OptionalInt $unknownStructures "unknownTechnologies"
                unresolvedBaseWorkers = Get-OptionalInt $unknownStructures "unresolvedBaseWorkers"
            }
            catalogDrift = [ordered]@{
                unknownIdentifiers = Get-OptionalInt $catalogDrift "unknownIdentifiers"
                categories = if (Get-OptionalProperty $catalogDrift "categories") { $catalogDrift.categories } else { [ordered]@{} }
            }
        }
        output = [ordered]@{
            snapshotBytes = Get-NullableInt $sourceDiagnostics.output.snapshotBytes
            snapshotGzipBytes = Get-NullableInt $sourceDiagnostics.output.snapshotGzipBytes
            basesBytes = Get-NullableInt $sourceDiagnostics.output.basesBytes
            basesGzipBytes = Get-NullableInt $sourceDiagnostics.output.basesGzipBytes
            privateBasesBytes = Get-NullableInt $sourceDiagnostics.output.privateBasesBytes
            historyArchiveBytes = Get-NullableInt $sourceDiagnostics.output.historyArchiveBytes
            basesHistoryArchiveBytes = Get-NullableInt $sourceDiagnostics.output.basesHistoryArchiveBytes
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
            indexBytes = Get-JsonFileBytes -Value $publicIndex -Depth 14
            snapshotBytes = Get-JsonFileBytes -Value $public -Depth 24
            basesBytes = Get-JsonFileBytes -Value $publicBases -Depth 24
        }
        assets = [ordered]@{
            worldMapBytes = if (Test-Path $worldMap) { (Get-Item $worldMap).Length } else { $null }
            worldMapWidth = 8192
            worldMapHeight = 8192
            treeMapBytes = if (Test-Path $treeMap) { (Get-Item $treeMap).Length } else { $null }
        }
        footprint = [ordered]@{
            totalBytes = $footprintTotalBytes
            publicDataBytes = $footprintDataBytes
            micrositeBytes = $footprintMicrositeBytes
            assetsBytes = $footprintAssetsBytes
            scriptsBytes = $footprintScriptsBytes
            serverBytes = $footprintServerBytes
            dockerBytes = $footprintDockerBytes
        }
    }
    Assert-PublicPayload $publicDiagnostics
}

if (-not $publicBases -or -not $publicDiagnostics) {
    throw "La génération distante est incomplète; la génération locale précédente est conservée."
}

$fileOperationMaxAttempts = if ($TestFileOperationMaxAttempts -gt 0) { $TestFileOperationMaxAttempts } else { 18 }
Publish-PublicSaveGeneration `
    -Snapshot $public `
    -Index $publicIndex `
    -Bases $publicBases `
    -Diagnostics $publicDiagnostics `
    -SnapshotPath $OutputPath `
    -IndexPath $indexPath `
    -BasesPath $BasesOutputPath `
    -DiagnosticsPath $DiagnosticsOutputPath `
    -PlayersRoot $PlayerDataRoot `
    -PlayerPagesRoot $PlayerPagesRoot `
    -GenerationId $sourceGeneration.generationId `
    -FailurePoint $TestFailurePoint `
    -FileOperationMaxAttempts $fileOperationMaxAttempts

Write-Host "Snapshot public v$($public.version), projection v$($public.projection.version) synchronisé vers $OutputPath"
Write-Host "Index léger synchronisé vers $indexPath"
Write-Host "Diagnostics publics synchronisés vers $DiagnosticsOutputPath"
Write-Host "Pages de partage joueurs générées dans $PlayerPagesRoot"
}
finally {
    Close-SaveSnapshotSyncLock
}
