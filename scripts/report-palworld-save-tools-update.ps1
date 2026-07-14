param(
    [string]$BaseCommit = "",
    [string]$TargetCommit = "",
    [string]$JsonOutputPath = (Join-Path $PSScriptRoot "..\portal\data\palworld-save-tools-update-report.json"),
    [string]$MarkdownOutputPath = (Join-Path $PSScriptRoot "..\portal\data\palworld-save-tools-update-report.md"),
    [int]$MaxCommits = 40
)

$ErrorActionPreference = "Stop"

try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $OutputEncoding = [Console]::OutputEncoding
}
catch {
    # Best effort for older PowerShell hosts.
}

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot
$lockPath = Join-Path $ProjectRoot "dependencies\palworld-save-tools.lock.json"
$lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json

function Invoke-GhJson([string]$Path) {
    $raw = (& gh api $Path | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) {
        throw "Impossible de lire GitHub: $Path"
    }
    return $raw | ConvertFrom-Json
}

function Get-HeadSha([string]$Repository) {
    $result = Invoke-GhJson "repos/$Repository/commits/main"
    return [string]$result.sha
}

function Get-ActiveRemoteSha {
    $command = "git -C '$($config.RemoteProjectRoot)/vendor/PalworldSaveTools-current' rev-parse HEAD 2>/dev/null || git -C '$($config.RemoteProjectRoot)/vendor/PalworldSaveTools' rev-parse HEAD 2>/dev/null || true"
    $sha = (& ssh.exe -o BatchMode=yes -o ConnectTimeout=8 $config.SshAlias $command 2>$null | Out-String).Trim()
    if ($sha -match '^[a-f0-9]{40}$') { return $sha }
    return $null
}

function Short-Sha([string]$Sha) {
    if ([string]::IsNullOrWhiteSpace($Sha)) { return "unknown" }
    return $Sha.Substring(0, [Math]::Min(12, $Sha.Length))
}

