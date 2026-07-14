#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/home/gaylemon/Gaylemon"
VENDOR="$ROOT/vendor"
CURRENT="$VENDOR/PalworldSaveTools-current"
RELEASES="$VENDOR/PalworldSaveTools-releases"
WORKER="$ROOT/server/bin/palworld-save-snapshot.py"
OUTPUT="$ROOT/runtime/public-save-snapshot.json"
REPOSITORY="https://github.com/MathieuLF/PalworldSaveTools.git"

mkdir -p "$RELEASES" "$ROOT/runtime"
target_sha="$(git ls-remote "$REPOSITORY" refs/heads/main | awk '{print $1}')"
if [[ -z "$target_sha" ]]; then
  echo "Impossible de lire la révision du fork." >&2
  exit 1
fi

current_sha=""
if [[ -e "$CURRENT/.git" ]]; then
  current_sha="$(git -C "$CURRENT" rev-parse HEAD 2>/dev/null || true)"
fi

if [[ "$current_sha" == "$target_sha" ]]; then
  echo "PalworldSaveTools est déjà à jour: ${target_sha:0:12}"
  exit 0
fi

candidate="$RELEASES/${target_sha}-$(date +%Y%m%d%H%M%S)"

cleanup() {
  if [[ -d "$candidate" && ! -L "$CURRENT" ]]; then
    echo "Le candidat incomplet est conservé pour diagnostic: $candidate" >&2
  fi
}
trap cleanup ERR

echo "Préparation de PalworldSaveTools ${target_sha:0:12}..."
git clone --quiet --depth 1 --branch main "$REPOSITORY" "$candidate"
python3 -m venv "$candidate/.venv"
"$candidate/.venv/bin/pip" install --quiet --disable-pip-version-check \
  -e "$candidate/src/palsav/palooz" \
  -e "$candidate/src/palsav" \
  pytest

(
  cd "$candidate/tests"
  "$candidate/.venv/bin/python" -m pytest unit/palsav_core -q
)

test_output="$ROOT/runtime/public-save-snapshot.${target_sha}.test.json"
test_diagnostics="$ROOT/runtime/public-save-diagnostics.${target_sha}.test.json"
test_lock="$ROOT/runtime/palworld-save-snapshot.${target_sha}.test.lock"
nice -n 15 ionice -c3 "$candidate/.venv/bin/python" "$WORKER" \
  --parser-repo "$candidate" \
  --output "$test_output" \
  --diagnostics "$test_diagnostics" \
  --lock "$test_lock" \
  --no-archive

"$candidate/.venv/bin/python" - "$test_output" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1], encoding="utf-8"))
assert payload.get("ok") is True
assert payload.get("summary", {}).get("players", 0) > 0
assert payload.get("summary", {}).get("pals", 0) > 0
assert payload.get("parser", {}).get("commit") not in {None, "", "unknown"}
print("Snapshot réel validé.")
PY

link_tmp="$VENDOR/.PalworldSaveTools-current.$target_sha"
ln -s "$candidate" "$link_tmp"
mv -Tf "$link_tmp" "$CURRENT"
mv -f "$test_output" "$OUTPUT"
mv -f "$test_diagnostics" "$ROOT/runtime/public-save-diagnostics.json"
trap - ERR
echo "PalworldSaveTools activé: ${target_sha:0:12}"
