param(
    [string]$OutputPath = (Join-Path $PSScriptRoot "..\portal\data\public-events.json"),
    [string]$RecentOutputPath = (Join-Path $PSScriptRoot "..\portal\data\public-events-recent.json"),
    [string]$IndexOutputPath = (Join-Path $PSScriptRoot "..\portal\data\public-events-index.json"),
    [int]$PageSize = 250,
    [int]$RecentEventLimit = 2000,
    [string]$SyncStatePath = (Join-Path $PSScriptRoot "..\portal\data\public-events-sync-state.json"),
    [string]$SourcePayloadPath = "",
    [string]$RecentSourcePayloadPath = "",
    [ValidateSet("", "AfterFragments", "AfterHead")]
    [string]$TestFailurePoint = "",
    [ValidateRange(0, 30000)]
    [int]$TestHoldLockMilliseconds = 0,
    [switch]$Fast,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
if ($PageSize -lt 1) {
    throw "La taille des pages d'échos doit être supérieure à zéro."
}
if ($RecentEventLimit -lt 1) {
    throw "La fenêtre récente des échos doit être supérieure à zéro."
}
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot
$PublicEventVersion = 5
$PublicEventContractVersion = 6
$PublicEventHeadLimit = 5
$ItemizedEventGroupWindowSeconds = 5 * 60
$allowedTypes = @(
    "join", "leave", "reconnect", "server", "maintenance", "discovery", "collection",
    "capture", "challenge", "quest", "loot", "adventure", "raid", "boss", "arena",
    "death", "recovery", "note", "pal", "mutation", "level", "progress", "camp",
    "craft", "build", "production", "hatch", "fishing", "research", "base", "repair",
    "settings"
)
$allowedSources = @("journal", "players", "save", "update", "server")
$remotePath = "$($config.RemoteProjectRoot)/runtime/public-events.json"
$remoteRecentPath = "$($config.RemoteProjectRoot)/runtime/public-events-recent.json"
$resolvedSourcePayloadPath = if ($SourcePayloadPath) {
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SourcePayloadPath)
}
else { "" }
$resolvedRecentSourcePayloadPath = if ($RecentSourcePayloadPath) {
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RecentSourcePayloadPath)
}
else { "" }

$script:EventSyncLock = $null

function Close-EventSyncLock {
    if ($null -ne $script:EventSyncLock) {
        try { $script:EventSyncLock.Dispose() } catch { }
        $script:EventSyncLock = $null
    }
}

$resolvedOutputPathForLock = [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath))
$lockDirectory = Split-Path -Parent $resolvedOutputPathForLock
New-Item -ItemType Directory -Force -Path $lockDirectory | Out-Null
$lockPath = "$resolvedOutputPathForLock.lock"
try {
    $script:EventSyncLock = [IO.File]::Open(
        $lockPath,
        [IO.FileMode]::OpenOrCreate,
        [IO.FileAccess]::ReadWrite,
        [IO.FileShare]::None
    )
}
catch [IO.IOException] {
    Write-Host "Synchronisation des échos déjà en cours; cette exécution se termine sans modification."
    return
}

try {
if ($TestHoldLockMilliseconds -gt 0) {
    Start-Sleep -Milliseconds $TestHoldLockMilliseconds
}

function Get-OptionalProperty {
    param($Value, [string]$Name)

    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        if ($Value.Contains($Name)) { return $Value[$Name] }
        return $null
    }
    $property = $Value.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Set-OptionalProperty {
    param(
        $Value,
        [Parameter(Mandatory)] [string]$Name,
        $PropertyValue
    )

    if ($null -eq $Value) { return }
    if ($Value -is [System.Collections.IDictionary]) {
        $Value[$Name] = $PropertyValue
        return
    }
    $property = $Value.PSObject.Properties[$Name]
    if ($null -ne $property) {
        $property.Value = $PropertyValue
        return
    }
    $Value | Add-Member -NotePropertyName $Name -NotePropertyValue $PropertyValue
}

function Read-JsonFile {
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Get-StateValue {
    param($Value, [Parameter(Mandatory)] [string]$Name)

    if ($null -eq $Value) { return $null }
    $property = $Value.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Write-SyncState {
    param([Parameter(Mandatory)] $State)

    $resolvedStatePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SyncStatePath)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedStatePath) | Out-Null
    $json = $State | ConvertTo-Json -Depth 8
    $temporary = "$resolvedStatePath.$([Guid]::NewGuid().ToString('N')).tmp"
    [IO.File]::WriteAllText($temporary, ($json.TrimEnd() + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $resolvedStatePath -Force
}

function Write-JsonAtomicEarly {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] $Value
    )

    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolved) | Out-Null
    $temporary = "$resolved.$([Guid]::NewGuid().ToString('N')).tmp"
    $json = $Value | ConvertTo-Json -Depth 16 -Compress
    [IO.File]::WriteAllText($temporary, ($json + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $resolved -Force
    return $resolved
}

function ConvertTo-ShellSingleQuoted {
    param([Parameter(Mandatory)] [string]$Value)

    return "'" + $Value.Replace("'", "'""'""'") + "'"
}

function ConvertTo-EventProbe {
    param([Parameter(Mandatory)] $Payload)

    $summary = $Payload.summary
    $eventCount = 0
    if ($summary -and $null -ne (Get-OptionalProperty $summary "echoes")) {
        $eventCount = [int](Get-OptionalProperty $summary "echoes")
    }
    elseif ($summary -and $null -ne (Get-OptionalProperty $summary "totalEvents")) {
        $eventCount = [int](Get-OptionalProperty $summary "totalEvents")
    }
    elseif ($summary -and $null -ne (Get-OptionalProperty $summary "events")) {
        $eventCount = [int](Get-OptionalProperty $summary "events")
    }

    return [pscustomobject]@{
        revision = [string]$Payload.revision
        projectionRevision = Get-ProjectionRevision -Payload $Payload
        provenanceRevision = [string](Get-OptionalProperty $Payload "provenanceRevision")
        updatedAt = [string]$Payload.updatedAt
        events = $eventCount
        lastAt = if ($summary -and (Get-OptionalProperty $summary "lastAt")) { [string](Get-OptionalProperty $summary "lastAt") } else { "" }
        mtime = 0
        size = 0
    }
}

function Read-RemoteEventProbe {
    param([Parameter(Mandatory)] [string]$Path)

    $probeScript = @'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
if not path.is_file() or path.stat().st_size <= 0:
    sys.exit(2)
with path.open("r", encoding="utf-8") as handle:
    payload = json.load(handle)
summary = payload.get("summary") or {}
stat = path.stat()
print(json.dumps({
    "revision": payload.get("revision") or "",
    "projectionRevision": payload.get("projectionRevision"),
    "provenanceRevision": payload.get("provenanceRevision") or "",
    "updatedAt": payload.get("updatedAt") or "",
    "events": summary.get("echoes") or summary.get("totalEvents") or summary.get("events") or 0,
    "lastAt": summary.get("lastAt") or "",
    "mtime": int(stat.st_mtime),
    "size": int(stat.st_size),
}, ensure_ascii=False, separators=(",", ":")))
'@
    $encodedProbeScript = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($probeScript))
    $quotedPath = ConvertTo-ShellSingleQuoted -Value $Path
    $probeCommand = "python3 -c 'import base64; exec(base64.b64decode(""$encodedProbeScript"").decode(""utf-8""))' $quotedPath"
    $rawProbe = & ssh.exe -n -T -o BatchMode=yes -o ConnectTimeout=8 $config.SshAlias $probeCommand 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "L'historique public distant n'est pas encore disponible: $Path"
    }
    return (($rawProbe | Out-String).Trim() | ConvertFrom-Json)
}

function Read-RemoteJsonPayload {
    param([Parameter(Mandatory)] [string]$Path)

    $rawPayload = & ssh.exe -n -T -o BatchMode=yes -o ConnectTimeout=8 $config.SshAlias "test -s '$Path' && base64 -w0 '$Path'" 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Le JSON public distant n'est pas encore disponible: $Path"
    }
    $payloadText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((($rawPayload | Out-String).Trim())))
    $payload = $payloadText | ConvertFrom-Json
    if (-not $payload.ok) {
        throw "Le JSON public distant est invalide: $Path"
    }
    return $payload
}

function Read-EventPayload {
    param(
        [Parameter(Mandatory)] [string]$RemotePath,
        [string]$LocalPath = ""
    )

    if ($LocalPath) {
        if (-not (Test-Path -LiteralPath $LocalPath -PathType Leaf)) {
            throw "Le JSON public local n'est pas disponible: $LocalPath"
        }
        try {
            $payload = Get-Content -Raw -Encoding UTF8 -LiteralPath $LocalPath | ConvertFrom-Json
        }
        catch {
            throw "Le JSON public local est invalide: $LocalPath. $($_.Exception.Message)"
        }
        if (-not $payload.ok) {
            throw "Le JSON public local n'est pas exploitable: $LocalPath"
        }
        return $payload
    }

    return Read-RemoteJsonPayload -Path $RemotePath
}

function Read-EventProbe {
    param(
        [Parameter(Mandatory)] [string]$RemotePath,
        [string]$LocalPath = ""
    )

    if ($LocalPath) {
        return ConvertTo-EventProbe -Payload (Read-EventPayload -RemotePath $RemotePath -LocalPath $LocalPath)
    }
    return Read-RemoteEventProbe -Path $RemotePath
}

function Test-LocalEventOutputsComplete {
    param([Parameter(Mandatory)] $State)

    $directory = Split-Path -Parent ($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath))
    foreach ($path in @(
        $OutputPath,
        $RecentOutputPath,
        $IndexOutputPath,
        (Join-Path $directory "public-events-manifest-v6.json"),
        (Join-Path $directory "public-events-head-v6.json")
    )) {
        if (-not (Test-Path -LiteralPath $path)) { return $false }
    }
    if (-not (Test-V6ContractFilesComplete -DataDirectory $directory -Deep:(-not $Fast))) { return $false }
    $expectedGeneration = [string](Get-StateValue $State "v6GenerationId")
    if ($expectedGeneration) {
        $pointer = Read-JsonFile -Path (Join-Path $directory "public-events-head-v6.json")
        if ([string](Get-OptionalProperty $pointer "baseGenerationId") -ne $expectedGeneration) { return $false }
    }
    $pageCount = [int](Get-StateValue $State "pageCount")
    if ($pageCount -lt 1) { return $false }
    foreach ($pageNumber in 1..$pageCount) {
        $pagePath = Join-Path $directory ("public-events-page-{0:D4}.json" -f $pageNumber)
        if (-not (Test-Path -LiteralPath $pagePath -PathType Leaf)) { return $false }
    }
    return [string](Get-StateValue $State "remoteRevision") -ne "" -or [string](Get-StateValue $State "recentRevision") -ne ""
}

function Get-EventsArray {
    param($Payload)

    return @($Payload.events | Where-Object { $null -ne $_ })
}

function Get-EventsMaxId {
    param([array]$Events)

    $maxId = @($Events | ForEach-Object { [long]$_.id } | Measure-Object -Maximum).Maximum
    if ($null -eq $maxId) { return 0 }
    return [long]$maxId
}

function Get-FastEventSummary {
    param(
        [Parameter(Mandatory)] [array]$Events,
        [Parameter(Mandatory)] [int]$TotalEvents
    )

    $types = [ordered]@{}
    foreach ($group in @($Events | Where-Object { $_.type } | Group-Object -Property type | Sort-Object -Property Name)) {
        $types[[string]$group.Name] = [int]$group.Count
    }

    [ordered]@{
        events = $Events.Count
        totalEvents = $TotalEvents
        firstAt = if ($Events.Count) { [string]$Events[-1].occurredAt } else { $null }
        lastAt = if ($Events.Count) { [string]$Events[0].occurredAt } else { $null }
        types = $types
        reconciledReconnects = if ($types.Contains("reconnect")) { [int]$types["reconnect"] } else { 0 }
    }
}

function Get-EventIdentity {
    param($Event, [int]$Index = 0, [string]$Prefix = "event")

    if ($null -eq $Event) { return "$Prefix`:$Index" }
    if (($Event.PSObject.Properties.Name -contains "source" -and $Event.source) -or
        ($Event.PSObject.Properties.Name -contains "id" -and $null -ne $Event.id)) {
        return "$($Event.source):$($Event.id)"
    }
    if ($Event.PSObject.Properties.Name -contains "key" -and $Event.key) {
        return "key:$($Event.key)"
    }
    return @(
        $Event.occurredAt,
        $Event.type,
        $Event.player,
        $Event.base,
        $Event.title,
        $Event.message
    ) -join "|"
}

function Convert-FastEventDate {
    param($Value)

    if (-not $Value) { return [datetimeoffset]::MinValue }
    $parsed = [datetimeoffset]::MinValue
    if ([datetimeoffset]::TryParse([string]$Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeLocal, [ref]$parsed)) {
        return $parsed
    }
    if ([datetimeoffset]::TryParse([string]$Value, [Globalization.CultureInfo]::GetCultureInfo("fr-CA"), [Globalization.DateTimeStyles]::AssumeLocal, [ref]$parsed)) {
        return $parsed
    }
    return [datetimeoffset]::MinValue
}

function Convert-ToGroupedEventDate {
    param($Value)

    $date = Convert-FastEventDate $Value
    if ($date -eq [datetimeoffset]::MinValue) { return $null }
    return $date
}

function Convert-ToPositiveInt {
    param($Value)

    if ($null -eq $Value) { return 0 }
    try {
        return [Math]::Max(0, [int]$Value)
    }
    catch {
        return 0
    }
}

$ItemizedPublicGroupTypes = @("craft", "fishing", "production", "build", "repair", "base", "research")
$WorldDropStructureNames = @("commondropitem3d", "commonitemdrop3d")

function Test-WorldDropStructureName {
    param($Value)

    $text = ([string]$Value).Trim()
    if (-not $text) { return $false }
    $tail = @($text -split '[\\/]')[-1]
    $normalized = ($tail -replace '[\s_-]+', '').ToLowerInvariant()
    if ($WorldDropStructureNames -contains $normalized) { return $true }
    foreach ($name in $WorldDropStructureNames) {
        if ($normalized.Contains($name)) { return $true }
    }
    return $false
}

function Get-DetailRows {
    param(
        $Details,
        [Parameter(Mandatory)] [string]$Name
    )

    if ($null -eq $Details) { return @() }
    $rows = Get-OptionalProperty $Details $Name
    if ($null -eq $rows) { return @() }
    if ($rows -is [array]) {
        return @($rows | Where-Object { $null -ne $_ })
    }
    return @($rows)
}

function Get-FrenchPlural {
    param(
        [Parameter(Mandatory)] [int]$Value,
        [Parameter(Mandatory)] [string]$Singular,
        [string]$Plural
    )

    if ($Value -eq 1) { return $Singular }
    if ($Plural) { return $Plural }
    return "$($Singular)s"
}

function Get-ItemizedEventDetails {
    param($Event)

    $details = Get-OptionalProperty $Event "details"
    if ($null -eq $details) { return $null }
    return $details
}

function Get-ItemizedEventItems {
    param($Event)

    $details = Get-ItemizedEventDetails -Event $Event
    if ($null -eq $details) { return @() }
    $rows = [System.Collections.ArrayList]::new()
    foreach ($item in (Get-DetailRows -Details $details -Name "items")) {
        [void]$rows.Add($item)
    }
    if ([string](Get-OptionalProperty $Event "type") -eq "build") {
        foreach ($item in (Get-DetailRows -Details $details -Name "structures")) {
            [void]$rows.Add($item)
        }
    }
    return @($rows | Where-Object {
        -not (Test-WorldDropStructureName (Get-OptionalProperty $_ "name")) -and
        -not (Test-WorldDropStructureName (Get-OptionalProperty $_ "asset"))
    })
}

function Get-ItemizedEventAddedTotal {
    param($Event)

    $total = 0
    foreach ($item in (Get-ItemizedEventItems -Event $Event)) {
        $added = Convert-ToPositiveInt (Get-OptionalProperty $item "added")
        if ($added -le 0) {
            $added = Convert-ToPositiveInt (Get-OptionalProperty $item "count")
        }
        $total += $added
    }
    if ($total -gt 0) { return $total }

    $details = Get-ItemizedEventDetails -Event $Event
    $bullets = if ($details) { Get-OptionalProperty $details "bullets" } else { @() }
    foreach ($bullet in @($bullets)) {
        if (Test-WorldDropStructureName $bullet) { continue }
        if ([string]$bullet -match '^[+-]?(\d+)') {
            $total += [int]$Matches[1]
        }
    }
    return $total
}

function Get-ItemizedEventBucket {
    param($Event)

    $occurredAt = Convert-ToGroupedEventDate (Get-OptionalProperty $Event "occurredAt")
    if ($null -eq $occurredAt) { return $null }
    $bucketMinute = [int]([Math]::Floor($occurredAt.Minute / 5) * 5)
    return [DateTimeOffset]::new(
        $occurredAt.Year,
        $occurredAt.Month,
        $occurredAt.Day,
        $occurredAt.Hour,
        $bucketMinute,
        0,
        $occurredAt.Offset
    )
}

function Get-ItemizedGroupOwner {
    param($Event)

    foreach ($name in @("player", "base", "guild")) {
        $value = [string](Get-OptionalProperty $Event $name)
        if ($value.Trim()) { return $value.Trim() }
    }
    return "Monde"
}

