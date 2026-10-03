#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $(uname -s) != Linux || $(uname -m) != x86_64 ]]; then
  echo 'Ce setup cible Ubuntu 24.04 amd64.' >&2
  exit 1
fi
source /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == 24.04 ]] || { echo 'Ubuntu 24.04 est requis.' >&2; exit 1; }
if [[ $EUID == 0 ]]; then elevated=(); else elevated=(sudo -n); fi
"${elevated[@]}" apt-get update
"${elevated[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  ca-certificates curl git xz-utils tar build-essential python3 postgresql-16
tools="$PWD/runtime/.tools"
mkdir -p "$tools"
temporary=$(mktemp -d)
python3 -B -c 'import json,runpy; m=runpy.run_path("scripts/project.py"); json.dump(m["snapshot"](),open("'"$temporary"'/before.json","w"))'
finish() {
  local result=$?
  python3 -B -c 'import json,runpy; m=runpy.run_path("scripts/project.py"); assert m["snapshot"]()==json.load(open("'"$temporary"'/before.json")), "Le setup a modifié les fichiers suivis ou l état Git"' || result=1
  rm -rf -- "$temporary"
  exit "$result"
}
trap finish EXIT
read -r go_version node_version < <(python3 -B -c \
  'import json; d=json.load(open("config/development-tools.json")); print(d["go"],d["node"])')
if [[ ! -x "$tools/go/bin/go" ]] || [[ $("$tools/go/bin/go" version) != "go version go${go_version} linux/amd64" ]]; then
  curl --fail --location --retry 3 "https://go.dev/dl/go${go_version}.linux-amd64.tar.gz" -o "$temporary/go.tar.gz"
  echo '675c26c449cbb18fc24b74650de1eabbae6e16f64326fd85a283fb3b58280685  '"$temporary/go.tar.gz" | sha256sum -c -
  tar -xzf "$temporary/go.tar.gz" -C "$tools"
fi
if [[ ! -x "$tools/node/bin/node" ]] || [[ $("$tools/node/bin/node" --version) != "v${node_version}" ]]; then
  archive="node-v${node_version}-linux-x64.tar.xz"
  curl --fail --location --retry 3 "https://nodejs.org/dist/v${node_version}/$archive" -o "$temporary/$archive"
  curl --fail --location --retry 3 "https://nodejs.org/dist/v${node_version}/SHASUMS256.txt" -o "$temporary/SHASUMS256.txt"
  (cd "$temporary"; grep "  $archive$" SHASUMS256.txt | sha256sum -c -)
  mkdir -p "$tools/node"
  tar -xJf "$temporary/$archive" --strip-components=1 -C "$tools/node"
fi
export PATH="$tools/go/bin:$tools/node/bin:$PATH"
export GOFLAGS=-mod=readonly GOTOOLCHAIN=local
python3 -B -c 'import sys; assert sys.version_info >= (3,12), "Python 3.12 minimum"'
go mod download
npm ci --ignore-scripts
npx --no-install playwright install --with-deps chromium
npm run build:check
echo 'Installation terminée. Commande quotidienne : python3 -B scripts/project.py check-dev'
echo 'Démarrage : python3 -B scripts/project.py start; contrôle HTTP : ajouter --check.'
