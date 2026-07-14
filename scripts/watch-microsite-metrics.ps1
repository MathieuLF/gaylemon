param(
    [int]$IntervalSeconds = 60,
    [int]$UpdateTimeoutSeconds = 120
)

$ErrorActionPreference = "Continue"

$dataDirectory = Join-Path $PSScriptRoot "..\portal\data"
$pidPath = Join-Path $dataDirectory "metrics-watcher.pid"
$logPath = Join-Path $dataDirectory "metrics-watcher.log"
$recoveryAuditPending = $true
$nextRecoveryAuditAt = Get-Date
New-Item -ItemType Directory -Force -Path $dataDirectory | Out-Null

function Write-WatcherLog {
    param([string]$Message)

    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}

function Get-PowerShellHost {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh) {
        return $pwsh.Source
    }

    return (Get-Command powershell -ErrorAction Stop).Source
}

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

function Write-InterestingChildOutput {
    param(
        [string]$OutputPath,
        [string]$ErrorPath
    )

    $interesting = "(?i)(warning|avertissement|failed|erreur|error|echou|échou)"
    if ($ErrorPath -and (Test-Path -LiteralPath $ErrorPath)) {
        Get-Content -LiteralPath $ErrorPath -ErrorAction SilentlyContinue |
            Where-Object { $_ -and $_.Trim() } |
            ForEach-Object { Write-WatcherLog "Metrics update stderr: $_" }
    }

    if ($OutputPath -and (Test-Path -LiteralPath $OutputPath)) {
        Get-Content -LiteralPath $OutputPath -ErrorAction SilentlyContinue |
            Where-Object { $_ -and $_.Trim() -match $interesting } |
            ForEach-Object { Write-WatcherLog "Metrics update output: $_" }
    }
}

function Invoke-MetricsUpdate {
    $updateScript = Join-Path $PSScriptRoot "update-microsite-metrics.ps1"
    $powerShellHost = Get-PowerShellHost
    $runId = [Guid]::NewGuid().ToString("N")
    $outputPath = Join-Path ([IO.Path]::GetTempPath()) "gaylemon-metrics-$runId.out.log"
    $errorPath = Join-Path ([IO.Path]::GetTempPath()) "gaylemon-metrics-$runId.err.log"

    try {
        $process = Start-Process -FilePath $powerShellHost -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            $updateScript
        ) -WindowStyle Hidden -RedirectStandardOutput $outputPath -RedirectStandardError $errorPath -PassThru

        if (-not $process.WaitForExit([Math]::Max(5, $UpdateTimeoutSeconds) * 1000)) {
            Stop-ProcessTree -RootPid $process.Id
            throw "Metrics update timed out after $UpdateTimeoutSeconds seconds."
        }

        if ($process.ExitCode -ne 0) {
            throw "Metrics update failed with exit code $($process.ExitCode)."
        }
    }
    finally {
        Write-InterestingChildOutput -OutputPath $outputPath -ErrorPath $errorPath
        Remove-Item -LiteralPath $outputPath, $errorPath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-RecoveryAudit {
    $auditScript = Join-Path $PSScriptRoot "verify-microsite-recovery.ps1"
    $powerShellHost = Get-PowerShellHost
    $process = Start-Process -FilePath $powerShellHost -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $auditScript,
        "-Trigger",
        "watcher-retry"
    ) -WindowStyle Hidden -PassThru

    if (-not $process.WaitForExit(60000)) {
        Stop-ProcessTree -RootPid $process.Id
        throw "Recovery audit timed out after 60 seconds."
    }
    if ($process.ExitCode -ne 0) {
        throw "Recovery audit failed with exit code $($process.ExitCode)."
    }
}

if (Test-Path -LiteralPath $pidPath) {
    $existingPid = (Get-Content -LiteralPath $pidPath -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($existingPid -as [int]) {
        $existingProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$existingPid)" -ErrorAction SilentlyContinue
        if ($existingProcess -and $existingProcess.CommandLine -and $existingProcess.CommandLine.Contains("watch-microsite-metrics.ps1")) {
            exit 0
        }
    }
}

Set-Content -LiteralPath $pidPath -Value $PID -Encoding ASCII
Write-WatcherLog "Metrics watcher started. Interval=${IntervalSeconds}s Timeout=${UpdateTimeoutSeconds}s PID=$PID."

try {
    while ($true) {
        try {
            Invoke-MetricsUpdate
            Write-WatcherLog "Metrics update completed."
            if ($recoveryAuditPending -and (Get-Date) -ge $nextRecoveryAuditAt) {
                try {
                    Invoke-RecoveryAudit
                    $recoveryAuditPending = $false
                    Write-WatcherLog "Recovery audit completed."
                }
                catch {
                    $nextRecoveryAuditAt = (Get-Date).AddMinutes(1)
                    Write-WatcherLog "Recovery audit pending: $($_.Exception.Message)"
                }
            }
        }
        catch {
            Write-WatcherLog "Metrics update skipped: $($_.Exception.Message)"
        }

        Start-Sleep -Seconds ([Math]::Max(5, $IntervalSeconds))
    }
}
finally {
    Write-WatcherLog "Metrics watcher stopped. PID=$PID."
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
}
