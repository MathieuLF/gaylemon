param(
    [ValidateSet("allow", "remove", "status")]
    [string]$Action = "status",

    [string]$KumaIp
)

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "lib\Gaylemon.Config.ps1")
$config = Get-GaylemonConfig -ProjectRoot $ProjectRoot

if ($Action -ne "status" -and -not $KumaIp) {
    Write-Error "KumaIp is required for Action '$Action'."
    exit 1
}

if ($KumaIp) {
    $parsedIp = $null
    if (-not [System.Net.IPAddress]::TryParse($KumaIp, [ref]$parsedIp)) {
        Write-Error "Invalid KumaIp: $KumaIp"
        exit 1
    }
}

$remoteScript = switch ($Action) {
    "status" {
        @'
set -euo pipefail
ufw status numbered
'@
    }
    "allow" {
        @"
set -euo pipefail
if ufw status numbered | grep -F '8212/tcp' | grep -F 'ALLOW IN' | grep -F '$KumaIp' >/dev/null; then
  echo 'Uptime Kuma rule already exists for $KumaIp.'
else
  ufw insert 3 allow from $KumaIp to any port 8212 proto tcp
fi
ufw status numbered
"@
    }
    "remove" {
        @"
set -euo pipefail
ufw delete allow from $KumaIp to any port 8212 proto tcp || true
ufw status numbered
"@
    }
}

$sudoPassword = Read-Host "Mot de passe sudo pour $($config.SshAlias)" -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sudoPassword)

try {
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    $encodedScript = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($remoteScript))
    $remoteCommand = "tmp_script=`$(mktemp); printf '%s' '$encodedScript' | base64 -d > `$tmp_script; sudo -S -p '' bash `$tmp_script; status=`$?; rm -f `$tmp_script; exit `$status"

    $plainPassword | ssh.exe $config.SshAlias $remoteCommand
    exit $LASTEXITCODE
}
finally {
    if ($bstr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}