function First-Line([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    return (($Value -split "`r?`n") | Select-Object -First 1).Trim()
}

function Get-FileArea([string]$Path) {
    switch -Regex ($Path) {
        '^src/palsav/' { return "parseur_sauvegarde" }
        '^src/palworld_toolsets/' { return "outils_cli" }
        '^src/palworld_xgp_import/' { return "xgp_gamepass" }
        '^src/palworld_aio/' { return "application_desktop" }
        '^resources/game_data/icons/' { return "icones_jeu" }
        '^resources/game_data/' { return "donnees_jeu" }
        '^resources/i18n/|^src/i18n/' { return "traductions" }
        '^tests/' { return "tests" }
        '^\.github/|^build/' { return "ci_release" }
        default { return "autre" }
    }
}

function Add-Unique([Collections.Generic.List[string]]$List, [string]$Value) {
    if (-not [string]::IsNullOrWhiteSpace($Value) -and -not $List.Contains($Value)) {
        $List.Add($Value) | Out-Null
    }
}

$upstreamSha = Get-HeadSha $config.SaveToolsUpstream
$forkSha = Get-HeadSha $config.SaveToolsFork
$activeSha = Get-ActiveRemoteSha
if (-not $BaseCommit) { $BaseCommit = if ($activeSha) { $activeSha } else { [string]$lock.commit } }
if (-not $TargetCommit) { $TargetCommit = $upstreamSha }

$changed = $BaseCommit -ne $TargetCommit
$compare = $null
$commits = @()
$files = @()

if ($changed) {
    $compare = Invoke-GhJson "repos/$($config.SaveToolsUpstream)/compare/$BaseCommit...$TargetCommit"
    $commits = @($compare.commits | ForEach-Object {
        [pscustomobject][ordered]@{
            sha = [string]$_.sha
            short = Short-Sha ([string]$_.sha)
            date = [string]$_.commit.committer.date
            title = First-Line ([string]$_.commit.message)
            url = [string]$_.html_url
        }
    })
    $files = @($compare.files | ForEach-Object {
        [pscustomobject][ordered]@{
            path = [string]$_.filename
            area = Get-FileArea ([string]$_.filename)
            status = [string]$_.status
            additions = [int]$_.additions
            deletions = [int]$_.deletions
            changes = [int]$_.changes
        }
    })
}

$filePaths = @($files | ForEach-Object { [string]$_.path })
$commitText = (($commits | ForEach-Object { $_.title }) -join "`n").ToLowerInvariant()
$allText = (($filePaths -join "`n") + "`n" + $commitText).ToLowerInvariant()

$highlights = [Collections.Generic.List[string]]::new()
$opportunities = [Collections.Generic.List[string]]::new()
$risks = [Collections.Generic.List[string]]::new()

if (-not $changed) {
    Add-Unique $highlights "Aucune nouvelle revision upstream par rapport au parseur valide."
}
if ($allText -match 'rawdata/group\.py|guild data|guild|role|permission') {
    Add-Unique $highlights "Lecture des guildes/groupes modifiee, dont le format Palworld 2026-07."
    Add-Unique $opportunities "Verifier si les roles, permissions ou marqueurs de guilde peuvent enrichir les bases et les profils publics sans exposer d'identifiants."
    Add-Unique $risks "Contrat a surveiller: membres de guilde, niveau de camp, bases et rattachements joueurs."
}
if ($allText -match 'save_diagnostic|orphaned player|anomal') {
    Add-Unique $highlights "Nouveau diagnostic de sauvegarde pour joueurs orphelins et anomalies de structure."
    Add-Unique $opportunities "Ajouter un passage diagnostic hors publication pour expliquer les profils absents, guildes vides ou saves atypiques."
}
if ($allText -match 'resources/game_data/(items|skills)\.json') {
    Add-Unique $highlights "Donnees items/skills mises a jour."
    Add-Unique $opportunities "Rafraichir les libelles, icones et categories utilises dans les evenements craft, production, recherche et inventaire."
}
if ($allText -match 'resources/game_data/icons') {
    Add-Unique $highlights "Nouvelles icones de jeu detectees."
    Add-Unique $opportunities "Resynchroniser les assets visuels pour reduire les icones manquantes dans le microsite."
}
if ($allText -match 'src/palsav/palsav/(archive|paltypes)') {
    Add-Unique $highlights "Coeur de decodage des sauvegardes modifie."
    Add-Unique $risks "Toujours valider sur une vraie copie de sauvegarde avant activation du lien PalworldSaveTools-current."
}
if ($allText -match 'gamepass|xgp') {
    Add-Unique $highlights "Plusieurs changements concernent Game Pass/XGP."
    Add-Unique $opportunities "Impact direct faible pour le serveur dedie Ubuntu, mais utile pour les outils de recuperation hors serveur."
}
if (($files | Where-Object { $_.area -eq "ci_release" }).Count -gt 10) {
    Add-Unique $highlights "Une part importante des commits concerne CI, packaging et releases."
}
if ($highlights.Count -eq 0) {
    Add-Unique $highlights "Changements detectes, sans signal direct fort pour le pipeline Gaylemon."
}
if ($opportunities.Count -eq 0) {
    Add-Unique $opportunities "Conserver la validation actuelle: tests upstream, snapshot reel, diagnostics publics et absence de redemarrage Palworld."
}
if ($risks.Count -eq 0) {
    Add-Unique $risks "Risque faible si le snapshot reel et les contrats publics restent verts."
}

$areas = @($files | Group-Object area | Sort-Object Count -Descending | ForEach-Object {
    [ordered]@{
        area = [string]$_.Name
        files = [int]$_.Count
        changes = [int](($_.Group | Measure-Object changes -Sum).Sum)
    }
})

$report = [ordered]@{
    generatedAt = (Get-Date).ToString("o")
    repositories = [ordered]@{
        upstream = $config.SaveToolsUpstream
        fork = $config.SaveToolsFork
    }
    revisions = [ordered]@{
        locked = [string]$lock.commit
        activeUbuntu = $activeSha
        fork = $forkSha
        upstream = $upstreamSha
        base = $BaseCommit
        target = $TargetCommit
    }
    status = [ordered]@{
        hasChanges = [bool]$changed
        forkBehindUpstream = [bool]($forkSha -ne $upstreamSha)
        ubuntuBehindFork = [bool]($activeSha -and $activeSha -ne $forkSha)
        commitsAhead = if ($compare) { [int]$compare.ahead_by } else { 0 }
        filesChanged = $files.Count
    }
    highlights = @($highlights)
    opportunities = @($opportunities)
    risks = @($risks)
    areas = $areas
    commits = @($commits | Select-Object -First $MaxCommits)
    files = $files
}

$jsonResolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($JsonOutputPath)
$markdownResolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($MarkdownOutputPath)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $jsonResolved) | Out-Null

$json = $report | ConvertTo-Json -Depth 16
[IO.File]::WriteAllText($jsonResolved, $json.TrimEnd() + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

$commitLines = if ($commits.Count) {
    @($commits | Select-Object -First 12 | ForEach-Object { "- $($_.short) - $($_.title)" }) -join [Environment]::NewLine
}
else {
    "- Aucun commit a analyser."
}
$areaLines = if ($areas.Count) {
    @($areas | ForEach-Object { "- $($_.area): $($_.files) fichier(s), $($_.changes) changement(s)" }) -join [Environment]::NewLine
}
else {
    "- Aucun fichier modifie."
}
$markdown = @"
# Rapport PalworldSaveTools

Genere le $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

Base: $(Short-Sha $BaseCommit)
Target upstream: $(Short-Sha $TargetCommit)
Fork: $(Short-Sha $forkSha)
Ubuntu actif: $(Short-Sha $activeSha)

## A retenir
$(@($highlights | ForEach-Object { "- $_" }) -join [Environment]::NewLine)

## Pistes Gaylemon
$(@($opportunities | ForEach-Object { "- $_" }) -join [Environment]::NewLine)

## Points a surveiller
$(@($risks | ForEach-Object { "- $_" }) -join [Environment]::NewLine)

## Zones touchees
$areaLines

## Commits recents
$commitLines
"@
[IO.File]::WriteAllText($markdownResolved, $markdown.TrimEnd() + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    Report = $jsonResolved
    Markdown = $markdownResolved
    Base = $BaseCommit
    Target = $TargetCommit
    ForkBehindUpstream = [bool]($forkSha -ne $upstreamSha)
    CommitsAhead = if ($compare) { [int]$compare.ahead_by } else { 0 }
    FilesChanged = $files.Count
}
