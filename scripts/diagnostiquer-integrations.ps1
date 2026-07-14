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

Write-Host "Diagnostic en lecture seule des integrations Gaylemon" -ForegroundColor Cyan
Write-Host "Uptime Kuma et cloudflared restent externes au projet." -ForegroundColor DarkGray
Write-Host ""

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

        $apiTunnel = (& $docker.Source ps --filter "name=gaylemon-palworld-api-tunnel" --format "{{.Names}}|{{.Status}}" 2>$null | Select-Object -First 1)
        if ($apiTunnel) {
            Add-DiagnosticResult "Tunnel API Docker" "ok" $apiTunnel
        }
        else {
            Add-DiagnosticResult "Tunnel API Docker" "warning" "conteneur non detecte; le bot Discord ne pourra pas lire l'API REST Palworld"
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

if ($SansReseau) {
    Add-DiagnosticResult "SSH Ubuntu" "skipped" "verification reseau desactivee"
    Add-DiagnosticResult "Microsite public" "skipped" "verification reseau desactivee"
    Add-DiagnosticResult "Uptime Kuma externe" "skipped" "verification reseau desactivee"
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

    if ($config.UptimeKumaBaseUrl) {
        $kumaUrl = "$($config.UptimeKumaBaseUrl)/api/status-page/$($config.UptimeKumaStatusSlug)"
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri $kumaUrl -TimeoutSec 8
            Add-DiagnosticResult "Uptime Kuma externe" "ok" "API publique HTTP $($response.StatusCode)"
        }
        catch {
            Add-DiagnosticResult "Uptime Kuma externe" "warning" "API publique inaccessible; aucun parametre Kuma n'a ete modifie"
        }
    }
    else {
        Add-DiagnosticResult "Uptime Kuma externe" "skipped" "URL locale non configuree"
    }
}

Write-Host ""
Write-Host "Diagnostic termine. Aucune integration externe n'a ete modifiee." -ForegroundColor Cyan
$results
