[CmdletBinding()]
param([switch]$Check)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$server = Get-Content -Raw -LiteralPath (Join-Path $root 'internal\web\server.go')
$matches = [regex]::Matches($server, 'HandleFunc\("(?<method>[A-Z]+) (?<path>[^"]+)"')
$routes = @(
    $matches |
        ForEach-Object { [pscustomobject][ordered]@{ method = $_.Groups['method'].Value; path = $_.Groups['path'].Value } } |
        Sort-Object -Property method, path
)
$requiredRoutes = @(
    'GET /',
    'GET /api/agent/v1/commands',
    'GET /api/public/events/v1',
    'GET /api/public/seasons/v1',
    'GET /api/public/site-state/v1',
    'GET /health/live',
    'GET /health/ready',
    'GET /ops',
    'GET /saisons/{slug}/api/public/events/v1',
    'GET /saisons/{slug}/data/{path...}',
    'GET /api/version',
    'GET /version',
    'POST /api/agent/v1/commands/{id}/ack',
    'POST /api/agent/v1/heartbeat',
    'POST /api/ingest/v1/batches',
    'POST /ops/api/commands',
    'POST /ops/api/seasons',
    'POST /ops/api/seasons/{id}/activate',
    'POST /ops/api/seasons/{id}/archive',
    'POST /ops/api/seasons/{id}/reopen'
)
if ($Check) {
    $routeKeys = @($routes | ForEach-Object { "$($_.method) $($_.path)" })
    $duplicates = @($routeKeys | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name)
    $missingRoutes = @($requiredRoutes | Where-Object { $_ -notin $routeKeys })
if ($routes.Count -ne 29) { throw "Inventaire de routes inattendu: $($routes.Count), attendu: 29." }
    if ($duplicates.Count -gt 0) { throw "Routes dupliquées: $($duplicates -join ', ')." }
    if ($missingRoutes.Count -gt 0) { throw "Routes contractuelles absentes: $($missingRoutes -join ', ')." }
}
[ordered]@{
    schema = 'suite.route-inventory.v2'
    application = 'gaylemon'
    count = $routes.Count
    routes = $routes
} | ConvertTo-Json -Depth 5
