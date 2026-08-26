[CmdletBinding()]
param([string]$KeyDirectory = (Join-Path $env:USERPROFILE '.gaylemon'))

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$publicDestination = Join-Path $repoRoot 'security\cosign.pub'
$cosignImage = 'ghcr.io/sigstore/cosign/cosign:v3.1.3@sha256:9e5c2f2edc34351160407ca3416c61855bdf9403c3c5936e0f0be7fc261611b8'
$KeyDirectory = [IO.Path]::GetFullPath($KeyDirectory)
$privateKey = Join-Path $KeyDirectory 'cosign.key'
$generatedPublicKey = Join-Path $KeyDirectory 'cosign.pub'
$protectedPassword = Join-Path $KeyDirectory 'cosign-password.dpapi'

foreach ($path in @($privateKey,$generatedPublicKey,$protectedPassword,$publicDestination)) {
    if (Test-Path -LiteralPath $path) { throw "Refus d'écraser un matériel de signature existant : $path" }
}
New-Item -ItemType Directory -Force -Path $KeyDirectory | Out-Null
$password = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
$previousCosignPassword = $env:COSIGN_PASSWORD
try {
    $env:COSIGN_PASSWORD = $password
    docker run --rm -e COSIGN_PASSWORD -v "${KeyDirectory}:/keys" -w /keys $cosignImage generate-key-pair
    if ($LASTEXITCODE -ne 0) { throw 'La génération de la clé Cosign a échoué.' }
    $protected = $password | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
    [IO.File]::WriteAllText($protectedPassword, $protected + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $publicDestination) | Out-Null
    Copy-Item -LiteralPath $generatedPublicKey -Destination $publicDestination
}
finally {
    $env:COSIGN_PASSWORD = $previousCosignPassword
    $password = $null
}
Write-Host "Clé privée chiffrée : $privateKey" -ForegroundColor Green
Write-Host "Mot de passe protégé par DPAPI : $protectedPassword"
Write-Host "Clé publique à committer : $publicDestination"
