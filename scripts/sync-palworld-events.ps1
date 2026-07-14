param(
    [string]$OutputPath = (Join-Path $PSScriptRoot "..\portal\data\public-events.json"),
    [string]$RecentOutputPath = (Join-Path $PSScriptRoot "..\portal\data\public-events-recent.json")
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot
$remotePath = "$($config.RemoteProjectRoot)/runtime/public-events.json"
$raw = & ssh.exe $config.SshAlias "test -s '$remotePath' && base64 -w0 '$remotePath'" 2>$null
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
    "capture", "challenge", "quest", "loot", "adventure", "level", "progress", "camp",
    "craft", "build", "production", "hatch", "fishing", "research", "base", "repair"
)
$allowedSources = @("journal", "players", "save", "update")

function Get-OptionalProperty {
    param($Value, [string]$Name)

    if ($null -eq $Value) { return $null }
    if ($Value.PSObject.Properties.Name -notcontains $Name) { return $null }
    return $Value.$Name
}

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
    [ordered]@{
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
$events = Remove-DuplicateSessionFallbacks -Events $events

$recentEvents = @($events | Select-Object -First 250)

function New-EventPayload {
    param(
        [Parameter(Mandatory)] [array]$Events,
        [bool]$Recent = $false
    )

    $maxId = @($Events | ForEach-Object { [long]$_.id } | Measure-Object -Maximum).Maximum
    if ($null -eq $maxId) { $maxId = 0 }

    [ordered]@{
        version = 3
        ok = $true
        revision = "3:{0}:{1}" -f $Events.Count, $maxId
        updatedAt = [string]$source.updatedAt
        recent = $Recent
        summary = [ordered]@{
            events = $Events.Count
            firstAt = if ($Events.Count) { [string]$Events[-1].occurredAt } else { $null }
            lastAt = if ($Events.Count) { [string]$Events[0].occurredAt } else { $null }
        }
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
    [IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $resolved -Force
    return $resolved
}

$public = New-EventPayload -Events $events
$recent = New-EventPayload -Events $recentEvents -Recent $true

$resolved = Write-JsonAtomic -Path $OutputPath -Value $public
$recentResolved = Write-JsonAtomic -Path $RecentOutputPath -Value $recent
Write-Host "Historique public synchronisé vers $resolved"
Write-Host "Flux récent synchronisé vers $recentResolved"
