$ErrorActionPreference = "Stop"
$logPath = Join-Path $PSScriptRoot "..\portal\data\palworld-save-tools-maintenance.log"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $logPath) | Out-Null

function Write-MaintenanceLog([string]$Message) {
    $line = "[{0}] {1}" -f (Get-Date).ToString("o"), $Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
    Write-Host $line
}

try {
    Write-MaintenanceLog "Début de la vérification PalworldSaveTools."
    $result = & (Join-Path $PSScriptRoot "check-palworld-save-tools.ps1") -SyncFork -UpdateRemote 2>&1
    foreach ($line in $result) { Write-MaintenanceLog ([string]$line) }
    if ($LASTEXITCODE -ne 0) { throw "Le script de maintenance a retourné le code $LASTEXITCODE." }
    & (Join-Path $PSScriptRoot "sync-palworld-save-snapshot.ps1") | Out-Null
    Write-MaintenanceLog "Maintenance terminée avec succès."
}
catch {
    Write-MaintenanceLog "ÉCHEC: $($_.Exception.Message)"
    exit 1
}

