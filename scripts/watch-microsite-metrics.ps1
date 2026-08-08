param(
    [int]$IntervalSeconds = 20,
    [int]$EventSyncIntervalSeconds = 20,
    [int]$EventSyncTimeoutSeconds = 60,
    [int]$FullEventSyncIntervalSeconds = 900,
    [int]$FullEventSyncTimeoutSeconds = 240,
    [int]$SaveSnapshotSyncIntervalSeconds = 45,
    [int]$SaveSnapshotSyncTimeoutSeconds = 180,
    [int]$UpdateTimeoutSeconds = 120,
    [int]$RecoveryAuditRetrySeconds = 300,
    [int]$MaxSaveSnapshotBackoffSeconds = 900,
    [int]$MaxEventSyncBackoffSeconds = 300,
    [int]$MaxMetricsBackoffSeconds = 120
)

$ErrorActionPreference = "Continue"

$dataDirectory = Join-Path $PSScriptRoot "..\portal\data"
$pidPath = Join-Path $dataDirectory "metrics-watcher.pid"
$logPath = Join-Path $dataDirectory "metrics-watcher.log"
$publicSaveSnapshotPath = Join-Path $dataDirectory "public-save-snapshot.json"
$publicSaveIndexPath = Join-Path $dataDirectory "public-save-index.json"
$eventSyncStatePath = Join-Path $dataDirectory "public-events-sync-state.json"
$recoveryReportPath = Join-Path $PSScriptRoot "..\runtime\recovery\microsite-recovery-latest.json"
$recoveryAuditPending = $true
$nextRecoveryAuditAt = Get-Date
$saveSnapshotSyncProcess = $null
$saveSnapshotSyncOutputPath = $null
$saveSnapshotSyncErrorPath = $null
$saveSnapshotSyncOutputTask = $null
$saveSnapshotSyncErrorTask = $null
$saveSnapshotSyncStartedAt = $null
$saveSnapshotSyncJustFinished = $false
New-Item -ItemType Directory -Force -Path $dataDirectory | Out-Null

$IntervalSeconds = [Math]::Max(30, $IntervalSeconds)
$EventSyncIntervalSeconds = [Math]::Max(60, $EventSyncIntervalSeconds)
$FullEventSyncIntervalSeconds = [Math]::Max(900, $FullEventSyncIntervalSeconds)
$SaveSnapshotSyncIntervalSeconds = [Math]::Max(300, $SaveSnapshotSyncIntervalSeconds)
$RecoveryAuditRetrySeconds = [Math]::Max(300, $RecoveryAuditRetrySeconds)
$MaxSaveSnapshotBackoffSeconds = [Math]::Max($SaveSnapshotSyncIntervalSeconds, $MaxSaveSnapshotBackoffSeconds)
$MaxEventSyncBackoffSeconds = [Math]::Max($EventSyncIntervalSeconds, $MaxEventSyncBackoffSeconds)
$MaxMetricsBackoffSeconds = [Math]::Max($IntervalSeconds, $MaxMetricsBackoffSeconds)
$nextRecoveryAuditAt = (Get-Date).AddSeconds([Math]::Min(60, $RecoveryAuditRetrySeconds))
$saveSnapshotSyncFailureCount = 0
$saveSnapshotSyncNextDelaySeconds = $SaveSnapshotSyncIntervalSeconds
$eventSyncFailureCount = 0
$metricsUpdateFailureCount = 0
$fullEventReconciliationPendingLogged = $false

function Write-WatcherLog {
    param([string]$Message)

    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}

function Get-RetryDelaySeconds {
    param(
        [int]$BaseSeconds,
        [int]$FailureCount,
        [int]$MaxSeconds
    )

    $safeBase = [Math]::Max(5, $BaseSeconds)
    $safeMax = [Math]::Max($safeBase, $MaxSeconds)
    if ($FailureCount -le 0) { return $safeBase }
    $multiplier = [Math]::Pow(2, [Math]::Min(5, $FailureCount - 1))
    return [int][Math]::Min($safeMax, $safeBase * $multiplier)
}

