param(
    [string]$Rapport = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
. (Join-Path $PSScriptRoot "lib\Gaylemon.Deployment.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot
$deploymentManifest = Get-GaylemonDeploymentManifest -ProjectRoot $ProjectRoot -Config $config

$entries = [Collections.Generic.List[object]]::new()

function Add-SourceEntry {
    param(
        [string]$Category,
        [string]$LocalPath,
        [string]$RemotePath,
        [string]$Owner,
        [string]$Group,
        [string]$Mode
    )

    $resolved = (Resolve-Path -LiteralPath $LocalPath).Path
    $relative = $resolved.Substring($ProjectRoot.Length + 1).Replace("\", "/")
    $entries.Add([pscustomobject]@{
        Category = $Category
        LocalPath = $resolved
        RelativePath = $relative
        RemotePath = $RemotePath
        Owner = $Owner
        Group = $Group
        Mode = $Mode.TrimStart("0")
    })
}

foreach ($manifestEntry in $deploymentManifest.Entries | Sort-Object Source) {
    $category = ($manifestEntry.Source -split "/")[1]
    Add-SourceEntry `
        -Category $category `
        -LocalPath $manifestEntry.LocalPath `
        -RemotePath $manifestEntry.Destination `
        -Owner $manifestEntry.Owner `
        -Group $manifestEntry.Group `
        -Mode $manifestEntry.Mode
}

$manifestText = ($entries | ForEach-Object { "$($_.RelativePath)`t$($_.RemotePath)" }) -join "`n"
$manifestBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($manifestText + "`n"))
$remoteScript = @'
set -u

manifest_file="$(mktemp)"
trap 'rm -f "$manifest_file"' EXIT
printf '%s' '__MANIFEST_BASE64__' | base64 -d > "$manifest_file"

while IFS="$(printf '\t')" read -r key path; do
  [ -n "$key" ] || continue
  if [ ! -e "$path" ]; then
    printf 'FILE\t%s\tabsent\t0\t-\n' "$key"
  elif [ ! -f "$path" ]; then
    printf 'FILE\t%s\tnot-file\t0\t-\n' "$key"
  elif [ -r "$path" ]; then
    size="$(stat -c '%s' "$path")"
    hash="$(sha256sum "$path" | awk '{print $1}')"
    mode="$(stat -c '%a' "$path")"
    owner="$(stat -c '%U' "$path")"
    group="$(stat -c '%G' "$path")"
    printf 'FILE\t%s\treadable\t%s\t%s\t%s\t%s\t%s\n' "$key" "$size" "$hash" "$mode" "$owner" "$group"
  else
    size="$(stat -c '%s' "$path" 2>/dev/null || printf '0')"
    mode="$(stat -c '%a' "$path" 2>/dev/null || printf -- '-')"
    owner="$(stat -c '%U' "$path" 2>/dev/null || printf -- '-')"
    group="$(stat -c '%G' "$path" 2>/dev/null || printf -- '-')"
    printf 'FILE\t%s\tunreadable\t%s\t-\t%s\t%s\t%s\n' "$key" "$size" "$mode" "$owner" "$group"
  fi
done < "$manifest_file"

emit_active_files() {
  category="$1"
  root="$2"
  shift 2
  find "$root" -maxdepth 1 -type f "$@" 2>/dev/null | sort | while IFS= read -r path; do
    name="$(basename "$path")"
    case "$name" in
      *.bak|*.bak-*|*.backup-*|*.previous|*.new) continue ;;
    esac
    printf 'ACTIVE\t%s\t%s\n' "$category" "$path"
  done
}

emit_active_files script '__STEAM_ROOT__/bin'
emit_active_files project-script '__PROJECT_ROOT__/server/bin'
emit_active_files sbin /usr/local/sbin -name 'gaylemon-*'
emit_active_files systemd /etc/systemd/system \( -name 'palworld*' -o -name 'cloudflare-update-dns*' \)
emit_active_files sysctl /etc/sysctl.d -name '*palworld*'
emit_active_files sudoers /etc/sudoers.d \( -name '*palworld*' -o -name 'gaylemon-*' \)

printf 'META\tprojectGit\t'
if git -C '__PROJECT_ROOT__' rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C '__PROJECT_ROOT__' rev-parse HEAD
else
  printf 'not-a-git-worktree\n'
fi

tools_path="$(readlink -f '__PROJECT_ROOT__/vendor/PalworldSaveTools-current' 2>/dev/null || true)"
[ -n "$tools_path" ] || tools_path="__PROJECT_ROOT__/vendor/PalworldSaveTools"
printf 'META\tsaveToolsPath\t%s\n' "$tools_path"
printf 'META\tsaveToolsHead\t%s\n' "$(git -C "$tools_path" rev-parse HEAD 2>/dev/null || printf 'unknown')"
printf 'META\tsaveToolsRemote\t%s\n' "$(git -C "$tools_path" remote get-url origin 2>/dev/null || printf 'unknown')"
'@

$remoteScript = $remoteScript.Replace("__MANIFEST_BASE64__", $manifestBase64).Replace("__PROJECT_ROOT__", $config.RemoteProjectRoot).Replace("__STEAM_ROOT__", $config.RemoteSteamRoot)
$encodedScript = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteScript))
$lines = @(& ssh.exe -o BatchMode=yes -o ConnectTimeout=8 $config.SshAlias "printf '%s' '$encodedScript' | base64 -d | bash" 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "Audit SSH impossible: $($lines -join ' ')"
}