function Get-ItemizedGroupKey {
    param($Event)

    $type = [string](Get-OptionalProperty $Event "type")
    $sourceName = [string](Get-OptionalProperty $Event "source")
    if ($type -notin $ItemizedPublicGroupTypes -or $sourceName -ne "save") { return $null }

    $details = Get-ItemizedEventDetails -Event $Event
    if ((Convert-ToPositiveInt (Get-OptionalProperty $details "aggregatedEvents")) -gt 0) { return $null }
    if ((Get-ItemizedEventAddedTotal -Event $Event) -le 0) { return $null }

    $bucket = Get-ItemizedEventBucket -Event $Event
    if ($null -eq $bucket) { return $null }

    $owner = (Get-ItemizedGroupOwner -Event $Event).ToLowerInvariant()
    return "$type|$owner|$($bucket.ToString("o"))"
}

function New-PublicEventKey {
    param([Parameter(Mandatory)] [string]$Value)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value))
        $hex = -join ($hash | ForEach-Object { $_.ToString("x2") })
        return "evt_$($hex.Substring(0, 20))"
    }
    finally {
        $sha.Dispose()
    }
}

function Get-QuantityBullets {
    param([array]$Items)

    return @(
        foreach ($item in $Items) {
            $added = Convert-ToPositiveInt (Get-OptionalProperty $item "added")
            $name = [string](Get-OptionalProperty $item "name")
            if ($added -gt 0 -and $name.Trim()) {
                "+$added $($name.Trim())"
            }
        }
    )
}

function Merge-ItemizedPublicItems {
    param([array]$Events)

    $grouped = [ordered]@{}
    $sortedEvents = @(
        $Events | Sort-Object `
            @{ Expression = { Convert-FastEventDate (Get-OptionalProperty $_ "occurredAt") }; Descending = $false },
            @{ Expression = { Convert-ToPositiveInt (Get-OptionalProperty $_ "id") }; Descending = $false }
    )

    foreach ($event in $sortedEvents) {
        foreach ($item in (Get-ItemizedEventItems -Event $event)) {
            $name = ([string](Get-OptionalProperty $item "name")).Trim()
            if (-not $name) { $name = "Objet" }
            $asset = ([string](Get-OptionalProperty $item "asset")).Trim()
            $groupKey = if ($asset) { $asset.ToLowerInvariant() } else { $name.ToLowerInvariant() }
            $added = Convert-ToPositiveInt (Get-OptionalProperty $item "added")
            if ($added -le 0) {
                $added = Convert-ToPositiveInt (Get-OptionalProperty $item "count")
            }
            if ($added -le 0) { continue }

            if (-not $grouped.Contains($groupKey)) {
                $grouped[$groupKey] = [ordered]@{
                    name = $name
                    asset = $asset
                    icon = Get-OptionalProperty $item "icon"
                    added = 0
                    count = 0
                    isNew = $false
                }
            }

            $current = $grouped[$groupKey]
            $current["added"] = [int]$current["added"] + $added
            $current["isNew"] = [bool]$current["isNew"] -or [bool](Get-OptionalProperty $item "isNew")
            if (-not [string]$current["asset"] -and $asset) { $current["asset"] = $asset }
            if (-not [string]$current["icon"] -and (Get-OptionalProperty $item "icon")) {
                $current["icon"] = Get-OptionalProperty $item "icon"
            }
            $current["name"] = $name
            $current["count"] = Convert-ToPositiveInt (Get-OptionalProperty $item "count")
        }
    }

    return @(
        $grouped.Values | Sort-Object `
            @{ Expression = { Convert-ToPositiveInt (Get-OptionalProperty $_ "added") }; Descending = $true },
            @{ Expression = { ([string](Get-OptionalProperty $_ "name")).ToLowerInvariant() }; Descending = $false }
    )
}

function Get-EventMaxDetailTotal {
    param([array]$Events)

    $total = 0
    foreach ($event in $Events) {
        $details = Get-ItemizedEventDetails -Event $event
        $total = [Math]::Max($total, (Convert-ToPositiveInt (Get-OptionalProperty $details "total")))
    }
    return $total
}

function Get-ObservedDetailTotalByBase {
    param(
        [array]$Events,
        [array]$Bases
    )

    if ($Bases.Count -eq 1) {
        return Get-EventMaxDetailTotal -Events $Events
    }

    $totalsByBase = @{}
    foreach ($event in $Events) {
        $base = ([string](Get-OptionalProperty $event "base")).Trim()
        $detailsForEvent = Get-ItemizedEventDetails -Event $event
        $totalForEvent = Convert-ToPositiveInt (Get-OptionalProperty $detailsForEvent "total")
        if ($base -and $totalForEvent -gt 0) {
            if (-not $totalsByBase.ContainsKey($base) -or $totalForEvent -gt $totalsByBase[$base]) {
                $totalsByBase[$base] = $totalForEvent
            }
        }
    }

    $total = 0
    foreach ($value in $totalsByBase.Values) { $total += [int]$value }
    return $total
}

function Get-BaseScopeLabel {
    param([array]$Bases)

    if ($Bases.Count -eq 1) { return " à $($Bases[0])" }
    if ($Bases.Count -gt 1) { return " dans $($Bases.Count) bases" }
    return ""
}

function Get-AggregatedEventBullets {
    param([array]$Events)

    $bullets = [System.Collections.ArrayList]::new()
    foreach ($event in $Events) {
        $details = Get-ItemizedEventDetails -Event $event
        foreach ($bullet in @((Get-OptionalProperty $details "bullets"))) {
            $text = ([string]$bullet).Trim()
            if (-not $text) { continue }
            if (Test-WorldDropStructureName $text) { continue }
            [void]$bullets.Add($text)
        }
    }
    return @($bullets | Select-Object -First 8)
}

function New-AggregatedItemizedPublicEvent {
    param([Parameter(Mandatory)] [array]$Events)

    if ($Events.Count -lt 1) { return $null }
    $latest = @(
        $Events | Sort-Object `
            @{ Expression = { Convert-FastEventDate (Get-OptionalProperty $_ "occurredAt") }; Descending = $true },
            @{ Expression = { Convert-ToPositiveInt (Get-OptionalProperty $_ "id") }; Descending = $true } |
            Select-Object -First 1
    )[0]
    $eventType = [string](Get-OptionalProperty $latest "type")
    $owner = Get-ItemizedGroupOwner -Event $latest
    $bucket = Get-ItemizedEventBucket -Event $latest
    if ($null -eq $bucket) {
        $bucket = Convert-ToGroupedEventDate (Get-OptionalProperty $latest "occurredAt")
    }
    $windowEnd = if ($bucket) { $bucket.AddSeconds($ItemizedEventGroupWindowSeconds) } else { $null }
    $items = @(Merge-ItemizedPublicItems -Events $Events)
    $addedTotal = 0
    foreach ($item in $items) {
        $addedTotal += Convert-ToPositiveInt (Get-OptionalProperty $item "added")
    }
    if ($addedTotal -le 0) {
        foreach ($event in $Events) {
            $addedTotal += Get-ItemizedEventAddedTotal -Event $event
        }
    }
    $batches = $Events.Count
    $bases = @(
        $Events |
            ForEach-Object { ([string](Get-OptionalProperty $_ "base")).Trim() } |
            Where-Object { $_ } |
            Sort-Object -Unique
    )
    $icon = $null
    foreach ($item in $items) {
        $itemIcon = Get-OptionalProperty $item "icon"
        if ($itemIcon) {
            $icon = [string]$itemIcon
            break
        }
    }
    if (-not $icon) { $icon = Get-OptionalProperty $latest "icon" }

    $bullets = @(Get-QuantityBullets -Items $items)
    if ($bullets.Count -lt 1) {
        $bullets = @(Get-AggregatedEventBullets -Events $Events)
    }

    $details = [ordered]@{
        bullets = $bullets
        aggregatedEvents = $batches
        windowMinutes = [int]($ItemizedEventGroupWindowSeconds / 60)
    }
    if ($items.Count -gt 0) {
        if ($eventType -eq "build") {
            $details["structures"] = $items
        }
        else {
            $details["items"] = $items
        }
    }
    if ($bucket) { $details["windowStart"] = $bucket.ToString("o") }
    if ($windowEnd) { $details["windowEnd"] = $windowEnd.ToString("o") }
    if ($bases.Count -gt 0) { $details["bases"] = $bases }

    if ($eventType -eq "craft") {
        $title = "Fabrications compilées"
        $total = Get-EventMaxDetailTotal -Events $Events
        $label = Get-FrenchPlural -Value $addedTotal -Singular "fabrication"
        if ($total -gt 0) {
            $message = "$owner termine $addedTotal $label en 5 min. Total cumulé: $total."
            $details["total"] = $total
        }
        else {
            $message = "$owner termine $addedTotal $label en 5 min."
        }
    }
    elseif ($eventType -eq "fishing") {
        $title = "Prises de pêche compilées"
        $total = Get-EventMaxDetailTotal -Events $Events
        $label = Get-FrenchPlural -Value $addedTotal -Singular "prise de pêche" -Plural "prises de pêche"
        if ($total -gt 0) {
            $message = "$owner ramène $addedTotal $label en 5 min. Total cumulé: $total."
            $details["total"] = $total
        }
        else {
            $message = "$owner ramène $addedTotal $label en 5 min."
        }
    }
    elseif ($eventType -eq "production") {
        $title = "Productions compilées"
        $resourceLabel = Get-FrenchPlural -Value $addedTotal -Singular "ressource produite est prête" -Plural "ressources produites sont prêtes"
        if ($bases.Count -eq 1) {
            $baseLabel = " à $($bases[0])"
            $total = Get-EventMaxDetailTotal -Events $Events
            $stock = if ($total -gt 0) { " Stock de production actuel: $total." } else { "" }
            if ($total -gt 0) { $details["total"] = $total }
        }
        else {
            $baseLabel = if ($bases.Count -gt 0) { " dans $($bases.Count) bases" } else { "" }
            $totalsByBase = @{}
            foreach ($event in $Events) {
                $base = ([string](Get-OptionalProperty $event "base")).Trim()
                $detailsForEvent = Get-ItemizedEventDetails -Event $event
                $totalForEvent = Convert-ToPositiveInt (Get-OptionalProperty $detailsForEvent "total")
                if ($base -and $totalForEvent -gt 0) {
                    if (-not $totalsByBase.ContainsKey($base) -or $totalForEvent -gt $totalsByBase[$base]) {
                        $totalsByBase[$base] = $totalForEvent
                    }
                }
            }
            $total = 0
            foreach ($value in $totalsByBase.Values) { $total += [int]$value }
            $stock = if ($total -gt 0) { " Stock de production observé: $total." } else { "" }
            if ($total -gt 0) { $details["total"] = $total }
        }
        $productionLabel = Get-FrenchPlural -Value $batches -Singular "production"
        $message = "$owner boucle $batches $productionLabel en 5 min. $addedTotal $resourceLabel$baseLabel.$stock"
    }
    elseif ($eventType -eq "build") {
        $title = "Constructions compilées"
        $total = Get-ObservedDetailTotalByBase -Events $Events -Bases $bases
        if ($total -gt 0) { $details["total"] = $total }
        $structureLabel = Get-FrenchPlural -Value $addedTotal -Singular "nouvelle structure confirmée" -Plural "nouvelles structures confirmées"
        $baseLabel = Get-BaseScopeLabel -Bases $bases
        $message = "$owner confirme $addedTotal $structureLabel en 5 min$baseLabel."
    }
    elseif ($eventType -eq "repair") {
        $title = "Réparations compilées"
        $structureLabel = Get-FrenchPlural -Value $addedTotal -Singular "structure"
        $baseLabel = Get-BaseScopeLabel -Bases $bases
        $message = "$owner répare $addedTotal $structureLabel en 5 min$baseLabel."
    }
    elseif ($eventType -eq "research") {
        $title = "Recherches compilées"
        $researchLabel = Get-FrenchPlural -Value $addedTotal -Singular "recherche"
        $baseLabel = Get-BaseScopeLabel -Bases $bases
        $message = "$owner confirme $addedTotal $researchLabel en 5 min$baseLabel."
    }
    else {
        $title = "Dégâts de base compilés"
        $damageLabel = Get-FrenchPlural -Value $addedTotal -Singular "structure endommagée" -Plural "structures endommagées"
        $baseLabel = Get-BaseScopeLabel -Bases $bases
        $message = "$owner compte $addedTotal $damageLabel en plus en 5 min$baseLabel."
    }

    $details["headline"] = $title
    $details["body"] = $message

    $guild = Get-OptionalProperty $latest "guild"
    $sameGuild = @($Events | Where-Object { (Get-OptionalProperty $_ "guild") -ne $guild }).Count -eq 0
    $displayBullets = @($details["bullets"] | Select-Object -First 8)
    $fingerprint = "public-group:${eventType}:$($owner.ToLowerInvariant()):$(if ($bucket) { $bucket.ToString("o") } else { Get-OptionalProperty $latest "occurredAt" })"

    return [pscustomobject][ordered]@{
        key = New-PublicEventKey -Value $fingerprint
        id = Convert-ToPositiveInt (Get-OptionalProperty $latest "id")
        occurredAt = [string](Get-OptionalProperty $latest "occurredAt")
        type = $eventType
        player = if (Get-OptionalProperty $latest "player") { [string](Get-OptionalProperty $latest "player") } else { $null }
        guild = if ($sameGuild -and $guild) { [string]$guild } else { $null }
        base = if ($bases.Count -eq 1) { [string]$bases[0] } else { $null }
        title = $title
        message = $message
        display = [ordered]@{
            headline = $title
            body = if ($message.Length -gt 1000) { $message.Substring(0, 1000) } else { $message }
            bullets = $displayBullets
        }
        details = $details
        confidence = "confirmed"
        icon = if ($icon) { [string]$icon } else { $null }
        source = "save"
    }
}

function Group-ItemizedPublicEvents {
    param([array]$Events)

    $groups = @{}
    $eventKeys = @{}
    for ($index = 0; $index -lt $Events.Count; $index++) {
        $event = $Events[$index]
        $key = Get-ItemizedGroupKey -Event $event
        if (-not $key) { continue }
        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = [System.Collections.ArrayList]::new()
        }
        [void]$groups[$key].Add($event)
        $eventKeys[$index] = $key
    }

    $emitted = @{}
    $grouped = [System.Collections.ArrayList]::new()
    for ($index = 0; $index -lt $Events.Count; $index++) {
        $event = $Events[$index]
        $key = $eventKeys[$index]
        if (-not $key -or $groups[$key].Count -lt 2) {
            [void]$grouped.Add($event)
            continue
        }
        if ($emitted.ContainsKey($key)) { continue }
        $aggregated = New-AggregatedItemizedPublicEvent -Events @($groups[$key])
        if ($null -ne $aggregated) {
            [void]$grouped.Add($aggregated)
        }
        $emitted[$key] = $true
    }
    return @($grouped)
}

function Repair-WorldDropBuildEvent {
    param($Event)

    if ([string](Get-OptionalProperty $Event "type") -ne "build") { return $Event }
    $details = Get-OptionalProperty $Event "details"
    if ($null -eq $details) { return $Event }

    $structures = Get-DetailRows -Details $details -Name "structures"
    $keptStructures = [System.Collections.ArrayList]::new()
    $removed = 0
    foreach ($structure in $structures) {
        if (
            (Test-WorldDropStructureName (Get-OptionalProperty $structure "name")) -or
            (Test-WorldDropStructureName (Get-OptionalProperty $structure "asset"))
        ) {
            $removed += [Math]::Max(1, (Convert-ToPositiveInt (Get-OptionalProperty $structure "added")))
            continue
        }
        [void]$keptStructures.Add($structure)
    }

    $bullets = @(
        foreach ($bullet in @((Get-OptionalProperty $details "bullets"))) {
            $text = ([string]$bullet).Trim()
            if ($text) { $text }
        }
    )
    $keptBullets = @($bullets | Where-Object { -not (Test-WorldDropStructureName $_) })
    $changed = $removed -gt 0 -or $keptBullets.Count -ne $bullets.Count
    if (-not $changed) { return $Event }

    $keptTotal = 0
    foreach ($structure in $keptStructures) {
        $added = Convert-ToPositiveInt (Get-OptionalProperty $structure "added")
        if ($added -le 0) { $added = Convert-ToPositiveInt (Get-OptionalProperty $structure "count") }
        $keptTotal += $added
    }
    if ($keptTotal -le 0) {
        foreach ($bullet in $keptBullets) {
            if ([string]$bullet -match '^[+-]?(\d+)') {
                $keptTotal += [int]$Matches[1]
            }
        }
    }
    if ($keptTotal -le 0) { return $null }

    if ($keptStructures.Count -gt 0) {
        Set-OptionalProperty -Value $details -Name "structures" -PropertyValue @($keptStructures)
        Set-OptionalProperty -Value $details -Name "bullets" -PropertyValue (Get-QuantityBullets -Items @($keptStructures))
    }
    else {
        Set-OptionalProperty -Value $details -Name "bullets" -PropertyValue $keptBullets
    }

    $headline = ([string](Get-OptionalProperty $details "headline")).Trim()
    if (-not $headline) {
        $headline = ([string](Get-OptionalProperty $Event "message")).Split(".")[0].Trim()
    }
    if (-not $headline) { $headline = [string](Get-OptionalProperty $Event "title") }
    Set-OptionalProperty -Value $details -Name "headline" -PropertyValue $headline
    Set-OptionalProperty -Value $details -Name "body" -PropertyValue "De nouvelles structures sont confirmées dans la sauvegarde."

    $structureLabel = Get-FrenchPlural -Value $keptTotal -Singular "nouvelle structure confirmée" -Plural "nouvelles structures confirmées"
    $message = "$headline. $keptTotal $structureLabel."
    Set-OptionalProperty -Value $Event -Name "message" -PropertyValue $message
    Set-OptionalProperty -Value $Event -Name "details" -PropertyValue $details
    Set-OptionalProperty -Value $Event -Name "display" -PropertyValue ([ordered]@{
        headline = [string](Get-OptionalProperty $Event "title")
        body = $message
        bullets = @((Get-OptionalProperty $details "bullets") | Select-Object -First 8)
    })
    return $Event
}

function Remove-WorldDropBuildEvents {
    param([array]$Events)

    return @(
        foreach ($event in $Events) {
            $clean = Repair-WorldDropBuildEvent -Event $event
            if ($null -ne $clean) { $clean }
        }
    )
}

function Test-V6ContractFilesComplete {
    param(
        [Parameter(Mandatory)] [string]$DataDirectory,
        [switch]$Deep
    )

    $stableManifest = Read-JsonFile -Path (Join-Path $DataDirectory "public-events-manifest-v6.json")
    $pointer = Read-JsonFile -Path (Join-Path $DataDirectory "public-events-head-v6.json")
    if ($null -eq $stableManifest -or $null -eq $pointer) { return $false }
    $generationId = [string](Get-OptionalProperty $stableManifest "generationId")
    if (-not $generationId -or [string](Get-OptionalProperty $pointer "baseGenerationId") -ne $generationId) { return $false }

    $manifestReference = Get-OptionalProperty $pointer "manifest"
    $immutableManifestContractPath = [string](Get-OptionalProperty $manifestReference "path")
    if (-not $immutableManifestContractPath) { return $false }
    $immutableManifestPath = Resolve-V6ContractPath -DataDirectory $DataDirectory -ContractPath $immutableManifestContractPath
    if (-not (Test-V6FileHash -Path $immutableManifestPath -ExpectedHash ([string](Get-OptionalProperty $manifestReference "sha256")))) { return $false }
    $immutableManifest = Read-JsonFile -Path $immutableManifestPath
    if ($null -eq $immutableManifest -or [string](Get-OptionalProperty $immutableManifest "generationId") -ne $generationId) { return $false }

    $headReference = Get-OptionalProperty $pointer "head"
    $manifestHead = Get-OptionalProperty $immutableManifest "head"
    if ([string](Get-OptionalProperty $headReference "path") -ne [string](Get-OptionalProperty $manifestHead "path") -or
        [string](Get-OptionalProperty $headReference "sha256") -ne [string](Get-OptionalProperty $manifestHead "sha256")) { return $false }
    $headContractPath = [string](Get-OptionalProperty $headReference "path")
    if (-not $headContractPath) { return $false }
    $headPath = Resolve-V6ContractPath -DataDirectory $DataDirectory -ContractPath $headContractPath
    if (-not (Test-V6FileHash -Path $headPath -ExpectedHash ([string](Get-OptionalProperty $headReference "sha256")))) { return $false }
    $headPayload = Read-JsonFile -Path $headPath
    if ($null -eq $headPayload -or [string](Get-OptionalProperty $headPayload "baseGenerationId") -ne $generationId) { return $false }
    if (-not $Deep) { return $true }

    [long]$echoes = 0
    [long]$represented = 0
    foreach ($day in @(Get-OptionalProperty $immutableManifest "days")) {
        $fragmentContractPath = [string](Get-OptionalProperty $day "path")
        $dailyContractPath = [string](Get-OptionalProperty $day "dailyPath")
        if (-not $fragmentContractPath -or -not $dailyContractPath) { return $false }
        $fragmentPath = Resolve-V6ContractPath -DataDirectory $DataDirectory -ContractPath $fragmentContractPath
        $dailyPath = Resolve-V6ContractPath -DataDirectory $DataDirectory -ContractPath $dailyContractPath
        if (-not (Test-V6FileHash -Path $fragmentPath -ExpectedHash ([string](Get-OptionalProperty $day "sha256"))) -or
            -not (Test-V6FileHash -Path $dailyPath -ExpectedHash ([string](Get-OptionalProperty $day "dailySha256")))) { return $false }
        $fragment = Read-JsonFile -Path $fragmentPath
        $daily = Read-JsonFile -Path $dailyPath
        $fragmentGeneration = [string](Get-OptionalProperty $day "fragmentGenerationId")
        $dailyGeneration = [string](Get-OptionalProperty $day "dailyGenerationId")
        if ($null -eq $fragment -or [string](Get-OptionalProperty $fragment "generationId") -ne $fragmentGeneration -or
            $null -eq $daily -or [string](Get-OptionalProperty $daily "generationId") -ne $dailyGeneration) { return $false }
        $echoes += [long](Convert-ToPositiveInt (Get-OptionalProperty $day "events"))
        $represented += [long](Convert-ToPositiveInt (Get-OptionalProperty $day "representedEvents"))
    }
    $counts = Get-OptionalProperty $immutableManifest "counts"
    return $echoes -eq [long](Convert-ToPositiveInt (Get-OptionalProperty $counts "echoes")) -and
        $represented -eq [long](Convert-ToPositiveInt (Get-OptionalProperty $counts "representedEvents"))
}

function Test-CanonicalEventProjection {
    param($Payload)

    if ($null -eq $Payload) { return $false }
    try {
        $version = Get-StrictInteger -Value (Get-OptionalProperty $Payload "version") -Name "version"
        $schemaVersion = Get-StrictInteger -Value (Get-OptionalProperty $Payload "schemaVersion") -Name "schemaVersion"
    }
    catch { return $false }
    return $version -eq $PublicEventContractVersion -and
        $schemaVersion -eq $PublicEventContractVersion -and
        ([string](Get-OptionalProperty $Payload "projection")) -ceq "canonical-echoes"
}

function Test-CanonicalProjectionClaim {
    param($Payload)

    if ($null -eq $Payload) { return $false }
    $projection = ([string](Get-OptionalProperty $Payload "projection")).Trim()
    if ($projection) { return $true }
    try {
        if ([long](Get-OptionalProperty $Payload "version") -ge $PublicEventContractVersion) { return $true }
        if ([long](Get-OptionalProperty $Payload "schemaVersion") -ge $PublicEventContractVersion) { return $true }
    }
    catch { }
    return $false
}

function Test-ObjectHasProperty {
    param($Value, [Parameter(Mandatory)] [string]$Name)

    if ($null -eq $Value) { return $false }
    if ($Value -is [System.Collections.IDictionary]) { return $Value.Contains($Name) }
    return $null -ne $Value.PSObject.Properties[$Name]
}

function Get-StrictInteger {
    param(
        $Value,
        [Parameter(Mandatory)] [string]$Name,
        [long]$Minimum = 0
    )

    $integral = $Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64]
    if (-not $integral) {
        throw "La projection canonique exige un entier pour '$Name'."
    }
    try { $result = [long]$Value }
    catch { throw "La projection canonique contient un entier hors plage pour '$Name'." }
    if ($result -lt $Minimum) {
        throw "La projection canonique exige '$Name' supérieur ou égal à $Minimum."
    }
    return $result
}

function Get-StrictIsoTimestamp {
    param($Value, [Parameter(Mandatory)] [string]$Name)

    if ($Value -is [datetimeoffset]) { return [datetimeoffset]$Value }
    if ($Value -is [datetime]) {
        $date = [datetime]$Value
        if ($date.Kind -eq [DateTimeKind]::Unspecified) {
            throw "La projection canonique exige une date ISO avec fuseau pour '$Name'."
        }
        return [datetimeoffset]$date
    }
    $text = ([string]$Value).Trim()
    if ($text -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})$') {
        throw "La projection canonique exige une date ISO avec fuseau pour '$Name'."
    }
    $parsed = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse($text, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AllowWhiteSpaces, [ref]$parsed)) {
        throw "La projection canonique contient une date ISO invalide pour '$Name'."
    }
    return $parsed
}

function Test-TextContainsIpLiteral {
    param($Value)

    $text = [string]$Value
    foreach ($match in [regex]::Matches($text, '(?<![0-9A-Za-z.])(?:\d{1,3}\.){3}\d{1,3}(?![0-9A-Za-z]|\.\d)')) {
        $address = $null
        if ([Net.IPAddress]::TryParse($match.Value, [ref]$address)) { return $true }
    }
    foreach ($match in [regex]::Matches($text, '[0-9A-Fa-f:.%]{2,}')) {
        $candidate = $match.Value.Trim([char[]]".,;!?()[]{}<>`"'")
        if ($candidate -notmatch '[.:]') { continue }
        $address = $null
        if ([Net.IPAddress]::TryParse($candidate, [ref]$address)) { return $true }
    }
    return $false
}