function Test-EventReprojectionRequired {
    if (-not (Test-Path -LiteralPath $eventSyncStatePath -PathType Leaf)) { return $false }
    try {
        $state = Get-Content -LiteralPath $eventSyncStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        return [bool]$state.requiresReprojection
    }
    catch {
        return $false
    }
}

function Read-RecoveryAuditReport {
    if (-not (Test-Path -LiteralPath $recoveryReportPath -PathType Leaf)) { return $null }
    try {
        return Get-Content -LiteralPath $recoveryReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
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

function Start-RedirectedChildProcess {
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [Parameter(Mandatory)] [string[]]$ArgumentList,
        [Parameter(Mandatory)] [string]$OutputPath,
        [Parameter(Mandatory)] [string]$ErrorPath
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    foreach ($argument in $ArgumentList) {
        [void]$startInfo.ArgumentList.Add([string]$argument)
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw "Le sous-processus n'a pas démarré."
        }
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        return [pscustomobject]@{
            Process = $process
            OutputTask = $outputTask
            ErrorTask = $errorTask
            OutputPath = $OutputPath
            ErrorPath = $ErrorPath
        }
    }
    catch {
        try { $process.Dispose() } catch { }
        throw
    }
}

function Complete-RedirectedChildOutput {
    param($Child)

    if (-not $Child) { return }
    if ($Child.Process -and -not $Child.Process.HasExited) {
        [void]$Child.Process.WaitForExit(2000)
    }
    if ($Child.Process -and -not $Child.Process.HasExited) {
        return
    }

    $utf8NoBom = [Text.UTF8Encoding]::new($false)
    if ($Child.OutputPath -and $Child.OutputTask) {
        try {
            $outputText = [string]$Child.OutputTask.GetAwaiter().GetResult()
            [IO.File]::WriteAllText($Child.OutputPath, $outputText, $utf8NoBom)
        }
        catch { }
    }
    if ($Child.ErrorPath -and $Child.ErrorTask) {
        try {
            $errorText = [string]$Child.ErrorTask.GetAwaiter().GetResult()
            [IO.File]::WriteAllText($Child.ErrorPath, $errorText, $utf8NoBom)
        }
        catch { }
    }
}

function Write-InterestingChildOutput {
    param(
        [string]$OutputPath,
        [string]$ErrorPath,
        [string]$Label = "Child"
    )

    $interesting = "(?i)(warning|avertissement|failed|erreur|error|echou|échou|diff[eé]r[eé]|deferred|d[eé]j[aà] en cours|sans modification|rattrapage|reprojection|retard)"
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
    $child = $null

    try {
        $child = Start-RedirectedChildProcess -FilePath $powerShellHost -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            $updateScript,
            "-FastOnly",
            "-SkipEvents"
        ) -OutputPath $outputPath -ErrorPath $errorPath
        $process = $child.Process

        if (-not $process.WaitForExit([Math]::Max(5, $UpdateTimeoutSeconds) * 1000)) {
            Stop-ProcessTree -RootPid $process.Id
            throw "Metrics update timed out after $UpdateTimeoutSeconds seconds."
        }
        Complete-RedirectedChildOutput -Child $child

        if ($process.ExitCode -ne 0) {
            throw "Metrics update failed with exit code $($process.ExitCode)."
        }
    }
    finally {
        Complete-RedirectedChildOutput -Child $child
        Write-InterestingChildOutput -OutputPath $outputPath -ErrorPath $errorPath
        Remove-Item -LiteralPath $outputPath, $errorPath -Force -ErrorAction SilentlyContinue
        if ($child -and $child.Process) { $child.Process.Dispose() }
    }
}

