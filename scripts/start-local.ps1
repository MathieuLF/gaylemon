[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)][int]$Port = 8080,
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$localRoot = Join-Path $projectRoot 'runtime/local'
foreach ($command in @('go', 'docker')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "$command est requis." }
}
New-Item -ItemType Directory -Path $localRoot -Force | Out-Null
$runRoot = Join-Path $localRoot ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runRoot | Out-Null
$containerName = 'gaylemon-local-' + [guid]::NewGuid().ToString('N')
$containerID = $null
$webProcess = $null
$previousEnvironment = @{}
$environment = @{
    GAYLEMON_WEB_LISTEN = "127.0.0.1:$Port"
    GAYLEMON_PUBLIC_BASE_URL = "http://127.0.0.1:$Port"
    GAYLEMON_PORTAL_ROOT = Join-Path $projectRoot 'portal'
    GAYLEMON_ASSET_ROOT = Join-Path $runRoot 'public-assets'
    GAYLEMON_ANALYTICS_BASE_URL = ''
    GAYLEMON_LEGACY_HOSTS = ''
    GAYLEMON_GITHUB_CLIENT_ID = ''
    GAYLEMON_GITHUB_CLIENT_SECRET = ''
    GAYLEMON_GITHUB_ALLOWED_USER_ID = '1'
}
Push-Location $projectRoot
try {
    # The generated keys only belong to this disposable local instance.
    foreach ($name in @('agent', 'response')) {
        & go run ./cmd/gaylemon keygen --private (Join-Path $runRoot "$name.key") | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'La préparation des clés locales a échoué.' }
    }
    $agentKey = [Convert]::FromBase64String((Get-Content -Raw -LiteralPath (Join-Path $runRoot 'agent.key')).Trim())
    $environment.GAYLEMON_AGENT_PUBLIC_KEYS = 'local-agent:' + [Convert]::ToBase64String($agentKey[32..63])
    $environment.GAYLEMON_RESPONSE_PRIVATE_KEY = (Get-Content -Raw -LiteralPath (Join-Path $runRoot 'response.key')).Trim()
    $password = [guid]::NewGuid().ToString('N')
    $containerID = (& docker run --detach --name $containerName --publish '127.0.0.1::5432' --env "POSTGRES_PASSWORD=$password" --env 'POSTGRES_DB=gaylemon_local' postgres:16-alpine).Trim()
    if ($LASTEXITCODE -ne 0 -or $containerID -notmatch '^[0-9a-f]{64}$') { throw 'PostgreSQL local ne démarre pas.' }
    $binding = (& docker port $containerName '5432/tcp').Trim()
    if ($LASTEXITCODE -ne 0 -or $binding -notmatch ':(?<port>[0-9]+)$') { throw 'Port PostgreSQL introuvable.' }
    $environment.GAYLEMON_DATABASE_URL = "postgres://postgres:$password@127.0.0.1:$($Matches['port'])/gaylemon_local?sslmode=disable"
    $ready = 0
    foreach ($attempt in 1..40) {
        & docker exec $containerName pg_isready --username postgres --dbname gaylemon_local *> $null
        if ($LASTEXITCODE -eq 0) { $ready++ } else { $ready = 0 }
        if ($ready -ge 2) { break }
        Start-Sleep -Milliseconds 500
    }
    if ($ready -lt 2) { throw 'PostgreSQL demeure indisponible.' }
    foreach ($entry in $environment.GetEnumerator()) {
        $previousEnvironment[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key, 'Process')
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }
    $binary = Join-Path $runRoot 'gaylemon-web.exe'
    & go build -o $binary ./cmd/gaylemon-web
    if ($LASTEXITCODE -ne 0) { throw 'La compilation du service a échoué.' }
    $webProcess = Start-Process -FilePath $binary -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runRoot 'web.log') -RedirectStandardError (Join-Path $runRoot 'web-error.log')
    $healthy = $false
    foreach ($attempt in 1..40) {
        if ($webProcess.HasExited) { throw "Le service s'est arrêté. Consulter $runRoot." }
        try { $healthy = (Invoke-WebRequest "http://127.0.0.1:$Port/health/ready" -TimeoutSec 2).StatusCode -eq 200 } catch { }
        if ($healthy) { break }
        Start-Sleep -Milliseconds 500
    }
    if (-not $healthy) { throw 'Le service local demeure indisponible.' }
    Write-Host "Gaylémon local : http://127.0.0.1:$Port — PostgreSQL temporaire, clés locales, OAuth désactivé."
    if ($Check) {
        $page = Invoke-WebRequest "http://127.0.0.1:$Port/offline.html"
        if ($page.Content -notmatch '/assets/styles\.[a-f0-9]+\.css' -or $page.Content -match '<style') { throw 'La page hors ligne ne respecte pas le contrat des actifs.' }
        Write-Host 'Démarrage et actifs vérifiés.'
    } else {
        Write-Host 'Ctrl+C arrête cette instance et retire son conteneur PostgreSQL.'
        while (-not $webProcess.HasExited) { Start-Sleep -Seconds 1 }
    }
}
finally {
    if ($webProcess -and -not $webProcess.HasExited) { Stop-Process -Id $webProcess.Id }
    foreach ($entry in $previousEnvironment.GetEnumerator()) { [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process') }
    if ($containerID) {
        $resolvedID = (& docker inspect --format '{{.Id}}' $containerName 2>$null).Trim()
        if ($resolvedID -eq $containerID) { & docker rm --force $containerName *> $null }
    }
    Pop-Location
}