function Get-CanonicalEventOrderRank {
    param($Event)

    $sourceName = [string](Get-OptionalProperty $Event "source")
    $type = [string](Get-OptionalProperty $Event "type")
    if ($sourceName -in @("journal", "players") -and $type -eq "leave") { return 0 }
    if ($sourceName -in @("journal", "players") -and $type -in @("join", "reconnect")) { return 2 }
    return 1
}

function Assert-CanonicalEventProjection {
    param(
        [Parameter(Mandatory)] $Payload,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$Events
    )

    if (-not (Test-CanonicalEventProjection -Payload $Payload)) {
        throw "Le contrat canonique exige version=6, schemaVersion=6 et projection=canonical-echoes."
    }
    foreach ($required in @("revision", "projectionRevision", "provenanceRevision", "provenance", "projectionWindow", "recent", "summary", "events")) {
        if (-not (Test-ObjectHasProperty $Payload $required)) {
            throw "La projection canonique ne contient pas la propriété obligatoire '$required'."
        }
    }
    if ([string]::IsNullOrWhiteSpace([string](Get-OptionalProperty $Payload "revision"))) {
        throw "La projection canonique exige une révision non vide."
    }
    $projectionRevision = Get-StrictInteger -Value (Get-OptionalProperty $Payload "projectionRevision") -Name "projectionRevision"
    if ([string]::IsNullOrWhiteSpace([string](Get-OptionalProperty $Payload "provenanceRevision"))) {
        throw "La projection canonique exige une révision de provenance non vide."
    }

    $provenance = Get-OptionalProperty $Payload "provenance"
    if ($provenance -isnot [pscustomobject] -and $provenance -isnot [System.Collections.IDictionary]) {
        throw "La projection canonique exige un objet de provenance."
    }
    foreach ($required in @("observedAt", "sourceUpdatedAt", "gameVersion", "steamBuildId", "parserCommit", "catalogCommit", "schemaVersion", "freshness", "sourceStatus")) {
        if (-not (Test-ObjectHasProperty $provenance $required)) {
            throw "La provenance canonique ne contient pas '$required'."
        }
    }
    if ((Get-StrictInteger -Value (Get-OptionalProperty $provenance "schemaVersion") -Name "provenance.schemaVersion") -ne $PublicEventContractVersion) {
        throw "La provenance canonique n'utilise pas le schéma v6."
    }
    foreach ($name in @("freshness", "sourceStatus")) {
        if ([string]::IsNullOrWhiteSpace([string](Get-OptionalProperty $provenance $name))) {
            throw "La provenance canonique exige '$name'."
        }
    }

    if ((Get-OptionalProperty $Payload "recent") -isnot [bool]) {
        throw "La projection canonique exige un indicateur recent booléen."
    }
    $isRecent = [bool](Get-OptionalProperty $Payload "recent")
    $projectionWindow = Get-OptionalProperty $Payload "projectionWindow"
    if ($projectionWindow -isnot [pscustomobject] -and $projectionWindow -isnot [System.Collections.IDictionary]) {
        throw "La projection canonique exige un objet projectionWindow."
    }
    foreach ($required in @("mode", "replaceFrom", "complete", "fromProjectionRevision", "throughProjectionRevision")) {
        if (-not (Test-ObjectHasProperty $projectionWindow $required)) {
            throw "La fenêtre canonique ne contient pas '$required'."
        }
    }
    if ((Get-OptionalProperty $projectionWindow "complete") -isnot [bool]) {
        throw "La fenêtre canonique exige un indicateur complete booléen."
    }
    $windowMode = [string](Get-OptionalProperty $projectionWindow "mode")
    $throughProjectionRevision = Get-StrictInteger -Value (Get-OptionalProperty $projectionWindow "throughProjectionRevision") -Name "projectionWindow.throughProjectionRevision"
    if ($throughProjectionRevision -ne $projectionRevision) {
        throw "La fenêtre canonique ne couvre pas la révision annoncée."
    }
    $replaceFrom = Get-OptionalProperty $projectionWindow "replaceFrom"
    $fromProjectionRevision = Get-OptionalProperty $projectionWindow "fromProjectionRevision"
    if ($isRecent) {
        if ($windowMode -cne "replace-tail") {
            throw "Une projection récente exige une fenêtre replace-tail."
        }
        if ($null -ne $fromProjectionRevision) {
            [void](Get-StrictInteger -Value $fromProjectionRevision -Name "projectionWindow.fromProjectionRevision")
        }
        if ($null -ne $replaceFrom) {
            [void](Get-StrictIsoTimestamp -Value $replaceFrom -Name "projectionWindow.replaceFrom")
        }
    }
    elseif ($windowMode -cne "full" -or $null -ne $replaceFrom -or $null -ne $fromProjectionRevision -or
        -not [bool](Get-OptionalProperty $projectionWindow "complete")) {
        throw "Une projection complète exige une fenêtre full, complète et sans borne de remplacement."
    }

    $eventsValue = $null
    if ($Payload -is [System.Collections.IDictionary]) {
        $eventsValue = $Payload["events"]
    }
    else {
        $eventsValue = $Payload.PSObject.Properties["events"].Value
    }
    if (-not (Test-ObjectHasProperty $Payload "events") -or $eventsValue -isnot [array]) {
        throw "La projection canonique exige une propriété events de type tableau."
    }
    $rawEvents = @($eventsValue)
    if ($rawEvents.Count -ne $Events.Count) {
        throw "La projection canonique contient un événement nul ou non exploitable."
    }

    $summary = Get-OptionalProperty $Payload "summary"
    if ($summary -isnot [pscustomobject] -and $summary -isnot [System.Collections.IDictionary]) {
        throw "La projection canonique exige un objet summary."
    }
    $counts = @{}
    foreach ($name in @("events", "totalEvents", "rawEvents", "publicEvents", "echoes", "representedEvents", "totalEchoes", "totalRepresentedEvents")) {
        if (-not (Test-ObjectHasProperty $summary $name)) {
            throw "Le résumé canonique ne contient pas le compte obligatoire '$name'."
        }
        $counts[$name] = Get-StrictInteger -Value (Get-OptionalProperty $summary $name) -Name "summary.$name"
    }
    if ($counts["events"] -ne $Events.Count -or $counts["echoes"] -ne $Events.Count) {
        throw "Le nombre d'échos du résumé canonique ne correspond pas au tableau events."
    }
    $represented = Get-RepresentedEventCount -Events $Events
    if ($counts["representedEvents"] -ne $represented) {
        throw "Le nombre d'événements représentés du résumé canonique est inexact."
    }
    $globalCountsValid = if ($isRecent) {
        $counts["totalEchoes"] -ge $Events.Count -and
            $counts["totalRepresentedEvents"] -ge $represented -and
            $counts["publicEvents"] -ge $counts["totalRepresentedEvents"]
    }
    else {
        $counts["totalEchoes"] -eq $Events.Count -and
            $counts["totalRepresentedEvents"] -eq $represented -and
            $counts["publicEvents"] -ge $represented
    }
    if ($counts["totalEvents"] -ne $counts["rawEvents"] -or $counts["rawEvents"] -lt $counts["publicEvents"] -or
        -not $globalCountsValid) {
        throw "Les comptes globaux de la projection canonique sont incohérents."
    }

    $keys = @{}
    $ids = @{}
    $previousAt = [datetimeoffset]::MaxValue
    $previousRank = -1
    $previousId = [long]::MaxValue
    for ($index = 0; $index -lt $Events.Count; $index++) {
        $event = $Events[$index]
        if ($null -eq $event -or ($event -isnot [pscustomobject] -and $event -isnot [System.Collections.IDictionary])) {
            throw "La projection canonique contient un événement nul ou non-objet à l'index $index."
        }
        foreach ($required in @("key", "occurredAt", "type", "source")) {
            $value = ([string](Get-OptionalProperty $event $required)).Trim()
            if (-not $value) {
                throw "La projection canonique contient un écho sans champ obligatoire '$required'."
            }
        }
        $key = [string](Get-OptionalProperty $event "key")
        $id = Get-StrictInteger -Value (Get-OptionalProperty $event "id") -Name "events[$index].id" -Minimum 1
        if ($ids.ContainsKey($id)) {
            throw "La projection canonique contient un identifiant d'écho dupliqué: $id"
        }
        $ids[$id] = $true
        $occurredAt = Get-StrictIsoTimestamp -Value (Get-OptionalProperty $event "occurredAt") -Name "events[$index].occurredAt"
        $type = [string](Get-OptionalProperty $event "type")
        $sourceName = [string](Get-OptionalProperty $event "source")
        $orderRank = Get-CanonicalEventOrderRank -Event $event
        $confidence = ([string](Get-OptionalProperty $event "confidence")).Trim()
        if ($allowedTypes -notcontains $type) {
            throw "La projection canonique contient un type d'écho non autorisé: $type"
        }
        if ($allowedSources -notcontains $sourceName) {
            throw "La projection canonique contient une source non autorisée: $sourceName"
        }
        if (-not (Test-ObjectHasProperty $event "confidence") -or $confidence -notin @("confirmed", "derived")) {
            throw "La projection canonique contient un niveau de confiance non autorisé: $confidence"
        }
        if ($keys.ContainsKey($key)) {
            throw "La projection canonique contient une clé d'écho dupliquée: $key"
        }
        $keys[$key] = $true
        if ($occurredAt -gt $previousAt -or
            ($occurredAt -eq $previousAt -and $orderRank -lt $previousRank) -or
            ($occurredAt -eq $previousAt -and $orderRank -eq $previousRank -and $id -gt $previousId)) {
            throw "La projection canonique n'est pas triée par date décroissante, rang métier croissant et identifiant décroissant."
        }
        if ($occurredAt -ne $previousAt) { $previousRank = -1 }
        $previousAt = $occurredAt
        $previousRank = $orderRank
        $previousId = $id
        $serialized = $event | ConvertTo-Json -Depth 16 -Compress
        if ((Test-TextContainsIpLiteral -Value $serialized) -or
            $serialized -match '(?i)Common(?:Item)?DropItem?3D|SHOULD_NOT_BE_PUBLIC|PublicPort|BanListURL|/srv/|[A-Z]:\\|https?://|"(?:ip|ipAddress|address|host|hostname|port|endpoint|url|uri|uid|guid|instance|container|account|steam|password|token|dynamic_id|position|coordinates?|map[xyz]|world[xyz])"\s*:') {
            throw "La projection canonique contient une donnée privée ou un objet transitoire: $key"
        }
    }
}

