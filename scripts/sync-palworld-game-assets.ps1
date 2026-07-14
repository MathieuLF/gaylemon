param(
    [string]$ParserRoot = (Join-Path $PSScriptRoot "..\vendor\PalworldSaveTools"),
    [string]$Destination = (Join-Path $PSScriptRoot "..\portal\assets\game")
)

$ErrorActionPreference = "Stop"
$SyncVersion = 2
$ParserRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ParserRoot)
$Destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
$resources = Join-Path $ParserRoot "resources"
if (-not (Test-Path -LiteralPath $resources)) {
    throw "Les ressources PalworldSaveTools sont absentes: $resources"
}

$commit = (& git -C $ParserRoot rev-parse HEAD | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($commit)) {
    throw "Impossible d'identifier la version locale de PalworldSaveTools."
}

$marker = Join-Path $Destination ".source-commit"
$markerValue = "$commit sync-v$SyncVersion"
$iconSource = Join-Path $resources "game_data\icons"
$iconDestination = Join-Path $Destination "icons"
$mapDestination = Join-Path $Destination "maps"
$iconDirectories = @(Get-ChildItem -LiteralPath $iconSource -Directory | Sort-Object Name)

function Test-VisualAssetsComplete {
    foreach ($directory in $iconDirectories) {
        $targetRoot = Join-Path $iconDestination $directory.Name
        if (-not (Test-Path -LiteralPath $targetRoot)) { return $false }
        foreach ($sourceFile in Get-ChildItem -LiteralPath $directory.FullName -File -Recurse) {
            $relative = [IO.Path]::GetRelativePath($directory.FullName, $sourceFile.FullName)
            $targetFile = Join-Path $targetRoot $relative
            if (-not (Test-Path -LiteralPath $targetFile)) { return $false }
            if ((Get-Item -LiteralPath $targetFile).Length -ne $sourceFile.Length) { return $false }
        }
    }
    return $true
}

if ((Test-Path -LiteralPath $marker) -and ((Get-Content -Raw $marker).Trim() -eq $markerValue) -and (Test-VisualAssetsComplete)) {
    (Get-Item -LiteralPath $marker).LastWriteTimeUtc = (Get-Date).ToUniversalTime()
    Write-Host "Ressources visuelles Palworld déjà à jour: $($commit.Substring(0, 12))"
    exit 0
}

New-Item -ItemType Directory -Force -Path $iconDestination, $mapDestination | Out-Null

foreach ($directory in $iconDirectories) {
    $source = $directory.FullName
    $target = Join-Path $iconDestination $directory.Name
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Copy-Item -Path (Join-Path $source "*") -Destination $target -Recurse -Force
}

Copy-Item -LiteralPath (Join-Path $resources "assets\maps\T_WorldMap.webp") -Destination $mapDestination -Force
Copy-Item -LiteralPath (Join-Path $resources "assets\maps\T_TreeMap.webp") -Destination $mapDestination -Force
if (-not (Test-VisualAssetsComplete)) {
    throw "La vérification d'intégrité des ressources visuelles a échoué."
}
[System.IO.File]::WriteAllText($marker, $markerValue + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
Write-Host "Ressources visuelles Palworld synchronisées: $($commit.Substring(0, 12))"
