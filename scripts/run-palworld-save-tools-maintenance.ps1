$ErrorActionPreference = "Stop"
$logPath = Join-Path $PSScriptRoot "..\portal\data\palworld-save-tools-maintenance.log"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $logPath) | Out-Null

try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $OutputEncoding = [Console]::OutputEncoding
}
catch {
    # Best effort for older PowerShell hosts.
}

function Write-MaintenanceLog([string]$Message) {
    $cleanMessage = [regex]::Replace($Message, "`e\[[0-9;]*m", "")
    $line = "[{0}] {1}" -f (Get-Date).ToString("o"), $cleanMessage
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
    Write-Host $line
}

function Get-PowerShellHost {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh) { return $pwsh.Source }
    return (Get-Command powershell.exe -ErrorAction Stop).Source
}

function Invoke-MaintenanceScript {
    param(
        [Parameter(Mandatory)] [string]$ScriptName,
        [string[]]$Arguments = @()
    )

    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    $runId = [Guid]::NewGuid().ToString("N")
    $stdoutPath = Join-Path ([IO.Path]::GetTempPath()) "gaylemon-save-tools-$runId.out.log"
    $stderrPath = Join-Path ([IO.Path]::GetTempPath()) "gaylemon-save-tools-$runId.err.log"
    $powerShellHost = Get-PowerShellHost
    $argumentList = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $scriptPath
    )
    $argumentList += $Arguments
    try {
        $process = Start-Process -FilePath $powerShellHost -ArgumentList $argumentList -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
        $process.WaitForExit()
        $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -ErrorAction SilentlyContinue } else { @() }
        $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -ErrorAction SilentlyContinue } else { @() }
        return [pscustomobject]@{
            ExitCode = [int]$process.ExitCode
            Output = @($stdout)
            ErrorOutput = @($stderr)
        }
    }
    finally {
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

try {
    Write-MaintenanceLog "Début de la vérification PalworldSaveTools."
    $report = Invoke-MaintenanceScript -ScriptName "report-palworld-save-tools-update.ps1"
    foreach ($line in @($report.Output + $report.ErrorOutput)) { Write-MaintenanceLog ([string]$line) }
    if ($report.ExitCode -ne 0) { throw "Le rapport PalworldSaveTools a retourné le code $($report.ExitCode)." }

    $result = Invoke-MaintenanceScript -ScriptName "check-palworld-save-tools.ps1" -Arguments @("-SyncFork", "-UpdateRemote")
    foreach ($line in @($result.Output + $result.ErrorOutput)) { Write-MaintenanceLog ([string]$line) }
    if ($result.ExitCode -ne 0) { throw "Le script de maintenance a retourné le code $($result.ExitCode)." }

    $snapshot = Invoke-MaintenanceScript -ScriptName "sync-palworld-save-snapshot.ps1"
    foreach ($line in @($snapshot.Output + $snapshot.ErrorOutput)) { Write-MaintenanceLog ([string]$line) }
    if ($snapshot.ExitCode -ne 0) { throw "La synchronisation du snapshot a retourné le code $($snapshot.ExitCode)." }
    Write-MaintenanceLog "Maintenance terminée avec succès."
}
catch {
    Write-MaintenanceLog "ÉCHEC: $($_.Exception.Message)"
    exit 1
}
