param(
    [int]$IntervalSeconds = 20,
    [int]$EventSyncIntervalSeconds = 20,
    [int]$EventSyncTimeoutSeconds = 60,
    [int]$SaveSnapshotSyncIntervalSeconds = 60,
    [int]$SaveSnapshotSyncTimeoutSeconds = 180,
    [int]$UpdateTimeoutSeconds = 120
)

$ErrorActionPreference = "Continue"

$dataDirectory = Join-Path $PSScriptRoot "..\portal\data"
$pidPath = Join-Path $dataDirectory "metrics-watcher.pid"
$logPath = Join-Path $dataDirectory "metrics-watcher.log"
$recoveryAuditPending = $true
$nextRecoveryAuditAt = Get-Date
$saveSnapshotSyncProcess = $null
$saveSnapshotSyncOutputPath = $null
$saveSnapshotSyncErrorPath = $null
$saveSnapshotSyncStartedAt = $null
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
        [string]$ErrorPath,
        [string]$Label = "Child"
    )

    $interesting = "(?i)(warning|avertissement|failed|erreur|error|echou|échou)"
    if ($ErrorPath -and (Test-Path -LiteralPath $ErrorPath)) {
        Get-Content -LiteralPath $ErrorPath -ErrorAction SilentlyContinue |
            Where-Object { $_ -and $_.Trim() } |
            ForEach-Object { Write-WatcherLog "${Label} stderr: $_" }
    }

    if ($OutputPath -and (Test-Path -LiteralPath $OutputPath)) {
        Get-Content -LiteralPath $OutputPath -ErrorAction SilentlyContinue |
            Where-Object { $_ -and $_.Trim() -match $interesting } |
            ForEach-Object { Write-WatcherLog "${Label} output: $_" }
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
            $updateScript,
            "-SkipEvents"
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

function Invoke-EventHistorySync {
    $syncScript = Join-Path $PSScriptRoot "sync-palworld-events.ps1"
    $powerShellHost = Get-PowerShellHost
    $runId = [Guid]::NewGuid().ToString("N")
    $outputPath = Join-Path ([IO.Path]::GetTempPath()) "gaylemon-events-$runId.out.log"
    $errorPath = Join-Path ([IO.Path]::GetTempPath()) "gaylemon-events-$runId.err.log"

    try {
        $process = Start-Process -FilePath $powerShellHost -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            $syncScript,
            "-Fast"
        ) -WindowStyle Hidden -RedirectStandardOutput $outputPath -RedirectStandardError $errorPath -PassThru

        if (-not $process.WaitForExit([Math]::Max(15, $EventSyncTimeoutSeconds) * 1000)) {
            Stop-ProcessTree -RootPid $process.Id
            throw "Event history sync timed out after $EventSyncTimeoutSeconds seconds."
        }

        if ($process.ExitCode -ne 0) {
            throw "Event history sync failed with exit code $($process.ExitCode)."
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

function Clear-SaveSnapshotSyncProcess {
    if ($script:saveSnapshotSyncOutputPath -or $script:saveSnapshotSyncErrorPath) {
        Write-InterestingChildOutput -OutputPath $script:saveSnapshotSyncOutputPath -ErrorPath $script:saveSnapshotSyncErrorPath -Label "Save snapshot sync"
        Remove-Item -LiteralPath $script:saveSnapshotSyncOutputPath, $script:saveSnapshotSyncErrorPath -Force -ErrorAction SilentlyContinue
    }
    if ($script:saveSnapshotSyncProcess) {
        $script:saveSnapshotSyncProcess.Dispose()
    }
    $script:saveSnapshotSyncProcess = $null
    $script:saveSnapshotSyncOutputPath = $null
    $script:saveSnapshotSyncErrorPath = $null
    $script:saveSnapshotSyncStartedAt = $null
}

function Update-SaveSnapshotSync {
    param([datetime]$Now = (Get-Date))

    if (-not $script:saveSnapshotSyncProcess) {
        return
    }

    if (-not $script:saveSnapshotSyncProcess.HasExited) {
        $elapsedSeconds = if ($script:saveSnapshotSyncStartedAt) {
            ($Now - $script:saveSnapshotSyncStartedAt).TotalSeconds
        }
        else {
            0
        }
        if ($elapsedSeconds -ge [Math]::Max(60, $SaveSnapshotSyncTimeoutSeconds)) {
            Stop-ProcessTree -RootPid $script:saveSnapshotSyncProcess.Id
            Write-WatcherLog "Save snapshot sync timed out after $SaveSnapshotSyncTimeoutSeconds seconds."
            Clear-SaveSnapshotSyncProcess
        }
        return
    }

    if ($script:saveSnapshotSyncProcess.ExitCode -eq 0) {
        Write-WatcherLog "Save snapshot sync completed."
    }
    else {
        Write-WatcherLog "Save snapshot sync skipped: exit code $($script:saveSnapshotSyncProcess.ExitCode)."
    }
    Clear-SaveSnapshotSyncProcess
}

function Start-SaveSnapshotSync {
    $syncScript = Join-Path $PSScriptRoot "sync-palworld-save-snapshot.ps1"
    $powerShellHost = Get-PowerShellHost
    $runId = [Guid]::NewGuid().ToString("N")
    $script:saveSnapshotSyncOutputPath = Join-Path ([IO.Path]::GetTempPath()) "gaylemon-save-snapshot-$runId.out.log"
    $script:saveSnapshotSyncErrorPath = Join-Path ([IO.Path]::GetTempPath()) "gaylemon-save-snapshot-$runId.err.log"
    $script:saveSnapshotSyncStartedAt = Get-Date

    try {
        $script:saveSnapshotSyncProcess = Start-Process -FilePath $powerShellHost -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            $syncScript
        ) -WindowStyle Hidden -RedirectStandardOutput $script:saveSnapshotSyncOutputPath -RedirectStandardError $script:saveSnapshotSyncErrorPath -PassThru
        Write-WatcherLog "Save snapshot sync started."
    }
    catch {
        Write-WatcherLog "Save snapshot sync skipped: $($_.Exception.Message)"
        Clear-SaveSnapshotSyncProcess
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
Write-WatcherLog "Microsite watcher started. MetricsInterval=${IntervalSeconds}s EventSyncInterval=${EventSyncIntervalSeconds}s SaveSnapshotInterval=${SaveSnapshotSyncIntervalSeconds}s MetricsTimeout=${UpdateTimeoutSeconds}s EventSyncTimeout=${EventSyncTimeoutSeconds}s SaveSnapshotTimeout=${SaveSnapshotSyncTimeoutSeconds}s PID=$PID."

try {
    $nextEventSyncAt = Get-Date
    $nextSaveSnapshotSyncAt = Get-Date
    while ($true) {
        $now = Get-Date
        Update-SaveSnapshotSync -Now $now
        if (-not $saveSnapshotSyncProcess -and $now -ge $nextSaveSnapshotSyncAt) {
            Start-SaveSnapshotSync
            $nextSaveSnapshotSyncAt = (Get-Date).AddSeconds([Math]::Max(15, $SaveSnapshotSyncIntervalSeconds))
        }

        $eventSyncAttempted = $false
        if ((Get-Date) -ge $nextEventSyncAt) {
            $eventSyncAttempted = $true
            try {
                Invoke-EventHistorySync
                Write-WatcherLog "Event history sync completed."
                $nextEventSyncAt = (Get-Date).AddSeconds([Math]::Max(5, $EventSyncIntervalSeconds))
            }
            catch {
                Write-WatcherLog "Event history sync skipped: $($_.Exception.Message)"
                $nextEventSyncAt = (Get-Date).AddSeconds([Math]::Max(10, [Math]::Min(60, $EventSyncIntervalSeconds)))
            }
        }

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
            if ($eventSyncAttempted) {
                Start-Sleep -Seconds ([Math]::Max(5, $IntervalSeconds))
                continue
            }
            try {
                Invoke-EventHistorySync
                Write-WatcherLog "Event history sync completed after skipped metrics update."
                $nextEventSyncAt = (Get-Date).AddSeconds([Math]::Max(5, $EventSyncIntervalSeconds))
            }
            catch {
                Write-WatcherLog "Event history sync skipped after metrics failure: $($_.Exception.Message)"
            }
        }

        Start-Sleep -Seconds ([Math]::Max(5, $IntervalSeconds))
    }
}
finally {
    if ($saveSnapshotSyncProcess -and -not $saveSnapshotSyncProcess.HasExited) {
        Stop-ProcessTree -RootPid $saveSnapshotSyncProcess.Id
    }
    Clear-SaveSnapshotSyncProcess
    Write-WatcherLog "Metrics watcher stopped. PID=$PID."
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
}
