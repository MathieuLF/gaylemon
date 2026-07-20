param(
    [int]$Port = 0,
    [int]$MetricIntervalSeconds = 0,
    [int]$EventSyncIntervalSeconds = 0,
    [int]$EventSyncTimeoutSeconds = 0,
    [int]$UpdateTimeoutSeconds = 0,
    [int]$SaveSnapshotSyncIntervalSeconds = 0,
    [int]$SaveSnapshotSyncTimeoutSeconds = 0,
    [string]$PublicUrl = "",
    [switch]$NoOpen
)

$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot
if ($Port -le 0) { $Port = $config.MicrositePort }
if ($MetricIntervalSeconds -le 0) { $MetricIntervalSeconds = $config.MetricIntervalSeconds }
if ($EventSyncIntervalSeconds -le 0) { $EventSyncIntervalSeconds = $config.EventSyncIntervalSeconds }
if ($EventSyncTimeoutSeconds -le 0) { $EventSyncTimeoutSeconds = $config.EventSyncTimeoutSeconds }
if ($UpdateTimeoutSeconds -le 0) { $UpdateTimeoutSeconds = $config.MetricUpdateTimeoutSeconds }
if ($SaveSnapshotSyncIntervalSeconds -le 0) { $SaveSnapshotSyncIntervalSeconds = $config.SaveSnapshotSyncIntervalSeconds }
if ($SaveSnapshotSyncTimeoutSeconds -le 0) { $SaveSnapshotSyncTimeoutSeconds = $config.SaveSnapshotSyncTimeoutSeconds }
if (-not $PublicUrl) { $PublicUrl = $config.MicrositePublicUrl }
$dataDirectory = Join-Path $ProjectRoot "portal\data"
$originUrl = "http://127.0.0.1:$Port/"

New-Item -ItemType Directory -Force -Path $dataDirectory | Out-Null

function Test-LocalSite {
    param([string]$TargetUrl)

    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $TargetUrl -TimeoutSec 2
        return $response.StatusCode -ge 200 -and $response.StatusCode -lt 500
    }
    catch {
        return $false
    }
}

function Get-PowerShellHost {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh) {
        return $pwsh.Source
    }

    return (Get-Command powershell -ErrorAction Stop).Source
}

function Open-InBrowser {
    param([string]$TargetUrl)

    foreach ($name in @("msedge", "chrome", "firefox")) {
        $browser = Get-Command $name -ErrorAction SilentlyContinue
        if ($browser) {
            Start-Process -FilePath $browser.Source -ArgumentList $TargetUrl | Out-Null
            return
        }
    }

    Start-Process $TargetUrl
}

function Start-DockerDesktopIfAvailable {
    $dockerDesktop = Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe"
    if (Test-Path -LiteralPath $dockerDesktop) {
        Start-Process -FilePath $dockerDesktop -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
    }
}

function Wait-DockerEngine {
    param([int]$TimeoutSeconds = 75)

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "Docker CLI introuvable. Installe ou demarre Docker Desktop."
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        & docker info *> $null
        if ($LASTEXITCODE -eq 0) {
            return
        }

        Start-Sleep -Seconds 3
    }

    throw "Docker Desktop ne repond pas apres $TimeoutSeconds secondes."
}

function Invoke-MicrositeCompose {
    param([string[]]$Arguments)

    $previousPort = $env:GAYLEMON_MICROSITE_PORT
    $env:GAYLEMON_MICROSITE_PORT = [string]$Port

    try {
        & docker compose --project-directory $ProjectRoot @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "docker compose $($Arguments -join ' ') a echoue avec le code $LASTEXITCODE."
        }
    }
    finally {
        if ($null -eq $previousPort) {
            Remove-Item Env:\GAYLEMON_MICROSITE_PORT -ErrorAction SilentlyContinue
        }
        else {
            $env:GAYLEMON_MICROSITE_PORT = $previousPort
        }
    }
}

