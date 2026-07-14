param(
    [string]$OutputPath = (Join-Path $PSScriptRoot "..\portal\data\public-events.json")
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
    "capture", "challenge", "quest", "loot", "adventure", "level", "progress", "camp"
)
$allowedSources = @("journal", "players", "save", "update")
$events = @($source.events | ForEach-Object {
    if ($allowedTypes -notcontains [string]$_.type) { return }
    if ($allowedSources -notcontains [string]$_.source) { return }
    [ordered]@{
        id = [long]$_.id
        occurredAt = [string]$_.occurredAt
        type = [string]$_.type
        player = if ($_.player) { [string]$_.player } else { $null }
        title = [string]$_.title
        message = [string]$_.message
        icon = if ($_.icon -and ([string]$_.icon).StartsWith("assets/game/icons/")) { [string]$_.icon } else { $null }
        source = [string]$_.source
    }
})

$public = [ordered]@{
    version = 2
    ok = $true
    revision = [string]$source.revision
    updatedAt = [string]$source.updatedAt
    summary = [ordered]@{
        events = $events.Count
        firstAt = if ($events.Count) { [string]$events[-1].occurredAt } else { $null }
        lastAt = if ($events.Count) { [string]$events[0].occurredAt } else { $null }
    }
    events = $events
}

$resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolved) | Out-Null
$json = $public | ConvertTo-Json -Depth 6 -Compress
[IO.File]::WriteAllText($resolved, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
Write-Host "Historique public synchronisé vers $OutputPath"
