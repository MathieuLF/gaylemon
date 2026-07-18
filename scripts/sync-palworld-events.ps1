param(
    [string]$OutputPath = (Join-Path $PSScriptRoot "..\portal\data\public-events.json"),
    [string]$RecentOutputPath = (Join-Path $PSScriptRoot "..\portal\data\public-events-recent.json"),
    [string]$IndexOutputPath = (Join-Path $PSScriptRoot "..\portal\data\public-events-index.json"),
    [int]$PageSize = 250,
    [int]$RecentEventLimit = 2000,
    [string]$SyncStatePath = (Join-Path $PSScriptRoot "..\portal\data\public-events-sync-state.json"),
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
$ItemizedEventGroupWindowSeconds = 5 * 60
$remotePath = "$($config.RemoteProjectRoot)/runtime/public-events.json"
$remoteRecentPath = "$($config.RemoteProjectRoot)/runtime/public-events-recent.json"

function Get-OptionalProperty {
    param($Value, [string]$Name)

    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        if ($Value.Contains($Name)) { return $Value[$Name] }
        return $null
    }
    if ($Value.PSObject.Properties.Name -notcontains $Name) { return $null }
    return $Value.$Name
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
    if ($Value.PSObject.Properties.Name -contains $Name) {
        $Value.$Name = $PropertyValue
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
    if ($Value.PSObject.Properties.Name -notcontains $Name) { return $null }
    return $Value.$Name
}

function Write-SyncState {
    param([Parameter(Mandatory)] $State)

    $resolvedStatePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SyncStatePath)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedStatePath) | Out-Null
    $json = $State | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($resolvedStatePath, ($json.TrimEnd() + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
}

function Write-JsonAtomicEarly {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] $Value
    )

    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolved) | Out-Null
    $temporary = "$resolved.tmp"
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
    if ($summary -and $summary.PSObject.Properties.Name -contains "totalEvents" -and $null -ne $summary.totalEvents) {
        $eventCount = [int]$summary.totalEvents
    }
    elseif ($summary -and $summary.PSObject.Properties.Name -contains "events" -and $null -ne $summary.events) {
        $eventCount = [int]$summary.events
    }

    return [pscustomobject]@{
        revision = [string]$Payload.revision
        updatedAt = [string]$Payload.updatedAt
        events = $eventCount
        lastAt = if ($summary -and $summary.lastAt) { [string]$summary.lastAt } else { "" }
        mtime = 0
        size = 0
    }
}

function Read-RemoteEventProbe {
    param([Parameter(Mandatory)] [string]$Path)

    if ($PSVersionTable.PSVersion.Major -lt 6) {
        return ConvertTo-EventProbe -Payload (Read-RemoteJsonPayload -Path $Path)
    }

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
    "updatedAt": payload.get("updatedAt") or "",
    "events": summary.get("totalEvents") or summary.get("events") or 0,
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

function Test-LocalEventOutputsComplete {
    param([Parameter(Mandatory)] $State)

    foreach ($path in @($OutputPath, $RecentOutputPath, $IndexOutputPath)) {
        if (-not (Test-Path -LiteralPath $path)) { return $false }
    }
    $directory = Split-Path -Parent ($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath))
    if (-not (Test-Path -LiteralPath (Join-Path $directory "public-events-page-0001.json"))) {
        return $false
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
        reconciledReconnects = 0
    }
}

