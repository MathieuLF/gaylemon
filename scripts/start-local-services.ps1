param(
    [int]$MicrositePort = 0,
    [int]$ApiLocalPort = 0,
    [int]$MetricIntervalSeconds = 0,
    [int]$EventSyncIntervalSeconds = 0,
    [int]$EventSyncTimeoutSeconds = 0,
    [int]$SaveSnapshotSyncIntervalSeconds = 0,
    [int]$SaveSnapshotSyncTimeoutSeconds = 0,
    [int]$UpdateTimeoutSeconds = 0
)

$ErrorActionPreference = "Continue"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot
if ($MicrositePort -le 0) { $MicrositePort = $config.MicrositePort }
if ($ApiLocalPort -le 0) { $ApiLocalPort = $config.ApiLocalPort }
if ($MetricIntervalSeconds -le 0) { $MetricIntervalSeconds = $config.MetricIntervalSeconds }
if ($EventSyncIntervalSeconds -le 0) { $EventSyncIntervalSeconds = $config.EventSyncIntervalSeconds }
if ($EventSyncTimeoutSeconds -le 0) { $EventSyncTimeoutSeconds = $config.EventSyncTimeoutSeconds }
if ($SaveSnapshotSyncIntervalSeconds -le 0) { $SaveSnapshotSyncIntervalSeconds = $config.SaveSnapshotSyncIntervalSeconds }
if ($SaveSnapshotSyncTimeoutSeconds -le 0) { $SaveSnapshotSyncTimeoutSeconds = $config.SaveSnapshotSyncTimeoutSeconds }
if ($UpdateTimeoutSeconds -le 0) { $UpdateTimeoutSeconds = $config.MetricUpdateTimeoutSeconds }
$LogDirectory = Join-Path $ProjectRoot "portal\data"
$LogPath = Join-Path $LogDirectory "local-services.log"

New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null

function Write-LocalLog {
    param([string]$Message)

    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    Write-Host $line
}

Write-LocalLog "Demarrage des services locaux Gaylemon."

try {
    & (Join-Path $PSScriptRoot "palworld-api-tunnel.ps1") start -LocalPort $ApiLocalPort | ForEach-Object {
        Write-LocalLog $_
    }
}
catch {
    Write-LocalLog "Echec du demarrage du tunnel API: $($_.Exception.Message)"
}

try {
    & (Join-Path $PSScriptRoot "open-microsite.ps1") `
        -Port $MicrositePort `
        -MetricIntervalSeconds $MetricIntervalSeconds `
        -EventSyncIntervalSeconds $EventSyncIntervalSeconds `
        -EventSyncTimeoutSeconds $EventSyncTimeoutSeconds `
        -SaveSnapshotSyncIntervalSeconds $SaveSnapshotSyncIntervalSeconds `
        -SaveSnapshotSyncTimeoutSeconds $SaveSnapshotSyncTimeoutSeconds `
        -UpdateTimeoutSeconds $UpdateTimeoutSeconds `
        -NoOpen | ForEach-Object {
        Write-LocalLog $_
    }
}
catch {
    Write-LocalLog "Echec du demarrage du microsite: $($_.Exception.Message)"
}

Write-LocalLog "Demarrage des services locaux Gaylemon termine."
