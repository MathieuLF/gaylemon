param(
    [switch]$SansReseau
)

$ErrorActionPreference = "Continue"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot
$results = [Collections.Generic.List[object]]::new()

function Add-DiagnosticResult {
    param(
        [string]$Integration,
        [ValidateSet("ok", "warning", "skipped")] [string]$Status,
        [string]$Details
    )

    $results.Add([pscustomobject]@{
        Integration = $Integration
        Status = $Status
        Details = $Details
    })

    $color = if ($Status -eq "ok") { "Green" } elseif ($Status -eq "warning") { "Yellow" } else { "DarkGray" }
    Write-Host ("[{0}] {1}: {2}" -f $Status.ToUpperInvariant(), $Integration, $Details) -ForegroundColor $color
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

function Get-WindowsApiTunnelProcesses {
    $forwardSpec = "127.0.0.1:$($config.ApiLocalPort):127.0.0.1:$($config.ApiRemotePort)"
    return @(
        Get-CimInstance Win32_Process -Filter "Name = 'ssh.exe'" -ErrorAction SilentlyContinue |
            Where-Object {
                $_.CommandLine -and
                $_.CommandLine.Contains($forwardSpec) -and
                $_.CommandLine -match "(^|\s)$([regex]::Escape($config.SshAlias))(\s|$)"
            }
    )
}

function ConvertTo-IPv4Number {
    param([string]$Address)

    $bytes = [Net.IPAddress]::Parse($Address).GetAddressBytes()
    [array]::Reverse($bytes)
    return [BitConverter]::ToUInt32($bytes, 0)
}

function Test-IPv4InCidr {
    param(
        [string]$Address,
        [string]$Cidr
    )

    if ($Address -notmatch '^(?:\d{1,3}\.){3}\d{1,3}$' -or $Cidr -notmatch '^((?:\d{1,3}\.){3}\d{1,3})/(\d{1,2})$') {
        return $false
    }

    $prefix = [int]$Matches[2]
    if ($prefix -lt 0 -or $prefix -gt 32) {
        return $false
    }

    try {
        $addressNumber = ConvertTo-IPv4Number $Address
        $networkNumber = ConvertTo-IPv4Number $Matches[1]
    }
    catch {
        return $false
    }

    if ($prefix -eq 0) {
        return $true
    }

    $hostBits = 32 - $prefix
    $blockSize = [uint64]1 -shl $hostBits
    $addressBlock = [Math]::Floor([double]([uint64]$addressNumber) / [double]$blockSize)
    $networkBlock = [Math]::Floor([double]([uint64]$networkNumber) / [double]$blockSize)
    return ($addressBlock -eq $networkBlock)
}

Write-Host "Diagnostic en lecture seule des integrations Gaylemon" -ForegroundColor Cyan
Write-Host "cloudflared reste externe au projet; l'uptime Palworld est sonde par l'API REST locale." -ForegroundColor DarkGray
Write-Host ""

$windowsApiTunnelProcesses = @(Get-WindowsApiTunnelProcesses)

$docker = Get-Command docker -ErrorAction SilentlyContinue
if ($docker) {
    & $docker.Source info 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Add-DiagnosticResult "Docker Desktop" "ok" "moteur accessible"

        $microsite = (& $docker.Source ps --filter "name=$($config.DockerMicrositeContainer)" --format "{{.Names}}|{{.Status}}" 2>$null | Select-Object -First 1)
        if ($microsite) {
            Add-DiagnosticResult "Microsite Docker" "ok" $microsite
        }
        else {
            Add-DiagnosticResult "Microsite Docker" "warning" "conteneur non detecte; aucune action effectuee"
        }

        $apiTunnel = (& $docker.Source ps --filter "name=gaylemon-palworld-api-tunnel" --format "{{.Names}}|{{.Status}}|{{.Ports}}" 2>$null | Select-Object -First 1)
        if ($apiTunnel) {
            Add-DiagnosticResult "Tunnel API Docker" "ok" $apiTunnel

            $restartPolicy = (& $docker.Source inspect gaylemon-palworld-api-tunnel --format "{{.HostConfig.RestartPolicy.Name}}" 2>$null | Select-Object -First 1)
            $restartCountText = (& $docker.Source inspect gaylemon-palworld-api-tunnel --format "{{.RestartCount}}" 2>$null | Select-Object -First 1)
            $healthStatus = (& $docker.Source inspect gaylemon-palworld-api-tunnel --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}" 2>$null | Select-Object -First 1)
            $restartCount = 0
            [void][int]::TryParse($restartCountText, [ref]$restartCount)
            if ($restartPolicy -eq "unless-stopped") {
                Add-DiagnosticResult "Tunnel API relance" "ok" "restart: unless-stopped"
            }
            else {
                Add-DiagnosticResult "Tunnel API relance" "warning" "politique inattendue: $restartPolicy"
            }

            if ($restartCount -gt 3) {
                Add-DiagnosticResult "Tunnel API stabilite" "warning" "$restartCount redemarrages detectes; lire les logs Docker"
            }
            elseif ($healthStatus -eq "healthy") {
                Add-DiagnosticResult "Tunnel API stabilite" "ok" "healthcheck healthy"
            }
            elseif ($healthStatus -and $healthStatus -ne "none") {
                Add-DiagnosticResult "Tunnel API stabilite" "warning" "healthcheck $healthStatus"
            }

            if ($apiTunnel -like "*127.0.0.1:$($config.ApiLocalPort)->*") {
                Add-DiagnosticResult "Tunnel API exposition" "ok" "port publie seulement sur 127.0.0.1:$($config.ApiLocalPort)"
            }
            else {
                Add-DiagnosticResult "Tunnel API exposition" "warning" "verifier que le port n'est pas publie sur une interface publique"
            }
        }
        else {
            if ($windowsApiTunnelProcesses.Count -gt 0) {
                Add-DiagnosticResult "Tunnel API Docker" "skipped" "conteneur non actif; mode SSH Windows detecte"
            }
            else {
                Add-DiagnosticResult "Tunnel API Docker" "skipped" "conteneur non detecte; requis seulement pour annonces Discord ou repli local de l'API REST"
            }
        }

        if ($config.ServerLanIp) {
            $networkIds = @(& $docker.Source network ls -q 2>$null)
            if ($networkIds.Count -gt 0) {
                $networkLines = @(& $docker.Source network inspect $networkIds --format "{{.Name}}|{{range .IPAM.Config}}{{.Subnet}} {{end}}" 2>$null)
                $overlaps = [Collections.Generic.List[string]]::new()
                foreach ($line in $networkLines) {
                    $parts = $line -split "\|", 2
                    if ($parts.Count -lt 2) { continue }
                    foreach ($subnet in ($parts[1] -split "\s+")) {
                        if ($subnet -and (Test-IPv4InCidr $config.ServerLanIp $subnet)) {
                            $overlaps.Add("$($parts[0]) $subnet")
                        }
                    }
                }

                if ($overlaps.Count -gt 0) {
                    Add-DiagnosticResult "Routage Docker LAN" "warning" "bridge(s) recouvrant $($config.ServerLanIp): $($overlaps -join ', ')"
                }
                else {
                    Add-DiagnosticResult "Routage Docker LAN" "ok" "aucun bridge Docker ne recouvre $($config.ServerLanIp)"
                }
            }
        }

        $cloudflared = @(& $docker.Source ps --format "{{.Names}}|{{.Status}}" 2>$null | Where-Object { $_ -like "*$($config.CloudflaredContainerPattern)*" })
        if ($cloudflared.Count -gt 0) {
            Add-DiagnosticResult "cloudflared externe" "ok" ($cloudflared -join ", ")
        }
        else {
            Add-DiagnosticResult "cloudflared externe" "warning" "conteneur partage non detecte; il n'est pas gere par ce projet"
        }
    }
    else {
        Add-DiagnosticResult "Docker Desktop" "warning" "CLI presente, moteur indisponible"
    }
}
else {
    Add-DiagnosticResult "Docker Desktop" "warning" "CLI introuvable"
}

