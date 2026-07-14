$ErrorActionPreference = "Continue"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot
$LogDirectory = Join-Path $ProjectRoot "portal\data"
$LogPath = Join-Path $LogDirectory "local-services.log"

New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null

function Write-LocalLog {
    param([string]$Message)

    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    Write-Host $line
}

Write-LocalLog "Arret des services locaux Gaylemon."

try {
    & (Join-Path $PSScriptRoot "palworld-api-tunnel.ps1") stop | ForEach-Object {
        Write-LocalLog $_
    }
}
catch {
    Write-LocalLog "Echec de l'arret du tunnel API: $($_.Exception.Message)"
}

try {
    & (Join-Path $PSScriptRoot "stop-microsite-metrics.ps1") | ForEach-Object {
        Write-LocalLog $_
    }
}
catch {
    Write-LocalLog "Echec de l'arret des metriques du microsite: $($_.Exception.Message)"
}

try {
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        $previousPort = $env:GAYLEMON_MICROSITE_PORT
        $env:GAYLEMON_MICROSITE_PORT = [string]$config.MicrositePort

        try {
            & docker compose --project-directory $ProjectRoot stop microsite 2>&1 | ForEach-Object {
                Write-LocalLog $_
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
    else {
        Write-LocalLog "Docker est introuvable; l'arret du microsite est ignore."
    }
}
catch {
    Write-LocalLog "Echec de l'arret du conteneur microsite: $($_.Exception.Message)"
}

try {
    $serverPidPath = Join-Path $LogDirectory "microsite-server.pid"
    $serverPids = @()

    if (Test-Path -LiteralPath $serverPidPath) {
        $pidValue = Get-Content -LiteralPath $serverPidPath -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pidValue -as [int]) {
            $serverPids += [int]$pidValue
        }
    }

    $httpProcesses = Get-CimInstance Win32_Process |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine.Contains("http.server") -and
            $_.CommandLine.Contains([string]$config.MicrositePort) -and
            $_.CommandLine.Contains("Gaylémon")
        }

    foreach ($process in $httpProcesses) {
        $serverPids += [int]$process.ProcessId
    }

    $serverPids = @($serverPids | Sort-Object -Unique)
    if ($serverPids.Count -eq 0) {
        Write-LocalLog "Aucun ancien processus HTTP du microsite n'a ete trouve."
    }
    else {
        foreach ($serverPid in $serverPids) {
            $process = Get-Process -Id $serverPid -ErrorAction SilentlyContinue
            if ($process) {
                Stop-Process -Id $serverPid -Force
                Write-LocalLog "Ancien processus HTTP du microsite arrete, PID $serverPid."
            }
        }
    }

    Remove-Item -LiteralPath $serverPidPath -Force -ErrorAction SilentlyContinue
}
catch {
    Write-LocalLog "Echec de l'arret de l'ancien serveur HTTP: $($_.Exception.Message)"
}

Write-LocalLog "Arret des services locaux Gaylemon termine."