$remoteFiles = @{}
$metadata = @{}
$activeFiles = [Collections.Generic.List[object]]::new()
foreach ($lineObject in $lines) {
    $line = [string]$lineObject
    $parts = $line -split "`t", 8
    if ($parts.Count -ge 8 -and $parts[0] -eq "FILE") {
        $remoteFiles[$parts[1]] = [pscustomobject]@{
            Access = $parts[2]
            Size = [long]$parts[3]
            Hash = $parts[4]
            Mode = $parts[5]
            Owner = $parts[6]
            Group = $parts[7]
        }
    }
    elseif ($parts.Count -ge 3 -and $parts[0] -eq "META") {
        $metadata[$parts[1]] = $parts[2]
    }
    elseif ($parts.Count -ge 3 -and $parts[0] -eq "ACTIVE") {
        $activeFiles.Add([pscustomobject]@{
            Category = $parts[1]
            RemotePath = $parts[2]
        })
    }
}

$results = [Collections.Generic.List[object]]::new()
foreach ($entry in $entries) {
    $localItem = Get-Item -LiteralPath $entry.LocalPath
    $localHash = (Get-FileHash -LiteralPath $entry.LocalPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $remote = $remoteFiles[$entry.RelativePath]
    $status = "absent"
    $details = "fichier distant absent"

    if ($remote) {
        $metadataMatches = (
            $remote.Mode -eq $entry.Mode -and
            $remote.Owner -eq $entry.Owner -and
            $remote.Group -eq $entry.Group
        )
        if ($remote.Access -eq "readable" -and $remote.Hash -eq $localHash -and $metadataMatches) {
            $status = "identique"
            $details = "SHA-256, proprietaire et mode identiques"
        }
        elseif ($remote.Access -eq "unreadable" -and $remote.Size -eq $localItem.Length -and $metadataMatches) {
            $status = "taille-identique"
            $details = "protege; taille et metadonnees identiques, empreinte non verifiee"
        }
        elseif ($remote.Access -eq "readable") {
            $status = "different"
            $details = if ($remote.Hash -ne $localHash) { "empreinte differente" } else { "proprietaire, groupe ou mode different" }
        }
        elseif ($remote.Access -eq "unreadable") {
            $status = "different"
            $details = if ($remote.Size -ne $localItem.Length) { "protege; taille differente" } else { "protege; proprietaire, groupe ou mode different" }
        }
        else {
            $details = "etat distant: $($remote.Access)"
        }
    }

    $results.Add([pscustomobject]@{
        Category = $entry.Category
        Source = $entry.RelativePath
        ActivePath = $entry.RemotePath
        Status = $status
        Details = $details
        LocalBytes = [long]$localItem.Length
        RemoteBytes = if ($remote) { [long]$remote.Size } else { 0 }
        LocalSha256 = $localHash
        RemoteSha256 = if ($remote -and $remote.Hash -ne "-") { $remote.Hash } else { $null }
        ExpectedOwner = $entry.Owner
        ExpectedGroup = $entry.Group
        ExpectedMode = $entry.Mode
        RemoteOwner = if ($remote) { $remote.Owner } else { $null }
        RemoteGroup = if ($remote) { $remote.Group } else { $null }
        RemoteMode = if ($remote) { $remote.Mode } else { $null }
    })
}

$expectedRemotePaths = @{}
foreach ($entry in $entries) { $expectedRemotePaths[$entry.RemotePath] = $true }
$unexpectedActiveFiles = @($activeFiles | Where-Object { -not $expectedRemotePaths.ContainsKey($_.RemotePath) })

$lockPath = Join-Path $ProjectRoot "dependencies\palworld-save-tools.lock.json"
$lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
$activeToolsHead = [string]$metadata.saveToolsHead
$activeToolsRemote = ([string]$metadata.saveToolsRemote).TrimEnd("/")
$lockedToolsRemote = ([string]$lock.repository).TrimEnd("/")
$forkMatches = $activeToolsHead -eq [string]$lock.commit -and $activeToolsRemote -eq $lockedToolsRemote

$summary = [ordered]@{
    files = $results.Count
    identical = @($results | Where-Object Status -eq "identique").Count
    sizeOnly = @($results | Where-Object Status -eq "taille-identique").Count
    different = @($results | Where-Object Status -eq "different").Count
    absent = @($results | Where-Object Status -eq "absent").Count
    unexpected = $unexpectedActiveFiles.Count
    forkMatchesLock = [bool]$forkMatches
    projectGit = [string]$metadata.projectGit
}

$report = [ordered]@{
    version = 1
    checkedAt = (Get-Date).ToString("o")
    sshAlias = $config.SshAlias
    summary = $summary
    palworldSaveTools = [ordered]@{
        path = [string]$metadata.saveToolsPath
        remote = $activeToolsRemote
        activeCommit = $activeToolsHead
        lockedCommit = [string]$lock.commit
        matchesLock = [bool]$forkMatches
    }
    files = @($results)
    unexpectedActiveFiles = $unexpectedActiveFiles
}

Write-Host "Audit de la source Ubuntu Gaylemon" -ForegroundColor Cyan
Write-Host "Comparaison en lecture seule; aucun sudo ou systemctl n'est execute." -ForegroundColor DarkGray
Write-Host ""
$results | Select-Object Status,Category,Source,Details | Format-Table -AutoSize
Write-Host ""
Write-Host "Identiques: $($summary.identical)" -ForegroundColor Green
Write-Host "Proteges, taille identique: $($summary.sizeOnly)" -ForegroundColor Yellow
Write-Host "Differents: $($summary.different)"
Write-Host "Absents: $($summary.absent)"
Write-Host "Fichiers actifs non suivis: $($summary.unexpected)"
foreach ($unexpected in $unexpectedActiveFiles) {
    Write-Host "- $($unexpected.RemotePath)" -ForegroundColor Red
}
Write-Host "Fork actif: $activeToolsHead"
Write-Host "Fork conforme au verrou: $forkMatches"
Write-Host "Projet Ubuntu Git: $($summary.projectGit)"

if ($Rapport) {
    $resolvedReport = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Rapport)
    $parent = Split-Path -Parent $resolvedReport
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $json = $report | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText($resolvedReport, $json.TrimEnd() + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Write-Host "Rapport: $resolvedReport"
}

if ($summary.different -gt 0 -or $summary.absent -gt 0 -or $summary.unexpected -gt 0 -or -not $forkMatches) {
    exit 1
}
