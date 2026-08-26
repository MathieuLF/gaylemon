[CmdletBinding()]
param(
    [string]$Version = ((Get-Content -Raw -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'VERSION')).Trim()),
    [string]$Image = 'ghcr.io/mathieulf/gaylemon',
    [string]$CosignKey = "$env:USERPROFILE\.gaylemon\cosign.key",
    [string]$CosignPublicKey = "$env:USERPROFILE\.gaylemon\cosign.pub",
    [switch]$Publish
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (@(& git -C $root status --porcelain).Count -ne 0) { throw 'La publication exige un arbre Git propre.' }
foreach ($command in 'docker','syft','trivy','cosign','go') {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Outil de release absent: $command" }
}
foreach ($keyPath in $CosignKey,$CosignPublicKey) {
    if (-not (Test-Path -LiteralPath $keyPath -PathType Leaf)) { throw "Clé CoSign absente: $keyPath" }
}
$commit = (& git -C $root rev-parse HEAD).Trim()
$releaseNotes = Get-Content -Raw -LiteralPath (Join-Path $root 'portal\release-notes.json') | ConvertFrom-Json
if (-not @($releaseNotes.releases | Where-Object { $_.version -eq $Version })) { throw 'Les notes de version ne couvrent pas la version demandée.' }
if (-not (Select-String -LiteralPath (Join-Path $root 'CHANGELOG.md') -SimpleMatch 'multi-saisons' -Quiet)) { throw 'Le journal des changements ne couvre pas le cycle multi-saisons.' }
$tag = "$Image`:$Version"
docker build --build-arg "GAYLEMON_VERSION=$Version" --build-arg "GAYLEMON_COMMIT=$commit" --build-arg GAYLEMON_CHANNEL=production --tag $tag $root
if ($LASTEXITCODE -ne 0) { throw 'Construction OCI impossible.' }
$output = Join-Path $root 'release'
New-Item -ItemType Directory -Force -Path $output | Out-Null
syft $tag -o "spdx-json=$output\gaylemon-$Version.spdx.json" -o "cyclonedx-json=$output\gaylemon-$Version.cdx.json"
if ($LASTEXITCODE -ne 0) { throw 'SBOM impossible.' }
trivy image --exit-code 1 --severity HIGH,CRITICAL $tag
if ($LASTEXITCODE -ne 0) { throw 'Scan Trivy bloquant.' }
$agent = Join-Path $output "gaylemon-agent-$Version-linux-amd64"
$env:CGO_ENABLED = '0'; $env:GOOS = 'linux'; $env:GOARCH = 'amd64'
try { go build -mod=readonly -trimpath -ldflags "-s -w -X main.version=$Version" -o $agent ./cmd/gaylemon }
finally { Remove-Item Env:CGO_ENABLED,Env:GOOS,Env:GOARCH -ErrorAction SilentlyContinue }
$agentSha = (Get-FileHash -LiteralPath $agent -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$agent.sha256", "$agentSha  $([IO.Path]::GetFileName($agent))`n", [Text.UTF8Encoding]::new($false))
cosign sign-blob --yes --key $CosignKey --output-signature "$agent.sig" --output-certificate "$agent.pem" $agent
if ($LASTEXITCODE -ne 0) { throw 'Signature du bundle agent impossible.' }
cosign verify-blob --key $CosignPublicKey --signature "$agent.sig" $agent
if ($LASTEXITCODE -ne 0) { throw 'Vérification du bundle agent impossible.' }
$localImageID = (docker image inspect $tag --format '{{.Id}}').Trim()
$descriptor = Join-Path $output "gaylemon-$Version-local-image.json"
[IO.File]::WriteAllText($descriptor, (([ordered]@{ image=$tag; imageId=$localImageID; commit=$commit } | ConvertTo-Json) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
cosign sign-blob --yes --key $CosignKey --output-signature "$descriptor.sig" --output-certificate "$descriptor.pem" $descriptor
if ($LASTEXITCODE -ne 0) { throw "Preuve Cosign locale de l'image impossible." }
cosign verify-blob --key $CosignPublicKey --signature "$descriptor.sig" $descriptor
if ($LASTEXITCODE -ne 0) { throw "Vérification de la preuve locale de l'image impossible." }
if ($Publish) {
    docker push $tag
    if ($LASTEXITCODE -ne 0) { throw 'Publication GHCR impossible.' }
    $digest = (docker buildx imagetools inspect $tag --format '{{.Manifest.Digest}}').Trim()
    if ($digest -notmatch '^sha256:[0-9a-f]{64}$') { throw 'Digest GHCR introuvable.' }
    $reference = "$Image@$digest"
    cosign sign --yes --key $CosignKey $reference
    if ($LASTEXITCODE -ne 0) { throw 'Signature du digest GHCR impossible.' }
    cosign attest --yes --key $CosignKey --type spdxjson --predicate "$output\gaylemon-$Version.spdx.json" $reference
    if ($LASTEXITCODE -ne 0) { throw 'Attestation SPDX impossible.' }
    cosign attest --yes --key $CosignKey --type cyclonedx --predicate "$output\gaylemon-$Version.cdx.json" $reference
    if ($LASTEXITCODE -ne 0) { throw 'Attestation CycloneDX impossible.' }
    [ordered]@{ schema='gaylemon.release.v2'; version=$Version; commit=$commit; image=$reference; agentSha256=$agentSha; signed=$true; attested=$true } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output "gaylemon-$Version-release.json") -Encoding utf8NoBOM
}
[ordered]@{ schema='gaylemon.release.v2'; version=$Version; commit=$commit; image=$tag; imageId=$localImageID; agentSha256=$agentSha; localSigningVerified=$true; published=[bool]$Publish } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'release-local.json') -Encoding utf8NoBOM
Write-Host "Release préparée: $tag"
