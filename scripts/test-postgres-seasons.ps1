[CmdletBinding()]
param(
    [string]$Image = 'postgres:16-alpine',
    [int]$ReadyAttempts = 40
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Docker est requis pour les tests PostgreSQL multi-saisons.' }

$containerName = 'gaylemon-seasons-test-' + [guid]::NewGuid().ToString('N')
$password = [guid]::NewGuid().ToString('N')
$previousDatabaseURL = $env:GAYLEMON_TEST_DATABASE_URL
$containerID = $null
try {
    $containerID = (& docker run --detach --name $containerName --publish '127.0.0.1::5432' --env "POSTGRES_PASSWORD=$password" --env 'POSTGRES_DB=gaylemon_test' $Image).Trim()
    if ($LASTEXITCODE -ne 0 -or $containerID -notmatch '^[0-9a-f]{64}$') { throw 'Le conteneur PostgreSQL de test ne démarre pas.' }

    $publishedPort = (& docker port $containerName '5432/tcp').Trim()
    if ($LASTEXITCODE -ne 0 -or $publishedPort -notmatch ':(?<port>[0-9]+)$') { throw 'Le port PostgreSQL de test est indétectable.' }
    $port = $Matches['port']

    $consecutiveReady = 0
    foreach ($attempt in 1..$ReadyAttempts) {
        & docker exec $containerName pg_isready --username postgres --dbname gaylemon_test *> $null
        if ($LASTEXITCODE -eq 0) {
            $consecutiveReady++
            if ($consecutiveReady -ge 2) { break }
        } else {
            $consecutiveReady = 0
        }
        Start-Sleep -Milliseconds 500
    }
    if ($consecutiveReady -lt 2) { throw 'PostgreSQL de test demeure instable.' }

    $env:GAYLEMON_TEST_DATABASE_URL = "postgres://postgres:$password@127.0.0.1:$port/gaylemon_test?sslmode=disable"
    & go test -tags=integration ./internal/store ./internal/background -count=1 -v
    if ($LASTEXITCODE -ne 0) { throw 'Les tests PostgreSQL multi-saisons échouent.' }
}
finally {
    if ($null -eq $previousDatabaseURL) {
        Remove-Item Env:GAYLEMON_TEST_DATABASE_URL -ErrorAction SilentlyContinue
    } else {
        $env:GAYLEMON_TEST_DATABASE_URL = $previousDatabaseURL
    }
    if ($containerID) {
        $resolvedID = (& docker inspect --format '{{.Id}}' $containerName 2>$null).Trim()
        if ($resolvedID -eq $containerID) {
            & docker rm --force $containerName *> $null
        }
    }
}
