param(
    [string]$TaskName = ""
)

$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot
if (-not $TaskName) { $TaskName = $config.StartupTaskName }
$StartupScript = Join-Path $PSScriptRoot "start-local-services.ps1"
$PowerShellExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$Argument = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $StartupScript
$TaskRunCommand = '"{0}" {1}' -f $PowerShellExe, $Argument
$StartupFolder = [Environment]::GetFolderPath("Startup")
$StartupLauncher = Join-Path $StartupFolder "$TaskName.cmd"

$action = New-ScheduledTaskAction -Execute $PowerShellExe -Argument $Argument -WorkingDirectory $ProjectRoot
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 30) `
    -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

try {
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description "Demarre les services locaux Gaylemon a l'ouverture de session." `
        -Force `
        -ErrorAction Stop | Out-Null
}
catch {
    Write-Host "⚠️  Module ScheduledTasks refusé, essai avec schtasks.exe: $($_.Exception.Message)" -ForegroundColor Yellow

    & schtasks.exe /Create /TN $TaskName /SC ONLOGON /TR $TaskRunCommand /RL LIMITED /F | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Host "⚠️  schtasks.exe a échoué avec le code $LASTEXITCODE. Repli vers le dossier Startup utilisateur." -ForegroundColor Yellow

        $launcher = @"
@echo off
cd /d "$ProjectRoot"
start "" /min "$PowerShellExe" $Argument
"@

        Set-Content -LiteralPath $StartupLauncher -Value $launcher -Encoding Default
        Write-Host "✅ Lanceur Startup installé: $StartupLauncher" -ForegroundColor Green
        Write-Host "Il se lancera à l’ouverture de session Windows de l’utilisateur courant."
        exit 0
    }
}

Write-Host "✅ Tâche planifiée installée: $TaskName" -ForegroundColor Green
Write-Host "Elle se lancera à l’ouverture de session Windows pour $env:USERDOMAIN\$env:USERNAME."
Write-Host "Lancer maintenant: Start-ScheduledTask -TaskName `"$TaskName`""
