param(
    [string]$TaskName = "",
    [DayOfWeek]$Day = [DayOfWeek]::Monday,
    [datetime]$At = "09:00"
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $projectRoot
if (-not $TaskName) { $TaskName = $config.SaveToolsTaskName }
$runner = (Resolve-Path (Join-Path $PSScriptRoot "run-palworld-save-tools-maintenance.ps1")).Path
$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
$arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $runner

$action = New-ScheduledTaskAction -Execute $powershell -Argument $arguments -WorkingDirectory $projectRoot
$trigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek $Day -At $At
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 2) `
    -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal `
    -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive `
    -RunLevel Limited

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "Synchronise et teste le fork PalworldSaveTools sans redémarrer Palworld." `
    -Force | Out-Null

Write-Host "Tâche interne installée: $TaskName"
Write-Host "Horaire: $Day à $($At.ToString('HH:mm'))"
Write-Host "Test manuel: .\scripts\run-palworld-save-tools-maintenance.ps1"