function Update-FastEventIndex {
    param(
        [Parameter(Mandatory)] $RecentPayload,
        [Parameter(Mandatory)] [array]$PageEvents,
        [Parameter(Mandatory)] [int]$TotalEvents,
        [Parameter(Mandatory)] [int]$MaxId
    )

    $existing = Read-JsonFile -Path $IndexOutputPath
    $pageCount = [Math]::Max(1, [int][Math]::Ceiling($TotalEvents / [double]$PageSize))
    $existingPages = @($existing.pages)
    $pages = @(
        for ($page = 1; $page -le $pageCount; $page++) {
            $current = $existingPages | Where-Object { [int]$_.page -eq $page } | Select-Object -First 1
            if ($page -eq 1) {
                [ordered]@{
                    page = 1
                    path = "data/public-events-page-0001.json"
                    events = $PageEvents.Count
                    firstAt = if ($PageEvents.Count) { [string]$PageEvents[-1].occurredAt } else { $null }
                    lastAt = if ($PageEvents.Count) { [string]$PageEvents[0].occurredAt } else { $null }
                }
            }
            elseif ($current) {
                [ordered]@{
                    page = [int]$current.page
                    path = [string]$current.path
                    events = [int]$current.events
                    firstAt = if ($current.firstAt) { [string]$current.firstAt } else { $null }
                    lastAt = if ($current.lastAt) { [string]$current.lastAt } else { $null }
                }
            }
            else {
                [ordered]@{
                    page = $page
                    path = "data/public-events-page-{0:D4}.json" -f $page
                    events = 0
                    firstAt = $null
                    lastAt = $null
                }
            }
        }
    )

    $summary = if ($existing -and $existing.summary) {
        [ordered]@{
            events = $TotalEvents
            totalEvents = $TotalEvents
            firstAt = if ($existing.summary.firstAt) { [string]$existing.summary.firstAt } else { $null }
            lastAt = if ($RecentPayload.summary.lastAt) { [string]$RecentPayload.summary.lastAt } else { $null }
            types = if ($existing.summary.types) { $existing.summary.types } else { [ordered]@{} }
            reconciledReconnects = if ($existing.summary.reconciledReconnects -ne $null) { [int]$existing.summary.reconciledReconnects } else { 0 }
        }
    }
    else {
        Get-FastEventSummary -Events $PageEvents -TotalEvents $TotalEvents
    }

    [ordered]@{
        version = $PublicEventVersion
        ok = $true
        revision = "{0}:{1}:{2}:pages:{3}:hot" -f $PublicEventVersion, $TotalEvents, $MaxId, $pageCount
        updatedAt = [string]$RecentPayload.updatedAt
        recent = $false
        truncated = $false
        pageSize = $PageSize
        summary = $summary
        facets = if ($existing -and $existing.facets) { $existing.facets } else { [ordered]@{ types = @(); players = @() } }
        pages = $pages
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
    $items = Merge-ItemizedPublicItems -Events $Events
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

    $bullets = Get-QuantityBullets -Items $items
    if ($bullets.Count -lt 1) {
        $bullets = Get-AggregatedEventBullets -Events $Events
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

function Merge-FastRecentEvents {
    param([Parameter(Mandatory)] $IncomingPayload)

    $incoming = Get-EventsArray -Payload $IncomingPayload
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
                @{ Expression = { if ($_.id -ne $null) { [long]$_.id } else { 0 } }; Descending = $true } |
            Select-Object -First $RecentEventLimit
    )
}

function Write-FastEventOutputs {
    param([Parameter(Mandatory)] $RecentPayload)

    $events = Merge-FastRecentEvents -IncomingPayload $RecentPayload
    $events = Remove-WorldDropBuildEvents -Events $events
    $events = Group-ItemizedPublicEvents -Events $events
    $pageEvents = @($events | Select-Object -First $PageSize)
    $existingIndex = Read-JsonFile -Path $IndexOutputPath
    $existingTotalEvents = 0
    if ($existingIndex -and $existingIndex.summary) {
        $existingTotalEvents = Convert-ToPositiveInt (Get-OptionalProperty $existingIndex.summary "events")
        if ($existingTotalEvents -le 0) {
            $existingTotalEvents = Convert-ToPositiveInt (Get-OptionalProperty $existingIndex.summary "totalEvents")
        }
    }
    $remoteTotalEvents = if ($RecentPayload.summary -and $RecentPayload.summary.totalEvents) {
        [int]$RecentPayload.summary.totalEvents
    }
    elseif ($RecentPayload.summary -and $RecentPayload.summary.events) {
        [int]$RecentPayload.summary.events
    }
    else {
        $events.Count
    }
    $totalEvents = if ($existingTotalEvents -gt 0) {
        [Math]::Max($existingTotalEvents, $events.Count)
    }
    else {
        $remoteTotalEvents
    }
    $maxId = Get-EventsMaxId -Events $events
    $hotRecentPayload = [ordered]@{
        version = $PublicEventVersion
        ok = $true
        revision = "{0}:{1}:{2}:hot" -f $PublicEventVersion, $events.Count, $maxId
        updatedAt = [string]$RecentPayload.updatedAt
        recent = $true
        truncated = [bool]$RecentPayload.truncated
        summary = Get-FastEventSummary -Events $events -TotalEvents $TotalEvents
        events = $events
    }
    $pagePayload = [ordered]@{
        version = $PublicEventVersion
        ok = $true
        revision = "{0}:{1}:{2}:page:1:hot" -f $PublicEventVersion, $TotalEvents, $MaxId
        updatedAt = [string]$RecentPayload.updatedAt
        recent = $false
        truncated = [bool]$RecentPayload.truncated
        page = 1
        pageSize = $PageSize
        summary = Get-FastEventSummary -Events $PageEvents -TotalEvents $TotalEvents
        events = $PageEvents
    }
    $indexPayload = Update-FastEventIndex -RecentPayload $hotRecentPayload -PageEvents $PageEvents -TotalEvents $TotalEvents -MaxId $MaxId
    $directory = Split-Path -Parent ($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath))
    $pagePath = Join-Path $directory "public-events-page-0001.json"

    [void](Write-JsonAtomicEarly -Path $RecentOutputPath -Value $hotRecentPayload)
    [void](Write-JsonAtomicEarly -Path $pagePath -Value $pagePayload)
    [void](Write-JsonAtomicEarly -Path $IndexOutputPath -Value $indexPayload)
    Write-SyncState -State ([ordered]@{
        remotePath = $remotePath
        remoteRecentPath = $remoteRecentPath
        remoteRevision = if ($syncState) { [string](Get-StateValue $syncState "remoteRevision") } else { "" }
        recentRevision = [string]$RecentPayload.revision
        localRecentRevision = [string]$hotRecentPayload.revision
        remoteUpdatedAt = [string]$RecentPayload.updatedAt
        remoteEvents = $TotalEvents
        remoteMaxId = $MaxId
        pageSize = $PageSize
        recentEventLimit = $RecentEventLimit
        pageCount = [Math]::Max(1, [int][Math]::Ceiling($TotalEvents / [double]$PageSize))
        fastSyncedAt = (Get-Date).ToString("o")
        fullSyncedAt = if ($syncState) { [string](Get-StateValue $syncState "fullSyncedAt") } else { $null }
    })
}

$remoteProbePath = if ($Fast) { $remoteRecentPath } else { $remotePath }
$remoteProbe = Read-RemoteEventProbe -Path $remoteProbePath
$syncState = Read-JsonFile -Path $SyncStatePath
if (-not $Force -and $syncState -and $remoteProbe.revision -and
    ((-not $Fast -and [string](Get-StateValue $syncState "remoteRevision") -eq [string]$remoteProbe.revision) -or
     ($Fast -and [string](Get-StateValue $syncState "recentRevision") -eq [string]$remoteProbe.revision)) -and
    [int](Get-StateValue $syncState "pageSize") -eq $PageSize -and
    [int](Get-StateValue $syncState "recentEventLimit") -eq $RecentEventLimit -and
    (Test-LocalEventOutputsComplete -State $syncState)) {
    Write-Host "Historique des échos déjà à jour: révision $($remoteProbe.revision), dernier événement $($remoteProbe.lastAt)."
    return
}

if ($Fast) {
    $recentSource = Read-RemoteJsonPayload -Path $remoteRecentPath
    Write-FastEventOutputs -RecentPayload $recentSource
    Write-Host "Flux rapide des échos synchronisé: révision $($recentSource.revision), dernier événement $($recentSource.summary.lastAt)."
    return
}

$raw = & ssh.exe -n -T -o BatchMode=yes -o ConnectTimeout=8 $config.SshAlias "test -s '$remotePath' && base64 -w0 '$remotePath'" 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "L'historique public distant n'est pas encore disponible: $remotePath"
}