function Get-ProjectionRevision {
    param($Payload)

    $value = Get-OptionalProperty $Payload "projectionRevision"
    if ($null -eq $value) { $value = Get-OptionalProperty $Payload "sourceProjectionRevision" }
    if ($null -eq $value) { return [long]-1 }
    try {
        $revision = [long]$value
        if ($revision -lt 0) { return [long]-1 }
        return $revision
    }
    catch {
        return [long]-1
    }
}

function Get-Sha256Hex {
    param([Parameter(Mandatory)] [byte[]]$Bytes)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return -join ($sha.ComputeHash($Bytes) | ForEach-Object { $_.ToString("x2") })
    }
    finally {
        $sha.Dispose()
    }
}

function Get-JsonContent {
    param([Parameter(Mandatory)] $Value)

    return (($Value | ConvertTo-Json -Depth 20 -Compress) + [Environment]::NewLine)
}

function Get-JsonContentHash {
    param([Parameter(Mandatory)] $Value)

    return Get-Sha256Hex -Bytes ([Text.Encoding]::UTF8.GetBytes((Get-JsonContent -Value $Value)))
}

function Write-ImmutableJson {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] $Value
    )

    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolved) | Out-Null
    $content = Get-JsonContent -Value $Value
    if (Test-Path -LiteralPath $resolved) {
        $existing = [IO.File]::ReadAllText($resolved, [Text.Encoding]::UTF8)
        if ($existing -ne $content) {
            throw "Le fragment immuable existe déjà avec un contenu différent: $resolved"
        }
        return [pscustomobject]@{
            Path = $resolved
            Sha256 = Get-Sha256Hex -Bytes ([Text.Encoding]::UTF8.GetBytes($existing))
        }
    }

    $temporary = "$resolved.$([Guid]::NewGuid().ToString('N')).tmp"
    [IO.File]::WriteAllText($temporary, $content, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $resolved
    return [pscustomobject]@{
        Path = $resolved
        Sha256 = Get-Sha256Hex -Bytes ([Text.Encoding]::UTF8.GetBytes($content))
    }
}

function Get-RepresentedEventCount {
    param([array]$Events)

    $total = 0
    foreach ($event in $Events) {
        $details = Get-OptionalProperty $event "details"
        $represented = Convert-ToPositiveInt (Get-OptionalProperty $details "aggregatedEvents")
        $total += if ($represented -gt 0) { $represented } else { 1 }
    }
    return $total
}

function Get-EventCursor {
    param([array]$Events)

    $ids = @($Events | ForEach-Object { Convert-ToPositiveInt (Get-OptionalProperty $_ "id") } | Where-Object { $_ -gt 0 })
    if ($ids.Count -lt 1) {
        return [ordered]@{ minId = 0; maxId = 0 }
    }
    return [ordered]@{
        minId = [long]($ids | Measure-Object -Minimum).Minimum
        maxId = [long]($ids | Measure-Object -Maximum).Maximum
    }
}

function Get-EventDateKey {
    param($Event)

    $date = Convert-FastEventDate (Get-OptionalProperty $Event "occurredAt")
    if ($date -eq [datetimeoffset]::MinValue) { return "unknown" }
    return $date.ToString("yyyy-MM-dd")
}

