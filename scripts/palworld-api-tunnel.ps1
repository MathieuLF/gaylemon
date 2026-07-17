param(
    [ValidateSet("status", "start", "stop")]
    [string]$Action = "status",

    [int]$LocalPort = 0,

    [int]$RemotePort = 0,

    [string]$SshHost = "",

    [string]$SshDirectory = "",

    [AllowEmptyString()]
    [ValidateSet("", "docker", "windows-ssh")]
    [string]$Mode = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot
if ($LocalPort -le 0) { $LocalPort = $config.ApiLocalPort }
if ($RemotePort -le 0) { $RemotePort = $config.ApiRemotePort }
if (-not $SshHost) { $SshHost = $config.SshAlias }
if (-not $SshDirectory) { $SshDirectory = $config.SshDirectory }
if (-not $Mode) { $Mode = $config.ApiTunnelMode }
$SshDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SshDirectory)

$runtimeDirectory = Join-Path $ProjectRoot "runtime"
New-Item -ItemType Directory -Path $runtimeDirectory -Force | Out-Null
$PidFile = Join-Path $runtimeDirectory "palworld-api-tunnel.pid"
$ForwardSpec = "127.0.0.1:${LocalPort}:127.0.0.1:${RemotePort}"
$ComposeServiceName = "palworld-api-tunnel"
$ContainerName = "gaylemon-palworld-api-tunnel"

function Assert-TunnelPort {
    param(
        [string]$Name,
        [int]$Port
    )

    if ($Port -lt 1 -or $Port -gt 65535) {
        throw "$Name doit etre un port TCP entre 1 et 65535. Valeur recue: $Port."
    }
}

function Assert-SshAlias {
    param([string]$Alias)

    if ([string]::IsNullOrWhiteSpace($Alias) -or $Alias -notmatch '^[A-Za-z0-9._@:-]+$' -or $Alias.StartsWith("-")) {
        throw "Alias SSH invalide pour le tunnel API. Utiliser un alias simple de config SSH, par exemple 'palworld'."
    }
}

Assert-TunnelPort "LocalPort" $LocalPort
Assert-TunnelPort "RemotePort" $RemotePort
Assert-SshAlias $SshHost

function Write-Title {
    param([string]$Text)

    Write-Host ""
    Write-Host "[API] $Text" -ForegroundColor Cyan
    Write-Host ("-" * ([Math]::Min(60, [Math]::Max(16, $Text.Length + 6)))) -ForegroundColor DarkCyan
}

function Test-LocalTcpPort {
    param(
        [string]$HostName = "127.0.0.1",
        [int]$Port
    )

    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $async = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne(1000, $false)) {
            return $false
        }

        $client.EndConnect($async)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Close()
    }
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

function Get-SshCommand {
    $ssh = Get-Command ssh.exe -ErrorAction SilentlyContinue
    if (-not $ssh) { $ssh = Get-Command ssh -ErrorAction SilentlyContinue }
    if (-not $ssh) {
        throw "Client SSH introuvable."
    }

    return $ssh.Source
}

function Invoke-TunnelCompose {
    param([string[]]$Arguments)

    $previousLocalPort = $env:GAYLEMON_API_LOCAL_PORT
    $previousRemotePort = $env:GAYLEMON_API_REMOTE_PORT
    $previousSshAlias = $env:GAYLEMON_SSH_ALIAS
    $previousSshDirectory = $env:GAYLEMON_SSH_DIR
    $env:GAYLEMON_API_LOCAL_PORT = [string]$LocalPort
    $env:GAYLEMON_API_REMOTE_PORT = [string]$RemotePort
    $env:GAYLEMON_SSH_ALIAS = $SshHost
    $env:GAYLEMON_SSH_DIR = $SshDirectory

    try {
        & docker compose --project-directory $ProjectRoot @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "docker compose $($Arguments -join ' ') a echoue avec le code $LASTEXITCODE."
        }
    }
    finally {
        if ($null -eq $previousLocalPort) {
            Remove-Item Env:\GAYLEMON_API_LOCAL_PORT -ErrorAction SilentlyContinue
        }
        else {
            $env:GAYLEMON_API_LOCAL_PORT = $previousLocalPort
        }

        if ($null -eq $previousRemotePort) {
            Remove-Item Env:\GAYLEMON_API_REMOTE_PORT -ErrorAction SilentlyContinue
        }
        else {
            $env:GAYLEMON_API_REMOTE_PORT = $previousRemotePort
        }

        if ($null -eq $previousSshAlias) {
            Remove-Item Env:\GAYLEMON_SSH_ALIAS -ErrorAction SilentlyContinue
        }
        else {
            $env:GAYLEMON_SSH_ALIAS = $previousSshAlias
        }

        if ($null -eq $previousSshDirectory) {
            Remove-Item Env:\GAYLEMON_SSH_DIR -ErrorAction SilentlyContinue
        }
        else {
            $env:GAYLEMON_SSH_DIR = $previousSshDirectory
        }
    }
}

