param()

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$syncScript = Join-Path $PSScriptRoot "sync-palworld-events.ps1"
$watcherScript = Join-Path $PSScriptRoot "watch-microsite-metrics.ps1"
$channelScript = Join-Path $PSScriptRoot "set-public-events-channel.ps1"
$samplePath = Join-Path $projectRoot "portal\data\public-events.example.json"
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("gaylemon-public-events-v6-test-" + [Guid]::NewGuid().ToString("N"))

function Assert-True {
    param(
        [Parameter(Mandatory)] [bool]$Condition,
        [Parameter(Mandatory)] [string]$Message
    )
    if (-not $Condition) { throw $Message }
}

function Get-ContractPath {
    param(
        [Parameter(Mandatory)] [string]$Root,
        [Parameter(Mandatory)] [string]$RelativePath
    )
    $relative = $RelativePath -replace '^data/', '' -replace '/', [IO.Path]::DirectorySeparatorChar
    return Join-Path $Root $relative
}

function Get-ManifestHead {
    param(
        [Parameter(Mandatory)] [string]$Root,
        [Parameter(Mandatory)] $Manifest
    )

    $path = Get-ContractPath -Root $Root -RelativePath ([string]$Manifest.head.path)
    return [pscustomobject]@{
        Path = $path
        Payload = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
}

function Get-V6FileSnapshot {
    param([Parameter(Mandatory)] [string]$Root)

    $snapshot = [ordered]@{}
    $paths = @(
        Get-ChildItem -LiteralPath $Root -Filter "public-events-manifest-v6*.json" -File -ErrorAction SilentlyContinue
        Get-ChildItem -LiteralPath $Root -Filter "public-events-head-v6.json" -File -ErrorAction SilentlyContinue
        Get-ChildItem -LiteralPath (Join-Path $Root "public-events-v6") -Filter "*.json" -File -Recurse -ErrorAction SilentlyContinue
        Get-ChildItem -LiteralPath (Join-Path $Root "public-daily") -Filter "*.json" -File -Recurse -ErrorAction SilentlyContinue
    )
    foreach ($file in @($paths)) {
        $relative = $file.FullName.Substring($Root.Length).TrimStart('\', '/')
        $snapshot[$relative] = "{0}|{1}" -f (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash, $file.LastWriteTimeUtc.Ticks
    }
    return $snapshot
}

function Get-PublicJsonSnapshot {
    param([Parameter(Mandatory)] [string]$Root)

    $snapshot = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return $snapshot }
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -Filter "*.json" -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($Root.Length).TrimStart('\', '/')
        $snapshot[$relative] = "{0}|{1}" -f (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash, $file.LastWriteTimeUtc.Ticks
    }
    return $snapshot
}

function Copy-JsonValue {
    param([Parameter(Mandatory)] $Value)

    return ($Value | ConvertTo-Json -Depth 16 | ConvertFrom-Json)
}

function Write-TestJson {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] $Value
    )

    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 16) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
}

function Set-TestProjectionWindow {
    param(
        [Parameter(Mandatory)] $Payload,
        [ValidateSet("full", "replace-tail")]
        [Parameter(Mandatory)] [string]$Mode,
        [Parameter(Mandatory)] [long]$ThroughProjectionRevision,
        $FromProjectionRevision = $null,
        $ReplaceFrom = $null,
        [bool]$Complete = $true
    )

    $Payload.recent = $Mode -eq "replace-tail"
    $Payload.projectionWindow = [pscustomobject]@{
        mode = $Mode
        replaceFrom = $ReplaceFrom
        complete = $Complete
        fromProjectionRevision = $FromProjectionRevision
        throughProjectionRevision = $ThroughProjectionRevision
    }
}

function Assert-SnapshotsEqual {
    param(
        [Parameter(Mandatory)] $Before,
        [Parameter(Mandatory)] $After,
        [Parameter(Mandatory)] [string]$Message
    )

    $beforeJson = $Before | ConvertTo-Json -Depth 4 -Compress
    $afterJson = $After | ConvertTo-Json -Depth 4 -Compress
    Assert-True ($beforeJson -eq $afterJson) $Message
}

function Invoke-LocalSync {
    param(
        [Parameter(Mandatory)] [string]$Source,
        [Parameter(Mandatory)] [string]$Root,
        [switch]$Fast,
        [switch]$RespectProbe,
        [ValidateSet("", "AfterFragments", "AfterHead")]
        [string]$TestFailurePoint = ""
    )
    $arguments = @{
        OutputPath = Join-Path $Root "public-events.json"
        RecentOutputPath = Join-Path $Root "public-events-recent.json"
        IndexOutputPath = Join-Path $Root "public-events-index.json"
        SyncStatePath = Join-Path $Root "public-events-sync-state.json"
        PageSize = 2
        RecentEventLimit = 4
    }
    if (-not $RespectProbe) { $arguments["Force"] = $true }
    if ($Fast) {
        $arguments["RecentSourcePayloadPath"] = $Source
        $arguments["Fast"] = $true
        if ($TestFailurePoint) { $arguments["TestFailurePoint"] = $TestFailurePoint }
    }
    else {
        $arguments["SourcePayloadPath"] = $Source
    }
    & $syncScript @arguments | Out-Null
}

function Assert-CanonicalRejectedWithoutArtifactChange {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] $Payload,
        [Parameter(Mandatory)] [string]$Root,
        [switch]$Fast
    )

    $safeName = $Name -replace '[^A-Za-z0-9_-]', '-'
    $sourcePath = Join-Path $tempRoot "invalid-$safeName.json"
    Write-TestJson -Path $sourcePath -Value $Payload
    $before = Get-PublicJsonSnapshot -Root $Root
    $rejected = $false
    try { Invoke-LocalSync -Source $sourcePath -Root $Root -Fast:$Fast }
    catch { $rejected = $true }
    Assert-True $rejected "La projection canonique invalide '$Name' a été acceptée."
    $after = Get-PublicJsonSnapshot -Root $Root
    Assert-SnapshotsEqual -Before $before -After $after -Message "La projection canonique invalide '$Name' a modifié un artefact actif."
}

