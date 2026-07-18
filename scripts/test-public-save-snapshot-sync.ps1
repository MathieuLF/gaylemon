param()

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$syncScript = Join-Path $PSScriptRoot "sync-palworld-save-snapshot.ps1"
$snapshotExample = Join-Path $projectRoot "portal\data\public-save-snapshot.example.json"
$basesExample = Join-Path $projectRoot "portal\data\public-save-bases.example.json"
$diagnosticsExample = Join-Path $projectRoot "portal\data\public-save-diagnostics.example.json"
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("gaylemon-public-save-sync-test-" + [Guid]::NewGuid().ToString("N"))
$lockJob = $null
$heldFile = $null

function Assert-True {
    param(
        [Parameter(Mandatory)] [bool]$Condition,
        [Parameter(Mandatory)] [string]$Message
    )
    if (-not $Condition) { throw $Message }
}

function Copy-JsonValue {
    param([Parameter(Mandatory)] $Value)

    return ($Value | ConvertTo-Json -Depth 30 | ConvertFrom-Json)
}

function Write-TestJson {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] $Value
    )

    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 30) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
}

function New-SourceBundle {
    param(
        [Parameter(Mandatory)] [string]$Backup,
        [Parameter(Mandatory)] [string]$SourceUpdatedAt,
        [string]$ParserCommit = "snapshot-test-commit"
    )

    $snapshot = Get-Content -LiteralPath $snapshotExample -Raw -Encoding UTF8 | ConvertFrom-Json
    $bases = Get-Content -LiteralPath $basesExample -Raw -Encoding UTF8 | ConvertFrom-Json
    $diagnostics = Get-Content -LiteralPath $diagnosticsExample -Raw -Encoding UTF8 | ConvertFrom-Json
    $diagnosticsAt = ([DateTimeOffset]::Parse($SourceUpdatedAt)).AddSeconds(30).ToString("o")

    $provenance = [pscustomobject]@{
        observedAt = $SourceUpdatedAt
        sourceUpdatedAt = $SourceUpdatedAt
        gameVersion = "v0.7-test"
        steamBuildId = "123456"
        parserCommit = $ParserCommit
        catalogCommit = $ParserCommit
        schemaVersion = 4
        freshness = "current"
        sourceStatus = "available"
    }
    $snapshot.updatedAt = $SourceUpdatedAt
    $snapshot.source.backup = $Backup
    $snapshot.parser.commit = $ParserCommit
    $snapshot.projection.version = 4
    foreach ($player in @($snapshot.players)) {
        foreach ($pal in @($player.pals.collection)) {
            foreach ($skill in @($pal.passives) + @($pal.activeSkills) + @($pal.learnedSkills)) {
                $skill | Add-Member -NotePropertyName power -NotePropertyValue $null -Force
                $skill | Add-Member -NotePropertyName cooldown -NotePropertyValue $null -Force
                $skill | Add-Member -NotePropertyName element -NotePropertyValue $null -Force
            }
        }
    }
    $snapshot | Add-Member -NotePropertyName provenance -NotePropertyValue (Copy-JsonValue $provenance) -Force

    $bases.updatedAt = $SourceUpdatedAt
    $bases.parser.commit = $ParserCommit
    $bases | Add-Member -NotePropertyName source -NotePropertyValue (Copy-JsonValue $snapshot.source) -Force
    $bases | Add-Member -NotePropertyName provenance -NotePropertyValue (Copy-JsonValue $provenance) -Force

    $diagnostics.updatedAt = $diagnosticsAt
    $diagnostics.parser.commit = $ParserCommit
    $diagnostics.save | Add-Member -NotePropertyName backupName -NotePropertyValue $Backup -Force
    $diagnosticsProvenance = Copy-JsonValue $provenance
    $diagnosticsProvenance.observedAt = $diagnosticsAt
    $diagnosticsProvenance.sourceUpdatedAt = ([DateTimeOffset]::Parse($SourceUpdatedAt)).AddMinutes(-1).ToString("o")
    $diagnostics | Add-Member -NotePropertyName provenance -NotePropertyValue $diagnosticsProvenance -Force

    return [pscustomobject]@{
        snapshot = $snapshot
        bases = $bases
        diagnostics = $diagnostics
        catalogsManifest = $null
    }
}