function Stop-LegacyPythonMicrosite {
    $serverPidPath = Join-Path $dataDirectory "microsite-server.pid"
    $serverPids = @()

    if (Test-Path -LiteralPath $serverPidPath) {
        $pidValue = Get-Content -LiteralPath $serverPidPath -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pidValue -as [int]) {
            $serverPids += [int]$pidValue
        }
    }

    $httpProcesses = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine.Contains("http.server") -and
            $_.CommandLine.Contains([string]$Port) -and
            $_.CommandLine.Contains("Gay")
        }

    foreach ($process in $httpProcesses) {
        $serverPids += [int]$process.ProcessId
    }

    foreach ($serverPid in @($serverPids | Sort-Object -Unique)) {
        $process = Get-Process -Id $serverPid -ErrorAction SilentlyContinue
        if ($process) {
            Stop-Process -Id $serverPid -Force -ErrorAction SilentlyContinue
        }
    }

    Remove-Item -LiteralPath $serverPidPath -Force -ErrorAction SilentlyContinue
}

function Get-ActiveWatcherProcess {
    $pidPath = Join-Path $dataDirectory "metrics-watcher.pid"
    if (Test-Path -LiteralPath $pidPath) {
        $pidValue = Get-Content -LiteralPath $pidPath -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pidValue -as [int]) {
            $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$pidValue)" -ErrorAction SilentlyContinue
            if ($processInfo -and $processInfo.CommandLine -and $processInfo.CommandLine.Contains("watch-microsite-metrics.ps1")) {
                return $processInfo
            }
        }
    }

    return Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains("watch-microsite-metrics.ps1") } |
        Select-Object -First 1
}

& (Join-Path $PSScriptRoot "update-microsite-metrics.ps1") | Out-Null

try {
    & (Join-Path $PSScriptRoot "verify-microsite-recovery.ps1") -Trigger microsite-startup | Out-Null
}
catch {
    Write-Warning "L'audit de reprise initial sera retenté par le watcher: $($_.Exception.Message)"
    try {
        & (Join-Path $PSScriptRoot "sync-palworld-save-snapshot.ps1") | Out-Null
        Write-Host "Snapshot joueurs resynchronisé après l'audit de reprise incomplet."
    }
    catch {
        Write-Warning "Snapshot joueurs non resynchronisé au démarrage: $($_.Exception.Message)"
    }
}

$watcherScript = Join-Path $PSScriptRoot "watch-microsite-metrics.ps1"
$powerShellHost = Get-PowerShellHost
Start-Process -FilePath $powerShellHost -ArgumentList @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $watcherScript,
    "-IntervalSeconds",
    "$MetricIntervalSeconds",
    "-EventSyncIntervalSeconds",
    "$EventSyncIntervalSeconds",
    "-EventSyncTimeoutSeconds",
    "$EventSyncTimeoutSeconds",
    "-SaveSnapshotSyncIntervalSeconds",
    "$SaveSnapshotSyncIntervalSeconds",
    "-SaveSnapshotSyncTimeoutSeconds",
    "$SaveSnapshotSyncTimeoutSeconds",
    "-UpdateTimeoutSeconds",
    "$UpdateTimeoutSeconds"
) -WindowStyle Hidden | Out-Null

Start-Sleep -Milliseconds 500
$watcherProcess = Get-ActiveWatcherProcess
if ($watcherProcess) {
    Write-Host "Rafraichisseur local: actif, PID $($watcherProcess.ProcessId), métriques ${MetricIntervalSeconds}s, échos ${EventSyncIntervalSeconds}s, fiches ${SaveSnapshotSyncIntervalSeconds}s, delai ${UpdateTimeoutSeconds}s."
}
else {
    Write-Warning "Le rafraichisseur de metriques n'a pas pu etre confirme apres le demarrage."
}

Stop-LegacyPythonMicrosite
Start-DockerDesktopIfAvailable
Wait-DockerEngine
Invoke-MicrositeCompose -Arguments @("up", "-d", "microsite")

if (-not (Test-LocalSite -TargetUrl $originUrl)) {
    Start-Sleep -Milliseconds 900
}

if (-not (Test-LocalSite -TargetUrl $originUrl)) {
    throw "Le conteneur microsite a demarre, mais l'origine locale $originUrl ne repond pas."
}

Write-Host "Microsite public: $PublicUrl"

if (-not $NoOpen) {
    Open-InBrowser $PublicUrl
}