try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $legacyRoot = Join-Path $tempRoot "legacy"
    New-Item -ItemType Directory -Force -Path $legacyRoot | Out-Null
    Invoke-LocalSync -Source $samplePath -Root $legacyRoot

    $manifestPath = Join-Path $legacyRoot "public-events-manifest-v6.json"
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $headResult = Get-ManifestHead -Root $legacyRoot -Manifest $manifest
    $headPath = $headResult.Path
    $head = $headResult.Payload
    Assert-True ($manifest.schemaVersion -eq 6) "Le manifeste n'utilise pas le schéma v6."
    Assert-True ($manifest.counts.echoes -eq 6) "Le manifeste ne compte pas tous les échos de l'exemple."
    Assert-True ($head.baseGenerationId -eq $manifest.generationId) "La tête ne référence pas la génération active."
    Assert-True ($manifest.head.path -eq "data/public-events-v6/$($manifest.generationId)/head.json") "La tête n'est pas une ressource immuable de la génération."
    Assert-True (("sha256:" + (Get-FileHash -LiteralPath $headPath -Algorithm SHA256).Hash.ToLowerInvariant()) -eq $manifest.head.sha256) "Le hash de la tête ne correspond pas au manifeste."
    Assert-True (@($head.events).Count -le 7) "La tête v6 dépasse la limite de sept échos."
    Assert-True ((Get-Item -LiteralPath $manifestPath).LastWriteTimeUtc -ge (Get-Item -LiteralPath $headPath).LastWriteTimeUtc) "Le manifeste n'a pas été publié après la tête."

    foreach ($day in @($manifest.days)) {
        $fragmentPath = Get-ContractPath -Root $legacyRoot -RelativePath $day.path
        $dailyPath = Get-ContractPath -Root $legacyRoot -RelativePath $day.dailyPath
        Assert-True (Test-Path -LiteralPath $fragmentPath -PathType Leaf) "Un fragment référencé est absent: $($day.path)"
        Assert-True (Test-Path -LiteralPath $dailyPath -PathType Leaf) "Un résumé référencé est absent: $($day.dailyPath)"
        Assert-True ((Get-Item -LiteralPath $manifestPath).LastWriteTimeUtc -ge (Get-Item -LiteralPath $fragmentPath).LastWriteTimeUtc) "Le manifeste a été publié avant un fragment."
        Assert-True ((Get-Item -LiteralPath $manifestPath).LastWriteTimeUtc -ge (Get-Item -LiteralPath $dailyPath).LastWriteTimeUtc) "Le manifeste a été publié avant un résumé quotidien."
        Assert-True ($day.dailyPath -like "data/public-daily/$($manifest.generationId)/*") "Le résumé quotidien n'est pas versionné par génération."
        Assert-True (("sha256:" + (Get-FileHash -LiteralPath $fragmentPath -Algorithm SHA256).Hash.ToLowerInvariant()) -eq $day.sha256) "Le hash d'un fragment ne correspond pas au manifeste."
        Assert-True (("sha256:" + (Get-FileHash -LiteralPath $dailyPath -Algorithm SHA256).Hash.ToLowerInvariant()) -eq $day.dailySha256) "Le hash d'un résumé ne correspond pas au manifeste."
        $fragment = Get-Content -LiteralPath $fragmentPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $daily = Get-Content -LiteralPath $dailyPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-True ($fragment.generationId -eq $manifest.generationId) "Un fragment appartient à une autre génération."
        Assert-True ($daily.generationId -eq $manifest.generationId) "Un résumé appartient à une autre génération."
        Assert-True ($daily.PSObject.Properties.Name -notcontains "events") "Le résumé quotidien contient le tableau détaillé des échos."
        Assert-True ($daily.digest.PSObject.Properties.Name -contains "totals") "Le résumé quotidien ne contient pas le digest précalculé."
        Assert-True ($daily.digest.totals.capture -eq 2 -and $daily.digest.totals.production -eq 40 -and $daily.digest.totals.build -eq 26) "Le digest quotidien ne conserve pas les quantités métier attendues."
    }

    $pagePath = Join-Path $legacyRoot "public-events-page-0001.json"
    $indexPath = Join-Path $legacyRoot "public-events-index.json"
    $pageHash = (Get-FileHash -LiteralPath $pagePath -Algorithm SHA256).Hash
    $indexHash = (Get-FileHash -LiteralPath $indexPath -Algorithm SHA256).Hash
    $manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
    $headHash = (Get-FileHash -LiteralPath $headPath -Algorithm SHA256).Hash
    Invoke-LocalSync -Source $samplePath -Root $legacyRoot -Fast
    $fastHead = Get-Content -LiteralPath $headPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ((Get-FileHash -LiteralPath $pagePath -Algorithm SHA256).Hash -eq $pageHash) "Le mode rapide a modifié la page v5 et peut créer une coupure de pagination."
    Assert-True ((Get-FileHash -LiteralPath $indexPath -Algorithm SHA256).Hash -eq $indexHash) "Le mode rapide a modifié l'index v5 sans réconciliation complète."
    Assert-True ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -eq $manifestHash) "Le mode rapide a remplacé le manifeste complet."
    Assert-True ((Get-FileHash -LiteralPath $headPath -Algorithm SHA256).Hash -eq $headHash) "Le mode rapide a rattaché de nouveaux échos à une ancienne génération v6."
    Assert-True ($fastHead.baseGenerationId -eq $manifest.generationId) "La tête rapide n'est pas rattachée à la génération active."

    # Le mode rapide compatible v5 applique exactement la même projection
    # publique que le mode complet : nettoyage, dédoublonnage de session et
    # regroupement des observations détaillées.
    $legacyParityPath = Join-Path $tempRoot "legacy-parity.json"
    $legacyParityFullRoot = Join-Path $tempRoot "legacy-parity-full"
    $legacyParityFastRoot = Join-Path $tempRoot "legacy-parity-fast"
    $legacyIp = @(8, 8, 4, 4) -join "."
    $legacyParityPayload = [ordered]@{
        version = 5; ok = $true; revision = "5:legacy-parity"; updatedAt = "2026-07-18T12:05:00-04:00"; recent = $false; truncated = $false
        summary = [ordered]@{ events = 6; totalEvents = 6; firstAt = "2026-07-18T11:59:30-04:00"; lastAt = "2026-07-18T12:04:00-04:00" }
        events = @(
            [ordered]@{ key = "legacy-craft-2"; id = 6; occurredAt = "2026-07-18T12:04:00-04:00"; type = "craft"; player = "Joueuse"; guild = $null; base = "Atelier"; title = "Fabrication"; message = "Une fabrication est observée."; display = [ordered]@{ headline = "Fabrication"; body = "Une fabrication est observée."; bullets = @() }; details = [ordered]@{ items = @([ordered]@{ name = "Lingot"; added = 2 }) }; confidence = "confirmed"; icon = $null; source = "save" },
            [ordered]@{ key = "legacy-craft-1"; id = 5; occurredAt = "2026-07-18T12:02:00-04:00"; type = "craft"; player = "Joueuse"; guild = $null; base = "Atelier"; title = "Fabrication"; message = "Une fabrication est observée."; display = [ordered]@{ headline = "Fabrication"; body = "Une fabrication est observée."; bullets = @() }; details = [ordered]@{ items = @([ordered]@{ name = "Lingot"; added = 1 }) }; confidence = "confirmed"; icon = $null; source = "save" },
            [ordered]@{ key = "legacy-world-drop"; id = 4; occurredAt = "2026-07-18T12:01:00-04:00"; type = "build"; player = "Joueuse"; guild = $null; base = "Atelier"; title = "Construction"; message = "Un objet transitoire est observé."; display = [ordered]@{ headline = "Construction"; body = "Un objet transitoire est observé."; bullets = @() }; details = [ordered]@{ structures = @([ordered]@{ name = "CommonDropItem3D"; added = 1 }) }; confidence = "confirmed"; icon = $null; source = "save" },
            [ordered]@{ key = "legacy-journal-join"; id = 3; occurredAt = "2026-07-18T12:00:00-04:00"; type = "join"; player = "Joueuse"; guild = $null; base = $null; title = "Arrivée"; message = "Joueuse rejoint Palpagos."; display = [ordered]@{ headline = "Arrivée"; body = "Joueuse rejoint Palpagos."; bullets = @() }; details = [ordered]@{}; confidence = "confirmed"; icon = $null; source = "journal" },
            [ordered]@{ key = "legacy-players-join"; id = 2; occurredAt = "2026-07-18T11:59:30-04:00"; type = "join"; player = "Joueuse"; guild = $null; base = $null; title = "Arrivée détectée"; message = "Joueuse est détectée en ligne."; display = [ordered]@{ headline = "Arrivée détectée"; body = "Joueuse est détectée en ligne."; bullets = @() }; details = [ordered]@{}; confidence = "derived"; icon = $null; source = "players" },
            [ordered]@{ key = "legacy-server"; id = 1; occurredAt = "2026-07-18T11:58:00-04:00"; type = "server"; player = $null; guild = $null; base = $null; title = "Diagnostic"; message = "Diagnostic à l'adresse $legacyIp."; display = [ordered]@{ headline = "Diagnostic"; body = "Diagnostic à l'adresse $legacyIp."; bullets = @() }; details = [ordered]@{}; confidence = "confirmed"; icon = $null; source = "server" }
        )
    }
    Write-TestJson -Path $legacyParityPath -Value $legacyParityPayload
    Invoke-LocalSync -Source $legacyParityPath -Root $legacyParityFullRoot
    Invoke-LocalSync -Source $legacyParityPath -Root $legacyParityFastRoot -Fast
    $legacyParityFull = Get-Content -LiteralPath (Join-Path $legacyParityFullRoot "public-events-recent.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $legacyParityFast = Get-Content -LiteralPath (Join-Path $legacyParityFastRoot "public-events-recent.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $legacyParityFullJson = @($legacyParityFull.events) | ConvertTo-Json -Depth 12 -Compress
    $legacyParityFastJson = @($legacyParityFast.events) | ConvertTo-Json -Depth 12 -Compress
    Assert-True ($legacyParityFullJson -eq $legacyParityFastJson) "Les projections v5 complète et rapide divergent. Complet: $legacyParityFullJson Rapide: $legacyParityFastJson"
    Assert-True (@($legacyParityFast.events).Count -eq 3) "La projection v5 rapide n'a pas supprimé les doublons et l'objet transitoire attendus."
    Assert-True (@($legacyParityFast.events | Where-Object { $_.source -eq "players" -and $_.type -eq "join" }).Count -eq 0) "La reprise players du journal a survécu au mode rapide."
    Assert-True (@($legacyParityFast.events | Where-Object { $_.details.aggregatedEvents -eq 2 }).Count -eq 1) "Les fabrications v5 n'ont pas été regroupées en mode rapide."
    Assert-True (($legacyParityFast | ConvertTo-Json -Depth 12 -Compress) -notmatch [regex]::Escape($legacyIp)) "Une IPv4 est restée visible dans la projection v5 rapide."

    $canonicalRoot = Join-Path $tempRoot "canonical"
    New-Item -ItemType Directory -Force -Path $canonicalRoot | Out-Null
    $canonicalPath = Join-Path $tempRoot "canonical-source.json"
    $canonicalEvents = @(
        [ordered]@{
            key = "canonical-craft-a"; id = 101; occurredAt = "2026-07-18T08:04:00-04:00"; type = "craft"
            player = "Joueuse"; guild = $null; base = "Atelier"; title = "Fabrication A"; message = "Une fabrication."
            display = [ordered]@{ headline = "Fabrication A"; body = "Une fabrication."; bullets = @() }
            details = [ordered]@{ aggregatedEvents = 2; items = @([ordered]@{ name = "Lingot"; added = 1 }) }
            confidence = "confirmed"; icon = $null; source = "save"
        },
        [ordered]@{
            key = "canonical-craft-b"; id = 100; occurredAt = "2026-07-17T08:03:00-04:00"; type = "craft"
            player = "Joueuse"; guild = $null; base = "Atelier"; title = "Fabrication B"; message = "Une autre fabrication."
            display = [ordered]@{ headline = "Fabrication B"; body = "Une autre fabrication."; bullets = @() }
            details = [ordered]@{ aggregatedEvents = 2; items = @([ordered]@{ name = "Lingot"; added = 1 }) }
            confidence = "confirmed"; icon = $null; source = "save"
        }
    )
    $canonicalPayload = [ordered]@{
        version = 6; schemaVersion = 6; projection = "canonical-echoes"; projectionRevision = 10; provenanceRevision = "provenance-a"; ok = $true
        revision = "6:canonical-test"; updatedAt = "2026-07-18T08:05:00-04:00"; recent = $false; truncated = $false
        provenance = [ordered]@{
            observedAt = "2026-07-18T08:05:00-04:00"; sourceUpdatedAt = "2026-07-18T08:04:00-04:00"
            gameVersion = "v1"; steamBuildId = "100"; parserCommit = "parser-a"; catalogCommit = "catalog-a"
            schemaVersion = 6; freshness = "current"; sourceStatus = "available"
        }
        projectionWindow = [ordered]@{
            mode = "full"; replaceFrom = $null; complete = $true
            fromProjectionRevision = $null; throughProjectionRevision = 10
        }
        summary = [ordered]@{
            rawEvents = 4; publicEvents = 4; echoes = 2; representedEvents = 4
            totalEchoes = 2; totalRepresentedEvents = 4; events = 2; totalEvents = 4
        }
        events = $canonicalEvents
    }
    [IO.File]::WriteAllText($canonicalPath, (($canonicalPayload | ConvertTo-Json -Depth 12) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    Invoke-LocalSync -Source $canonicalPath -Root $canonicalRoot
    $canonicalManifest = Get-Content -LiteralPath (Join-Path $canonicalRoot "public-events-manifest-v6.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $activePointer = Get-Content -LiteralPath (Join-Path $canonicalRoot "public-events-head-v6.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $immutableManifestPath = Get-ContractPath -Root $canonicalRoot -RelativePath ([string]$activePointer.manifest.path)
    $immutableManifest = Get-Content -LiteralPath $immutableManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($canonicalManifest.counts.echoes -eq 2) "La projection canonique a été regroupée une seconde fois côté Windows."
    Assert-True ($canonicalManifest.counts.rawEvents -eq 4 -and $canonicalManifest.counts.representedEvents -eq 4) "Les comptes distincts de la projection canonique ont été perdus."
    Assert-True ($activePointer.baseGenerationId -eq $canonicalManifest.generationId -and $immutableManifest.generationId -eq $canonicalManifest.generationId) "Le pointeur actif ne référence pas le manifeste immuable courant."
    Assert-True (("sha256:" + (Get-FileHash -LiteralPath $immutableManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()) -eq $activePointer.manifest.sha256) "L'empreinte du manifeste immuable ne correspond pas au pointeur actif."

    # Une nouvelle observation peut remplacer toute la queue canonique sans
    # ajouter d'écho distinct : le premier craft standalone devient un agrégat
    # avec une autre clé. La borne explicite permet ce remplacement sans refaire
    # le regroupement côté Windows.
    $tailRoot = Join-Path $tempRoot "canonical-tail-replacement"
    $tailPath = Join-Path $tempRoot "canonical-tail-replacement.json"
    $tailFull = Copy-JsonValue -Value $canonicalPayload
    $tailFull.events = [object[]]@([pscustomobject]@{
        key = "raw-craft-one"; id = 401; occurredAt = "2026-07-18T10:01:00-04:00"; type = "craft"
        player = "Joueuse"; guild = $null; base = "Atelier"; title = "Fabrication"; message = "Joueuse fabrique 2 Bois."
        display = [pscustomobject]@{ headline = "Fabrication"; body = "Joueuse fabrique 2 Bois."; bullets = @("+2 Bois") }
        details = [pscustomobject]@{ items = @([pscustomobject]@{ name = "Bois"; added = 2; count = 2 }) }
        confidence = "confirmed"; icon = $null; source = "save"
    })
    $tailFull.revision = "6:tail:20"
    $tailFull.projectionRevision = 20
    $tailFull.summary = [pscustomobject]@{ rawEvents = 1; publicEvents = 1; echoes = 1; representedEvents = 1; totalEchoes = 1; totalRepresentedEvents = 1; events = 1; totalEvents = 1 }
    Set-TestProjectionWindow -Payload $tailFull -Mode full -ThroughProjectionRevision 20
    Write-TestJson -Path $tailPath -Value $tailFull
    Invoke-LocalSync -Source $tailPath -Root $tailRoot
    $tailColdPagePath = Join-Path $tailRoot "public-events-page-0001.json"
    $tailColdPageHash = (Get-FileHash -LiteralPath $tailColdPagePath -Algorithm SHA256).Hash
    $tailV5FullRecent = Get-Content -LiteralPath (Join-Path $tailRoot "public-events-recent.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($tailV5FullRecent.version -eq 5 -and $tailV5FullRecent.projectionWindow.mode -eq "full") "Le checkpoint canonique n'a pas relayé sa fenêtre dans le récent v5."

    $tailRecent = Copy-JsonValue -Value $tailFull
    $tailRecent.events = [object[]]@([pscustomobject]@{
        key = "public-group:craft:joueuse:2026-07-18T10:00:00-04:00"; id = 402; occurredAt = "2026-07-18T10:02:00-04:00"; type = "craft"
        player = "Joueuse"; guild = $null; base = "Atelier"; title = "Fabrications terminées"; message = "Joueuse termine 5 fabrications."
        display = [pscustomobject]@{ headline = "Fabrications terminées"; body = "Joueuse termine 5 fabrications."; bullets = @("+5 Bois") }
        details = [pscustomobject]@{ aggregatedEvents = 2; items = @([pscustomobject]@{ name = "Bois"; added = 5; count = 5 }) }
        confidence = "confirmed"; icon = $null; source = "save"
    })
    $tailRecent.revision = "6:tail:21"
    $tailRecent.projectionRevision = 21
    $tailRecent.summary = [pscustomobject]@{ rawEvents = 2; publicEvents = 2; echoes = 1; representedEvents = 2; totalEchoes = 1; totalRepresentedEvents = 2; events = 1; totalEvents = 2 }
    Set-TestProjectionWindow -Payload $tailRecent -Mode replace-tail -FromProjectionRevision 20 -ThroughProjectionRevision 21 -ReplaceFrom "2026-07-18T10:00:00-04:00"
    Write-TestJson -Path $tailPath -Value $tailRecent
    Invoke-LocalSync -Source $tailPath -Root $tailRoot -Fast
    $tailV5Recent = Get-Content -LiteralPath (Join-Path $tailRoot "public-events-recent.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $tailManifest = Get-Content -LiteralPath (Join-Path $tailRoot "public-events-manifest-v6.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $tailFragment = Get-Content -LiteralPath (Get-ContractPath -Root $tailRoot -RelativePath ([string]$tailManifest.days[0].path)) -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ((Get-FileHash -LiteralPath $tailColdPagePath -Algorithm SHA256).Hash -eq $tailColdPageHash) "Le remplacement rapide a réécrit la page froide v5."
    Assert-True ($tailV5Recent.version -eq 5 -and $tailV5Recent.projectionRevision -eq 21) "Le récent de compatibilité n'a pas avancé avec la projection canonique."
    Assert-True ($tailV5Recent.projectionWindow.mode -eq "replace-tail" -and $tailV5Recent.projectionWindow.complete -and $tailV5Recent.projectionWindow.replaceFrom -eq "2026-07-18T10:00:00-04:00") "Le récent v5 n'a pas relayé la fenêtre de remplacement canonique."
    Assert-True ($tailManifest.counts.echoes -eq 1 -and $tailManifest.counts.representedEvents -eq 2 -and $tailManifest.cursor.maxId -eq 402) "Le remplacement de queue n'a pas conservé les comptes globaux du producteur."
    Assert-True (@($tailFragment.events).Count -eq 1 -and $tailFragment.events[0].key -eq $tailRecent.events[0].key -and $tailFragment.events[0].details.aggregatedEvents -eq 2) "Le standalone n'a pas été remplacé exactement une fois par l'agrégat."
    Assert-True ($tailManifest.facets.types[0].count -eq 1 -and $tailManifest.facets.players[0].count -eq 1) "Le remplacement de queue a doublé les facettes."

    $tailThird = Copy-JsonValue -Value $tailRecent
    $tailThird.events[0].id = 403
    $tailThird.events[0].occurredAt = "2026-07-18T10:03:00-04:00"
    $tailThird.events[0].details.aggregatedEvents = 3
    $tailThird.events[0].details.items[0].added = 7
    $tailThird.revision = "6:tail:22"
    $tailThird.projectionRevision = 22
    $tailThird.summary = [pscustomobject]@{ rawEvents = 3; publicEvents = 3; echoes = 1; representedEvents = 3; totalEchoes = 1; totalRepresentedEvents = 3; events = 1; totalEvents = 3 }
    Set-TestProjectionWindow -Payload $tailThird -Mode replace-tail -FromProjectionRevision 20 -ThroughProjectionRevision 22 -ReplaceFrom "2026-07-18T10:00:00-04:00"
    Write-TestJson -Path $tailPath -Value $tailThird
    Invoke-LocalSync -Source $tailPath -Root $tailRoot -Fast
    $tailThirdManifest = Get-Content -LiteralPath (Join-Path $tailRoot "public-events-manifest-v6.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $tailThirdFragment = Get-Content -LiteralPath (Get-ContractPath -Root $tailRoot -RelativePath ([string]$tailThirdManifest.days[0].path)) -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($tailThirdManifest.counts.echoes -eq 1 -and $tailThirdManifest.counts.representedEvents -eq 3 -and $tailThirdManifest.cursor.maxId -eq 403) "Le troisième craft n'a pas actualisé l'agrégat et son curseur."
    Assert-True (@($tailThirdFragment.events).Count -eq 1 -and $tailThirdFragment.events[0].id -eq 403 -and $tailThirdFragment.events[0].details.aggregatedEvents -eq 3) "Le troisième craft a laissé une ancienne version de l'agrégat."
    Assert-True ($tailThirdManifest.facets.types[0].count -eq 1 -and $tailThirdManifest.facets.players[0].count -eq 1) "Le second remplacement de queue a dérivé les facettes."
    $tailUnchanged = Get-V6FileSnapshot -Root $tailRoot
    Invoke-LocalSync -Source $tailPath -Root $tailRoot -Fast
    Assert-SnapshotsEqual -Before $tailUnchanged -After (Get-V6FileSnapshot -Root $tailRoot) -Message "La même queue canonique a été publiée deux fois."

    # Deux exports récents peuvent être produits avant le prochain passage
    # Windows. Une fenêtre rolling qui commence à la révision locale couvre les
    # deux changements; une fenêtre plus récente force au contraire le full.
    $rollingRoot = Join-Path $tempRoot "canonical-tail-rolling"
    Write-TestJson -Path $tailPath -Value $tailFull
    Invoke-LocalSync -Source $tailPath -Root $rollingRoot
    $rollingRecent = Copy-JsonValue -Value $tailThird
    Write-TestJson -Path $tailPath -Value $rollingRecent
    Invoke-LocalSync -Source $tailPath -Root $rollingRoot -Fast
    $rollingManifest = Get-Content -LiteralPath (Join-Path $rollingRoot "public-events-manifest-v6.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($rollingManifest.sourceProjectionRevision -eq 22 -and $rollingManifest.counts.echoes -eq 1 -and $rollingManifest.counts.representedEvents -eq 3) "La fenêtre rolling n'a pas réconcilié deux exports sautés."

    $gapRoot = Join-Path $tempRoot "canonical-tail-gap"
    Write-TestJson -Path $tailPath -Value $tailFull
    Invoke-LocalSync -Source $tailPath -Root $gapRoot
    Set-TestProjectionWindow -Payload $rollingRecent -Mode replace-tail -FromProjectionRevision 21 -ThroughProjectionRevision 22 -ReplaceFrom "2026-07-18T10:00:00-04:00"
    Write-TestJson -Path $tailPath -Value $rollingRecent
    $gapSnapshot = Get-V6FileSnapshot -Root $gapRoot
    $gapRecentHash = (Get-FileHash -LiteralPath (Join-Path $gapRoot "public-events-recent.json") -Algorithm SHA256).Hash
    Invoke-LocalSync -Source $tailPath -Root $gapRoot -Fast
    Assert-SnapshotsEqual -Before $gapSnapshot -After (Get-V6FileSnapshot -Root $gapRoot) -Message "Une fenêtre qui ne couvre pas la révision locale a modifié la génération active."
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $gapRoot "public-events-recent.json") -Algorithm SHA256).Hash -eq $gapRecentHash) "Une fenêtre incomplète a remplacé le flux récent stable."
    $gapState = Get-Content -LiteralPath (Join-Path $gapRoot "public-events-sync-state.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($gapState.requiresReprojection -and $gapState.reprojectionReason -eq "projection-window-revision-gap") "Le saut de révision non couvert n'a pas demandé le full."

    $mixedCorrectionRoot = Join-Path $tempRoot "canonical-tail-mixed-correction"
    Write-TestJson -Path $tailPath -Value $tailFull
    Invoke-LocalSync -Source $tailPath -Root $mixedCorrectionRoot
    $mixedCorrection = Copy-JsonValue -Value $tailFull
    $correctedHistoricalCraft = Copy-JsonValue -Value $tailFull.events[0]
    $correctedHistoricalCraft.message = "Cette ancienne observation a été modifiée."
    $mixedCorrection.events = [object[]]@(
        [pscustomobject]@{
            key = "new-server-append"; id = 402; occurredAt = "2026-07-18T10:02:00-04:00"; type = "server"
            player = $null; guild = $null; base = $null; title = "Nouvel écho"; message = "Un nouvel écho est confirmé."
            display = [pscustomobject]@{ headline = "Nouvel écho"; body = "Un nouvel écho est confirmé."; bullets = @() }
            details = [pscustomobject]@{}; confidence = "confirmed"; icon = $null; source = "journal"
        },
        $correctedHistoricalCraft
    )
    $mixedCorrection.revision = "6:mixed-correction:21"
    $mixedCorrection.projectionRevision = 21
    $mixedCorrection.summary = [pscustomobject]@{ rawEvents = 2; publicEvents = 2; echoes = 2; representedEvents = 2; totalEchoes = 2; totalRepresentedEvents = 2; events = 2; totalEvents = 2 }
    Set-TestProjectionWindow -Payload $mixedCorrection -Mode replace-tail -FromProjectionRevision 20 -ThroughProjectionRevision 21 -ReplaceFrom "2026-07-18T10:00:00-04:00"
    Write-TestJson -Path $tailPath -Value $mixedCorrection
    $mixedSnapshot = Get-V6FileSnapshot -Root $mixedCorrectionRoot
    $mixedRecentHash = (Get-FileHash -LiteralPath (Join-Path $mixedCorrectionRoot "public-events-recent.json") -Algorithm SHA256).Hash
    Invoke-LocalSync -Source $tailPath -Root $mixedCorrectionRoot -Fast
    Assert-SnapshotsEqual -Before $mixedSnapshot -After (Get-V6FileSnapshot -Root $mixedCorrectionRoot) -Message "Une correction historique mêlée à un append a modifié la génération active."
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $mixedCorrectionRoot "public-events-recent.json") -Algorithm SHA256).Hash -eq $mixedRecentHash) "Une correction historique mêlée à un append a remplacé le flux récent stable."
    $mixedState = Get-Content -LiteralPath (Join-Path $mixedCorrectionRoot "public-events-sync-state.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($mixedState.requiresReprojection -and $mixedState.reprojectionReason -eq "historical-event-inside-tail") "Une correction d'identifiant déjà projeté n'a pas demandé le full."

    # À heure égale, le producteur canonique ordonne les départs avant les
    # observations de sauvegarde, puis les arrivées. L'identifiant ne départage
    # que deux événements de même rang.
    $sameTimeRoot = Join-Path $tempRoot "canonical-same-time-order"
    $sameTimePath = Join-Path $tempRoot "canonical-same-time-order.json"
    $sameTimePayload = Copy-JsonValue -Value $canonicalPayload
    $sameOccurredAt = "2026-07-18T11:00:00-04:00"
    $sameTimePayload.events = [object[]]@(
        [pscustomobject]@{ key = "same-time-leave"; id = 901; occurredAt = $sameOccurredAt; type = "leave"; player = "Joueuse"; guild = $null; base = $null; title = "Départ"; message = "Joueuse quitte Palpagos."; display = [pscustomobject]@{ headline = "Départ"; body = "Joueuse quitte Palpagos."; bullets = @() }; details = [pscustomobject]@{}; confidence = "confirmed"; icon = $null; source = "journal" },
        [pscustomobject]@{ key = "same-time-save-high"; id = 950; occurredAt = $sameOccurredAt; type = "discovery"; player = "Joueuse"; guild = $null; base = $null; title = "Découverte"; message = "Une découverte est confirmée."; display = [pscustomobject]@{ headline = "Découverte"; body = "Une découverte est confirmée."; bullets = @() }; details = [pscustomobject]@{}; confidence = "confirmed"; icon = $null; source = "save" },
        [pscustomobject]@{ key = "same-time-save-low"; id = 949; occurredAt = $sameOccurredAt; type = "capture"; player = "Joueuse"; guild = $null; base = $null; title = "Capture"; message = "Une capture est confirmée."; display = [pscustomobject]@{ headline = "Capture"; body = "Une capture est confirmée."; bullets = @() }; details = [pscustomobject]@{}; confidence = "derived"; icon = $null; source = "save" },
        [pscustomobject]@{ key = "same-time-join"; id = 999; occurredAt = $sameOccurredAt; type = "join"; player = "Joueuse"; guild = $null; base = $null; title = "Arrivée"; message = "Joueuse rejoint Palpagos."; display = [pscustomobject]@{ headline = "Arrivée"; body = "Joueuse rejoint Palpagos."; bullets = @() }; details = [pscustomobject]@{}; confidence = "confirmed"; icon = $null; source = "players" }
    )
    $sameTimePayload.revision = "6:same-time-order"
    $sameTimePayload.projectionRevision = 12
    Set-TestProjectionWindow -Payload $sameTimePayload -Mode full -ThroughProjectionRevision 12
    $sameTimePayload.summary = [pscustomobject]@{ rawEvents = 4; publicEvents = 4; echoes = 4; representedEvents = 4; totalEchoes = 4; totalRepresentedEvents = 4; events = 4; totalEvents = 4 }
    Write-TestJson -Path $sameTimePath -Value $sameTimePayload
    Invoke-LocalSync -Source $sameTimePath -Root $sameTimeRoot
    $sameTimePublished = Get-Content -LiteralPath (Join-Path $sameTimeRoot "public-events-recent.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $sameTimeManifest = Get-Content -LiteralPath (Join-Path $sameTimeRoot "public-events-manifest-v6.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $sameTimeHead = (Get-ManifestHead -Root $sameTimeRoot -Manifest $sameTimeManifest).Payload
    $sameTimeFragment = Get-Content -LiteralPath (Get-ContractPath -Root $sameTimeRoot -RelativePath ([string]$sameTimeManifest.days[0].path)) -Raw -Encoding UTF8 | ConvertFrom-Json
    $expectedSameTimeOrder = "same-time-leave|same-time-save-high|same-time-save-low|same-time-join"
    Assert-True ((@($sameTimePublished.events | ForEach-Object { $_.key }) -join "|") -eq $expectedSameTimeOrder) "L'ordre canonique à heure égale n'a pas été conservé dans le contrat compatible."
    Assert-True ((@($sameTimeHead.events | ForEach-Object { $_.key }) -join "|") -eq $expectedSameTimeOrder) "La tête v6 a défait l'ordre canonique à heure égale."
    Assert-True ((@($sameTimeFragment.events | ForEach-Object { $_.key }) -join "|") -eq $expectedSameTimeOrder) "Le fragment v6 a défait l'ordre canonique à heure égale."

    # Le contrat strict refuse toute ambiguïté avant la première écriture. Les
    # snapshots couvrent tous les JSON actifs, pas seulement le manifeste v6.
    foreach ($name in @("revision", "projectionRevision", "provenanceRevision", "provenance", "projectionWindow", "recent", "events")) {
        $invalid = Copy-JsonValue -Value $canonicalPayload
        $invalid.PSObject.Properties.Remove($name)
        Assert-CanonicalRejectedWithoutArtifactChange -Name "missing-$name" -Payload $invalid -Root $canonicalRoot
    }
    foreach ($name in @("observedAt", "sourceUpdatedAt", "gameVersion", "steamBuildId", "parserCommit", "catalogCommit", "schemaVersion", "freshness", "sourceStatus")) {
        $invalid = Copy-JsonValue -Value $canonicalPayload
        $invalid.provenance.PSObject.Properties.Remove($name)
        Assert-CanonicalRejectedWithoutArtifactChange -Name "missing-provenance-$name" -Payload $invalid -Root $canonicalRoot
    }
    foreach ($name in @("events", "totalEvents", "rawEvents", "publicEvents", "echoes", "representedEvents", "totalEchoes", "totalRepresentedEvents")) {
        $invalid = Copy-JsonValue -Value $canonicalPayload
        $invalid.summary.PSObject.Properties.Remove($name)
        Assert-CanonicalRejectedWithoutArtifactChange -Name "missing-summary-$name" -Payload $invalid -Root $canonicalRoot
    }
    foreach ($name in @("mode", "replaceFrom", "complete", "fromProjectionRevision", "throughProjectionRevision")) {
        $invalid = Copy-JsonValue -Value $canonicalPayload
        $invalid.projectionWindow.PSObject.Properties.Remove($name)
        Assert-CanonicalRejectedWithoutArtifactChange -Name "missing-window-$name" -Payload $invalid -Root $canonicalRoot
    }

    $strictCases = @(
        [pscustomobject]@{ Name = "wrong-version"; Mutate = { param($p) $p.version = 5 } },
        [pscustomobject]@{ Name = "wrong-schema"; Mutate = { param($p) $p.schemaVersion = 5 } },
        [pscustomobject]@{ Name = "wrong-projection"; Mutate = { param($p) $p.projection = "events" } },
        [pscustomobject]@{ Name = "empty-revision"; Mutate = { param($p) $p.revision = "" } },
        [pscustomobject]@{ Name = "fractional-projection-revision"; Mutate = { param($p) $p.projectionRevision = 1.5 } },
        [pscustomobject]@{ Name = "empty-provenance-revision"; Mutate = { param($p) $p.provenanceRevision = "" } },
        [pscustomobject]@{ Name = "wrong-provenance-schema"; Mutate = { param($p) $p.provenance.schemaVersion = 5 } },
        [pscustomobject]@{ Name = "wrong-window-mode"; Mutate = { param($p) $p.projectionWindow.mode = "replace-tail" } },
        [pscustomobject]@{ Name = "wrong-window-through"; Mutate = { param($p) $p.projectionWindow.throughProjectionRevision = 9 } },
        [pscustomobject]@{ Name = "non-boolean-window-complete"; Mutate = { param($p) $p.projectionWindow.complete = "true" } },
        [pscustomobject]@{ Name = "events-object"; Mutate = { param($p) $p.events = [pscustomobject]@{ key = "not-an-array" } } },
        [pscustomobject]@{ Name = "events-null-member"; Mutate = { param($p) $p.events = [object[]]@($p.events[0], $null) } },
        [pscustomobject]@{ Name = "events-scalar-member"; Mutate = { param($p) $p.events = [object[]]@($p.events[0], 42) } },
        [pscustomobject]@{ Name = "id-zero"; Mutate = { param($p) $p.events[0].id = 0 } },
        [pscustomobject]@{ Name = "id-fractional"; Mutate = { param($p) $p.events[0].id = 1.5 } },
        [pscustomobject]@{ Name = "id-duplicate"; Mutate = { param($p) $p.events[1].id = $p.events[0].id } },
        [pscustomobject]@{ Name = "date-without-zone"; Mutate = { param($p) $p.events[0].occurredAt = "2026-07-18T08:04:00" } },
        [pscustomobject]@{ Name = "confidence-missing"; Mutate = { param($p) $p.events[0].PSObject.Properties.Remove("confidence") } },
        [pscustomobject]@{ Name = "confidence-unknown"; Mutate = { param($p) $p.events[0].confidence = "probable" } },
        [pscustomobject]@{ Name = "canonical-order"; Mutate = { param($p) $p.events = [object[]]@($p.events[1], $p.events[0]) } },
        [pscustomobject]@{ Name = "echo-count"; Mutate = { param($p) $p.summary.echoes = 1 } },
        [pscustomobject]@{ Name = "represented-count"; Mutate = { param($p) $p.summary.representedEvents = 3 } },
        [pscustomobject]@{ Name = "public-count"; Mutate = { param($p) $p.summary.publicEvents = 3 } },
        [pscustomobject]@{ Name = "recent-total-echoes"; Mutate = { param($p) $p.recent = $true; $p.projectionWindow.mode = "replace-tail"; $p.projectionWindow.fromProjectionRevision = 10; $p.summary.totalEchoes = 1 } },
        [pscustomobject]@{ Name = "recent-total-represented"; Mutate = { param($p) $p.recent = $true; $p.projectionWindow.mode = "replace-tail"; $p.projectionWindow.fromProjectionRevision = 10; $p.summary.totalRepresentedEvents = 3 } }
    )
    foreach ($case in $strictCases) {
        $invalid = Copy-JsonValue -Value $canonicalPayload
        & $case.Mutate $invalid
        Assert-CanonicalRejectedWithoutArtifactChange -Name $case.Name -Payload $invalid -Root $canonicalRoot
    }

    foreach ($privateKey in @("ip", "ipAddress", "address", "host", "hostname", "port", "endpoint", "url", "uri")) {
        $invalid = Copy-JsonValue -Value $canonicalPayload
        $invalid.events[0].details = [pscustomobject]@{}
        $invalid.events[0].details | Add-Member -NotePropertyName $privateKey -NotePropertyValue "masqué"
        Assert-CanonicalRejectedWithoutArtifactChange -Name "private-key-$privateKey" -Payload $invalid -Root $canonicalRoot
    }

    $ipv6Invalid = Copy-JsonValue -Value $canonicalPayload
    $ipv6Invalid.events[0].message = "Adresse IPv6 détectée : 2001:db8::1"
    Assert-CanonicalRejectedWithoutArtifactChange -Name "ipv6-literal" -Payload $ipv6Invalid -Root $canonicalRoot
    $ipv4PortInvalid = Copy-JsonValue -Value $canonicalPayload
    $ipv4WithPort = ((@(8, 8, 8, 8) -join ".") + ":8211")
    $ipv4PortInvalid.events[0].message = "Adresse détectée : $ipv4WithPort"
    Assert-CanonicalRejectedWithoutArtifactChange -Name "ipv4-with-port" -Payload $ipv4PortInvalid -Root $canonicalRoot -Fast

    # Deux processus, même depuis des sessions Windows distinctes, partagent le
    # verrou fichier du chemin de sortie. Le second quitte proprement sans
    # toucher aux artefacts pendant que le premier tient le verrou.
    $lockRoot = Join-Path $tempRoot "concurrent-lock"
    $lockOutputPath = Join-Path $lockRoot "public-events.json"
    $lockRecentPath = Join-Path $lockRoot "public-events-recent.json"
    $lockIndexPath = Join-Path $lockRoot "public-events-index.json"
    $lockStatePath = Join-Path $lockRoot "public-events-sync-state.json"
    $firstStdout = Join-Path $tempRoot "lock-first.stdout.log"
    $firstStderr = Join-Path $tempRoot "lock-first.stderr.log"
    $secondStdout = Join-Path $tempRoot "lock-second.stdout.log"
    $secondStderr = Join-Path $tempRoot "lock-second.stderr.log"
    $processArguments = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $syncScript,
        "-OutputPath", $lockOutputPath,
        "-RecentOutputPath", $lockRecentPath,
        "-IndexOutputPath", $lockIndexPath,
        "-SyncStatePath", $lockStatePath,
        "-SourcePayloadPath", $canonicalPath,
        "-PageSize", "2", "-RecentEventLimit", "4", "-Force"
    )
    $pwshPath = (Get-Process -Id $PID).Path
    $firstProcess = $null
    $secondProcess = $null
    try {
        $firstProcess = Start-Process -FilePath $pwshPath -ArgumentList @($processArguments + @("-TestHoldLockMilliseconds", "6000")) -RedirectStandardOutput $firstStdout -RedirectStandardError $firstStderr -WindowStyle Hidden -PassThru
        $lockHeld = $false
        $lockDeadline = (Get-Date).AddSeconds(5)
        while ((Get-Date) -lt $lockDeadline -and -not $lockHeld) {
            if (Test-Path -LiteralPath "$lockOutputPath.lock" -PathType Leaf) {
                try {
                    $probeLock = [IO.File]::Open("$lockOutputPath.lock", [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
                    $probeLock.Dispose()
                }
                catch [IO.IOException] { $lockHeld = $true }
            }
            if (-not $lockHeld) { Start-Sleep -Milliseconds 50 }
        }
        Assert-True $lockHeld "Le premier processus n'a pas acquis le verrou fichier."

        $secondProcess = Start-Process -FilePath $pwshPath -ArgumentList $processArguments -RedirectStandardOutput $secondStdout -RedirectStandardError $secondStderr -WindowStyle Hidden -PassThru
        Assert-True ($secondProcess.WaitForExit(5000)) "Le processus concurrent n'a pas quitté rapidement."
        $secondProcess.WaitForExit()
        $secondProcess.Refresh()
        $secondOutput = if (Test-Path -LiteralPath $secondStdout) { Get-Content -LiteralPath $secondStdout -Raw -Encoding UTF8 } else { "" }
        $secondError = if (Test-Path -LiteralPath $secondStderr) { Get-Content -LiteralPath $secondStderr -Raw -Encoding UTF8 } else { "" }
        if ($null -ne $secondProcess.ExitCode) {
            Assert-True ($secondProcess.ExitCode -eq 0) "Le processus concurrent a quitté en erreur. Sortie: $secondOutput $secondError"
        }
        Assert-True ([string]::IsNullOrWhiteSpace($secondError)) "Le processus concurrent a écrit une erreur: $secondError"
        Assert-True ($secondOutput -match "en cours") "Le processus concurrent n'a pas expliqué sa sortie propre. Sortie: $secondOutput"
        Assert-True (-not (Test-Path -LiteralPath $lockOutputPath -PathType Leaf)) "Le processus concurrent a publié pendant que le verrou était occupé."

        Assert-True ($firstProcess.WaitForExit(20000)) "Le premier processus n'a pas terminé sa synchronisation."
        $firstProcess.WaitForExit()
        $firstProcess.Refresh()
        $firstError = if (Test-Path -LiteralPath $firstStderr) { Get-Content -LiteralPath $firstStderr -Raw -Encoding UTF8 } else { "" }
        if ($null -ne $firstProcess.ExitCode) {
            Assert-True ($firstProcess.ExitCode -eq 0) "Le premier processus a quitté en erreur: $firstError"
        }
        Assert-True ([string]::IsNullOrWhiteSpace($firstError)) "Le premier processus a écrit une erreur: $firstError"
        Assert-True (Test-Path -LiteralPath $lockOutputPath -PathType Leaf) "Le détenteur du verrou n'a pas publié après sa libération."
        Assert-True (Test-Path -LiteralPath "$lockOutputPath.lock" -PathType Leaf) "Le verrou fichier stable n'a pas été conservé pour les synchronisations suivantes."
    }
    finally {
        foreach ($process in @($secondProcess, $firstProcess)) {
            if ($null -ne $process -and -not $process.HasExited) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            }
            if ($null -ne $process) { $process.Dispose() }
        }
    }

    $palDigestRoot = Join-Path $tempRoot "canonical-pal-digest"
    $palDigestPath = Join-Path $tempRoot "canonical-pal-digest.json"
    $palDigestPayload = ($canonicalPayload | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
    $palDigestPayload.events = [object[]]@([pscustomobject]@{
        key = "capture:joueuse:chillet:1"; id = 102; occurredAt = "2026-07-18T09:04:00-04:00"; type = "capture"
        player = "Joueuse"; guild = $null; base = $null; title = "Nouvelle capture"; message = "Joueuse capture Chillet."
        display = [pscustomobject]@{ headline = "Joueuse capture Chillet"; body = "La capture est confirmée."; bullets = @("+1 Chillet") }
        details = [pscustomobject]@{ pals = @([pscustomobject]@{ name = "Chillet"; count = 1 }) }
        confidence = "confirmed"; icon = $null; source = "save"
    })
    $palDigestPayload.revision = "6:canonical-pal-digest"
    $palDigestPayload.projectionRevision = 11
    Set-TestProjectionWindow -Payload $palDigestPayload -Mode full -ThroughProjectionRevision 11
    $palDigestPayload.summary = [pscustomobject]@{ rawEvents = 1; publicEvents = 1; echoes = 1; representedEvents = 1; totalEchoes = 1; totalRepresentedEvents = 1; events = 1; totalEvents = 1 }
    [IO.File]::WriteAllText($palDigestPath, (($palDigestPayload | ConvertTo-Json -Depth 12) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    Invoke-LocalSync -Source $palDigestPath -Root $palDigestRoot
    $palDigestManifest = Get-Content -LiteralPath (Join-Path $palDigestRoot "public-events-manifest-v6.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $palDigestDailyPath = Get-ContractPath -Root $palDigestRoot -RelativePath ([string]$palDigestManifest.days[0].dailyPath)
    $palDigestDaily = Get-Content -LiteralPath $palDigestDailyPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True (@($palDigestDaily.digest.palFinds).Count -eq 1 -and $palDigestDaily.digest.palFinds[0].name -eq "Chillet" -and $palDigestDaily.digest.palFinds[0].quantity -eq 1) "Le digest quotidien ne conserve pas une capture avec une seule ligne de Pal."

    $maliciousRoot = Join-Path $tempRoot "canonical-private-rejected"
    $maliciousPath = Join-Path $tempRoot "canonical-private.json"
    $maliciousPayload = ($canonicalPayload | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
    $maliciousPayload.events[0].details = [pscustomobject]@{
        structures = @([pscustomobject]@{ name = "CommonDropItem3D"; added = 1 })
        PublicIP = "SHOULD_NOT_BE_PUBLIC_IP"
        position = [pscustomobject]@{ mapX = 12; mapY = 34 }
    }
    [IO.File]::WriteAllText($maliciousPath, (($maliciousPayload | ConvertTo-Json -Depth 12) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    $privateProjectionRejected = $false
    try { Invoke-LocalSync -Source $maliciousPath -Root $maliciousRoot }
    catch { $privateProjectionRejected = $true }
    Assert-True $privateProjectionRejected "Une projection canonique contenant un objet transitoire ou une donnée privée a été acceptée."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $maliciousRoot "public-events-manifest-v6.json"))) "Une projection canonique invalide a publié un manifeste."

    # Contrôle isolé : le premier payload est publiable; le second ne diffère
    # que par une IPv4 publique littérale dans le texte de l'écho.
    $ipv4ControlRoot = Join-Path $tempRoot "canonical-ipv4-control"
    $ipv4ControlPath = Join-Path $tempRoot "canonical-ipv4-control.json"
    $ipv4ControlPayload = ($canonicalPayload | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
    $ipv4ControlPayload.events = [object[]]@([pscustomobject]@{
        key = "server:network-check"; id = 301; occurredAt = "2026-07-18T10:10:00-04:00"; type = "server"
        player = $null; guild = $null; base = $null; title = "Diagnostic réseau"; message = "Le diagnostic réseau est disponible."
        display = [pscustomobject]@{ headline = "Diagnostic réseau"; body = "Le diagnostic réseau est disponible."; bullets = @() }
        details = [pscustomobject]@{}; confidence = "confirmed"; icon = $null; source = "journal"
    })
    $ipv4ControlPayload.revision = "6:ipv4-control:1"
    $ipv4ControlPayload.projectionRevision = 1
    Set-TestProjectionWindow -Payload $ipv4ControlPayload -Mode full -ThroughProjectionRevision 1
    $ipv4ControlPayload.summary = [pscustomobject]@{ rawEvents = 1; publicEvents = 1; echoes = 1; representedEvents = 1; totalEchoes = 1; totalRepresentedEvents = 1; events = 1; totalEvents = 1 }
    [IO.File]::WriteAllText($ipv4ControlPath, (($ipv4ControlPayload | ConvertTo-Json -Depth 12) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    Invoke-LocalSync -Source $ipv4ControlPath -Root $ipv4ControlRoot
    Assert-True (Test-Path -LiteralPath (Join-Path $ipv4ControlRoot "public-events-manifest-v6.json") -PathType Leaf) "Le contrôle sans IPv4 publique aurait dû être accepté."

    $ipv4RejectedRoot = Join-Path $tempRoot "canonical-ipv4-rejected"
    $ipv4RejectedPath = Join-Path $tempRoot "canonical-ipv4-rejected.json"
    $ipv4RejectedPayload = ($ipv4ControlPayload | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
    $publicIpv4Literal = @(8, 8, 4, 4) -join "."
    $ipv4RejectedPayload.events[0].message = "Adresse publique détectée : $publicIpv4Literal"
    $ipv4RejectedPayload.events[0].display.body = "Adresse publique détectée : $publicIpv4Literal"
    [IO.File]::WriteAllText($ipv4RejectedPath, (($ipv4RejectedPayload | ConvertTo-Json -Depth 12) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    $literalIpv4Rejected = $false
    try { Invoke-LocalSync -Source $ipv4RejectedPath -Root $ipv4RejectedRoot }
    catch { $literalIpv4Rejected = $true }
    Assert-True $literalIpv4Rejected "Une projection canonique dont la seule donnée sensible est une IPv4 publique littérale a été acceptée."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $ipv4RejectedRoot "public-events-manifest-v6.json"))) "L'écho contenant uniquement une IPv4 publique a publié un manifeste."

    $settingsRoot = Join-Path $tempRoot "canonical-settings"
    $settingsPath = Join-Path $tempRoot "canonical-settings.json"
    $settingsPayload = ($canonicalPayload | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
    $settingsPayload.events = [object[]]@([pscustomobject]@{
        key = "settings:rules-1"; id = 201; occurredAt = "2026-07-18T10:00:00-04:00"; type = "settings"
        player = $null; guild = $null; base = $null; title = "Règles du monde ajustées"; message = "La difficulté a été ajustée."
        display = [pscustomobject]@{ headline = "Règles du monde ajustées"; body = "La difficulté a été ajustée."; bullets = @("Difficulty: Normal vers Hard") }
        details = [pscustomobject]@{ fields = [pscustomobject]@{ Difficulty = [pscustomobject]@{ before = "Normal"; after = "Hard" } } }
        confidence = "confirmed"; icon = $null; source = "server"
    })
    $settingsPayload.revision = "6:settings:1"
    $settingsPayload.projectionRevision = 1
    Set-TestProjectionWindow -Payload $settingsPayload -Mode full -ThroughProjectionRevision 1
    $settingsPayload.summary = [pscustomobject]@{ rawEvents = 1; publicEvents = 1; echoes = 1; representedEvents = 1; totalEchoes = 1; totalRepresentedEvents = 1; events = 1; totalEvents = 1 }
    [IO.File]::WriteAllText($settingsPath, (($settingsPayload | ConvertTo-Json -Depth 12) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    Invoke-LocalSync -Source $settingsPath -Root $settingsRoot
    $settingsManifest = Get-Content -LiteralPath (Join-Path $settingsRoot "public-events-manifest-v6.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $settingsHead = (Get-ManifestHead -Root $settingsRoot -Manifest $settingsManifest).Payload
    Assert-True ($settingsHead.events[0].type -eq "settings" -and $settingsHead.events[0].source -eq "server") "Un changement public de règles n'a pas traversé le contrat canonique."

    $cursorRoot = Join-Path $tempRoot "canonical-global-cursor"
    $cursorPath = Join-Path $tempRoot "canonical-global-cursor.json"
    $cursorEvents = @(7..1 | ForEach-Object {
        [ordered]@{
            key = "cursor-recent-$_"; id = $_; occurredAt = "2026-07-18T1$($_):00:00-04:00"; type = "discovery"
            player = "Joueuse"; guild = $null; base = $null; title = "Découverte $_"; message = "Découverte récente $_."
            display = [ordered]@{ headline = "Découverte $_"; body = "Découverte récente $_."; bullets = @() }
            details = [ordered]@{}; confidence = "confirmed"; icon = $null; source = "save"
        }
    })
    $cursorEvents += [ordered]@{
        key = "cursor-old-day"; id = 8; occurredAt = "2026-07-17T08:00:00-04:00"; type = "discovery"
        player = "Joueuse"; guild = $null; base = $null; title = "Découverte reprise"; message = "Découverte reprise sur une ancienne journée."
        display = [ordered]@{ headline = "Découverte reprise"; body = "Découverte reprise sur une ancienne journée."; bullets = @() }
        details = [ordered]@{}; confidence = "confirmed"; icon = $null; source = "save"
    }
    $cursorPayload = ($canonicalPayload | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
    $cursorPayload.events = $cursorEvents
    $cursorPayload.revision = "6:cursor:8"
    $cursorPayload.projectionRevision = 8
    Set-TestProjectionWindow -Payload $cursorPayload -Mode full -ThroughProjectionRevision 8
    $cursorPayload.summary = [pscustomobject]@{ rawEvents = 8; publicEvents = 8; echoes = 8; representedEvents = 8; totalEchoes = 8; totalRepresentedEvents = 8; events = 8; totalEvents = 8 }
    [IO.File]::WriteAllText($cursorPath, (($cursorPayload | ConvertTo-Json -Depth 12) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    Invoke-LocalSync -Source $cursorPath -Root $cursorRoot
    $cursorManifest = Get-Content -LiteralPath (Join-Path $cursorRoot "public-events-manifest-v6.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $cursorHead = (Get-ManifestHead -Root $cursorRoot -Manifest $cursorManifest).Payload
    Assert-True ($cursorManifest.cursor.maxId -eq 8 -and $cursorHead.cursor.maxId -eq 8) "La tête ne reprend pas le curseur maximal de la projection complète."
    Assert-True ($cursorHead.windowCursor.maxId -eq 7) "La plage de la fenêtre chaude ne reste pas distincte du curseur global."

    $day17Initial = @($canonicalManifest.days | Where-Object { $_.date -eq "2026-07-17" })[0]
    $day18Initial = @($canonicalManifest.days | Where-Object { $_.date -eq "2026-07-18" })[0]
    $initialGenerationId = [string]$canonicalManifest.generationId
    $eventC = [ordered]@{
        key = "canonical-craft-c"; id = 102; occurredAt = "2026-07-18T08:05:00-04:00"; type = "craft"
        player = "Joueuse"; guild = $null; base = "Atelier"; title = "Fabrication C"; message = "Une troisième fabrication."
        display = [ordered]@{ headline = "Fabrication C"; body = "Une troisième fabrication."; bullets = @() }
        details = [ordered]@{ items = @([ordered]@{ name = "Lingot"; added = 1 }) }
        confidence = "confirmed"; icon = $null; source = "save"
    }
    $canonicalPayload.events = @($eventC) + @($canonicalEvents)
    $canonicalPayload.revision = "6:canonical-fast-102"
    $canonicalPayload.projectionRevision = 11
    Set-TestProjectionWindow -Payload $canonicalPayload -Mode replace-tail -FromProjectionRevision 10 -ThroughProjectionRevision 11 -ReplaceFrom "2026-07-18T08:05:00-04:00"
    $canonicalPayload.summary.rawEvents = 5
    $canonicalPayload.summary.publicEvents = 5
    $canonicalPayload.summary.echoes = 3
    $canonicalPayload.summary.representedEvents = 5
    $canonicalPayload.summary.totalEchoes = 3
    $canonicalPayload.summary.totalRepresentedEvents = 5
    $canonicalPayload.summary.events = 3
    $canonicalPayload.summary.totalEvents = 5
    [IO.File]::WriteAllText($canonicalPath, (($canonicalPayload | ConvertTo-Json -Depth 12) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    Invoke-LocalSync -Source $canonicalPath -Root $canonicalRoot -Fast
    $afterFirstFast = Get-Content -LiteralPath (Join-Path $canonicalRoot "public-events-manifest-v6.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $day17AfterFirstFast = @($afterFirstFast.days | Where-Object { $_.date -eq "2026-07-17" })[0]
    $day18AfterFirstFast = @($afterFirstFast.days | Where-Object { $_.date -eq "2026-07-18" })[0]
    $day18Payload = Get-Content -LiteralPath (Get-ContractPath -Root $canonicalRoot -RelativePath $day18AfterFirstFast.path) -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($afterFirstFast.counts.echoes -eq 3 -and $afterFirstFast.cursor.maxId -eq 102) "Le nouveau curseur canonique n'a pas été publié."
    Assert-True (@($day18Payload.events | Where-Object { $_.key -eq "canonical-craft-c" }).Count -eq 1) "Le nouvel écho n'a pas été ajouté exactement une fois."
    Assert-True ($day17AfterFirstFast.path -eq $day17Initial.path) "Un jour non touché a été réécrit pendant le fast."
    Assert-True ($day18AfterFirstFast.path -ne $day18Initial.path -and $day18AfterFirstFast.fragmentGenerationId -eq $afterFirstFast.generationId) "Le jour touché n'a pas rejoint la génération incrémentale."
    $headAfterFirstFast = (Get-ManifestHead -Root $canonicalRoot -Manifest $afterFirstFast).Payload
    Assert-True ($headAfterFirstFast.baseGenerationId -eq $afterFirstFast.generationId) "La tête fast annonce une génération différente du manifeste actif."

    $unchangedSnapshot = Get-V6FileSnapshot -Root $canonicalRoot
    Invoke-LocalSync -Source $canonicalPath -Root $canonicalRoot -Fast
    $unchangedSnapshotAfter = Get-V6FileSnapshot -Root $canonicalRoot
    Assert-SnapshotsEqual -Before $unchangedSnapshot -After $unchangedSnapshotAfter -Message "Une projection récente inchangée a modifié des fichiers v6."

    $missingDailyPath = Get-ContractPath -Root $canonicalRoot -RelativePath ([string]$day17AfterFirstFast.dailyPath)
    Remove-Item -LiteralPath $missingDailyPath -Force
    Set-TestProjectionWindow -Payload $canonicalPayload -Mode full -ThroughProjectionRevision 11
    Write-TestJson -Path $canonicalPath -Value $canonicalPayload
    Invoke-LocalSync -Source $canonicalPath -Root $canonicalRoot -RespectProbe
    $repairedManifest = Get-Content -LiteralPath (Join-Path $canonicalRoot "public-events-manifest-v6.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $repairedDay17 = @($repairedManifest.days | Where-Object { $_.date -eq "2026-07-17" })[0]
    $repairedDailyPath = Get-ContractPath -Root $canonicalRoot -RelativePath ([string]$repairedDay17.dailyPath)
    Assert-True ((Test-Path -LiteralPath $repairedDailyPath -PathType Leaf) -and ("sha256:" + (Get-FileHash -LiteralPath $repairedDailyPath -Algorithm SHA256).Hash.ToLowerInvariant()) -eq $repairedDay17.dailySha256) "La reprojection n'a pas réparé le résumé v6 manquant."

    $eventD = [ordered]@{
        key = "canonical-old-day"; id = 103; occurredAt = "2026-07-17T09:00:00-04:00"; type = "discovery"
        player = "Joueuse"; guild = $null; base = $null; title = "Découverte ancienne"; message = "Une découverte plus ancienne est confirmée."
        display = [ordered]@{ headline = "Découverte ancienne"; body = "Une découverte plus ancienne est confirmée."; bullets = @() }
        details = [ordered]@{}; confidence = "confirmed"; icon = $null; source = "save"
    }
    $canonicalPayload.events = @($eventC, $canonicalEvents[0], $eventD, $canonicalEvents[1])
    $canonicalPayload.revision = "6:canonical-fast-103"
    $canonicalPayload.projectionRevision = 12
    Set-TestProjectionWindow -Payload $canonicalPayload -Mode replace-tail -FromProjectionRevision 11 -ThroughProjectionRevision 12 -ReplaceFrom "2026-07-17T09:00:00-04:00"
    $canonicalPayload.summary.rawEvents = 6
    $canonicalPayload.summary.publicEvents = 6
    $canonicalPayload.summary.echoes = 4
    $canonicalPayload.summary.representedEvents = 6
    $canonicalPayload.summary.totalEchoes = 4
    $canonicalPayload.summary.totalRepresentedEvents = 6
    $canonicalPayload.summary.events = 4
    $canonicalPayload.summary.totalEvents = 6
    [IO.File]::WriteAllText($canonicalPath, (($canonicalPayload | ConvertTo-Json -Depth 12) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    Invoke-LocalSync -Source $canonicalPath -Root $canonicalRoot -Fast
    $afterOldDayFast = Get-Content -LiteralPath (Join-Path $canonicalRoot "public-events-manifest-v6.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $day17AfterOldDay = @($afterOldDayFast.days | Where-Object { $_.date -eq "2026-07-17" })[0]
    $day18AfterOldDay = @($afterOldDayFast.days | Where-Object { $_.date -eq "2026-07-18" })[0]
    Assert-True ($day17AfterOldDay.path -ne $day17AfterFirstFast.path) "Un nouvel écho n'a pas republié son ancienne journée."
    Assert-True ($day18AfterOldDay.path -ne $day18AfterFirstFast.path) "La queue canonique postérieure à une ancienne borne n'a pas été remplacée intégralement."

    $eventE = [ordered]@{
        key = "canonical-after-interruption"; id = 104; occurredAt = "2026-07-18T08:06:00-04:00"; type = "capture"
        player = "Joueuse"; guild = $null; base = $null; title = "Capture après reprise"; message = "Joueuse capture 1 Lamball."
        display = [ordered]@{ headline = "Capture après reprise"; body = "Joueuse capture 1 Lamball."; bullets = @() }
        details = [ordered]@{}; confidence = "confirmed"; icon = $null; source = "save"
    }
    $canonicalPayload.events = @($eventE, $eventC, $canonicalEvents[0], $eventD, $canonicalEvents[1])
    $canonicalPayload.revision = "6:canonical-fast-104"
    $canonicalPayload.projectionRevision = 13
    Set-TestProjectionWindow -Payload $canonicalPayload -Mode replace-tail -FromProjectionRevision 12 -ThroughProjectionRevision 13 -ReplaceFrom "2026-07-18T08:06:00-04:00"
    $canonicalPayload.summary.rawEvents = 7
    $canonicalPayload.summary.publicEvents = 7
    $canonicalPayload.summary.echoes = 5
    $canonicalPayload.summary.representedEvents = 7
    $canonicalPayload.summary.totalEchoes = 5
    $canonicalPayload.summary.totalRepresentedEvents = 7
    $canonicalPayload.summary.events = 5
    $canonicalPayload.summary.totalEvents = 7
    [IO.File]::WriteAllText($canonicalPath, (($canonicalPayload | ConvertTo-Json -Depth 12) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    $manifestHashBeforeInterruption = (Get-FileHash -LiteralPath (Join-Path $canonicalRoot "public-events-manifest-v6.json") -Algorithm SHA256).Hash
    $activePointerHashBeforeInterruption = (Get-FileHash -LiteralPath (Join-Path $canonicalRoot "public-events-head-v6.json") -Algorithm SHA256).Hash
    $activeHeadBeforeInterruption = Get-ManifestHead -Root $canonicalRoot -Manifest $afterOldDayFast
    $activeHeadHashBeforeInterruption = (Get-FileHash -LiteralPath $activeHeadBeforeInterruption.Path -Algorithm SHA256).Hash
    $knownGenerationIds = @(
        Get-ChildItem -LiteralPath (Join-Path $canonicalRoot "public-events-v6") -Directory -Filter "g6-*" |
            Select-Object -ExpandProperty Name
    )
    $interruptedGenerationIds = [Collections.Generic.List[string]]::new()

    foreach ($failurePoint in @("AfterFragments", "AfterHead")) {
        Start-Sleep -Milliseconds 10
        $interrupted = $false
        try {
            Invoke-LocalSync -Source $canonicalPath -Root $canonicalRoot -Fast -TestFailurePoint $failurePoint
        }
        catch {
            $interrupted = $true
        }
        Assert-True $interrupted "L'interruption injectée à l'étape $failurePoint n'a pas interrompu la publication."
        Assert-True ((Get-FileHash -LiteralPath (Join-Path $canonicalRoot "public-events-manifest-v6.json") -Algorithm SHA256).Hash -eq $manifestHashBeforeInterruption) "L'interruption à l'étape $failurePoint a remplacé le manifeste actif."
        Assert-True ((Get-FileHash -LiteralPath (Join-Path $canonicalRoot "public-events-head-v6.json") -Algorithm SHA256).Hash -eq $activePointerHashBeforeInterruption) "L'interruption à l'étape $failurePoint a remplacé le pointeur actif."
        Assert-True ((Get-FileHash -LiteralPath $activeHeadBeforeInterruption.Path -Algorithm SHA256).Hash -eq $activeHeadHashBeforeInterruption) "L'interruption à l'étape $failurePoint a altéré la tête de la génération active."
        $currentGenerationIds = @(
            Get-ChildItem -LiteralPath (Join-Path $canonicalRoot "public-events-v6") -Directory -Filter "g6-*" |
                Select-Object -ExpandProperty Name
        )
        $newInterruptedIds = @($currentGenerationIds | Where-Object { $_ -notin $knownGenerationIds -and $_ -notin $interruptedGenerationIds })
        Assert-True ($newInterruptedIds.Count -ge 1) "L'interruption à l'étape $failurePoint n'a pas laissé de génération préparée à nettoyer."
        foreach ($generationId in $newInterruptedIds) { $interruptedGenerationIds.Add($generationId) }
    }

    Invoke-LocalSync -Source $canonicalPath -Root $canonicalRoot -Fast
    $afterResume = Get-Content -LiteralPath (Join-Path $canonicalRoot "public-events-manifest-v6.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $headAfterResume = (Get-ManifestHead -Root $canonicalRoot -Manifest $afterResume).Payload
    $day18AfterResume = @($afterResume.days | Where-Object { $_.date -eq "2026-07-18" })[0]
    $day18AfterResumePayload = Get-Content -LiteralPath (Get-ContractPath -Root $canonicalRoot -RelativePath $day18AfterResume.path) -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($afterResume.counts.echoes -eq 5 -and @($day18AfterResumePayload.events | Where-Object { $_.key -eq "canonical-after-interruption" }).Count -eq 1) "La reprise n'a pas projeté le curseur interrompu exactement une fois."
    Assert-True ($headAfterResume.baseGenerationId -eq $afterResume.generationId) "La reprise laisse une tête hors génération."
    foreach ($failedGenerationId in $interruptedGenerationIds) {
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $canonicalRoot "public-events-v6\$failedGenerationId"))) "La génération interrompue $failedGenerationId n'a pas été nettoyée après reprise."
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $canonicalRoot "public-daily\$failedGenerationId"))) "Les résumés interrompus $failedGenerationId n'ont pas été nettoyés après reprise."
    }

    $correctedB = [ordered]@{}
    foreach ($key in $canonicalEvents[1].Keys) { $correctedB[$key] = $canonicalEvents[1][$key] }
    $correctedB["message"] = "Une correction historique modifie cet écho."
    # La correction porte sur un écho volontairement absent de la fenêtre
    # récente. Seul le watermark SQLite permet de savoir qu'un append pur
    # n'est plus prouvé.
    $canonicalPayload.events = @($eventE, $eventC, $canonicalEvents[0], $eventD)
    $canonicalPayload.revision = "6:canonical-fast-104"
    $canonicalPayload.projectionRevision = 14
    Set-TestProjectionWindow -Payload $canonicalPayload -Mode replace-tail -FromProjectionRevision 13 -ThroughProjectionRevision 14 -ReplaceFrom "2026-07-17T08:03:00-04:00"
    $canonicalPayload.summary.echoes = 4
    $canonicalPayload.summary.representedEvents = 5
    $canonicalPayload.summary.events = 4
    [IO.File]::WriteAllText($canonicalPath, (($canonicalPayload | ConvertTo-Json -Depth 12) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    $beforeCorrection = Get-V6FileSnapshot -Root $canonicalRoot
    $recentHashBeforeCorrection = (Get-FileHash -LiteralPath (Join-Path $canonicalRoot "public-events-recent.json") -Algorithm SHA256).Hash
    Invoke-LocalSync -Source $canonicalPath -Root $canonicalRoot -Fast -RespectProbe
    $afterCorrection = Get-V6FileSnapshot -Root $canonicalRoot
    Assert-SnapshotsEqual -Before $beforeCorrection -After $afterCorrection -Message "Une correction historique ambiguë a modifié la génération v6 active."
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $canonicalRoot "public-events-recent.json") -Algorithm SHA256).Hash -eq $recentHashBeforeCorrection) "Une correction historique ambiguë a remplacé le flux récent stable avant reprojection."
    $correctionState = Get-Content -LiteralPath (Join-Path $canonicalRoot "public-events-sync-state.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($correctionState.requiresReprojection -and $correctionState.reprojectionReason -eq "projection-not-append-only") "La correction historique hors fenêtre n'a pas demandé de reprojection complète."

    $canonicalPayload.events = @($eventE, $eventC, $canonicalEvents[0], $eventD, $correctedB)
    $canonicalPayload.revision = "6:14:5:104"
    Set-TestProjectionWindow -Payload $canonicalPayload -Mode full -ThroughProjectionRevision 14
    $canonicalPayload.summary.echoes = 5
    $canonicalPayload.summary.representedEvents = 7
    $canonicalPayload.summary.events = 5
    [IO.File]::WriteAllText($canonicalPath, (($canonicalPayload | ConvertTo-Json -Depth 12) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    Invoke-LocalSync -Source $canonicalPath -Root $canonicalRoot
    $afterReprojection = Get-Content -LiteralPath (Join-Path $canonicalRoot "public-events-manifest-v6.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $correctedDay17 = @($afterReprojection.days | Where-Object { $_.date -eq "2026-07-17" })[0]
    $correctedDay17Payload = Get-Content -LiteralPath (Get-ContractPath -Root $canonicalRoot -RelativePath $correctedDay17.path) -Raw -Encoding UTF8 | ConvertFrom-Json
    $reprojectedState = Get-Content -LiteralPath (Join-Path $canonicalRoot "public-events-sync-state.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($afterReprojection.sourceProjectionRevision -eq 14) "La reprojection complète n'a pas mémorisé le watermark SQLite."
    Assert-True (@($correctedDay17Payload.events | Where-Object { $_.key -eq "canonical-craft-b" -and $_.message -eq "Une correction historique modifie cet écho." }).Count -eq 1) "La reprojection complète n'a pas appliqué la correction historique."
    Assert-True (-not $reprojectedState.requiresReprojection) "La reprojection complète n'a pas levé son marqueur de reprise."

    # Une génération complète peut ne posséder aucun nouveau fragment de jour.
    # Sa tête reste néanmoins un fichier immuable propre à la génération.
    $canonicalPayload.projectionRevision = 15
    $canonicalPayload.revision = "6:15:5:104"
    Set-TestProjectionWindow -Payload $canonicalPayload -Mode full -ThroughProjectionRevision 15
    [IO.File]::WriteAllText($canonicalPath, (($canonicalPayload | ConvertTo-Json -Depth 12) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    Invoke-LocalSync -Source $canonicalPath -Root $canonicalRoot
    $headOnlyGeneration = Get-Content -LiteralPath (Join-Path $canonicalRoot "public-events-manifest-v6.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $headOnlyResult = Get-ManifestHead -Root $canonicalRoot -Manifest $headOnlyGeneration
    Assert-True (@($headOnlyGeneration.days | Where-Object { $_.fragmentGenerationId -eq $headOnlyGeneration.generationId }).Count -eq 0) "La génération de tête a inutilement réécrit un fragment inchangé."
    Assert-True ($headOnlyResult.Payload.baseGenerationId -eq $headOnlyGeneration.generationId) "La génération sans nouveau fragment a perdu sa tête immuable."
    Assert-True (("sha256:" + (Get-FileHash -LiteralPath $headOnlyResult.Path -Algorithm SHA256).Hash.ToLowerInvariant()) -eq $headOnlyGeneration.head.sha256) "La tête de la génération sans fragment ne correspond plus au manifeste."

    # Aligne d'abord l'état du petit probe récent sur la génération complète.
    Set-TestProjectionWindow -Payload $canonicalPayload -Mode replace-tail -FromProjectionRevision 15 -ThroughProjectionRevision 15
    Invoke-LocalSync -Source $canonicalPath -Root $canonicalRoot -Fast -RespectProbe
    $generationBeforeProvenance = [string]$headOnlyGeneration.generationId
    $pathsBeforeProvenance = @($headOnlyGeneration.days | ForEach-Object { [string]$_.path } | Sort-Object)
    $canonicalPayload.provenanceRevision = "provenance-b"
    $canonicalPayload.provenance.gameVersion = "v2"
    $canonicalPayload.provenance.steamBuildId = "200"
    $canonicalPayload.provenance.catalogCommit = "catalog-b"
    # La chaîne revision et le watermark métier restent volontairement
    # identiques : le petit probe doit détecter la provenance à lui seul.
    [IO.File]::WriteAllText($canonicalPath, (($canonicalPayload | ConvertTo-Json -Depth 12) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    Invoke-LocalSync -Source $canonicalPath -Root $canonicalRoot -Fast -RespectProbe
    $afterProvenance = Get-Content -LiteralPath (Join-Path $canonicalRoot "public-events-manifest-v6.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $provenanceHead = (Get-ManifestHead -Root $canonicalRoot -Manifest $afterProvenance).Payload
    $pathsAfterProvenance = @($afterProvenance.days | ForEach-Object { [string]$_.path } | Sort-Object)
    Assert-True ($afterProvenance.generationId -ne $generationBeforeProvenance) "Un nouveau build n'a pas publié une nouvelle génération de métadonnées."
    Assert-True (($pathsBeforeProvenance -join "|") -eq ($pathsAfterProvenance -join "|")) "Un changement de provenance a réécrit des journées inchangées."
    Assert-True ($afterProvenance.sourceProvenanceRevision -eq "provenance-b" -and $afterProvenance.gameVersion -eq "v2" -and $afterProvenance.catalogCommit -eq "catalog-b") "La nouvelle provenance n'a pas atteint le manifeste."
    Assert-True ($provenanceHead.baseGenerationId -eq $afterProvenance.generationId -and $provenanceHead.gameVersion -eq "v2") "La tête n'a pas suivi le changement de provenance."

    Assert-True (@($provenanceHead.events).Count -le 7) "La fenêtre de curseur de la tête dépasse sept échos."
    Assert-True (@($provenanceHead.verifiedEchoes | Where-Object { $_.confidence -ne "confirmed" }).Count -eq 0) "La tête vérifiée contient un écho dérivé."
    Assert-True ($provenanceHead.counts.totalEchoes -eq $afterProvenance.counts.echoes) "La tête n'expose pas le compte exact des échos."
    Assert-True ($provenanceHead.hasMore -eq ($provenanceHead.counts.totalEchoes -gt @($provenanceHead.events).Count)) "Le signal de saturation de la tête est incohérent."
    Assert-True ($provenanceHead.cursor.minId -gt 0 -and $provenanceHead.cursor.maxId -ge $provenanceHead.cursor.minId) "La tête n'expose pas sa plage de curseurs."

    # La promotion lit une copie autonome du portail pour valider tout le jeu
    # immuable avant de remplacer le canal. Une corruption doit laisser le
    # contrat précédent intégralement actif.
    $channelProjectRoot = Join-Path $tempRoot "channel-project"
    $channelPortalDataRoot = Join-Path $channelProjectRoot "portal\data"
    New-Item -ItemType Directory -Force -Path $channelPortalDataRoot | Out-Null
    Copy-Item -Path (Join-Path $canonicalRoot "*") -Destination $channelPortalDataRoot -Recurse -Force
    $channelPath = Join-Path $channelProjectRoot "portal\public-events-channel.json"
    $v5Channel = [ordered]@{ schemaVersion = 1; activeContract = "v5"; candidateContract = "v6" }
    Write-TestJson -Path $channelPath -Value $v5Channel

    & $channelScript -ActiveContract v6 -ProjectRoot $channelProjectRoot | Out-Null
    $promotedChannel = Get-Content -LiteralPath $channelPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($promotedChannel.activeContract -eq "v6") "La génération v6 valide n'a pas été promue."

    & $channelScript -ActiveContract v5 -ProjectRoot $channelProjectRoot | Out-Null
    $channelHashBeforeCorruption = (Get-FileHash -LiteralPath $channelPath -Algorithm SHA256).Hash
    $channelPointer = Get-Content -LiteralPath (Join-Path $channelPortalDataRoot "public-events-head-v6.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $channelManifestPath = Get-ContractPath -Root $channelPortalDataRoot -RelativePath ([string]$channelPointer.manifest.path)
    $channelManifest = Get-Content -LiteralPath $channelManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $corruptedFragmentPath = Get-ContractPath -Root $channelPortalDataRoot -RelativePath ([string]$channelManifest.days[0].path)
    [IO.File]::AppendAllText($corruptedFragmentPath, " `n", [Text.UTF8Encoding]::new($false))

    $corruptionRejected = $false
    try { & $channelScript -ActiveContract v6 -ProjectRoot $channelProjectRoot | Out-Null }
    catch { $corruptionRejected = $true }
    Assert-True $corruptionRejected "La promotion a accepté un fragment dont l'empreinte ne correspond plus au manifeste."
    Assert-True ((Get-FileHash -LiteralPath $channelPath -Algorithm SHA256).Hash -eq $channelHashBeforeCorruption) "Une promotion v6 invalide a remplacé le canal actif."
    $preservedChannel = Get-Content -LiteralPath $channelPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($preservedChannel.activeContract -eq "v5") "Le canal v5 n'a pas été préservé après le refus de promotion."

    # Intégration réelle : le collecteur crée/migre SQLite, matérialise le
    # contrat canonique complet, puis un append récent est injecté au même
    # portail par le chemin rapide.
    $collectorRoot = Join-Path $tempRoot "python-collector-integration"
    $collectorPortalRoot = Join-Path $collectorRoot "portal"
    New-Item -ItemType Directory -Force -Path $collectorRoot, $collectorPortalRoot | Out-Null
    $collectorDatabase = Join-Path $collectorRoot "events.sqlite3"
    $collectorFullPath = Join-Path $collectorRoot "collector-full.json"
    $collectorRecentPath = Join-Path $collectorRoot "collector-recent.json"
    $collectorFixturePath = Join-Path $collectorRoot "journal.jsonl"
    $collectorScript = Join-Path $projectRoot "server\bin\palworld-events-collect.py"
    $pythonCommand = (Get-Command python -ErrorAction Stop).Source
    $journalMessageOne = [ordered]@{ timestamp = "2026-07-18T10:00:00-04:00"; message = "Started palworld.service" } | ConvertTo-Json -Compress
    $journalLineOne = [ordered]@{ __CURSOR = "integration-cursor-1"; MESSAGE = $journalMessageOne } | ConvertTo-Json -Compress
    [IO.File]::WriteAllLines($collectorFixturePath, [string[]]@($journalLineOne), [Text.UTF8Encoding]::new($false))
    $collectorArguments = @(
        $collectorScript,
        "--database", $collectorDatabase,
        "--output", $collectorFullPath,
        "--recent-output", $collectorRecentPath,
        "--recent-limit", "4",
        "--journal-fixture", $collectorFixturePath,
        "--snapshot", (Join-Path $collectorRoot "absent-snapshot.json"),
        "--bases-snapshot", (Join-Path $collectorRoot "absent-bases.json"),
        "--history", (Join-Path $collectorRoot "absent-history"),
        "--bases-history", (Join-Path $collectorRoot "absent-bases-history"),
        "--stats", (Join-Path $collectorRoot "absent-stats.json"),
        "--recovery-report", (Join-Path $collectorRoot "recovery.json"),
        "--skip-archive-backfill",
        "--full-export-interval", "86400"
    )
    & $pythonCommand @($collectorArguments + @("--write-full-export")) | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "Le collecteur Python n'a pas produit l'export canonique complet."
    $collectorFull = Get-Content -LiteralPath $collectorFullPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($collectorFull.version -eq 6 -and $collectorFull.schemaVersion -eq 6 -and $collectorFull.projection -eq "canonical-echoes" -and -not $collectorFull.recent) "L'export complet réel ne respecte pas l'en-tête canonique strict."
    Invoke-LocalSync -Source $collectorFullPath -Root $collectorPortalRoot
    $collectorFullHash = (Get-FileHash -LiteralPath $collectorFullPath -Algorithm SHA256).Hash
    $collectorRecentHash = (Get-FileHash -LiteralPath $collectorRecentPath -Algorithm SHA256).Hash

    $journalMessageTwo = [ordered]@{ timestamp = "2026-07-18T10:05:00-04:00"; message = "Stopped palworld.service" } | ConvertTo-Json -Compress
    $journalLineTwo = [ordered]@{ __CURSOR = "integration-cursor-2"; MESSAGE = $journalMessageTwo } | ConvertTo-Json -Compress
    [IO.File]::WriteAllLines($collectorFixturePath, [string[]]@($journalLineOne, $journalLineTwo), [Text.UTF8Encoding]::new($false))
    & $pythonCommand @collectorArguments | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "Le collecteur Python n'a pas produit l'append canonique récent."
    Assert-True ((Get-FileHash -LiteralPath $collectorFullPath -Algorithm SHA256).Hash -eq $collectorFullHash) "Le passage chaud du collecteur a réécrit l'export froid."
    Assert-True ((Get-FileHash -LiteralPath $collectorRecentPath -Algorithm SHA256).Hash -ne $collectorRecentHash) "Le passage chaud du collecteur n'a pas actualisé son export récent."
    $collectorRecent = Get-Content -LiteralPath $collectorRecentPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($collectorRecent.version -eq 6 -and $collectorRecent.schemaVersion -eq 6 -and $collectorRecent.recent -and @($collectorRecent.events).Count -eq 2) "L'export récent réel ne respecte pas le contrat canonique attendu."
    Invoke-LocalSync -Source $collectorRecentPath -Root $collectorPortalRoot -Fast
    $collectorManifest = Get-Content -LiteralPath (Join-Path $collectorPortalRoot "public-events-manifest-v6.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $collectorPublishedRecent = Get-Content -LiteralPath (Join-Path $collectorPortalRoot "public-events-recent.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($collectorManifest.counts.echoes -eq 2 -and @($collectorPublishedRecent.events).Count -eq 2) "L'append Python réel n'a pas traversé le chemin PowerShell rapide exactement une fois."

    $watcherSource = Get-Content -LiteralPath $watcherScript -Raw -Encoding UTF8
    Assert-True ($watcherSource.Contains("FullEventSyncIntervalSeconds")) "Le watcher ne planifie pas de réconciliation complète."
    Assert-True ($watcherSource.Contains("Invoke-EventHistorySync -Full:`$runFullEventSync")) "Le watcher ne choisit pas explicitement entre synchronisation rapide et complète."

    $syncSource = Get-Content -LiteralPath $syncScript -Raw -Encoding UTF8
    Assert-True (-not $syncSource.Contains('if ($PSVersionTable.PSVersion.Major -lt 6)')) "Windows PowerShell retélécharge encore le monolithe pour sonder sa révision."
    Assert-True ($syncSource.Contains('"provenanceRevision": payload.get("provenanceRevision")')) "Le petit probe ne lit pas la révision de provenance."

    Write-Host "Contrat de publication des échos v6 validé."
}
finally {
    $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
    $systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedTemp.StartsWith($systemTemp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTemp).StartsWith("gaylemon-public-events-v6-test-")) {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
