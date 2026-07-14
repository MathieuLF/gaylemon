param(
    [ValidateSet("status", "start", "stop")]
    [string]$Action = "status",

    [int]$LocalPort = 0,

    [int]$RemotePort = 0,

    [string]$SshHost = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot
if ($LocalPort -le 0) { $LocalPort = $config.ApiLocalPort }
if ($RemotePort -le 0) { $RemotePort = $config.ApiRemotePort }
if (-not $SshHost) { $SshHost = $config.SshAlias }

$runtimeDirectory = Join-Path $ProjectRoot "runtime"
New-Item -ItemType Directory -Path $runtimeDirectory -Force | Out-Null
$PidFile = Join-Path $runtimeDirectory "palworld-api-tunnel.pid"
$ForwardSpec = "127.0.0.1:${LocalPort}:127.0.0.1:${RemotePort}"

function Write-Title {
    param([string]$Text)

    Write-Host ""
    Write-Host "🔌 $Text" -ForegroundColor Cyan
    Write-Host ("─" * ([Math]::Min(60, [Math]::Max(16, $Text.Length + 3)))) -ForegroundColor DarkCyan
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

function Get-TunnelProcesses {
    Get-CimInstance Win32_Process -Filter "Name = 'ssh.exe'" |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine.Contains($ForwardSpec) -and
            $_.CommandLine -match "(^|\s)$([regex]::Escape($SshHost))(\s|$)"
        }
}

function Show-TunnelStatus {
    Write-Title "Tunnel API Palworld"

    $processes = @(Get-TunnelProcesses)
    $isListening = Test-LocalTcpPort -Port $LocalPort

    if ($processes.Count -gt 0) {
        $ids = ($processes | ForEach-Object { $_.ProcessId }) -join ", "
        Write-Host "✅ Processus tunnel SSH: actif ($ids)" -ForegroundColor Green
    }
    else {
        Write-Host "⚠️  Processus tunnel SSH: non détecté" -ForegroundColor Yellow
    }

    if ($isListening) {
        Write-Host "✅ Port local 127.0.0.1:${LocalPort}: ouvert" -ForegroundColor Green
        Write-Host "🌐 URL REST locale: http://127.0.0.1:${LocalPort}/v1/api" -ForegroundColor Cyan
    }
    else {
        Write-Host "⚠️  Port local 127.0.0.1:${LocalPort}: fermé" -ForegroundColor Yellow
    }
}

function Start-Tunnel {
    Write-Title "Démarrage du tunnel API Palworld"

    $existing = @(Get-TunnelProcesses)
    if ($existing.Count -gt 0 -or (Test-LocalTcpPort -Port $LocalPort)) {
        Write-Host "⚠️  Le tunnel semble déjà actif. Aucun nouveau processus lancé." -ForegroundColor Yellow
        Show-TunnelStatus
        return
    }

    $sshArgs = @(
        "-N",
        "-L", $ForwardSpec,
        $SshHost
    )

    $process = Start-Process -FilePath "ssh.exe" -ArgumentList $sshArgs -WindowStyle Hidden -PassThru
    Set-Content -LiteralPath $PidFile -Value $process.Id -Encoding ASCII

    Start-Sleep -Seconds 1
    if (Test-LocalTcpPort -Port $LocalPort) {
        Write-Host "✅ Tunnel démarré." -ForegroundColor Green
        Write-Host "🌐 URL REST locale: http://127.0.0.1:${LocalPort}/v1/api" -ForegroundColor Cyan
        return
    }

    Write-Host "⚠️  Le processus SSH a été lancé, mais le port local ne répond pas encore." -ForegroundColor Yellow
    Write-Host "Relance le statut dans quelques secondes: .\scripts\palworld-api-tunnel.ps1 status"
}

function Stop-Tunnel {
    Write-Title "Arrêt du tunnel API Palworld"

    $processes = @(Get-TunnelProcesses)

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

    if ($processes.Count -eq 0) {
        Write-Host "⚠️  Aucun tunnel SSH détecté." -ForegroundColor Yellow
        Remove-Item -LiteralPath $PidFile -ErrorAction SilentlyContinue
        return
    }

    foreach ($process in $processes) {
        Stop-Process -Id $process.ProcessId -Force
        Write-Host "✅ Processus SSH arrêté: $($process.ProcessId)" -ForegroundColor Green
    }

    Remove-Item -LiteralPath $PidFile -ErrorAction SilentlyContinue
}

switch ($Action) {
    "status" { Show-TunnelStatus }
    "start" { Start-Tunnel }
    "stop" { Stop-Tunnel }
}