function Convert-ToIsoTimestamp {
    param($Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    if ($Value -is [datetimeoffset]) { return ([datetimeoffset]$Value).ToString("o") }
    if ($Value -is [datetime]) {
        $date = [datetime]$Value
        if ($date.Kind -eq [DateTimeKind]::Utc) { return ([datetimeoffset]::new($date)).ToString("o") }
        return ([datetimeoffset]$date).ToString("o")
    }
    $parsed = Convert-FastEventDate $Value
    if ($parsed -ne [datetimeoffset]::MinValue) { return $parsed.ToString("o") }
    return [string]$Value
}

function Get-SourceSummaryMetric {
    param(
        $Payload,
        [Parameter(Mandatory)] [string[]]$Names,
        [int]$Fallback = 0
    )

    $summary = Get-OptionalProperty $Payload "summary"
    foreach ($name in $Names) {
        $value = Get-OptionalProperty $summary $name
        if ($null -ne $value) {
            try { return [int]$value } catch { }
        }
    }
    return $Fallback
}

function Get-V6Facets {
    param([array]$Events)

    $types = @(
        $Events | Where-Object { Get-OptionalProperty $_ "type" } |
            Group-Object -Property type | Sort-Object -Property Name | ForEach-Object {
                [ordered]@{ value = [string]$_.Name; count = [int]$_.Count }
            }
    )
    $players = @(
        $Events | Where-Object { Get-OptionalProperty $_ "player" } |
            Group-Object -Property player | Sort-Object -Property Name | ForEach-Object {
                [ordered]@{ value = [string]$_.Name; count = [int]$_.Count }
            }
    )
    return [ordered]@{ types = $types; players = $players }
}

function Get-EventAddedQuantity {
    param($Event)

    $items = Get-ItemizedEventItems -Event $Event
    $total = 0
    foreach ($item in $items) {
        $quantity = Convert-ToPositiveInt (Get-OptionalProperty $item "added")
        if ($quantity -le 0) { $quantity = Convert-ToPositiveInt (Get-OptionalProperty $item "count") }
        $total += $quantity
    }
    if ($total -gt 0) { return $total }

    $details = Get-OptionalProperty $Event "details"
    foreach ($name in @("added", "count", "repaired", "captures", "newCount")) {
        $quantity = Convert-ToPositiveInt (Get-OptionalProperty $details $name)
        if ($quantity -gt 0) { return $quantity }
    }
    $message = "$(Get-OptionalProperty $Event 'message') $(Get-OptionalProperty (Get-OptionalProperty $Event 'display') 'body')"
    if ($message -match '(?i)capture\s+(\d[\d\s]*)\b') {
        return Convert-ToPositiveInt ($Matches[1] -replace '\s', '')
    }
    if ($message -match '(?i)compte\s+(\d[\d\s]*)\s+pals?\s+de\s+plus') {
        return Convert-ToPositiveInt ($Matches[1] -replace '\s', '')
    }
    if ($message -match '(?i)(\d[\d\s]*)\s+(?:fabrications?|ressources?|structures?|captures?|pals?|prises?)') {
        return Convert-ToPositiveInt ($Matches[1] -replace '\s', '')
    }
    return 1
}

function Get-V6DailyDigest {
    param([Parameter(Mandatory)] [array]$Events)

    $metricNames = @(
        "craft", "production", "build", "repair", "capture", "collection", "fishing",
        "levelUps", "boss", "discovery", "progress", "challenge", "quest", "loot",
        "note", "mutation", "death", "recovery", "adventure", "rare"
    )
    $totals = [ordered]@{ eventCount = $Events.Count; activePlayers = 0 }
    foreach ($name in $metricNames) { $totals[$name] = 0 }
    $totals["onlineSeconds"] = 0
    $totals["presenceSessions"] = 0

    $hourly = @(
        for ($hour = 0; $hour -lt 24; $hour++) {
            [ordered]@{ hour = $hour; count = 0 }
        }
    )
    $types = [ordered]@{}
    $players = @{}
    $craftedItems = @{}
    $producedItems = @{}
    $palFinds = @{}
    $highlights = [Collections.Generic.List[object]]::new()
    $rareTypes = @("level", "boss", "mutation", "research", "quest", "challenge", "note", "camp")

    foreach ($event in $Events) {
        $type = ([string](Get-OptionalProperty $event "type")).Trim()
        if (-not $type) { $type = "server" }
        if (-not $types.Contains($type)) { $types[$type] = 0 }
        $types[$type] = [int]$types[$type] + 1

        $date = Convert-FastEventDate (Get-OptionalProperty $event "occurredAt")
        if ($date -ne [datetimeoffset]::MinValue) {
            $hourly[$date.Hour]["count"] = [int]$hourly[$date.Hour]["count"] + 1
        }

        $playerName = ([string](Get-OptionalProperty $event "player")).Trim()
        if (-not $playerName) { $playerName = "Monde" }
        if (-not $players.ContainsKey($playerName)) {
            $playerMetrics = [ordered]@{}
            foreach ($name in $metricNames) { $playerMetrics[$name] = 0 }
            $players[$playerName] = [ordered]@{
                name = $playerName
                eventCount = 0
                firstAt = $null
                lastAt = $null
                metrics = $playerMetrics
                typeCounts = [ordered]@{}
                highlights = @()
            }
        }
        $player = $players[$playerName]
        $player["eventCount"] = [int]$player["eventCount"] + 1
        if (-not $player["typeCounts"].Contains($type)) { $player["typeCounts"][$type] = 0 }
        $player["typeCounts"][$type] = [int]$player["typeCounts"][$type] + 1
        $occurredAt = Convert-ToIsoTimestamp (Get-OptionalProperty $event "occurredAt")
        if (-not $player["firstAt"] -or (Convert-FastEventDate $occurredAt) -lt (Convert-FastEventDate $player["firstAt"])) { $player["firstAt"] = $occurredAt }
        if (-not $player["lastAt"] -or (Convert-FastEventDate $occurredAt) -gt (Convert-FastEventDate $player["lastAt"])) { $player["lastAt"] = $occurredAt }

        $metric = switch ($type) {
            "level" { "levelUps" }
            "research" { "progress" }
            "camp" { "progress" }
            default { if ($metricNames -contains $type) { $type } else { "" } }
        }
        if ($metric) {
            $quantity = if ($type -in @("craft", "production", "build", "repair", "capture", "collection", "fishing")) {
                Get-EventAddedQuantity -Event $event
            }
            else { 1 }
            $totals[$metric] = [int]$totals[$metric] + $quantity
            $player["metrics"][$metric] = [int]$player["metrics"][$metric] + $quantity
        }
        if ($rareTypes -contains $type) {
            $totals["rare"] = [int]$totals["rare"] + 1
            $player["metrics"]["rare"] = [int]$player["metrics"]["rare"] + 1
        }

        if ($type -in @("craft", "production")) {
            $target = if ($type -eq "craft") { $craftedItems } else { $producedItems }
            foreach ($item in (Get-ItemizedEventItems -Event $event)) {
                $name = ([string](Get-OptionalProperty $item "name")).Trim()
                if (-not $name) { continue }
                $asset = ([string](Get-OptionalProperty $item "asset")).Trim()
                $itemKey = "$type|$(if ($asset) { $asset } else { $name })".ToLowerInvariant()
                if (-not $target.ContainsKey($itemKey)) {
                    $target[$itemKey] = [ordered]@{
                        key = $itemKey; type = $type; name = $name
                        icon = Get-OptionalProperty $item "icon"
                        quantity = 0; newCount = 0
                    }
                }
                $quantity = Convert-ToPositiveInt (Get-OptionalProperty $item "added")
                if ($quantity -le 0) { $quantity = Convert-ToPositiveInt (Get-OptionalProperty $item "count") }
                $target[$itemKey]["quantity"] = [int]$target[$itemKey]["quantity"] + [Math]::Max(1, $quantity)
                if ([bool](Get-OptionalProperty $item "isNew")) {
                    $target[$itemKey]["newCount"] = [int]$target[$itemKey]["newCount"] + [Math]::Max(1, $quantity)
                }
            }
        }

        if ($type -in @("capture", "collection")) {
            $details = Get-OptionalProperty $event "details"
            $palRows = @(
                @(Get-DetailRows -Details $details -Name "pals") +
                @(Get-DetailRows -Details $details -Name "captures")
            )
            foreach ($pal in $palRows) {
                $name = ([string](Get-OptionalProperty $pal "name")).Trim()
                if (-not $name) { continue }
                $palKey = "$type|$name".ToLowerInvariant()
                if (-not $palFinds.ContainsKey($palKey)) {
                    $palFinds[$palKey] = [ordered]@{ key = $palKey; type = $type; name = $name; quantity = 0 }
                }
                $quantity = Convert-ToPositiveInt (Get-OptionalProperty $pal "count")
                $palFinds[$palKey]["quantity"] = [int]$palFinds[$palKey]["quantity"] + [Math]::Max(1, $quantity)
            }
        }

        $headline = [string](Get-OptionalProperty (Get-OptionalProperty $event "display") "headline")
        if (-not $headline) { $headline = [string](Get-OptionalProperty $event "title") }
        $body = [string](Get-OptionalProperty (Get-OptionalProperty $event "display") "body")
        if (-not $body) { $body = [string](Get-OptionalProperty $event "message") }
        $score = if ($type -in @("level", "boss", "mutation", "research", "quest", "challenge")) { 80 } elseif ($type -in @("capture", "collection", "discovery")) { 45 } else { 10 }
        $highlights.Add([ordered]@{
            key = [string](Get-OptionalProperty $event "key")
            type = $type
            player = $playerName
            base = [string](Get-OptionalProperty $event "base")
            occurredAt = $occurredAt
            headline = $headline
            body = $body
            confidence = if (Get-OptionalProperty $event "confidence") { [string](Get-OptionalProperty $event "confidence") } else { "confirmed" }
            score = $score
        })
    }

    $activePlayers = @($players.Values | Where-Object { $_["name"] -ne "Monde" -and [int]$_["eventCount"] -gt 0 }).Count
    $totals["activePlayers"] = $activePlayers
    return [ordered]@{
        totals = $totals
        hourly = $hourly
        types = $types
        players = @($players.Values | Sort-Object @{ Expression = { [int]$_["eventCount"] }; Descending = $true }, @{ Expression = { [string]$_["name"] }; Descending = $false })
        craftedItems = @($craftedItems.Values | Sort-Object @{ Expression = { [int]$_["quantity"] }; Descending = $true })
        producedItems = @($producedItems.Values | Sort-Object @{ Expression = { [int]$_["quantity"] }; Descending = $true })
        palFinds = @($palFinds.Values | Sort-Object @{ Expression = { [int]$_["quantity"] }; Descending = $true })
        highlights = @($highlights | Sort-Object @{ Expression = { [int]$_["score"] }; Descending = $true }, @{ Expression = { Convert-FastEventDate $_["occurredAt"] }; Descending = $true } | Select-Object -First 14)
    }
}

function Get-V6Provenance {
    param([Parameter(Mandatory)] $SourcePayload)

    $sourceProvenance = Get-OptionalProperty $SourcePayload "provenance"
    if (Test-CanonicalEventProjection -Payload $SourcePayload) {
        return [ordered]@{
            observedAt = Convert-ToIsoTimestamp (Get-OptionalProperty $sourceProvenance "observedAt")
            sourceUpdatedAt = Convert-ToIsoTimestamp (Get-OptionalProperty $sourceProvenance "sourceUpdatedAt")
            gameVersion = Get-OptionalProperty $sourceProvenance "gameVersion"
            steamBuildId = Get-OptionalProperty $sourceProvenance "steamBuildId"
            parserCommit = Get-OptionalProperty $sourceProvenance "parserCommit"
            catalogCommit = Get-OptionalProperty $sourceProvenance "catalogCommit"
            freshness = [string](Get-OptionalProperty $sourceProvenance "freshness")
            sourceStatus = [string](Get-OptionalProperty $sourceProvenance "sourceStatus")
        }
    }
    $sourceUpdatedAt = Convert-ToIsoTimestamp (Get-OptionalProperty $sourceProvenance "sourceUpdatedAt")
    if (-not $sourceUpdatedAt) { $sourceUpdatedAt = Convert-ToIsoTimestamp (Get-OptionalProperty $SourcePayload "updatedAt") }
    $observedAt = Convert-ToIsoTimestamp (Get-OptionalProperty $sourceProvenance "observedAt")
    if (-not $observedAt) { $observedAt = Convert-ToIsoTimestamp (Get-OptionalProperty $SourcePayload "observedAt") }
    if (-not $observedAt) { $observedAt = $sourceUpdatedAt }
    return [ordered]@{
        observedAt = if ($observedAt) { $observedAt } else { $null }
        sourceUpdatedAt = if ($sourceUpdatedAt) { $sourceUpdatedAt } else { $null }
        gameVersion = if (Get-OptionalProperty $sourceProvenance "gameVersion") { [string](Get-OptionalProperty $sourceProvenance "gameVersion") } elseif (Get-OptionalProperty $SourcePayload "gameVersion") { [string](Get-OptionalProperty $SourcePayload "gameVersion") } else { $null }
        steamBuildId = if (Get-OptionalProperty $sourceProvenance "steamBuildId") { [string](Get-OptionalProperty $sourceProvenance "steamBuildId") } elseif (Get-OptionalProperty $SourcePayload "steamBuildId") { [string](Get-OptionalProperty $SourcePayload "steamBuildId") } else { $null }
        parserCommit = if (Get-OptionalProperty $sourceProvenance "parserCommit") { [string](Get-OptionalProperty $sourceProvenance "parserCommit") } elseif (Get-OptionalProperty $SourcePayload "parserCommit") { [string](Get-OptionalProperty $SourcePayload "parserCommit") } else { $null }
        catalogCommit = if (Get-OptionalProperty $sourceProvenance "catalogCommit") { [string](Get-OptionalProperty $sourceProvenance "catalogCommit") } elseif (Get-OptionalProperty $SourcePayload "catalogCommit") { [string](Get-OptionalProperty $SourcePayload "catalogCommit") } else { $null }
        freshness = if (Get-OptionalProperty $sourceProvenance "freshness") { [string](Get-OptionalProperty $sourceProvenance "freshness") } elseif (Get-OptionalProperty $SourcePayload "freshness") { [string](Get-OptionalProperty $SourcePayload "freshness") } else { "current" }
        sourceStatus = if (Get-OptionalProperty $sourceProvenance "sourceStatus") { [string](Get-OptionalProperty $sourceProvenance "sourceStatus") } elseif (Get-OptionalProperty $SourcePayload "sourceStatus") { [string](Get-OptionalProperty $SourcePayload "sourceStatus") } else { "available" }
    }
}

function Resolve-V6ContractPath {
    param(
        [Parameter(Mandatory)] [string]$DataDirectory,
        [Parameter(Mandatory)] [string]$ContractPath
    )

    $relative = $ContractPath -replace '^data/', '' -replace '/', [IO.Path]::DirectorySeparatorChar
    return Join-Path $DataDirectory $relative
}

function Test-V6FileHash {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$ExpectedHash
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $normalized = $ExpectedHash -replace '^sha256:', ''
    if (-not $normalized) { return $false }
    return (Get-Sha256Hex -Bytes ([IO.File]::ReadAllBytes($Path))) -eq $normalized.ToLowerInvariant()
}

function Get-V6ReusableDayEntry {
    param(
        $ActiveManifest,
        [Parameter(Mandatory)] [string]$DateKey,
        [Parameter(Mandatory)] [string]$ContentHash,
        [Parameter(Mandatory)] [string]$DataDirectory
    )

    if ($null -eq $ActiveManifest) { return $null }
    $entry = @((Get-OptionalProperty $ActiveManifest "days") | Where-Object { [string](Get-OptionalProperty $_ "date") -eq $DateKey } | Select-Object -First 1)
    if ($entry.Count -lt 1) { return $null }
    $entry = $entry[0]
    $fragmentPath = Resolve-V6ContractPath -DataDirectory $DataDirectory -ContractPath ([string](Get-OptionalProperty $entry "path"))
    $dailyPath = Resolve-V6ContractPath -DataDirectory $DataDirectory -ContractPath ([string](Get-OptionalProperty $entry "dailyPath"))
    if (-not (Test-V6FileHash -Path $fragmentPath -ExpectedHash ([string](Get-OptionalProperty $entry "sha256")))) { return $null }
    if (-not (Test-V6FileHash -Path $dailyPath -ExpectedHash ([string](Get-OptionalProperty $entry "dailySha256")))) { return $null }

    $entryContentHash = [string](Get-OptionalProperty $entry "contentHash")
    $fragment = $null
    if (-not $entryContentHash) {
        $fragment = Read-JsonFile -Path $fragmentPath
        $entryContentHash = [string](Get-OptionalProperty $fragment "contentHash")
    }
    if ($entryContentHash -ne "sha256:$ContentHash") { return $null }
    if ($null -eq $fragment) { $fragment = Read-JsonFile -Path $fragmentPath }
    $daily = Read-JsonFile -Path $dailyPath
    if ($null -eq $fragment -or $null -eq $daily) { return $null }

    $fragmentGenerationId = [string](Get-OptionalProperty $entry "fragmentGenerationId")
    if (-not $fragmentGenerationId) { $fragmentGenerationId = [string](Get-OptionalProperty $fragment "generationId") }
    $dailyGenerationId = [string](Get-OptionalProperty $entry "dailyGenerationId")
    if (-not $dailyGenerationId) { $dailyGenerationId = [string](Get-OptionalProperty $daily "generationId") }
    if (-not $fragmentGenerationId -or -not $dailyGenerationId) { return $null }

    return [ordered]@{
        date = $DateKey
        path = [string](Get-OptionalProperty $entry "path")
        sha256 = [string](Get-OptionalProperty $entry "sha256")
        fragmentGenerationId = $fragmentGenerationId
        dailyPath = [string](Get-OptionalProperty $entry "dailyPath")
        dailySha256 = [string](Get-OptionalProperty $entry "dailySha256")
        dailyGenerationId = $dailyGenerationId
        contentHash = "sha256:$ContentHash"
        events = Convert-ToPositiveInt (Get-OptionalProperty $entry "events")
        representedEvents = Convert-ToPositiveInt (Get-OptionalProperty $entry "representedEvents")
        firstAt = Convert-ToIsoTimestamp (Get-OptionalProperty $entry "firstAt")
        lastAt = Convert-ToIsoTimestamp (Get-OptionalProperty $entry "lastAt")
    }
}

function Get-V6ReferencedGenerationIds {
    param($Manifest)

    $ids = @{}
    if ($null -eq $Manifest) { return $ids }

    # Une génération peut ne contenir que sa tête lorsque tous ses jours sont
    # réutilisés. Elle doit rester référencée même si aucun fragment journalier
    # ne porte son identifiant.
    $manifestGenerationId = ([string](Get-OptionalProperty $Manifest "generationId")).Trim()
    if ($manifestGenerationId) { $ids[$manifestGenerationId] = $true }

    $head = Get-OptionalProperty $Manifest "head"
    $headPath = [string](Get-OptionalProperty $head "path")
    if ($headPath -match '/(g6-[^/]+)/') { $ids[$Matches[1]] = $true }

    foreach ($entry in @((Get-OptionalProperty $Manifest "days"))) {
        foreach ($name in @("fragmentGenerationId", "dailyGenerationId")) {
            $value = ([string](Get-OptionalProperty $entry $name)).Trim()
            if ($value) { $ids[$value] = $true }
        }
        foreach ($name in @("path", "dailyPath")) {
            $path = [string](Get-OptionalProperty $entry $name)
            if ($path -match '/(g6-[^/]+)/') { $ids[$Matches[1]] = $true }
        }
    }
    return $ids
}

function Remove-UnreferencedV6Generations {
    param(
        [Parameter(Mandatory)] [string]$DataDirectory,
        [Parameter(Mandatory)] [hashtable]$KeepGenerationIds
    )

    foreach ($relativeRoot in @("public-events-v6", "public-daily")) {
        $root = Join-Path $DataDirectory $relativeRoot
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $resolvedRoot = [IO.Path]::GetFullPath($root).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        foreach ($directory in Get-ChildItem -LiteralPath $root -Directory -Filter "g6-*") {
            if ($KeepGenerationIds.ContainsKey($directory.Name)) { continue }
            $resolvedTarget = [IO.Path]::GetFullPath($directory.FullName)
            if (-not ($resolvedTarget + [IO.Path]::DirectorySeparatorChar).StartsWith($resolvedRoot, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Refus de nettoyer un répertoire v6 hors de la racine attendue: $resolvedTarget"
            }
            Remove-Item -LiteralPath $resolvedTarget -Recurse -Force
        }
    }
}

function Write-V6DayArtifacts {
    param(
        [Parameter(Mandatory)] [string]$DataDirectory,
        [Parameter(Mandatory)] [string]$GenerationId,
        [Parameter(Mandatory)] [string]$DateKey,
        [Parameter(Mandatory)] [array]$Events,
        [Parameter(Mandatory)] [string]$GeneratedAt,
        [Parameter(Mandatory)] $Provenance
    )

    $cursor = Get-EventCursor -Events $Events
    $representedEvents = Get-RepresentedEventCount -Events $Events
    $derivedEchoes = @($Events | Where-Object { [string](Get-OptionalProperty $_ "confidence") -eq "derived" }).Count
    $confirmedEchoes = $Events.Count - $derivedEchoes
    $dayContentHash = Get-JsonContentHash -Value $Events
    $fragment = [ordered]@{
        schemaVersion = $PublicEventContractVersion
        ok = $true
        generationId = $GenerationId
        date = $DateKey
        generatedAt = $GeneratedAt
        observedAt = $Provenance.observedAt
        sourceUpdatedAt = $Provenance.sourceUpdatedAt
        gameVersion = $Provenance.gameVersion
        steamBuildId = $Provenance.steamBuildId
        parserCommit = $Provenance.parserCommit
        catalogCommit = $Provenance.catalogCommit
        freshness = $Provenance.freshness
        sourceStatus = $Provenance.sourceStatus
        cursor = $cursor
        counts = [ordered]@{
            echoes = $Events.Count
            representedEvents = $representedEvents
            confirmedEchoes = $confirmedEchoes
            derivedEchoes = $derivedEchoes
        }
        contentHash = "sha256:$dayContentHash"
        events = $Events
    }
    $fragmentPath = Join-Path $DataDirectory "public-events-v6\$GenerationId\$DateKey.json"
    $writtenFragment = Write-ImmutableJson -Path $fragmentPath -Value $fragment

    $daily = [ordered]@{
        schemaVersion = $PublicEventContractVersion
        ok = $true
        generationId = $GenerationId
        date = $DateKey
        generatedAt = $GeneratedAt
        observedAt = $Provenance.observedAt
        sourceUpdatedAt = $Provenance.sourceUpdatedAt
        gameVersion = $Provenance.gameVersion
        steamBuildId = $Provenance.steamBuildId
        parserCommit = $Provenance.parserCommit
        catalogCommit = $Provenance.catalogCommit
        freshness = $Provenance.freshness
        sourceStatus = $Provenance.sourceStatus
        cursor = $cursor
        counts = [ordered]@{
            echoes = $Events.Count
            representedEvents = $representedEvents
            confirmedEchoes = $confirmedEchoes
            derivedEchoes = $derivedEchoes
        }
        digest = Get-V6DailyDigest -Events $Events
        latest = @($Events | Select-Object -First $PublicEventHeadLimit)
    }
    $dailyPath = Join-Path $DataDirectory "public-daily\$GenerationId\$DateKey.json"
    $writtenDaily = Write-ImmutableJson -Path $dailyPath -Value $daily

    return [ordered]@{
        date = $DateKey
        path = "data/public-events-v6/$GenerationId/$DateKey.json"
        sha256 = "sha256:$($writtenFragment.Sha256)"
        fragmentGenerationId = $GenerationId
        dailyPath = "data/public-daily/$GenerationId/$DateKey.json"
        dailySha256 = "sha256:$($writtenDaily.Sha256)"
        dailyGenerationId = $GenerationId
        contentHash = "sha256:$dayContentHash"
        events = $Events.Count
        representedEvents = $representedEvents
        firstAt = if ($Events.Count) { Convert-ToIsoTimestamp (Get-OptionalProperty $Events[-1] "occurredAt") } else { $null }
        lastAt = if ($Events.Count) { Convert-ToIsoTimestamp (Get-OptionalProperty $Events[0] "occurredAt") } else { $null }
    }
}

function Read-V6DayEvents {
    param(
        [Parameter(Mandatory)] [string]$DataDirectory,
        [Parameter(Mandatory)] $Entry
    )

    $path = Resolve-V6ContractPath -DataDirectory $DataDirectory -ContractPath ([string](Get-OptionalProperty $Entry "path"))
    if (-not (Test-V6FileHash -Path $path -ExpectedHash ([string](Get-OptionalProperty $Entry "sha256")))) {
        throw "Le fragment v6 actif est absent ou son hachage est invalide: $path"
    }
    $payload = Read-JsonFile -Path $path
    $expectedGeneration = [string](Get-OptionalProperty $Entry "fragmentGenerationId")
    if (-not $expectedGeneration) { $expectedGeneration = [string](Get-OptionalProperty $Entry "generationId") }
    if (-not $expectedGeneration) {
        $contractPath = [string](Get-OptionalProperty $Entry "path")
        if ($contractPath -match '/(g6-[^/]+)/') { $expectedGeneration = $Matches[1] }
    }
    if ($null -eq $payload -or [string](Get-OptionalProperty $payload "generationId") -ne $expectedGeneration) {
        throw "Le fragment v6 actif appartient à une autre génération: $path"
    }
    return @(Get-EventsArray -Payload $payload)
}

function Write-V6Head {
    param(
        [Parameter(Mandatory)] [array]$Events,
        [Parameter(Mandatory)] $SourcePayload,
        [string]$BaseGenerationId = "",
        [int]$TotalEchoes = -1,
        $GlobalCursor = $null
    )

    $directory = Split-Path -Parent ($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath))
    if (-not $BaseGenerationId) {
        throw "Une tête v6 immuable exige un identifiant de génération."
    }
    $sortedEvents = @(
        $Events | Sort-Object `
            @{ Expression = { Convert-FastEventDate (Get-OptionalProperty $_ "occurredAt") }; Descending = $true },
            @{ Expression = { Get-CanonicalEventOrderRank -Event $_ }; Descending = $false },
            @{ Expression = { Convert-ToPositiveInt (Get-OptionalProperty $_ "id") }; Descending = $true }
    )
    $headEvents = @($sortedEvents | Select-Object -First $PublicEventHeadLimit)
    $verifiedEchoes = @(
        $sortedEvents |
            Where-Object { [string](Get-OptionalProperty $_ "confidence") -eq "confirmed" } |
            Select-Object -First $PublicEventHeadLimit
    )
    $windowCursor = Get-EventCursor -Events $headEvents
    $cursor = if ($null -ne $GlobalCursor) { $GlobalCursor } else { $windowCursor }
    if ($TotalEchoes -lt 0) { $TotalEchoes = $Events.Count }
    $provenance = Get-V6Provenance -SourcePayload $SourcePayload
    $head = [ordered]@{
        schemaVersion = $PublicEventContractVersion
        ok = $true
        baseGenerationId = if ($BaseGenerationId) { $BaseGenerationId } else { $null }
        revision = "6:$([string](Get-OptionalProperty $SourcePayload 'revision')):$($cursor.maxId):head"
        generatedAt = (Get-Date).ToString("o")
        observedAt = $provenance.observedAt
        sourceUpdatedAt = $provenance.sourceUpdatedAt
        gameVersion = $provenance.gameVersion
        steamBuildId = $provenance.steamBuildId
        parserCommit = $provenance.parserCommit
        catalogCommit = $provenance.catalogCommit
        freshness = $provenance.freshness
        sourceStatus = $provenance.sourceStatus
        cursor = $cursor
        windowCursor = $windowCursor
        counts = [ordered]@{
            echoes = $headEvents.Count
            verifiedEchoes = $verifiedEchoes.Count
            totalEchoes = $TotalEchoes
            representedEvents = Get-RepresentedEventCount -Events $headEvents
        }
        hasMore = $TotalEchoes -gt $headEvents.Count
        events = $headEvents
        verifiedEchoes = $verifiedEchoes
    }
    $headPath = Join-Path $directory "public-events-v6\$BaseGenerationId\head.json"
    $written = Write-ImmutableJson -Path $headPath -Value $head
    return [pscustomobject]@{
        Payload = $head
        Path = "data/public-events-v6/$BaseGenerationId/head.json"
        Sha256 = "sha256:$($written.Sha256)"
    }
}

function Publish-V6ActiveContract {
    param(
        [Parameter(Mandatory)] [string]$DataDirectory,
        [Parameter(Mandatory)] [string]$StableManifestPath,
        [Parameter(Mandatory)] $Manifest
    )

    $generationId = [string](Get-OptionalProperty $Manifest "generationId")
    if ($generationId -notmatch '^[A-Za-z0-9._-]+$') {
        throw "La génération v6 active est invalide."
    }
    $immutableManifestPath = Join-Path $DataDirectory "public-events-v6\$generationId\manifest.json"
    $immutableManifest = Write-ImmutableJson -Path $immutableManifestPath -Value $Manifest
    $manifestReference = [ordered]@{
        path = "data/public-events-v6/$generationId/manifest.json"
        sha256 = "sha256:$($immutableManifest.Sha256)"
    }
    [void](Write-JsonAtomicEarly -Path $StableManifestPath -Value $Manifest)

    $head = Get-OptionalProperty $Manifest "head"
    $pointer = [ordered]@{
        schemaVersion = $PublicEventContractVersion
        ok = $true
        baseGenerationId = $generationId
        revision = [string](Get-OptionalProperty $head "revision")
        generatedAt = [string](Get-OptionalProperty $Manifest "generatedAt")
        sourceUpdatedAt = [string](Get-OptionalProperty $Manifest "sourceUpdatedAt")
        cursor = Get-OptionalProperty $Manifest "cursor"
        counts = [ordered]@{
            totalEchoes = [int](Get-OptionalProperty (Get-OptionalProperty $Manifest "counts") "echoes")
        }
        manifest = $manifestReference
        head = [ordered]@{
            path = [string](Get-OptionalProperty $head "path")
            sha256 = [string](Get-OptionalProperty $head "sha256")
            revision = [string](Get-OptionalProperty $head "revision")
        }
    }
    $pointerPath = Join-Path $DataDirectory "public-events-head-v6.json"
    [void](Write-JsonAtomicEarly -Path $pointerPath -Value $pointer)
    return $pointer
}

function Write-V6Generation {
    param(
        [Parameter(Mandatory)] [array]$Events,
        [Parameter(Mandatory)] $SourcePayload
    )

    $directory = Split-Path -Parent ($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath))
    $manifestPath = Join-Path $directory "public-events-manifest-v6.json"
    $previousManifestPath = Join-Path $directory "public-events-manifest-v6.previous.json"
    $activeManifest = Read-JsonFile -Path $manifestPath
    $generatedAt = (Get-Date).ToString("o")
    $provenance = Get-V6Provenance -SourcePayload $SourcePayload
    $contentHash = Get-JsonContentHash -Value $Events
    $generationId = "g6-$((Get-Date).ToString('yyyyMMddTHHmmssfff'))-$($contentHash.Substring(0, 12))"
    $days = [Collections.Generic.List[object]]::new()

    $groupedDays = @($Events | Group-Object -Property { Get-EventDateKey -Event $_ } | Sort-Object -Property Name -Descending)
    foreach ($group in $groupedDays) {
        $dateKey = [string]$group.Name
        $dayEvents = @($group.Group)
        $dayContentHash = Get-JsonContentHash -Value $dayEvents
        $reusableEntry = Get-V6ReusableDayEntry -ActiveManifest $activeManifest -DateKey $dateKey -ContentHash $dayContentHash -DataDirectory $directory
        if ($null -ne $reusableEntry) {
            $days.Add($reusableEntry)
            continue
        }
        $days.Add((Write-V6DayArtifacts -DataDirectory $directory -GenerationId $generationId -DateKey $dateKey -Events $dayEvents -GeneratedAt $generatedAt -Provenance $provenance))
    }

    $cursor = Get-EventCursor -Events $Events
    $head = Write-V6Head -Events $Events -SourcePayload $SourcePayload -BaseGenerationId $generationId -TotalEchoes $Events.Count -GlobalCursor $cursor
    if (Test-CanonicalEventProjection -Payload $SourcePayload) {
        $sourceSummary = Get-OptionalProperty $SourcePayload "summary"
        $rawEvents = [int](Get-OptionalProperty $sourceSummary "rawEvents")
        $publicEvents = [int](Get-OptionalProperty $sourceSummary "publicEvents")
        $representedEvents = [int](Get-OptionalProperty $sourceSummary "representedEvents")
    }
    else {
        $rawEvents = Get-SourceSummaryMetric -Payload $SourcePayload -Names @("rawEvents", "sourceEvents", "totalEvents") -Fallback $Events.Count
        $publicEvents = Get-SourceSummaryMetric -Payload $SourcePayload -Names @("publicEvents", "events") -Fallback $Events.Count
        $representedEvents = Get-SourceSummaryMetric -Payload $SourcePayload -Names @("representedEvents") -Fallback (Get-RepresentedEventCount -Events $Events)
    }
    $manifest = [ordered]@{
        schemaVersion = $PublicEventContractVersion
        ok = $true
        generationId = $generationId
        generatedAt = $generatedAt
        observedAt = $provenance.observedAt
        sourceUpdatedAt = $provenance.sourceUpdatedAt
        gameVersion = $provenance.gameVersion
        steamBuildId = $provenance.steamBuildId
        parserCommit = $provenance.parserCommit
        catalogCommit = $provenance.catalogCommit
        freshness = $provenance.freshness
        sourceStatus = $provenance.sourceStatus
        sourceRevision = [string](Get-OptionalProperty $SourcePayload "revision")
        sourceProjectionRevision = if ((Get-ProjectionRevision -Payload $SourcePayload) -ge 0) { Get-ProjectionRevision -Payload $SourcePayload } else { $null }
        sourceProvenanceRevision = if (Get-OptionalProperty $SourcePayload "provenanceRevision") { [string](Get-OptionalProperty $SourcePayload "provenanceRevision") } else { $null }
        previousGenerationId = if ($activeManifest) { [string](Get-OptionalProperty $activeManifest "generationId") } else { $null }
        requiresReprojection = $false
        cursor = $cursor
        counts = [ordered]@{
            rawEvents = $rawEvents
            publicEvents = $publicEvents
            echoes = $Events.Count
            representedEvents = $representedEvents
            days = $days.Count
        }
        facets = Get-V6Facets -Events $Events
        head = [ordered]@{
            path = [string]$head.Path
            sha256 = [string]$head.Sha256
            revision = [string]$head.Payload.revision
        }
        days = @($days)
    }

    if ($activeManifest) {
        [void](Write-JsonAtomicEarly -Path $previousManifestPath -Value $activeManifest)
    }
    $keepGenerationIds = Get-V6ReferencedGenerationIds -Manifest $manifest
    foreach ($entry in (Get-V6ReferencedGenerationIds -Manifest $activeManifest).GetEnumerator()) {
        $keepGenerationIds[$entry.Key] = $true
    }
    Remove-UnreferencedV6Generations -DataDirectory $directory -KeepGenerationIds $keepGenerationIds

    # Les artefacts et le manifeste immuable sont préparés avant le petit pointeur actif.
    [void](Publish-V6ActiveContract -DataDirectory $directory -StableManifestPath $manifestPath -Manifest $manifest)
    return $manifest
}

function Add-V6FacetRows {
    param(
        $Rows,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$Events,
        [Parameter(Mandatory)] [string]$PropertyName
    )

    $counts = @{}
    foreach ($row in @($Rows)) {
        $value = ([string](Get-OptionalProperty $row "value")).Trim()
        if ($value) { $counts[$value] = Convert-ToPositiveInt (Get-OptionalProperty $row "count") }
    }
    foreach ($event in $Events) {
        $value = ([string](Get-OptionalProperty $event $PropertyName)).Trim()
        if (-not $value) { continue }
        if (-not $counts.ContainsKey($value)) { $counts[$value] = 0 }
        $counts[$value] = [int]$counts[$value] + 1
    }
    return @(
        $counts.GetEnumerator() | Sort-Object -Property Key | ForEach-Object {
            [ordered]@{ value = [string]$_.Key; count = [int]$_.Value }
        }
    )
}

function Update-V6FacetRows {
    param(
        $Rows,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$RemovedEvents,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$AddedEvents,
        [Parameter(Mandatory)] [string]$PropertyName
    )

    $counts = @{}
    foreach ($row in @($Rows)) {
        $value = ([string](Get-OptionalProperty $row "value")).Trim()
        if ($value) { $counts[$value] = Convert-ToPositiveInt (Get-OptionalProperty $row "count") }
    }
    foreach ($event in $RemovedEvents) {
        $value = ([string](Get-OptionalProperty $event $PropertyName)).Trim()
        if (-not $value) { continue }
        if (-not $counts.ContainsKey($value) -or [int]$counts[$value] -lt 1) {
            throw "La facette '$PropertyName' ne peut pas retirer la valeur '$value'."
        }
        $counts[$value] = [int]$counts[$value] - 1
    }
    foreach ($event in $AddedEvents) {
        $value = ([string](Get-OptionalProperty $event $PropertyName)).Trim()
        if (-not $value) { continue }
        if (-not $counts.ContainsKey($value)) { $counts[$value] = 0 }
        $counts[$value] = [int]$counts[$value] + 1
    }
    return @(
        $counts.GetEnumerator() |
            Where-Object { [int]$_.Value -gt 0 } |
            Sort-Object -Property Key |
            ForEach-Object { [ordered]@{ value = [string]$_.Key; count = [int]$_.Value } }
    )
}

function New-V6FastResult {
    param(
        [bool]$Changed = $false,
        [bool]$RequiresReprojection = $false,
        [string]$Reason = "",
        $Manifest = $null
    )

    return [pscustomobject]@{
        Changed = $Changed
        RequiresReprojection = $RequiresReprojection
        Reason = $Reason
        Manifest = $Manifest
    }
}

function Write-V6IncrementalGeneration {
    param(
        [Parameter(Mandatory)] $RecentPayload,
        [Parameter(Mandatory)] [array]$RecentEvents
    )

    if (-not (Test-CanonicalEventProjection -Payload $RecentPayload)) {
        return New-V6FastResult -Reason "legacy-source"
    }

    $directory = Split-Path -Parent ($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath))
    $manifestPath = Join-Path $directory "public-events-manifest-v6.json"
    $previousManifestPath = Join-Path $directory "public-events-manifest-v6.previous.json"
    $activeManifest = Read-JsonFile -Path $manifestPath
    if ($null -eq $activeManifest -or (Convert-ToPositiveInt (Get-OptionalProperty $activeManifest "schemaVersion")) -ne $PublicEventContractVersion) {
        return New-V6FastResult -RequiresReprojection $true -Reason "initial-generation-required"
    }
    if (-not (Test-V6ContractFilesComplete -DataDirectory $directory)) {
        return New-V6FastResult -RequiresReprojection $true -Reason "local-generation-incomplete"
    }

    $activeGenerationId = [string](Get-OptionalProperty $activeManifest "generationId")
    $activeCursor = Get-OptionalProperty $activeManifest "cursor"
    $activeCounts = Get-OptionalProperty $activeManifest "counts"
    $lastProjectedId = [long](Convert-ToPositiveInt (Get-OptionalProperty $activeCursor "maxId"))
    $activeEchoes = Convert-ToPositiveInt (Get-OptionalProperty $activeCounts "echoes")
    $activeRepresented = Convert-ToPositiveInt (Get-OptionalProperty $activeCounts "representedEvents")
    $activeRawEvents = Convert-ToPositiveInt (Get-OptionalProperty $activeCounts "rawEvents")
    $activePublicEvents = Convert-ToPositiveInt (Get-OptionalProperty $activeCounts "publicEvents")
    $activeProjectionRevision = Get-ProjectionRevision -Payload $activeManifest
    $recentProjectionRevision = Get-ProjectionRevision -Payload $RecentPayload
    $activeProvenanceRevision = ([string](Get-OptionalProperty $activeManifest "sourceProvenanceRevision")).Trim()
    $recentProvenanceRevision = ([string](Get-OptionalProperty $RecentPayload "provenanceRevision")).Trim()
    $totalEchoes = Get-SourceSummaryMetric -Payload $RecentPayload -Names @("totalEchoes") -Fallback -1
    $totalRepresented = Get-SourceSummaryMetric -Payload $RecentPayload -Names @("totalRepresentedEvents") -Fallback -1
    $totalRawEvents = Get-SourceSummaryMetric -Payload $RecentPayload -Names @("rawEvents", "totalEvents") -Fallback -1
    $totalPublicEvents = Get-SourceSummaryMetric -Payload $RecentPayload -Names @("publicEvents") -Fallback -1
    if ($totalEchoes -lt 0 -or $totalRepresented -lt 0 -or $totalRawEvents -lt 0 -or $totalPublicEvents -lt 0) {
        return New-V6FastResult -RequiresReprojection $true -Reason "global-counts-unavailable"
    }
    if ($activeProjectionRevision -lt 0 -or $recentProjectionRevision -lt 0) {
        return New-V6FastResult -RequiresReprojection $true -Reason "projection-revision-unavailable"
    }
    if (-not $activeProvenanceRevision -or -not $recentProvenanceRevision) {
        return New-V6FastResult -RequiresReprojection $true -Reason "provenance-revision-unavailable"
    }
    if ($recentProjectionRevision -lt $activeProjectionRevision) {
        return New-V6FastResult -RequiresReprojection $true -Reason "projection-revision-regressed"
    }

    $projectionDelta = $recentProjectionRevision - $activeProjectionRevision
    $rawDelta = [long]$totalRawEvents - [long]$activeRawEvents
    $publicDelta = [long]$totalPublicEvents - [long]$activePublicEvents
    if ($projectionDelta -eq 0) {
        if ($rawDelta -ne 0 -or $publicDelta -ne 0) {
            return New-V6FastResult -RequiresReprojection $true -Reason "projection-revision-inconsistent"
        }
    }
    elseif ($rawDelta -le 0 -or $publicDelta -lt 0 -or $publicDelta -gt $rawDelta -or
        $projectionDelta -lt $rawDelta) {
        # Une insertion peut aussi déclencher une suppression publique et donc
        # plusieurs changements de projection. Le producteur refuse en amont
        # toute mutation d'un identifiant déjà matérialisé; il reste néanmoins
        # nécessaire de prouver ici une hausse des seules nouvelles lignes.
        return New-V6FastResult -RequiresReprojection $true -Reason "projection-not-append-only"
    }

    $provenanceChanged = $recentProvenanceRevision -ne $activeProvenanceRevision
    if ($projectionDelta -eq 0) {
        if ($totalEchoes -ne $activeEchoes -or $totalRepresented -ne $activeRepresented) {
            return New-V6FastResult -RequiresReprojection $true -Reason "unchanged-counts-diverged"
        }
        if (-not $provenanceChanged) {
            return New-V6FastResult -Manifest $activeManifest
        }
    }

    $entryByDate = @{}
    foreach ($entry in @((Get-OptionalProperty $activeManifest "days"))) {
        $dateKey = [string](Get-OptionalProperty $entry "date")
        if ($dateKey) { $entryByDate[$dateKey] = $entry }
    }
    $eventsByDate = @{}
    $removedTailEvents = [Collections.Generic.List[object]]::new()
    $addedTailEvents = [Collections.Generic.List[object]]::new()
    $touchedDateKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $replaceFromDate = [datetimeoffset]::MinValue

    if ($projectionDelta -gt 0) {
        $projectionWindow = Get-OptionalProperty $RecentPayload "projectionWindow"
        if ([string](Get-OptionalProperty $projectionWindow "mode") -cne "replace-tail" -or
            -not [bool](Get-OptionalProperty $projectionWindow "complete") -or
            $null -eq (Get-OptionalProperty $projectionWindow "replaceFrom")) {
            return New-V6FastResult -RequiresReprojection $true -Reason "projection-window-incomplete"
        }
        try {
            $windowFromRevision = Get-StrictInteger -Value (Get-OptionalProperty $projectionWindow "fromProjectionRevision") -Name "projectionWindow.fromProjectionRevision"
            $windowThroughRevision = Get-StrictInteger -Value (Get-OptionalProperty $projectionWindow "throughProjectionRevision") -Name "projectionWindow.throughProjectionRevision"
            $replaceFromDate = Get-StrictIsoTimestamp -Value (Get-OptionalProperty $projectionWindow "replaceFrom") -Name "projectionWindow.replaceFrom"
        }
        catch {
            return New-V6FastResult -RequiresReprojection $true -Reason "projection-window-invalid"
        }
        if ($activeProjectionRevision -lt $windowFromRevision -or
            $activeProjectionRevision -ge $windowThroughRevision -or
            $windowThroughRevision -ne $recentProjectionRevision) {
            return New-V6FastResult -RequiresReprojection $true -Reason "projection-window-revision-gap"
        }

        $replaceDateKey = $replaceFromDate.ToString("yyyy-MM-dd")
        try {
            foreach ($dateKey in @($entryByDate.Keys)) {
                if ([string]::CompareOrdinal([string]$dateKey, $replaceDateKey) -lt 0) { continue }
                $dayEvents = @(Read-V6DayEvents -DataDirectory $directory -Entry $entryByDate[$dateKey])
                $eventsByDate[$dateKey] = $dayEvents
                foreach ($event in $dayEvents) {
                    $eventDate = Convert-FastEventDate (Get-OptionalProperty $event "occurredAt")
                    if ($eventDate -ge $replaceFromDate) {
                        $removedTailEvents.Add($event)
                        [void]$touchedDateKeys.Add([string]$dateKey)
                    }
                }
            }
        }
        catch {
            return New-V6FastResult -RequiresReprojection $true -Reason "active-fragment-invalid"
        }
        foreach ($event in $RecentEvents) {
            $eventDate = Convert-FastEventDate (Get-OptionalProperty $event "occurredAt")
            if ($eventDate -lt $replaceFromDate) { continue }
            $addedTailEvents.Add($event)
            [void]$touchedDateKeys.Add((Get-EventDateKey -Event $event))
        }
        $activeTailByKey = @{}
        foreach ($event in $removedTailEvents) {
            $key = [string](Get-OptionalProperty $event "key")
            if ($key) { $activeTailByKey[$key] = $event }
        }
        foreach ($event in $addedTailEvents) {
            $id = [long](Convert-ToPositiveInt (Get-OptionalProperty $event "id"))
            if ($id -gt $lastProjectedId) { continue }
            $key = [string](Get-OptionalProperty $event "key")
            if (-not $key -or -not $activeTailByKey.ContainsKey($key) -or
                (Get-JsonContentHash -Value $activeTailByKey[$key]) -ne (Get-JsonContentHash -Value $event)) {
                return New-V6FastResult -RequiresReprojection $true -Reason "historical-event-inside-tail"
            }
        }
        if ($publicDelta -gt 0 -and (Get-EventsMaxId -Events @($addedTailEvents)) -le $lastProjectedId) {
            return New-V6FastResult -RequiresReprojection $true -Reason "projection-window-cursor-did-not-advance"
        }
        $expectedEchoes = $activeEchoes - $removedTailEvents.Count + $addedTailEvents.Count
        $expectedRepresented = $activeRepresented - (Get-RepresentedEventCount -Events @($removedTailEvents)) + (Get-RepresentedEventCount -Events @($addedTailEvents))
        if ($totalEchoes -ne $expectedEchoes) {
            return New-V6FastResult -RequiresReprojection $true -Reason "echo-count-diverged"
        }
        if ($totalRepresented -ne $expectedRepresented) {
            return New-V6FastResult -RequiresReprojection $true -Reason "represented-count-diverged"
        }
    }

    if ($projectionDelta -eq 0 -and -not $provenanceChanged) {
        return New-V6FastResult -Manifest $activeManifest
    }

    $generatedAt = (Get-Date).ToString("o")
    $provenance = Get-V6Provenance -SourcePayload $RecentPayload
    $generationSeed = "$activeGenerationId|$([string](Get-OptionalProperty $RecentPayload 'revision'))|$($replaceFromDate.ToString('o'))|$(Get-JsonContentHash -Value @($addedTailEvents))"
    $generationHash = Get-Sha256Hex -Bytes ([Text.Encoding]::UTF8.GetBytes($generationSeed))
    $generationId = "g6-$((Get-Date).ToString('yyyyMMddTHHmmssfff'))-$($generationHash.Substring(0, 12))"
    foreach ($dateKey in @($touchedDateKeys | Sort-Object)) {
        $existingEvents = if ($eventsByDate.ContainsKey($dateKey)) { @($eventsByDate[$dateKey]) } else { @() }
        $prefixEvents = @($existingEvents | Where-Object {
            (Convert-FastEventDate (Get-OptionalProperty $_ "occurredAt")) -lt $replaceFromDate
        })
        $replacementEvents = @($addedTailEvents | Where-Object { (Get-EventDateKey -Event $_) -eq $dateKey })
        $merged = @(
            @($prefixEvents) + @($replacementEvents) |
                Sort-Object `
                    @{ Expression = { Convert-FastEventDate (Get-OptionalProperty $_ "occurredAt") }; Descending = $true },
                    @{ Expression = { Get-CanonicalEventOrderRank -Event $_ }; Descending = $false },
                    @{ Expression = { Convert-ToPositiveInt (Get-OptionalProperty $_ "id") }; Descending = $true }
        )
        if ($merged.Count -gt 0) {
            $entryByDate[$dateKey] = Write-V6DayArtifacts -DataDirectory $directory -GenerationId $generationId -DateKey $dateKey -Events $merged -GeneratedAt $generatedAt -Provenance $provenance
        }
        else {
            [void]$entryByDate.Remove($dateKey)
        }
    }

    if ($TestFailurePoint -eq "AfterFragments") {
        throw "Interruption de test après l'écriture des fragments v6."
    }

    $newCursorMax = [Math]::Max($lastProjectedId, (Get-EventsMaxId -Events @($addedTailEvents)))
    $newCursorMin = Convert-ToPositiveInt (Get-OptionalProperty $activeCursor "minId")
    if ($newCursorMin -le 0) {
        $newCursorMin = Convert-ToPositiveInt (Get-OptionalProperty (Get-EventCursor -Events @($addedTailEvents)) "minId")
    }
    $globalCursor = [ordered]@{ minId = $newCursorMin; maxId = $newCursorMax }
    $sortedRecentEvents = @(
        $RecentEvents | Sort-Object `
            @{ Expression = { Convert-FastEventDate (Get-OptionalProperty $_ "occurredAt") }; Descending = $true },
            @{ Expression = { Get-CanonicalEventOrderRank -Event $_ }; Descending = $false },
            @{ Expression = { Convert-ToPositiveInt (Get-OptionalProperty $_ "id") }; Descending = $true }
    )
    $head = Write-V6Head -Events $sortedRecentEvents -SourcePayload $RecentPayload -BaseGenerationId $generationId -TotalEchoes $totalEchoes -GlobalCursor $globalCursor
    if ($TestFailurePoint -eq "AfterHead") {
        throw "Interruption de test après l'écriture de la tête v6."
    }

    $days = @($entryByDate.Values | Sort-Object -Property @{ Expression = { [string](Get-OptionalProperty $_ "date") }; Descending = $true })
    $facets = Get-OptionalProperty $activeManifest "facets"
    $rawEvents = $totalRawEvents
    $publicEvents = $totalPublicEvents
    $manifest = [ordered]@{
        schemaVersion = $PublicEventContractVersion
        ok = $true
        generationId = $generationId
        generatedAt = $generatedAt
        observedAt = $provenance.observedAt
        sourceUpdatedAt = $provenance.sourceUpdatedAt
        gameVersion = $provenance.gameVersion
        steamBuildId = $provenance.steamBuildId
        parserCommit = $provenance.parserCommit
        catalogCommit = $provenance.catalogCommit
        freshness = $provenance.freshness
        sourceStatus = $provenance.sourceStatus
        sourceRevision = [string](Get-OptionalProperty $RecentPayload "revision")
        sourceProjectionRevision = $recentProjectionRevision
        sourceProvenanceRevision = $recentProvenanceRevision
        previousGenerationId = $activeGenerationId
        requiresReprojection = $false
        cursor = [ordered]@{
            minId = $newCursorMin
            maxId = $newCursorMax
        }
        counts = [ordered]@{
            rawEvents = $rawEvents
            publicEvents = $publicEvents
            echoes = $totalEchoes
            representedEvents = $totalRepresented
            days = $days.Count
        }
        facets = [ordered]@{
            types = Update-V6FacetRows -Rows (Get-OptionalProperty $facets "types") -RemovedEvents @($removedTailEvents) -AddedEvents @($addedTailEvents) -PropertyName "type"
            players = Update-V6FacetRows -Rows (Get-OptionalProperty $facets "players") -RemovedEvents @($removedTailEvents) -AddedEvents @($addedTailEvents) -PropertyName "player"
        }
        head = [ordered]@{
            path = [string]$head.Path
            sha256 = [string]$head.Sha256
            revision = [string]$head.Payload.revision
        }
        days = $days
    }

    [void](Write-JsonAtomicEarly -Path $previousManifestPath -Value $activeManifest)
    $keepGenerationIds = Get-V6ReferencedGenerationIds -Manifest $manifest
    foreach ($entry in (Get-V6ReferencedGenerationIds -Manifest $activeManifest).GetEnumerator()) {
        $keepGenerationIds[$entry.Key] = $true
    }
    Remove-UnreferencedV6Generations -DataDirectory $directory -KeepGenerationIds $keepGenerationIds
    [void](Publish-V6ActiveContract -DataDirectory $directory -StableManifestPath $manifestPath -Manifest $manifest)
    return New-V6FastResult -Changed $true -Manifest $manifest
}

function Merge-FastRecentEvents {
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [array]$IncomingEvents)

    $incoming = $IncomingEvents
    $existingPayload = Read-JsonFile -Path $RecentOutputPath
    $existing = if ($existingPayload -and $existingPayload.recent) { Get-EventsArray -Payload $existingPayload } else { @() }
    $byKey = [ordered]@{}
    $index = 0
    foreach ($event in $existing) {
        $byKey[(Get-EventIdentity -Event $event -Index $index -Prefix "local")] = $event
        $index++
    }
    $index = 0
    foreach ($event in $incoming) {
        $byKey[(Get-EventIdentity -Event $event -Index $index -Prefix "remote")] = $event
        $index++
    }

    return @(
        $byKey.Values |
            Sort-Object `
                @{ Expression = { Convert-FastEventDate $_.occurredAt }; Descending = $true },
                @{ Expression = { Get-CanonicalEventOrderRank -Event $_ }; Descending = $false },
                @{ Expression = { if ($_.id -ne $null) { [long]$_.id } else { 0 } }; Descending = $true }
    )
}

