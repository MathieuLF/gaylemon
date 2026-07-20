param(
    [switch]$SansDonneesExemple
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$envExample = Join-Path $ProjectRoot ".env.example"
$envLocal = Join-Path $ProjectRoot ".env"

if (-not (Test-Path -LiteralPath $envLocal)) {
    Copy-Item -LiteralPath $envExample -Destination $envLocal
    Write-Host "Configuration locale creee: .env" -ForegroundColor Green
}
else {
    Write-Host "Configuration locale conservee: .env" -ForegroundColor DarkGray
}

$directories = @(
    "config\local",
    "portal\assets\game",
    "portal\data\public-catalogs",
    "portal\data\public-daily",
    "portal\data\public-events-v6",
    "portal\data\players",
    "portal\joueur",
    "runtime\backups",
    "runtime\deploy",
    "runtime\logs",
    "runtime\recovery",
    "runtime\validation",
    "vendor"
)

foreach ($relativePath in $directories) {
    $path = Join-Path $ProjectRoot $relativePath
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        Write-Host "Repertoire cree: $relativePath" -ForegroundColor Green
    }
}

if (-not $SansDonneesExemple) {
    $dataDirectory = Join-Path $ProjectRoot "portal\data"
    foreach ($example in Get-ChildItem -LiteralPath $dataDirectory -Filter "*.example.json" -File) {
        $targetName = $example.Name.Replace(".example.json", ".json")
        $target = Join-Path $dataDirectory $targetName
        if (-not (Test-Path -LiteralPath $target)) {
            Copy-Item -LiteralPath $example.FullName -Destination $target
            Write-Host "Donnee de demonstration creee: portal/data/$targetName" -ForegroundColor Green
        }
    }
}

. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot

Write-Host ""
Write-Host "Initialisation terminee." -ForegroundColor Cyan
Write-Host "Configuration: $($config.EnvPath)"
Write-Host "Validation: .\scripts\valider-depot.ps1"
Write-Host "Diagnostic: .\scripts\diagnostiquer-integrations.ps1"
Write-Host "Console: .\Gaylemon Ops Console.ps1"
