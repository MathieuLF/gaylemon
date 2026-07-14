param(
    [string]$TaskName = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot
if (-not $TaskName) { $TaskName = $config.StartupTaskName }

$StartupFolder = [Environment]::GetFolderPath("Startup")
$StartupLauncher = Join-Path $StartupFolder "$TaskName.cmd"

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "✅ Tâche planifiée supprimée: $TaskName" -ForegroundColor Green
}
else {
    Write-Host "ℹ️  Tâche planifiée introuvable: $TaskName" -ForegroundColor DarkGray
}

if (Test-Path -LiteralPath $StartupLauncher) {
    Remove-Item -LiteralPath $StartupLauncher -Force
    Write-Host "✅ Lanceur Startup supprimé: $StartupLauncher" -ForegroundColor Green
}
else {
    Write-Host "ℹ️  Lanceur Startup introuvable: $StartupLauncher" -ForegroundColor DarkGray
}