function Write-FastEventOutputs {
    param([Parameter(Mandatory)] $RecentPayload)

    if (Test-CanonicalEventProjection -Payload $RecentPayload) {
        $events = @(Get-EventsArray -Payload $RecentPayload)
        Assert-CanonicalEventProjection -Payload $RecentPayload -Events $events
    }
    elseif (Test-CanonicalProjectionClaim -Payload $RecentPayload) {
        throw "Le payload récent prétend utiliser le contrat canonique sans respecter strictement sa version et sa projection."
    }
    else {
        $incomingEvents = @($RecentPayload.events | ForEach-Object { Convert-PublicEvent $_ } | Where-Object { $null -ne $_ })
        $events = Merge-FastRecentEvents -IncomingEvents $incomingEvents
        $events = @(Remove-WorldDropBuildEvents -Events $events)
        $events = @(Remove-DuplicateSessionFallbacks -Events $events)
        $events = @(Group-ItemizedPublicEvents -Events $events)
        $events = @($events | Select-Object -First $RecentEventLimit)
    }
    $events = @($events | Select-Object -First $RecentEventLimit)
    $existingIndex = Read-JsonFile -Path $IndexOutputPath
    $existingTotalEvents = 0
    if ($existingIndex -and $existingIndex.summary) {
        $existingTotalEvents = Convert-ToPositiveInt (Get-OptionalProperty $existingIndex.summary "events")
        if ($existingTotalEvents -le 0) {
            $existingTotalEvents = Convert-ToPositiveInt (Get-OptionalProperty $existingIndex.summary "totalEvents")
        }
    }
    $remoteTotalEvents = if ($RecentPayload.summary -and $null -ne (Get-OptionalProperty $RecentPayload.summary "totalEchoes")) {
        [int](Get-OptionalProperty $RecentPayload.summary "totalEchoes")
    }
    elseif ($RecentPayload.summary -and $null -ne (Get-OptionalProperty $RecentPayload.summary "echoes")) {
        [int](Get-OptionalProperty $RecentPayload.summary "echoes")
    }
    elseif ($RecentPayload.summary -and $RecentPayload.summary.totalEvents) {
        [int]$RecentPayload.summary.totalEvents
    }
    elseif ($RecentPayload.summary -and $RecentPayload.summary.events) {
        [int]$RecentPayload.summary.events
    }
    else {
        $events.Count
    }
    $totalEvents = if ($remoteTotalEvents -gt 0) {
        [Math]::Max($remoteTotalEvents, $events.Count)
    }
    elseif ($existingTotalEvents -gt 0) {
        [Math]::Max($existingTotalEvents, $events.Count)
    }
    else {
        $remoteTotalEvents
    }
    $maxId = Get-EventsMaxId -Events $events
    $hotRecentPayload = [ordered]@{
        version = $PublicEventVersion
        schemaVersion = $PublicEventVersion
        ok = $true
        revision = "{0}:{1}:{2}:hot:{3}" -f $PublicEventVersion, $events.Count, $maxId, ([string](Get-OptionalProperty $RecentPayload "provenanceRevision"))
        sourceRevision = [string](Get-OptionalProperty $RecentPayload "revision")
        projectionRevision = Get-ProjectionRevision -Payload $RecentPayload
        provenanceRevision = [string](Get-OptionalProperty $RecentPayload "provenanceRevision")
        provenance = Get-V6Provenance -SourcePayload $RecentPayload
        updatedAt = [string]$RecentPayload.updatedAt
        recent = $true
        truncated = [bool]$RecentPayload.truncated
        summary = Get-FastEventSummary -Events $events -TotalEvents $TotalEvents
        events = $events
    }
    if (Test-CanonicalEventProjection -Payload $RecentPayload) {
        # Le contrat v5 reste actif pendant l'observation. Il relaie donc la
        # borne canonique sans tenter de réinterpréter le regroupement serveur.
        $hotRecentPayload["projectionWindow"] = Get-OptionalProperty $RecentPayload "projectionWindow"
    }
    $v6FastResult = Write-V6IncrementalGeneration -RecentPayload $RecentPayload -RecentEvents $events
    if (-not $v6FastResult.RequiresReprojection) {
        [void](Write-JsonAtomicEarly -Path $RecentOutputPath -Value $hotRecentPayload)
    }
    Write-SyncState -State ([ordered]@{
        remotePath = $remotePath
        remoteRecentPath = $remoteRecentPath
        remoteRevision = if ($syncState) { [string](Get-StateValue $syncState "remoteRevision") } else { "" }
        recentRevision = [string]$RecentPayload.revision
        remoteProjectionRevision = if ($syncState) { Get-StateValue $syncState "remoteProjectionRevision" } else { $null }
        recentProjectionRevision = if ((Get-ProjectionRevision -Payload $RecentPayload) -ge 0) { Get-ProjectionRevision -Payload $RecentPayload } else { $null }
        remoteProvenanceRevision = if ($syncState) { Get-StateValue $syncState "remoteProvenanceRevision" } else { $null }
        recentProvenanceRevision = if (Get-OptionalProperty $RecentPayload "provenanceRevision") { [string](Get-OptionalProperty $RecentPayload "provenanceRevision") } else { $null }
        localRecentRevision = [string]$hotRecentPayload.revision
        remoteUpdatedAt = [string]$RecentPayload.updatedAt
        remoteEvents = $TotalEvents
        remoteMaxId = $MaxId
        pageSize = $PageSize
        recentEventLimit = $RecentEventLimit
        pageCount = if ($existingIndex -and $existingIndex.pages) { @($existingIndex.pages).Count } else { 0 }
        v6GenerationId = if ($v6FastResult.Manifest) { [string](Get-OptionalProperty $v6FastResult.Manifest "generationId") } elseif ($syncState) { [string](Get-StateValue $syncState "v6GenerationId") } else { "" }
        v6IncrementalChanged = [bool]$v6FastResult.Changed
        v6IncrementalSyncedAt = if ($v6FastResult.Changed) { (Get-Date).ToString("o") } elseif ($syncState) { [string](Get-StateValue $syncState "v6IncrementalSyncedAt") } else { $null }
        requiresReprojection = [bool]$v6FastResult.RequiresReprojection
        reprojectionReason = if ($v6FastResult.RequiresReprojection) { [string]$v6FastResult.Reason } else { $null }
        fastSyncedAt = (Get-Date).ToString("o")
        fullSyncedAt = if ($syncState) { [string](Get-StateValue $syncState "fullSyncedAt") } else { $null }
    })
}