$text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((($raw | Out-String).Trim())))
$source = $text | ConvertFrom-Json
if (-not $source.ok) {
    throw "L'historique public distant est invalide."
}

$allowedTypes = @(
    "join", "leave", "reconnect", "server", "maintenance", "discovery", "collection",
    "capture", "challenge", "quest", "loot", "adventure", "raid", "boss", "arena",
    "death", "recovery", "note", "pal", "mutation", "level", "progress", "camp",
    "craft", "build", "production", "hatch", "fishing", "research", "base", "repair"
)
$allowedSources = @("journal", "players", "save", "update")

function Convert-PublicDetails {
    param($Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -or $Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [bool]) {
        return $Value
    }
    if ($Value -is [array]) {
        return @($Value | Select-Object -First 50 | ForEach-Object { Convert-PublicDetails $_ } | Where-Object { $null -ne $_ })
    }
    if ($Value -is [pscustomobject]) {
        $result = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            if ($property.Name -match '(?i)uid|guid|instance|container|account|steam|password|token|dynamic_id') {
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
    $title = [string](Get-OptionalProperty $Event "title")
    $message = [string](Get-OptionalProperty $Event "message")
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

$events = @($source.events | ForEach-Object {
    Convert-PublicEvent $_
} | Where-Object { $null -ne $_ })
$events = Remove-WorldDropBuildEvents -Events $events
$events = Remove-DuplicateSessionFallbacks -Events $events
$events = Group-ItemizedPublicEvents -Events $events

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
        reconciledReconnects = 0
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

    [ordered]@{
        version = $PublicEventVersion
        ok = $true
        revision = "{0}:{1}:{2}" -f $PublicEventVersion, $Events.Count, $maxId
        updatedAt = [string]$source.updatedAt
        recent = $Recent
        truncated = $sourceTruncated
        summary = Get-EventSummary -Events $Events -TotalEvents $TotalEvents
        events = $Events
    }
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
        ok = $true
        revision = "{0}:{1}:{2}:pages:{3}" -f $PublicEventVersion, $Events.Count, $maxId, $pageCount
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
        ok = $true
        revision = "{0}:{1}:{2}:page:{3}" -f $PublicEventVersion, $TotalEvents, $maxId, $Page
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
    $temporary = "$resolved.tmp"
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
$indexResolved = Write-JsonAtomic -Path $IndexOutputPath -Value $index
$pageResolved = Write-EventPages -Events $events -OutputPath $OutputPath -PageSize $PageSize
Write-SyncState -State ([ordered]@{
    remotePath = $remotePath
    remoteRecentPath = $remoteRecentPath
    remoteRevision = [string]$source.revision
    recentRevision = [string]$recent.revision
    localRecentRevision = [string]$recent.revision
    remoteUpdatedAt = [string]$source.updatedAt
    remoteEvents = [int]$events.Count
    remoteMaxId = @($events | ForEach-Object { [long]$_.id } | Measure-Object -Maximum).Maximum
    pageSize = $PageSize
    recentEventLimit = $RecentEventLimit
    pageCount = $pageResolved.Count
    syncedAt = (Get-Date).ToString("o")
    fullSyncedAt = (Get-Date).ToString("o")
    fastSyncedAt = (Get-Date).ToString("o")
})
Write-Host "Historique public synchronisé vers $resolved"
Write-Host "Flux récent synchronisé vers $recentResolved"
Write-Host "Index paginé synchronisé vers $indexResolved"
Write-Host "$($pageResolved.Count) page(s) d'échos synchronisée(s)"
