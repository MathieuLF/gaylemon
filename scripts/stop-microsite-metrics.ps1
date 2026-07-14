$dataDirectory = Join-Path $PSScriptRoot "..\portal\data"
$pidPath = Join-Path $dataDirectory "metrics-watcher.pid"

function Stop-ProcessTree {
    param([int]$RootPid)

    $children = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.ParentProcessId -eq $RootPid })
    foreach ($child in $children) {
        Stop-ProcessTree -RootPid ([int]$child.ProcessId)
    }

    $process = Get-Process -Id $RootPid -ErrorAction SilentlyContinue
    if ($process) {
        Stop-Process -Id $RootPid -Force -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path -LiteralPath $pidPath)) {
    Write-Host "Aucun fichier PID du rafraichisseur de metriques."
}
else {
    $existingPid = Get-Content -LiteralPath $pidPath -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($existingPid -as [int]) {
        $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$existingPid)" -ErrorAction SilentlyContinue
        if ($processInfo -and $processInfo.CommandLine -and $processInfo.CommandLine.Contains("watch-microsite-metrics.ps1")) {
            Stop-ProcessTree -RootPid ([int]$existingPid)
            Write-Host "Rafraichisseur de metriques arrete, PID $existingPid."
        }
        elseif ($processInfo) {
            Write-Host "Le PID $existingPid existe, mais ce n'est pas le rafraichisseur. Rien n'a ete arrete."
        }
        else {
            Write-Host "Le rafraichisseur PID $existingPid ne tourne pas."
        }
    }
}

$staleChildren = @(Get-CimInstance Win32_Process -Filter "Name = 'ssh.exe'" -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -and (
        $_.CommandLine.Contains("/srv/storage/steam/servers/palworld/stats/stats.json") -or
        $_.CommandLine.Contains("/srv/storage/steam/bin/palworld-api.sh GET")
    )
})

foreach ($child in $staleChildren) {
    Stop-Process -Id ([int]$child.ProcessId) -Force -ErrorAction SilentlyContinue
    Write-Host "Sous-processus SSH Palworld arrete, PID $($child.ProcessId)."
}

Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