function Invoke-EventHistorySync {
    param([switch]$Full)

    $syncScript = Join-Path $PSScriptRoot "sync-palworld-events.ps1"
    $powerShellHost = Get-PowerShellHost
    $runId = [Guid]::NewGuid().ToString("N")
    $outputPath = Join-Path ([IO.Path]::GetTempPath()) "gaylemon-events-$runId.out.log"
    $errorPath = Join-Path ([IO.Path]::GetTempPath()) "gaylemon-events-$runId.err.log"

    $arguments = [Collections.Generic.List[string]]::new()
    foreach ($argument in @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            $syncScript
        )) {
        $arguments.Add($argument)
    }
    if (-not $Full) { $arguments.Add("-Fast") }
    if ($Full) { $arguments.Add("-TreatRemoteBackfillRequestAsNoop") }
    $timeoutSeconds = if ($Full) { [Math]::Max(30, $FullEventSyncTimeoutSeconds) } else { [Math]::Max(15, $EventSyncTimeoutSeconds) }
    $child = $null

    try {
        $child = Start-RedirectedChildProcess -FilePath $powerShellHost -ArgumentList $arguments.ToArray() -OutputPath $outputPath -ErrorPath $errorPath
        $process = $child.Process

        if (-not $process.WaitForExit($timeoutSeconds * 1000)) {
            Stop-ProcessTree -RootPid $process.Id
            throw "Event history sync timed out after $timeoutSeconds seconds."
        }
        Complete-RedirectedChildOutput -Child $child

        if ($process.ExitCode -ne 0) {
            throw "Event history sync failed with exit code $($process.ExitCode)."
        }
    }
    finally {
        Complete-RedirectedChildOutput -Child $child
        Write-InterestingChildOutput -OutputPath $outputPath -ErrorPath $errorPath
        Remove-Item -LiteralPath $outputPath, $errorPath -Force -ErrorAction SilentlyContinue
        if ($child -and $child.Process) { $child.Process.Dispose() }
    }
}

function Invoke-RecoveryAudit {
    $auditScript = Join-Path $PSScriptRoot "verify-microsite-recovery.ps1"
    $powerShellHost = Get-PowerShellHost
    $runId = [Guid]::NewGuid().ToString("N")
    $outputPath = Join-Path ([IO.Path]::GetTempPath()) "gaylemon-recovery-$runId.out.log"
    $errorPath = Join-Path ([IO.Path]::GetTempPath()) "gaylemon-recovery-$runId.err.log"
    $child = $null

    try {
        $child = Start-RedirectedChildProcess -FilePath $powerShellHost -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            $auditScript,
            "-Trigger",
            "watcher-retry",
            "-SkipRepair",
            "-NoThrowOnUnhealthy"
        ) -OutputPath $outputPath -ErrorPath $errorPath
        $process = $child.Process

        if (-not $process.WaitForExit(60000)) {
            Stop-ProcessTree -RootPid $process.Id
            throw "Recovery audit timed out after 60 seconds."
        }
        Complete-RedirectedChildOutput -Child $child

        if ($process.ExitCode -ne 0) {
            throw "Recovery audit failed with exit code $($process.ExitCode)."
        }
        $report = Read-RecoveryAuditReport
        if (-not $report) {
            throw "Recovery audit report was not written."
        }
        if (-not [bool]$report.ok) {
            $status = if ($report.status) { [string]$report.status } else { "unknown" }
            throw "Recovery audit reported $status."
        }
    }
    finally {
        Complete-RedirectedChildOutput -Child $child
        Remove-Item -LiteralPath $outputPath, $errorPath -Force -ErrorAction SilentlyContinue
        if ($child -and $child.Process) { $child.Process.Dispose() }
    }
}