$remoteProbePath = if ($Fast) { $remoteRecentPath } else { $remotePath }
$localProbePath = if ($Fast) { $resolvedRecentSourcePayloadPath } else { $resolvedSourcePayloadPath }
$remoteProbe = Read-EventProbe -RemotePath $remoteProbePath -LocalPath $localProbePath
$syncState = Read-JsonFile -Path $SyncStatePath
$probeProjectionRevision = Get-ProjectionRevision -Payload $remoteProbe
$stateProjectionRevision = if ($Fast) {
    Get-ProjectionRevision -Payload ([ordered]@{ projectionRevision = Get-StateValue $syncState "recentProjectionRevision" })
}
else {
    Get-ProjectionRevision -Payload ([ordered]@{ projectionRevision = Get-StateValue $syncState "remoteProjectionRevision" })
}
$revisionMatches = ((-not $Fast -and [string](Get-StateValue $syncState "remoteRevision") -eq [string]$remoteProbe.revision) -or
    ($Fast -and [string](Get-StateValue $syncState "recentRevision") -eq [string]$remoteProbe.revision))
$projectionRevisionMatches = $probeProjectionRevision -lt 0 -or
    ($stateProjectionRevision -ge 0 -and $stateProjectionRevision -eq $probeProjectionRevision)
$probeProvenanceRevision = ([string](Get-OptionalProperty $remoteProbe "provenanceRevision")).Trim()
$stateProvenanceRevision = if ($Fast) {
    ([string](Get-StateValue $syncState "recentProvenanceRevision")).Trim()
}
else {
    ([string](Get-StateValue $syncState "remoteProvenanceRevision")).Trim()
}
$provenanceRevisionMatches = -not $probeProvenanceRevision -or
    ($stateProvenanceRevision -and $stateProvenanceRevision -eq $probeProvenanceRevision)
if (-not $Force -and $syncState -and $remoteProbe.revision -and
    $revisionMatches -and $projectionRevisionMatches -and $provenanceRevisionMatches -and
    [int](Get-StateValue $syncState "pageSize") -eq $PageSize -and
    [int](Get-StateValue $syncState "recentEventLimit") -eq $RecentEventLimit -and
    (Test-LocalEventOutputsComplete -State $syncState)) {
    Write-Host "Historique des échos déjà à jour: révision $($remoteProbe.revision), dernier événement $($remoteProbe.lastAt)."
    return
}

$source = if (-not $Fast) {
    Read-EventPayload -RemotePath $remotePath -LocalPath $resolvedSourcePayloadPath
}
else { $null }

