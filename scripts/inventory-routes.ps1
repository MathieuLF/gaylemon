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
if ($Check -and $routes.Count -lt 20) { throw "Inventaire de routes incomplet: $($routes.Count)." }
[ordered]@{
    schema = 'suite.route-inventory.v2'
    application = 'gaylemon'
    count = $routes.Count
    routes = $routes
} | ConvertTo-Json -Depth 5