function Stop-DockerTunnelContainer {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        return
    }

    try {
        & docker info *> $null
        if ($LASTEXITCODE -eq 0) {
            Invoke-TunnelCompose -Arguments @("stop", $ComposeServiceName)
        }
    }
    catch {
        Write-Host "WARN Arret du tunnel Docker ignore: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Get-TunnelContainerLine {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        return $null
    }

    $line = & docker ps -a --filter "name=$ContainerName" --format "{{.Names}}|{{.Status}}|{{.Ports}}" 2>$null |
        Where-Object { ($_ -split "\|", 2)[0] -eq $ContainerName } |
        Select-Object -First 1
    return $line
}

function Get-TunnelRestartPolicy {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        return ""
    }

    $policy = (& docker inspect $ContainerName --format "{{.HostConfig.RestartPolicy.Name}}" 2>$null | Select-Object -First 1)
    return [string]$policy
}

function Get-LegacyTunnelProcesses {
    Get-CimInstance Win32_Process -Filter "Name = 'ssh.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine.Contains($ForwardSpec) -and
            $_.CommandLine -match "(^|\s)$([regex]::Escape($SshHost))(\s|$)"
        }
}

function Stop-LegacyTunnelProcesses {
    $processes = @(Get-LegacyTunnelProcesses)

    if ($processes.Count -eq 0 -and (Test-Path -LiteralPath $PidFile)) {
        $pidValue = (Get-Content -LiteralPath $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($pidValue -as [int]) {
            $process = Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue
            if ($process -and $process.ProcessName -eq "ssh") {
                $processes = @($process | ForEach-Object {
                    [pscustomobject]@{
                        ProcessId = $_.Id
                    }
                })
            }
        }
    }

    foreach ($process in $processes) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Host "OK Ancien processus SSH Windows arrete: $($process.ProcessId)" -ForegroundColor Green
    }

    Remove-Item -LiteralPath $PidFile -ErrorAction SilentlyContinue
}

function Show-TunnelStatus {
    Write-Title "Tunnel API Palworld"

    $containerLine = Get-TunnelContainerLine
    if ($containerLine) {
        $parts = $containerLine -split "\|", 3
        $dockerColor = if ($parts.Count -gt 1 -and $parts[1] -like "Up*") { "Green" } else { "Yellow" }
        $dockerPrefix = if ($dockerColor -eq "Green") { "OK" } else { "WARN" }
        Write-Host "$dockerPrefix Conteneur Docker: $($parts[0])" -ForegroundColor $dockerColor
        if ($parts.Count -gt 1) {
            Write-Host "Etat: $($parts[1])"
        }
        if ($parts.Count -gt 2 -and $parts[2]) {
            Write-Host "Ports: $($parts[2])"
        }

        $restartPolicy = Get-TunnelRestartPolicy
        if ($restartPolicy) {
            Write-Host "Relance Docker: $restartPolicy"
        }
    }
    elseif (Get-Command docker -ErrorAction SilentlyContinue) {
        Write-Host "WARN Conteneur Docker: non cree" -ForegroundColor Yellow
    }
    else {
        Write-Host "WARN Docker CLI: introuvable" -ForegroundColor Yellow
    }

    $legacyProcesses = @(Get-LegacyTunnelProcesses)
    if ($legacyProcesses.Count -gt 0) {
        $ids = ($legacyProcesses | ForEach-Object { $_.ProcessId }) -join ", "
        Write-Host "OK Tunnel SSH Windows actif: $ids" -ForegroundColor Green
    }

    if (Test-Path -LiteralPath $SshDirectory -PathType Container) {
        Write-Host "OK Dossier SSH source: $SshDirectory" -ForegroundColor Green
    }
    else {
        Write-Host "WARN Dossier SSH source introuvable: $SshDirectory" -ForegroundColor Yellow
    }

    if (Test-LocalTcpPort -Port $LocalPort) {
        Write-Host "OK Port local 127.0.0.1:${LocalPort}: ouvert" -ForegroundColor Green
        Write-Host "URL REST locale: http://127.0.0.1:${LocalPort}/v1/api" -ForegroundColor Cyan
    }
    else {
        Write-Host "WARN Port local 127.0.0.1:${LocalPort}: ferme" -ForegroundColor Yellow
    }
}