function Convert-PublicText {
    param($Value)

    $text = [string]$Value
    $text = $text -replace '(?i)https?://\S+', '[lien masqué]'
    $text = [regex]::Replace($text, '[0-9A-Fa-f:.%]{2,}', [Text.RegularExpressions.MatchEvaluator]{
        param($Match)
        $candidate = $Match.Value.TrimEnd('.')
        $suffix = $Match.Value.Substring($candidate.Length)
        $address = $null
        if ([Net.IPAddress]::TryParse($candidate, [ref]$address) -and
            $address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6) {
            return "[adresse masquée]$suffix"
        }
        return $Match.Value
    })
    return $text -replace '(?<![A-Za-z0-9.])(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)(?![A-Za-z0-9]|\.\d)', '[adresse masquée]'
}

function Convert-PublicDetails {
    param($Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) {
        return Convert-PublicText $Value
    }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [bool]) {
        return $Value
    }
    if ($Value -is [array]) {
        return @($Value | Select-Object -First 50 | ForEach-Object { Convert-PublicDetails $_ } | Where-Object { $null -ne $_ })
    }
    if ($Value -is [pscustomobject]) {
        $result = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            if ($property.Name -match '(?i)^(?:ip|ipAddress|address|host|hostname|port|endpoint|url|uri|uid|guid|instance|container|account|steam|password|token|dynamic_id|position|coordinates?|map[xyz]|world[xyz])$') {
                continue
            }
            $clean = Convert-PublicDetails $property.Value
            if ($null -ne $clean) { $result[$property.Name] = $clean }
        }
        return $result
    }
    return [string]$Value
}

function Convert-PublicEvent {
    param($Event)

    $type = [string](Get-OptionalProperty $Event "type")
    $sourceName = [string](Get-OptionalProperty $Event "source")
    if ($allowedTypes -notcontains $type) { return $null }
    if ($allowedSources -notcontains $sourceName) { return $null }

    $id = Get-OptionalProperty $Event "id"
    $occurredAt = [string](Get-OptionalProperty $Event "occurredAt")
    $title = Convert-PublicText (Get-OptionalProperty $Event "title")
    $message = Convert-PublicText (Get-OptionalProperty $Event "message")
    $key = Get-OptionalProperty $Event "key"
    if (-not $key) {
        $keyParts = @($sourceName, $id, $occurredAt, $type, $title) | Where-Object { $_ }
        $key = $keyParts -join ":"
    }

    $details = Convert-PublicDetails (Get-OptionalProperty $Event "details")
    $display = Convert-PublicDetails (Get-OptionalProperty $Event "display")
    $icon = Get-OptionalProperty $Event "icon"
    [pscustomobject][ordered]@{
        key = [string]$key
        id = if ($null -ne $id) { [long]$id } else { 0 }
        occurredAt = $occurredAt
        type = $type
        player = if (Get-OptionalProperty $Event "player") { [string](Get-OptionalProperty $Event "player") } else { $null }
        guild = if (Get-OptionalProperty $Event "guild") { [string](Get-OptionalProperty $Event "guild") } else { $null }
        base = if (Get-OptionalProperty $Event "base") { [string](Get-OptionalProperty $Event "base") } else { $null }
        title = $title
        message = $message
        display = if ($display) { $display } else { [ordered]@{ headline = $title; body = $message; bullets = @() } }
        details = if ($details) { $details } else { [ordered]@{} }
        confidence = if (Get-OptionalProperty $Event "confidence") { [string](Get-OptionalProperty $Event "confidence") } else { "confirmed" }
        icon = if ($icon -and ([string]$icon).StartsWith("assets/game/icons/")) { [string]$icon } else { $null }
        source = $sourceName
    }
}

function Convert-ToEventDate {
    param($Value)

    if (-not $Value) { return $null }
    if ($Value -is [DateTimeOffset]) { return $Value }
    if ($Value -is [DateTime]) {
        $date = [DateTime]$Value
        if ($date.Kind -eq [DateTimeKind]::Utc) { return [DateTimeOffset]::new($date) }
        return [DateTimeOffset]::new($date)
    }

    $parsed = [DateTimeOffset]::MinValue
    $styles = [Globalization.DateTimeStyles]::AssumeLocal
    if ([DateTimeOffset]::TryParse([string]$Value, [Globalization.CultureInfo]::CurrentCulture, $styles, [ref]$parsed)) {
        return $parsed
    }
    if ([DateTimeOffset]::TryParse([string]$Value, [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
        return $parsed
    }
    return $null
}

function Remove-DuplicateSessionFallbacks {
    param([array]$Events)

    $toleranceSeconds = 120
    $journalTransitions = @(
        $Events | Where-Object {
            $_.source -eq "journal" -and $_.type -in @("join", "leave") -and $_.player
        } | ForEach-Object {
            [pscustomobject]@{
                Player = ([string]$_.player).ToLowerInvariant()
                Type = [string]$_.type
                OccurredAt = Convert-ToEventDate $_.occurredAt
            }
        } | Where-Object { $null -ne $_.OccurredAt }
    )

    return @($Events | Where-Object {
        $event = $_
        if ($event.source -ne "players" -or $event.type -notin @("join", "leave") -or -not $event.player) {
            return $true
        }
        $occurredAt = Convert-ToEventDate $event.occurredAt
        if ($null -eq $occurredAt) { return $true }
        $player = ([string]$event.player).ToLowerInvariant()
        $duplicate = @($journalTransitions | Where-Object {
            $_.Player -eq $player -and
            $_.Type -eq [string]$event.type -and
            [Math]::Abs(($_.OccurredAt - $occurredAt).TotalSeconds) -le $toleranceSeconds
        }).Count -gt 0
        return -not $duplicate
    })
}

if ($Fast) {
    $recentSource = Read-EventPayload -RemotePath $remoteRecentPath -LocalPath $resolvedRecentSourcePayloadPath
    Write-FastEventOutputs -RecentPayload $recentSource
    $recentSummary = Get-OptionalProperty $recentSource "summary"
    $recentLastAt = [string](Get-OptionalProperty $recentSummary "lastAt")
    Write-Host "Flux rapide des échos synchronisé: révision $([string](Get-OptionalProperty $recentSource 'revision')), dernier événement $recentLastAt."
    return
}

if (Test-CanonicalEventProjection -Payload $source) {
    $events = @(Get-EventsArray -Payload $source)
    Assert-CanonicalEventProjection -Payload $source -Events $events
}
elseif (Test-CanonicalProjectionClaim -Payload $source) {
    throw "Le payload prétend utiliser le contrat canonique sans respecter strictement sa version et sa projection."
}
else {
    $events = @($source.events | ForEach-Object {
        Convert-PublicEvent $_
    } | Where-Object { $null -ne $_ })
    $events = @(Remove-WorldDropBuildEvents -Events $events)
    $events = @(Remove-DuplicateSessionFallbacks -Events $events)
    $events = @(Group-ItemizedPublicEvents -Events $events)
}

$recentEvents = @($events | Select-Object -First $RecentEventLimit)

function Get-EventSummary {
    param(
        [Parameter(Mandatory)] [array]$Events,
        [Parameter(Mandatory)] [int]$TotalEvents
    )

    $types = [ordered]@{}
    foreach ($group in @($Events | Where-Object { $_.type } | Group-Object -Property type | Sort-Object -Property Name)) {
        $types[[string]$group.Name] = [int]$group.Count
    }

    [pscustomobject][ordered]@{
        events = $Events.Count
        totalEvents = $TotalEvents
        firstAt = if ($Events.Count) { [string]$Events[-1].occurredAt } else { $null }
        lastAt = if ($Events.Count) { [string]$Events[0].occurredAt } else { $null }
        types = $types
        reconciledReconnects = if ($types.Contains("reconnect")) { [int]$types["reconnect"] } else { 0 }
    }
}

function New-EventPayload {
    param(
        [Parameter(Mandatory)] [array]$Events,
        [bool]$Recent = $false,
        [int]$TotalEvents = $events.Count
    )

    $maxId = @($Events | ForEach-Object { [long]$_.id } | Measure-Object -Maximum).Maximum
    if ($null -eq $maxId) { $maxId = 0 }
    $sourceTruncated = [bool](Get-OptionalProperty $source "truncated")

    $payload = [ordered]@{
        version = $PublicEventVersion
        schemaVersion = $PublicEventVersion
        ok = $true
        revision = "{0}:{1}:{2}:{3}" -f $PublicEventVersion, $Events.Count, $maxId, ([string](Get-OptionalProperty $source "provenanceRevision"))
        sourceRevision = [string](Get-OptionalProperty $source "revision")
        projectionRevision = Get-ProjectionRevision -Payload $source
        provenanceRevision = [string](Get-OptionalProperty $source "provenanceRevision")
        provenance = Get-V6Provenance -SourcePayload $source
        updatedAt = [string]$source.updatedAt
        recent = $Recent
        truncated = $sourceTruncated
        summary = Get-EventSummary -Events $Events -TotalEvents $TotalEvents
        events = $Events
    }
    if ($Recent -and (Test-CanonicalEventProjection -Payload $source)) {
        $payload["projectionWindow"] = Get-OptionalProperty $source "projectionWindow"
    }
    return $payload
}

function Get-EventFacets {
    param([Parameter(Mandatory)] [array]$Events)

    $types = @(
        $Events |
            Where-Object { $_.type } |
            Group-Object -Property type |
            Sort-Object -Property Name |
            ForEach-Object {
                [ordered]@{
                    value = [string]$_.Name
                    count = [int]$_.Count
                }
            }
    )
    $players = @(
        $Events |
            Where-Object { $_.player } |
            Group-Object -Property player |
            Sort-Object -Property Name |
            ForEach-Object {
                [ordered]@{
                    value = [string]$_.Name
                    count = [int]$_.Count
                }
            }
    )

    [ordered]@{
        types = $types
        players = $players
    }
}

function New-EventIndexPayload {
    param(
        [Parameter(Mandatory)] [array]$Events,
        [Parameter(Mandatory)] [int]$PageSize
    )

    $maxId = @($Events | ForEach-Object { [long]$_.id } | Measure-Object -Maximum).Maximum
    if ($null -eq $maxId) { $maxId = 0 }
    $pageCount = [Math]::Max(1, [int][Math]::Ceiling($Events.Count / [double]$PageSize))
    $pages = @(
        for ($page = 1; $page -le $pageCount; $page++) {
            $offset = ($page - 1) * $PageSize
            $pageEvents = @($Events | Select-Object -Skip $offset -First $PageSize)
            [ordered]@{
                page = $page
                path = "data/public-events-page-{0:D4}.json" -f $page
                events = $pageEvents.Count
                firstAt = if ($pageEvents.Count) { [string]$pageEvents[-1].occurredAt } else { $null }
                lastAt = if ($pageEvents.Count) { [string]$pageEvents[0].occurredAt } else { $null }
            }
        }
    )

    [ordered]@{
        version = $PublicEventVersion
        schemaVersion = $PublicEventVersion
        ok = $true
        revision = "{0}:{1}:{2}:pages:{3}:{4}" -f $PublicEventVersion, $Events.Count, $maxId, $pageCount, ([string](Get-OptionalProperty $source "provenanceRevision"))
        sourceRevision = [string](Get-OptionalProperty $source "revision")
        projectionRevision = Get-ProjectionRevision -Payload $source
        provenanceRevision = [string](Get-OptionalProperty $source "provenanceRevision")
        provenance = Get-V6Provenance -SourcePayload $source
        updatedAt = [string]$source.updatedAt
        recent = $false
        truncated = $false
        pageSize = $PageSize
        summary = Get-EventSummary -Events $Events -TotalEvents $Events.Count
        facets = Get-EventFacets -Events $Events
        pages = $pages
    }
}

function New-EventPagePayload {
    param(
        [Parameter(Mandatory)] [array]$Events,
        [Parameter(Mandatory)] [int]$Page,
        [Parameter(Mandatory)] [int]$PageSize,
        [Parameter(Mandatory)] [int]$TotalEvents
    )

    $maxId = @($Events | ForEach-Object { [long]$_.id } | Measure-Object -Maximum).Maximum
    if ($null -eq $maxId) { $maxId = 0 }
    [ordered]@{
        version = $PublicEventVersion
        schemaVersion = $PublicEventVersion
        ok = $true
        revision = "{0}:{1}:{2}:page:{3}:{4}" -f $PublicEventVersion, $TotalEvents, $maxId, $Page, ([string](Get-OptionalProperty $source "provenanceRevision"))
        sourceRevision = [string](Get-OptionalProperty $source "revision")
        projectionRevision = Get-ProjectionRevision -Payload $source
        provenanceRevision = [string](Get-OptionalProperty $source "provenanceRevision")
        provenance = Get-V6Provenance -SourcePayload $source
        updatedAt = [string]$source.updatedAt
        recent = $false
        truncated = $false
        page = $Page
        pageSize = $PageSize
        summary = Get-EventSummary -Events $Events -TotalEvents $TotalEvents
        events = $Events
    }
}

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] $Value
    )

    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolved) | Out-Null
    $temporary = "$resolved.$([Guid]::NewGuid().ToString('N')).tmp"
    $json = $Value | ConvertTo-Json -Depth 16 -Compress
    $content = $json + [Environment]::NewLine
    if ((Test-Path -LiteralPath $resolved) -and [IO.File]::ReadAllText($resolved, [Text.Encoding]::UTF8) -eq $content) {
        return $resolved
    }

    [IO.File]::WriteAllText($temporary, $content, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $resolved -Force
    return $resolved
}

function Write-EventPages {
    param(
        [Parameter(Mandatory)] [array]$Events,
        [Parameter(Mandatory)] [string]$OutputPath,
        [Parameter(Mandatory)] [int]$PageSize
    )

    $directory = Split-Path -Parent ($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath))
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $pageCount = [Math]::Max(1, [int][Math]::Ceiling($Events.Count / [double]$PageSize))
    $written = [Collections.Generic.List[string]]::new()

    for ($page = 1; $page -le $pageCount; $page++) {
        $offset = ($page - 1) * $PageSize
        $pageEvents = @($Events | Select-Object -Skip $offset -First $PageSize)
        $pagePath = Join-Path $directory ("public-events-page-{0:D4}.json" -f $page)
        $payload = New-EventPagePayload -Events $pageEvents -Page $page -PageSize $PageSize -TotalEvents $Events.Count
        [void](Write-JsonAtomic -Path $pagePath -Value $payload)
        $written.Add($pagePath)
    }

    $keep = @{}
    foreach ($path in $written) {
        $keep[(Split-Path -Leaf $path)] = $true
    }
    foreach ($stale in Get-ChildItem -LiteralPath $directory -Filter "public-events-page-*.json" -File | Where-Object { $_.Name -notlike "*.example.json" }) {
        if (-not $keep.ContainsKey($stale.Name)) {
            Remove-Item -LiteralPath $stale.FullName -Force
        }
    }

    return $written.ToArray()
}

$public = New-EventPayload -Events $events -TotalEvents $events.Count
$recent = New-EventPayload -Events $recentEvents -Recent $true -TotalEvents $events.Count
$index = New-EventIndexPayload -Events $events -PageSize $PageSize

$resolved = Write-JsonAtomic -Path $OutputPath -Value $public
$recentResolved = Write-JsonAtomic -Path $RecentOutputPath -Value $recent
$pageResolved = @(Write-EventPages -Events $events -OutputPath $OutputPath -PageSize $PageSize)
$indexResolved = Write-JsonAtomic -Path $IndexOutputPath -Value $index
$v6Manifest = Write-V6Generation -Events $events -SourcePayload $source
Write-SyncState -State ([ordered]@{
    remotePath = $remotePath
    remoteRecentPath = $remoteRecentPath
    remoteRevision = [string]$source.revision
    recentRevision = [string]$recent.revision
    remoteProjectionRevision = if ((Get-ProjectionRevision -Payload $source) -ge 0) { Get-ProjectionRevision -Payload $source } else { $null }
    recentProjectionRevision = if ((Get-ProjectionRevision -Payload $source) -ge 0) { Get-ProjectionRevision -Payload $source } else { $null }
    remoteProvenanceRevision = if (Get-OptionalProperty $source "provenanceRevision") { [string](Get-OptionalProperty $source "provenanceRevision") } else { $null }
    recentProvenanceRevision = if (Get-OptionalProperty $source "provenanceRevision") { [string](Get-OptionalProperty $source "provenanceRevision") } else { $null }
    localRecentRevision = [string]$recent.revision
    remoteUpdatedAt = [string]$source.updatedAt
    remoteEvents = [int]$events.Count
    remoteMaxId = Get-EventsMaxId -Events $events
    pageSize = $PageSize
    recentEventLimit = $RecentEventLimit
    pageCount = $pageResolved.Count
    v6GenerationId = [string]$v6Manifest.generationId
    v6IncrementalChanged = $false
    v6IncrementalSyncedAt = $null
    requiresReprojection = $false
    reprojectionReason = $null
    syncedAt = (Get-Date).ToString("o")
    fullSyncedAt = (Get-Date).ToString("o")
    fastSyncedAt = (Get-Date).ToString("o")
})
Write-Host "Historique public synchronisé vers $resolved"
Write-Host "Flux récent synchronisé vers $recentResolved"
Write-Host "Index paginé synchronisé vers $indexResolved"
Write-Host "$($pageResolved.Count) page(s) d'échos synchronisée(s)"
}
finally {
    Close-EventSyncLock
}