if ($windowsApiTunnelProcesses.Count -gt 0) {
    $ids = ($windowsApiTunnelProcesses | ForEach-Object { $_.ProcessId }) -join ", "
    Add-DiagnosticResult "Tunnel API SSH Windows" "ok" "processus actif: $ids"
}
else {
    Add-DiagnosticResult "Tunnel API SSH Windows" "skipped" "aucun processus actif"
}

if (Test-Path -LiteralPath $config.SshDirectory -PathType Container) {
    Add-DiagnosticResult "Dossier SSH tunnel" "ok" $config.SshDirectory
}
else {
    Add-DiagnosticResult "Dossier SSH tunnel" "warning" "introuvable: $($config.SshDirectory)"
}

$botEnvExamplePath = Join-Path $ProjectRoot "config\exemples\bot.env.example"
if (Test-Path -LiteralPath $botEnvExamplePath) {
    $botEnvExample = Get-Content -LiteralPath $botEnvExamplePath -Raw -Encoding UTF8
    if (
        $botEnvExample -match '(?m)^GAYLEMON_PUBLIC_BASE_URL=https://gaylemon\.mathieu\.pro/?$' -and
        $botEnvExample -match '(?m)^BOT_PALWORLD_REST_API_URL=$' -and
        $botEnvExample -match '(?m)^BOT_PALWORLD_REST_API_USERNAME=$' -and
        $botEnvExample -match '(?m)^BOT_PALWORLD_REST_API_PASSWORD=$'
    ) {
        Add-DiagnosticResult "Config bot Discord" "ok" "JSON publics par defaut; REST annonce optionnelle"
    }
    else {
        Add-DiagnosticResult "Config bot Discord" "warning" "exemple incomplet ou non conforme"
    }
}
else {
    Add-DiagnosticResult "Config bot Discord" "warning" "config/exemples/bot.env.example introuvable"
}