function Get-PublicGenerationSnapshot {
    param([Parameter(Mandatory)] [string]$Root)

    $snapshot = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return $snapshot }
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force | Where-Object {
        $_.Name -notlike "*.lock" -and $_.FullName -notmatch '[\\/]\.public-save-sync-'
    } | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($Root.Length).TrimStart('\', '/')
        $snapshot[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
    return $snapshot
}

function Assert-SnapshotsEqual {
    param(
        [Parameter(Mandatory)] $Expected,
        [Parameter(Mandatory)] $Actual,
        [Parameter(Mandatory)] [string]$Message
    )

    Assert-True (($Expected | ConvertTo-Json -Depth 5 -Compress) -eq ($Actual | ConvertTo-Json -Depth 5 -Compress)) $Message
}

function Invoke-TestSync {
    param(
        [Parameter(Mandatory)] [string]$BundlePath,
        [string]$FailurePoint = ""
    )

    $dataRoot = Join-Path $tempRoot "site\data"
    & $syncScript `
        -SourceBundlePath $BundlePath `
        -OutputPath (Join-Path $dataRoot "public-save-snapshot.json") `
        -DiagnosticsOutputPath (Join-Path $dataRoot "public-save-diagnostics.json") `
        -BasesOutputPath (Join-Path $dataRoot "public-save-bases.json") `
        -CatalogsManifestOutputPath (Join-Path $dataRoot "public-catalogs-manifest.json") `
        -CatalogsOutputRoot (Join-Path $dataRoot "public-catalogs") `
        -PlayerDataRoot (Join-Path $dataRoot "players") `
        -PlayerPagesRoot (Join-Path $tempRoot "site\joueur") `
        -TestFailurePoint $FailurePoint | Out-Null
}

function Start-TestSyncJob {
    param(
        [Parameter(Mandatory)] [string]$BundlePath,
        [Parameter(Mandatory)] [string]$DataRoot,
        [Parameter(Mandatory)] [string]$SiteRoot,
        [int]$HoldLockMilliseconds = 0,
        [int]$FileOperationMaxAttempts = 0
    )

    return Start-Job -ScriptBlock {
        param($ScriptPath, $SourceBundle, $DestinationDataRoot, $DestinationSiteRoot, $HoldMilliseconds, $MaxAttempts)
        & $ScriptPath `
            -SourceBundlePath $SourceBundle `
            -OutputPath (Join-Path $DestinationDataRoot "public-save-snapshot.json") `
            -DiagnosticsOutputPath (Join-Path $DestinationDataRoot "public-save-diagnostics.json") `
            -BasesOutputPath (Join-Path $DestinationDataRoot "public-save-bases.json") `
            -CatalogsManifestOutputPath (Join-Path $DestinationDataRoot "public-catalogs-manifest.json") `
            -CatalogsOutputRoot (Join-Path $DestinationDataRoot "public-catalogs") `
            -PlayerDataRoot (Join-Path $DestinationDataRoot "players") `
            -PlayerPagesRoot (Join-Path $DestinationSiteRoot "joueur") `
            -TestHoldLockMilliseconds $HoldMilliseconds `
            -TestFileOperationMaxAttempts $MaxAttempts | Out-Null
    } -ArgumentList $syncScript, $BundlePath, $DataRoot, $SiteRoot, $HoldLockMilliseconds, $FileOperationMaxAttempts
}

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $firstBundlePath = Join-Path $tempRoot "bundle-first.json"
    $firstBundle = New-SourceBundle -Backup "2026.07.18-18.30.00" -SourceUpdatedAt "2026-07-18T18:30:20-04:00"
    Write-TestJson -Path $firstBundlePath -Value $firstBundle
    Invoke-TestSync -BundlePath $firstBundlePath

    $dataRoot = Join-Path $tempRoot "site\data"
    $primaryPaths = @(
        Join-Path $dataRoot "public-save-snapshot.json"
        Join-Path $dataRoot "public-save-index.json"
        Join-Path $dataRoot "public-save-bases.json"
        Join-Path $dataRoot "public-save-diagnostics.json"
    )
    $primary = @($primaryPaths | ForEach-Object { Get-Content -LiteralPath $_ -Raw -Encoding UTF8 | ConvertFrom-Json })
    Assert-True ((@($primary.generationId | Sort-Object -Unique)).Count -eq 1) "Les artefacts publiés ne partagent pas la même génération."
    Assert-True ((@($primary.provenance.sourceUpdatedAt | Sort-Object -Unique)).Count -eq 1) "Les artefacts publiés ne partagent pas la même source."
    $playerPayload = Get-Content -LiteralPath (Join-Path $dataRoot "players\aventuriere.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($playerPayload.generationId -eq $primary[0].generationId) "La fiche joueur ne suit pas la génération principale."
    $firstGeneration = [string]$primary[0].generationId
    $beforeMismatch = Get-PublicGenerationSnapshot -Root (Join-Path $tempRoot "site")

    $mismatchedBundle = Copy-JsonValue $firstBundle
    $mismatchedBundle.bases.provenance.sourceUpdatedAt = "2026-07-18T18:31:20-04:00"
    $mismatchedBundlePath = Join-Path $tempRoot "bundle-mismatched.json"
    Write-TestJson -Path $mismatchedBundlePath -Value $mismatchedBundle
    $rejected = $false
    try { Invoke-TestSync -BundlePath $mismatchedBundlePath }
    catch { $rejected = $true }
    Assert-True $rejected "Un lot distant composé de deux captures a été accepté."
    Assert-SnapshotsEqual -Expected $beforeMismatch -Actual (Get-PublicGenerationSnapshot -Root (Join-Path $tempRoot "site")) -Message "Le lot incohérent a modifié la génération locale active."

    $secondBundlePath = Join-Path $tempRoot "bundle-second.json"
    $secondBundle = New-SourceBundle -Backup "2026.07.18-18.45.00" -SourceUpdatedAt "2026-07-18T18:45:20-04:00"
    Write-TestJson -Path $secondBundlePath -Value $secondBundle
    $beforeFailure = Get-PublicGenerationSnapshot -Root (Join-Path $tempRoot "site")
    $failed = $false
    try { Invoke-TestSync -BundlePath $secondBundlePath -FailurePoint "AfterFirstPublish" }
    catch { $failed = $true }
    Assert-True $failed "L'échec de publication injecté n'a pas interrompu la transaction."
    Assert-SnapshotsEqual -Expected $beforeFailure -Actual (Get-PublicGenerationSnapshot -Root (Join-Path $tempRoot "site")) -Message "Le rollback n'a pas restauré intégralement la génération précédente."

    Invoke-TestSync -BundlePath $secondBundlePath
    $secondPrimary = @($primaryPaths | ForEach-Object { Get-Content -LiteralPath $_ -Raw -Encoding UTF8 | ConvertFrom-Json })
    Assert-True ((@($secondPrimary.generationId | Sort-Object -Unique)).Count -eq 1) "La deuxième génération n'a pas été publiée comme un lot."
    Assert-True ($secondPrimary[0].generationId -ne $firstGeneration) "La nouvelle capture n'a pas changé l'identité de génération."
    Assert-True ((Get-ChildItem -LiteralPath $dataRoot -Directory -Filter ".public-save-sync-*" -Force -ErrorAction SilentlyContinue).Count -eq 0) "Un dossier transactionnel temporaire subsiste."

    $thirdBundlePath = Join-Path $tempRoot "bundle-third.json"
    $thirdBundle = New-SourceBundle -Backup "2026.07.18-19.00.00" -SourceUpdatedAt "2026-07-18T19:00:20-04:00"
    Write-TestJson -Path $thirdBundlePath -Value $thirdBundle
    $lockJob = Start-TestSyncJob `
        -BundlePath $thirdBundlePath `
        -DataRoot $dataRoot `
        -SiteRoot (Join-Path $tempRoot "site") `
        -HoldLockMilliseconds 2000

    $lockPath = (Join-Path $dataRoot "public-save-snapshot.json.lock")
    $lockObserved = $false
    for ($attempt = 0; $attempt -lt 100 -and -not $lockObserved; $attempt++) {
        if (Test-Path -LiteralPath $lockPath) {
            try {
                $probe = [IO.File]::Open($lockPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
                $probe.Dispose()
            }
            catch [IO.IOException] {
                $lockObserved = $true
            }
        }
        if (-not $lockObserved) { Start-Sleep -Milliseconds 50 }
    }
    Assert-True $lockObserved "Le verrou exclusif de synchronisation n'a pas été observé."
    $beforeContender = Get-PublicGenerationSnapshot -Root (Join-Path $tempRoot "site")
    Invoke-TestSync -BundlePath $thirdBundlePath
    Assert-SnapshotsEqual -Expected $beforeContender -Actual (Get-PublicGenerationSnapshot -Root (Join-Path $tempRoot "site")) -Message "Une synchronisation concurrente a modifié les artefacts actifs."
    $lockJob | Wait-Job -Timeout 30 | Out-Null
    Assert-True ($lockJob.State -eq "Completed") "La synchronisation détentrice du verrou ne s'est pas terminée."
    Receive-Job -Job $lockJob -ErrorAction Stop | Out-Null
    Remove-Job -Job $lockJob -Force
    $lockJob = $null
    $thirdPrimary = @($primaryPaths | ForEach-Object { Get-Content -LiteralPath $_ -Raw -Encoding UTF8 | ConvertFrom-Json })
    Assert-True ((@($thirdPrimary.generationId | Sort-Object -Unique)).Count -eq 1) "La génération publiée après contention est incohérente."
    Assert-True ($thirdPrimary[0].generationId -ne $secondPrimary[0].generationId) "La synchronisation détentrice du verrou n'a pas publié sa génération."

    $fourthBundlePath = Join-Path $tempRoot "bundle-fourth.json"
    $fourthBundle = New-SourceBundle -Backup "2026.07.18-19.15.00" -SourceUpdatedAt "2026-07-18T19:15:20-04:00"
    Write-TestJson -Path $fourthBundlePath -Value $fourthBundle
    $beforeLockedFailure = Get-PublicGenerationSnapshot -Root (Join-Path $tempRoot "site")
    $heldFile = [IO.File]::Open((Join-Path $dataRoot "public-save-bases.json"), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    $lockJob = Start-TestSyncJob `
        -BundlePath $fourthBundlePath `
        -DataRoot $dataRoot `
        -SiteRoot (Join-Path $tempRoot "site") `
        -FileOperationMaxAttempts 2
    $lockJob | Wait-Job -Timeout 30 | Out-Null
    Assert-True ($lockJob.State -in @("Completed", "Failed")) "La publication bloquée ne s'est pas terminée dans la borne prévue."
    $heldFile.Dispose()
    $heldFile = $null
    Receive-Job -Job $lockJob -ErrorAction SilentlyContinue | Out-Null
    Remove-Job -Job $lockJob -Force
    $lockJob = $null
    Assert-SnapshotsEqual -Expected $beforeLockedFailure -Actual (Get-PublicGenerationSnapshot -Root (Join-Path $tempRoot "site")) -Message "Une destination verrouillée n'a pas restauré intégralement la génération précédente."
    Assert-True ((Get-ChildItem -LiteralPath $dataRoot -Directory -Filter ".public-save-sync-*" -Force -ErrorAction SilentlyContinue).Count -eq 0) "Un dossier transactionnel subsiste après un échec de remplacement."

    $fifthBundlePath = Join-Path $tempRoot "bundle-fifth.json"
    $fifthBundle = New-SourceBundle -Backup "2026.07.18-19.30.00" -SourceUpdatedAt "2026-07-18T19:30:20-04:00"
    Write-TestJson -Path $fifthBundlePath -Value $fifthBundle
    $heldFile = [IO.File]::Open((Join-Path $dataRoot "public-save-diagnostics.json"), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    $lockJob = Start-TestSyncJob `
        -BundlePath $fifthBundlePath `
        -DataRoot $dataRoot `
        -SiteRoot (Join-Path $tempRoot "site")
    Start-Sleep -Milliseconds 650
    $heldFile.Dispose()
    $heldFile = $null
    $lockJob | Wait-Job -Timeout 30 | Out-Null
    Assert-True ($lockJob.State -eq "Completed") "Le remplacement avec backoff n'a pas repris après la libération du fichier."
    Receive-Job -Job $lockJob -ErrorAction Stop | Out-Null
    Remove-Job -Job $lockJob -Force
    $lockJob = $null
    $fifthPrimary = @($primaryPaths | ForEach-Object { Get-Content -LiteralPath $_ -Raw -Encoding UTF8 | ConvertFrom-Json })
    Assert-True ((@($fifthPrimary.generationId | Sort-Object -Unique)).Count -eq 1) "La génération publiée après backoff est incohérente."
    Assert-True ($fifthPrimary[0].generationId -ne $thirdPrimary[0].generationId) "Le remplacement avec backoff n'a pas publié la nouvelle génération."
    Assert-True ((Get-ChildItem -LiteralPath $dataRoot -Directory -Filter ".public-save-sync-*" -Force -ErrorAction SilentlyContinue).Count -eq 0) "Un dossier transactionnel subsiste après un remplacement réussi."

    Write-Host "[OK] Synchronisation atomique des snapshots: cohérence, rejet, rollback, verrou et backoff validés."
}
finally {
    if ($heldFile) { $heldFile.Dispose() }
    if ($lockJob) {
        Stop-Job -Job $lockJob -ErrorAction SilentlyContinue
        Remove-Job -Job $lockJob -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