function Clear-SaveSnapshotSyncProcess {
    $child = if ($script:saveSnapshotSyncProcess -or $script:saveSnapshotSyncOutputTask -or $script:saveSnapshotSyncErrorTask) {
        [pscustomobject]@{
            Process = $script:saveSnapshotSyncProcess
            OutputTask = $script:saveSnapshotSyncOutputTask
            ErrorTask = $script:saveSnapshotSyncErrorTask
            OutputPath = $script:saveSnapshotSyncOutputPath
            ErrorPath = $script:saveSnapshotSyncErrorPath
        }
    }
    else {
        $null
    }
    Complete-RedirectedChildOutput -Child $child

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
    $script:saveSnapshotSyncOutputTask = $null
    $script:saveSnapshotSyncErrorTask = $null
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
            $script:saveSnapshotSyncFailureCount += 1
            $script:saveSnapshotSyncNextDelaySeconds = Get-RetryDelaySeconds `
                -BaseSeconds $SaveSnapshotSyncIntervalSeconds `
                -FailureCount $script:saveSnapshotSyncFailureCount `
                -MaxSeconds $MaxSaveSnapshotBackoffSeconds
            Write-WatcherLog "Save snapshot sync timed out after $SaveSnapshotSyncTimeoutSeconds seconds. Next retry in $($script:saveSnapshotSyncNextDelaySeconds)s."
            Clear-SaveSnapshotSyncProcess
            $script:saveSnapshotSyncJustFinished = $true
        }
        return
    }

    Complete-RedirectedChildOutput -Child ([pscustomobject]@{
        Process = $script:saveSnapshotSyncProcess
        OutputTask = $script:saveSnapshotSyncOutputTask
        ErrorTask = $script:saveSnapshotSyncErrorTask
        OutputPath = $script:saveSnapshotSyncOutputPath
        ErrorPath = $script:saveSnapshotSyncErrorPath
    })

    $outputText = ""
    if ($script:saveSnapshotSyncOutputPath -and (Test-Path -LiteralPath $script:saveSnapshotSyncOutputPath)) {
        $outputText = [string](Get-Content -LiteralPath $script:saveSnapshotSyncOutputPath -Raw -ErrorAction SilentlyContinue)
    }
    $publishedAfterStart = $false
    foreach ($publishedPath in @($publicSaveSnapshotPath, $publicSaveIndexPath)) {
        $publishedItem = Get-Item -LiteralPath $publishedPath -ErrorAction SilentlyContinue
        if ($publishedItem -and $script:saveSnapshotSyncStartedAt -and $publishedItem.LastWriteTime -ge $script:saveSnapshotSyncStartedAt.AddSeconds(-2)) {
            $publishedAfterStart = $true
            break
        }
    }
    $madeNoChange = $outputText -match "(?i)diff[eé]r[eé]|deferred|d[eé]j[aà] en cours|sans modification|ignor[eé]"

    if ($script:saveSnapshotSyncProcess.ExitCode -eq 0 -and -not $madeNoChange -and $publishedAfterStart) {
        $script:saveSnapshotSyncFailureCount = 0
        $script:saveSnapshotSyncNextDelaySeconds = $SaveSnapshotSyncIntervalSeconds
        Write-WatcherLog "Save snapshot sync completed."
    }
    elseif ($script:saveSnapshotSyncProcess.ExitCode -eq 0) {
        $script:saveSnapshotSyncFailureCount += 1
        $script:saveSnapshotSyncNextDelaySeconds = Get-RetryDelaySeconds `
            -BaseSeconds $SaveSnapshotSyncIntervalSeconds `
            -FailureCount $script:saveSnapshotSyncFailureCount `
            -MaxSeconds $MaxSaveSnapshotBackoffSeconds
        Write-WatcherLog "Save snapshot sync made no local change. Next retry in $($script:saveSnapshotSyncNextDelaySeconds)s."
    }
    else {
        $script:saveSnapshotSyncFailureCount += 1
        $script:saveSnapshotSyncNextDelaySeconds = Get-RetryDelaySeconds `
            -BaseSeconds $SaveSnapshotSyncIntervalSeconds `
            -FailureCount $script:saveSnapshotSyncFailureCount `
            -MaxSeconds $MaxSaveSnapshotBackoffSeconds
        Write-WatcherLog "Save snapshot sync skipped: exit code $($script:saveSnapshotSyncProcess.ExitCode). Next retry in $($script:saveSnapshotSyncNextDelaySeconds)s."
    }
    Clear-SaveSnapshotSyncProcess
    $script:saveSnapshotSyncJustFinished = $true
}

function Start-SaveSnapshotSync {
    $syncScript = Join-Path $PSScriptRoot "sync-palworld-save-snapshot.ps1"
    $powerShellHost = Get-PowerShellHost
    $runId = [Guid]::NewGuid().ToString("N")
    $script:saveSnapshotSyncOutputPath = Join-Path ([IO.Path]::GetTempPath()) "gaylemon-save-snapshot-$runId.out.log"
    $script:saveSnapshotSyncErrorPath = Join-Path ([IO.Path]::GetTempPath()) "gaylemon-save-snapshot-$runId.err.log"
    $script:saveSnapshotSyncStartedAt = Get-Date

    try {
        $child = Start-RedirectedChildProcess -FilePath $powerShellHost -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            $syncScript,
            "-TreatRemoteStageFailureAsNoop"
        ) -OutputPath $script:saveSnapshotSyncOutputPath -ErrorPath $script:saveSnapshotSyncErrorPath
        $script:saveSnapshotSyncProcess = $child.Process
        $script:saveSnapshotSyncOutputTask = $child.OutputTask
        $script:saveSnapshotSyncErrorTask = $child.ErrorTask
        Write-WatcherLog "Save snapshot sync started."
    }
    catch {
        $script:saveSnapshotSyncFailureCount += 1
        $script:saveSnapshotSyncNextDelaySeconds = Get-RetryDelaySeconds `
            -BaseSeconds $SaveSnapshotSyncIntervalSeconds `
            -FailureCount $script:saveSnapshotSyncFailureCount `
            -MaxSeconds $MaxSaveSnapshotBackoffSeconds
        Write-WatcherLog "Save snapshot sync skipped: $($_.Exception.Message)"
        Clear-SaveSnapshotSyncProcess
        $script:saveSnapshotSyncJustFinished = $true
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
Write-WatcherLog "Microsite watcher started. MetricsInterval=${IntervalSeconds}s EventSyncInterval=${EventSyncIntervalSeconds}s FullEventSyncInterval=${FullEventSyncIntervalSeconds}s SaveSnapshotInterval=${SaveSnapshotSyncIntervalSeconds}s MetricsTimeout=${UpdateTimeoutSeconds}s EventSyncTimeout=${EventSyncTimeoutSeconds}s FullEventSyncTimeout=${FullEventSyncTimeoutSeconds}s SaveSnapshotTimeout=${SaveSnapshotSyncTimeoutSeconds}s PID=$PID."

try {
    $nextEventSyncAt = Get-Date
    $nextFullEventSyncAt = (Get-Date).AddSeconds([Math]::Min(300, $FullEventSyncIntervalSeconds))
    $nextSaveSnapshotSyncAt = Get-Date
    $nextMetricsUpdateAt = Get-Date
    while ($true) {
        $now = Get-Date
        Update-SaveSnapshotSync -Now $now
        if ($script:saveSnapshotSyncJustFinished) {
            $nextSaveSnapshotSyncAt = (Get-Date).AddSeconds([Math]::Max(15, $script:saveSnapshotSyncNextDelaySeconds))
            $script:saveSnapshotSyncJustFinished = $false
        }
        if (-not $saveSnapshotSyncProcess -and $now -ge $nextSaveSnapshotSyncAt) {
            Start-SaveSnapshotSync
            $nextSaveSnapshotSyncAt = (Get-Date).AddSeconds([Math]::Max(15, $SaveSnapshotSyncIntervalSeconds))
        }

        $eventSyncAttempted = $false
        if ((Get-Date) -ge $nextEventSyncAt) {
            $eventSyncAttempted = $true
            $runFullEventSync = (Get-Date) -ge $nextFullEventSyncAt
            try {
                Invoke-EventHistorySync -Full:$runFullEventSync
                $eventSyncFailureCount = 0
                if ($runFullEventSync) {
                    Write-WatcherLog "Full event history reconciliation completed."
                    $nextFullEventSyncAt = (Get-Date).AddSeconds([Math]::Max(60, $FullEventSyncIntervalSeconds))
                }
                else {
                    Write-WatcherLog "Recent event history sync completed."
                    if (Test-EventReprojectionRequired) {
                        if ((Get-Date) -ge $nextFullEventSyncAt) {
                            $fullEventReconciliationPendingLogged = $false
                            try {
                                Write-WatcherLog "A full event history reconciliation is required by the recent projection."
                                Invoke-EventHistorySync -Full
                                Write-WatcherLog "Full event history reconciliation completed after a recent projection divergence."
                                $nextFullEventSyncAt = (Get-Date).AddSeconds([Math]::Max(60, $FullEventSyncIntervalSeconds))
                            }
                            catch {
                                $fullDelaySeconds = Get-RetryDelaySeconds `
                                    -BaseSeconds ([Math]::Max(300, $EventSyncIntervalSeconds)) `
                                    -FailureCount ([Math]::Max(1, $eventSyncFailureCount + 1)) `
                                    -MaxSeconds $FullEventSyncIntervalSeconds
                                $nextFullEventSyncAt = (Get-Date).AddSeconds($fullDelaySeconds)
                                Write-WatcherLog "Full event history reconciliation deferred: $($_.Exception.Message) Next retry in ${fullDelaySeconds}s."
                            }
                        }
                        elseif (-not $fullEventReconciliationPendingLogged) {
                            $fullDelaySeconds = [int][Math]::Max(0, ($nextFullEventSyncAt - (Get-Date)).TotalSeconds)
                            Write-WatcherLog "Full event history reconciliation pending; next attempt in ${fullDelaySeconds}s."
                            $fullEventReconciliationPendingLogged = $true
                        }
                    }
                }
                $nextEventSyncAt = (Get-Date).AddSeconds([Math]::Max(5, $EventSyncIntervalSeconds))
            }
            catch {
                $eventSyncFailureCount += 1
                $eventDelaySeconds = Get-RetryDelaySeconds `
                    -BaseSeconds $EventSyncIntervalSeconds `
                    -FailureCount $eventSyncFailureCount `
                    -MaxSeconds $MaxEventSyncBackoffSeconds
                Write-WatcherLog "$(if ($runFullEventSync) { 'Full event history reconciliation' } else { 'Recent event history sync' }) skipped: $($_.Exception.Message) Next retry in ${eventDelaySeconds}s."
                if ($runFullEventSync) {
                    $nextFullEventSyncAt = (Get-Date).AddSeconds($eventDelaySeconds)
                }
                $nextEventSyncAt = (Get-Date).AddSeconds($eventDelaySeconds)
            }
        }

        if ((Get-Date) -ge $nextMetricsUpdateAt) {
            try {
                Invoke-MetricsUpdate
                $metricsUpdateFailureCount = 0
                $nextMetricsUpdateAt = (Get-Date).AddSeconds($IntervalSeconds)
                Write-WatcherLog "Metrics update completed."
                if ($recoveryAuditPending -and (Get-Date) -ge $nextRecoveryAuditAt) {
                    try {
                        Invoke-RecoveryAudit
                        $recoveryAuditPending = $false
                        Write-WatcherLog "Recovery audit completed."
                    }
                    catch {
                        $nextRecoveryAuditAt = (Get-Date).AddSeconds($RecoveryAuditRetrySeconds)
                        Write-WatcherLog "Recovery audit pending: $($_.Exception.Message) Next retry in ${RecoveryAuditRetrySeconds}s."
                    }
                }
            }
            catch {
                $metricsUpdateFailureCount += 1
                $metricsDelaySeconds = Get-RetryDelaySeconds `
                    -BaseSeconds $IntervalSeconds `
                    -FailureCount $metricsUpdateFailureCount `
                    -MaxSeconds $MaxMetricsBackoffSeconds
                $nextMetricsUpdateAt = (Get-Date).AddSeconds($metricsDelaySeconds)
                Write-WatcherLog "Metrics update skipped: $($_.Exception.Message) Next retry in ${metricsDelaySeconds}s."
            }
        }

        Start-Sleep -Seconds ([Math]::Min(30, [Math]::Max(5, $IntervalSeconds)))
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