function Start-Tunnel {
    if ($Mode -eq "windows-ssh") {
        Start-WindowsSshTunnel
        return
    }

    Start-DockerTunnel
}

function Start-DockerTunnel {
    Write-Title "Demarrage du tunnel API Palworld via Docker"

    Start-DockerDesktopIfAvailable
    Wait-DockerEngine
    if (-not (Test-Path -LiteralPath $SshDirectory -PathType Container)) {
        throw "Dossier SSH introuvable pour le tunnel API: $SshDirectory"
    }
    Stop-LegacyTunnelProcesses

    Invoke-TunnelCompose -Arguments @("up", "-d", "--build", $ComposeServiceName)

    Start-Sleep -Seconds 2
    Show-TunnelStatus
}

function Start-WindowsSshTunnel {
    Write-Title "Demarrage du tunnel API Palworld via SSH Windows"

    $sshPath = Get-SshCommand
    Stop-DockerTunnelContainer
    Stop-LegacyTunnelProcesses

    $stdoutPath = Join-Path $runtimeDirectory "palworld-api-tunnel-windows.out.log"
    $stderrPath = Join-Path $runtimeDirectory "palworld-api-tunnel-windows.err.log"
    Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue

    $arguments = @(
        "-N",
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=15",
        "-o", "ExitOnForwardFailure=yes",
        "-o", "ForwardAgent=no",
        "-o", "ForwardX11=no",
        "-o", "PermitLocalCommand=no",
        "-o", "ServerAliveInterval=30",
        "-o", "ServerAliveCountMax=3",
        "-L", $ForwardSpec,
        $SshHost
    )

    $process = Start-Process -FilePath $sshPath `
        -ArgumentList $arguments `
        -WindowStyle Hidden `
        -PassThru `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath

    Set-Content -LiteralPath $PidFile -Value ([string]$process.Id) -Encoding ASCII

    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 500
        if ($process.HasExited) {
            break
        }
        if (Test-LocalTcpPort -Port $LocalPort) {
            $ready = $true
            break
        }
    }

    if (-not $ready) {
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
        $errorTail = ""
        if (Test-Path -LiteralPath $stderrPath) {
            $errorTail = (Get-Content -LiteralPath $stderrPath -Tail 6 -ErrorAction SilentlyContinue | Out-String).Trim()
        }
        if ($errorTail) {
            throw "Tunnel SSH Windows non disponible: $errorTail"
        }
        throw "Tunnel SSH Windows non disponible."
    }

    Write-Host "OK Tunnel SSH Windows demarre, PID $($process.Id)" -ForegroundColor Green
    Show-TunnelStatus
}

function Stop-Tunnel {
    Write-Title "Arret du tunnel API Palworld"

    if (Get-Command docker -ErrorAction SilentlyContinue) {
        try {
            Stop-DockerTunnelContainer
        }
        catch {
            Write-Host "WARN Arret Docker impossible: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    Stop-LegacyTunnelProcesses
    Show-TunnelStatus
}

switch ($Action) {
    "status" { Show-TunnelStatus }
    "start" { Start-Tunnel }
    "stop" { Stop-Tunnel }
}
