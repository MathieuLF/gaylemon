param(
    [switch]$SansVerificationDependances
)

$ErrorActionPreference = "Continue"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$results = [Collections.Generic.List[object]]::new()

function Invoke-MaintenanceCheck {
    param(
        [Parameter(Mandatory = $true)] [string]$Name,
        [Parameter(Mandatory = $true)] [scriptblock]$Command
    )

    Write-Host ""
    Write-Host "== $Name ==" -ForegroundColor Cyan
    $global:LASTEXITCODE = 0
    try {
        & $Command
        $code = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
        $results.Add([pscustomobject]@{ Check = $Name; Success = ($code -eq 0); ExitCode = $code })
    }
    catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        $results.Add([pscustomobject]@{ Check = $Name; Success = $false; ExitCode = 1 })
    }
}

Write-Host "Bilan de maintenance Gaylémon" -ForegroundColor Cyan
Write-Host "Lecture seule: aucun service, conteneur ou fichier actif ne sera modifié." -ForegroundColor DarkGray

Invoke-MaintenanceCheck "Validation du dépôt" {
    & (Join-Path $PSScriptRoot "valider-depot.ps1")
}
Invoke-MaintenanceCheck "Source Ubuntu active" {
    & (Join-Path $PSScriptRoot "auditer-source-ubuntu.ps1") `
        -Rapport (Join-Path $ProjectRoot "runtime\validation\source-ubuntu.json")
}
Invoke-MaintenanceCheck "Intégrations locales et externes" {
    & (Join-Path $PSScriptRoot "diagnostiquer-integrations.ps1")
}

if (-not $SansVerificationDependances) {
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        Invoke-MaintenanceCheck "PalworldSaveTools" {
            & (Join-Path $PSScriptRoot "check-palworld-save-tools.ps1") | Format-List
        }
    }
    else {
        Write-Host ""
        Write-Host "[IGNORÉ] PalworldSaveTools: gh absent." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "== Résumé ==" -ForegroundColor Cyan
$results | Select-Object Check,Success,ExitCode | Format-Table -AutoSize
$failed = @($results | Where-Object { -not $_.Success })
if ($failed.Count -gt 0) {
    Write-Host "$($failed.Count) contrôle(s) demandent une intervention." -ForegroundColor Red
    exit 1
}

Write-Host "Tous les contrôles de maintenance sont nominaux." -ForegroundColor Green