if (Test-LocalTcpPort -Port $config.ApiLocalPort) {
    try {
        $apiResponse = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$($config.ApiLocalPort)/v1/api/info" -TimeoutSec 5
        Add-DiagnosticResult "API REST locale annonces" "ok" "HTTP $($apiResponse.StatusCode) sans secret"
    }
    catch {
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            if ($statusCode -in @(401, 403)) {
                Add-DiagnosticResult "API REST locale annonces" "ok" "HTTP $statusCode attendu sans identifiants"
            }
            else {
                Add-DiagnosticResult "API REST locale annonces" "warning" "HTTP $statusCode inattendu"
            }
        }
        else {
            Add-DiagnosticResult "API REST locale annonces" "warning" "port ouvert, mais sonde HTTP en echec"
        }
    }
}
else {
    Add-DiagnosticResult "API REST locale annonces" "skipped" "port 127.0.0.1:$($config.ApiLocalPort) ferme; normal si les annonces bot sont desactivees"
}

if ($SansReseau) {
    Add-DiagnosticResult "SSH Ubuntu" "skipped" "verification reseau desactivee"
    Add-DiagnosticResult "Microsite public" "skipped" "verification reseau desactivee"
    Add-DiagnosticResult "Sonde uptime REST Palworld" "skipped" "verification reseau desactivee"
}
else {
    $ssh = Get-Command ssh.exe -ErrorAction SilentlyContinue
    if (-not $ssh) { $ssh = Get-Command ssh -ErrorAction SilentlyContinue }
    if ($ssh) {
        $sshOutput = (& $ssh.Source -o BatchMode=yes -o ConnectTimeout=5 $config.SshAlias "printf gaylemon-ok" 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and $sshOutput -eq "gaylemon-ok") {
            Add-DiagnosticResult "SSH Ubuntu" "ok" "alias '$($config.SshAlias)' accessible par cle"
        }
        else {
            Add-DiagnosticResult "SSH Ubuntu" "warning" "alias '$($config.SshAlias)' inaccessible sans interaction"
        }
    }
    else {
        Add-DiagnosticResult "SSH Ubuntu" "warning" "client SSH introuvable"
    }

    foreach ($target in @(
        [pscustomobject]@{ Name = "Origine microsite"; Url = $config.MicrositeOriginUrl },
        [pscustomobject]@{ Name = "Microsite public"; Url = $config.MicrositePublicUrl }
    )) {
        if (-not $target.Url) {
            Add-DiagnosticResult $target.Name "skipped" "URL non configuree"
            continue
        }
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri $target.Url -TimeoutSec 8
            Add-DiagnosticResult $target.Name "ok" "HTTP $($response.StatusCode) sur $($target.Url)"
        }
        catch {
            Add-DiagnosticResult $target.Name "warning" "indisponible sur $($target.Url)"
        }
    }

    try {
        $metricsRaw = & (Join-Path $PSScriptRoot "palworld-api.ps1") metrics 2>$null
        if ($LASTEXITCODE -ne 0) {
            Add-DiagnosticResult "Sonde uptime REST Palworld" "warning" "appel metrics refuse ou indisponible"
        }
        else {
            $metrics = (($metricsRaw | Out-String).Trim() | ConvertFrom-Json)
            Add-DiagnosticResult "Sonde uptime REST Palworld" "ok" ("metrics OK: {0}/{1} joueur(s), {2} FPS" -f $metrics.currentplayernum, $metrics.maxplayernum, $metrics.serverfps)
        }
    }
    catch {
        Add-DiagnosticResult "Sonde uptime REST Palworld" "warning" "metrics illisible: $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "Diagnostic termine. Aucune integration externe n'a ete modifiee." -ForegroundColor Cyan
$results
