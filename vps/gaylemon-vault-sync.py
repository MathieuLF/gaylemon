#!/usr/bin/env python3
"""Synchronise l'environnement de production depuis le Vault DockPanel."""

from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import json
import os
import re
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


SITE_DOMAIN = "gaylemon.nethercore.dev"
VAULT_NAME = "Gaylémon production"
DOCKPANEL_API_URL = "http://127.0.0.1:3080/api"
DOCKPANEL_API_ENV = Path("/etc/dockpanel/api.env")
PRODUCTION_ENV = Path("/etc/gaylemon/production.env")
DOCKPANEL_DATABASE_CONTAINER = "dockpanel-postgres"
SECRET_DEFINITIONS = {
    "GAYLEMON_AGENT_PUBLIC_KEYS": (
        "api_key",
        "Clés publiques Ed25519 autorisées pour les agents Gaylémon.",
    ),
    "GAYLEMON_DATABASE_URL": (
        "password",
        "URL de connexion du rôle PostgreSQL applicatif Gaylémon.",
    ),
    "GAYLEMON_GITHUB_CLIENT_ID": (
        "env",
        "Identifiant de l'application OAuth GitHub du portail d'exploitation.",
    ),
    "GAYLEMON_GITHUB_CLIENT_SECRET": (
        "password",
        "Secret de l'application OAuth GitHub du portail d'exploitation.",
    ),
}
SECRET_KEYS = frozenset(SECRET_DEFINITIONS)
ENV_KEY_PATTERN = re.compile(r"^[A-Z][A-Z0-9_]*$")


class VaultSyncError(RuntimeError):
    pass


def read_dotenv(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise VaultSyncError(f"Ligne invalide dans {path} à la ligne {line_number}")
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not ENV_KEY_PATTERN.fullmatch(key):
            raise VaultSyncError(f"Nom de variable invalide dans {path}: {key}")
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
            quote = value[0]
            value = value[1:-1]
            if quote == "'":
                value = value.replace("\\'", "'").replace("\\\\", "\\")
            else:
                value = value.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")
        values[key] = value
    return values


def validate_secrets(values: dict[str, str]) -> dict[str, str]:
    available = set(values)
    missing = sorted(SECRET_KEYS - available)
    unexpected = sorted(available - SECRET_KEYS)
    empty = sorted(key for key in SECRET_KEYS if not values.get(key))
    if missing:
        raise VaultSyncError(f"Secrets absents: {', '.join(missing)}")
    if unexpected:
        raise VaultSyncError(f"Secrets non autorisés dans le coffre Gaylémon: {', '.join(unexpected)}")
    if empty:
        raise VaultSyncError(f"Secrets vides: {', '.join(empty)}")
    for key, value in values.items():
        if "\0" in value or "\n" in value or "\r" in value:
            raise VaultSyncError(f"La valeur de {key} doit tenir sur une ligne")
    return {key: values[key] for key in sorted(SECRET_KEYS)}


def quote_dotenv(value: str) -> str:
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"


def render_dotenv(values: dict[str, str]) -> str:
    validated = validate_secrets(values)
    lines = [
        "# Généré depuis le Vault DockPanel du site gaylemon.nethercore.dev.",
        "# Ne pas modifier directement; utiliser gaylemon-vault-sync.",
    ]
    lines.extend(f"{key}={quote_dotenv(validated[key])}" for key in sorted(validated))
    return "\n".join(lines) + "\n"


def run_psql(query: str) -> list[list[str]]:
    command = [
        "/usr/bin/docker",
        "exec",
        DOCKPANEL_DATABASE_CONTAINER,
        "psql",
        "-U",
        "dockpanel",
        "-d",
        "dockpanel",
        "-AtF",
        "|",
        "-c",
        query,
    ]
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise VaultSyncError("Impossible d'interroger la configuration DockPanel")
    return [line.split("|") for line in result.stdout.splitlines() if line.strip()]


def site_identity() -> dict[str, str]:
    rows = run_psql(
        "SELECT s.id::text, u.id::text, u.email, u.role "
        "FROM sites s JOIN users u ON u.id = s.user_id "
        f"WHERE s.domain = '{SITE_DOMAIN}';"
    )
    if len(rows) != 1 or len(rows[0]) != 4:
        raise VaultSyncError(f"Le site {SITE_DOMAIN} doit appartenir à un seul utilisateur DockPanel")
    site_id, user_id, email, role = rows[0]
    return {"site_id": site_id, "user_id": user_id, "email": email, "role": role}


def load_jwt_secret() -> str:
    values = read_dotenv(DOCKPANEL_API_ENV)
    jwt_secret = values.get("JWT_SECRET", "")
    if len(jwt_secret) < 32:
        raise VaultSyncError("JWT_SECRET DockPanel absent ou invalide")
    return jwt_secret


def base64url(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def issue_local_token(identity: dict[str, str], jwt_secret: str) -> str:
    now = int(time.time())
    header = base64url(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode())
    payload = base64url(
        json.dumps(
            {
                "sub": identity["user_id"],
                "email": identity["email"],
                "role": identity["role"],
                "iat": now,
                "exp": now + 120,
            },
            separators=(",", ":"),
        ).encode()
    )
    unsigned = f"{header}.{payload}"
    signature = base64url(hmac.new(jwt_secret.encode(), unsigned.encode(), hashlib.sha256).digest())
    return f"{unsigned}.{signature}"


def api_request(token: str, method: str, path: str, body: dict[str, Any] | None = None) -> Any:
    data = None
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}
    if body is not None:
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(
        f"{DOCKPANEL_API_URL}{path}",
        data=data,
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            payload = response.read()
    except urllib.error.HTTPError as error:
        raise VaultSyncError(f"L'API DockPanel a refusé l'opération ({error.code})") from None
    except urllib.error.URLError as error:
        raise VaultSyncError("L'API locale DockPanel est indisponible") from error
    if not payload:
        return None
    try:
        return json.loads(payload)
    except json.JSONDecodeError as error:
        raise VaultSyncError("Réponse DockPanel invalide") from error


def find_site_vault(token: str, site_id: str) -> dict[str, Any] | None:
    vaults = api_request(token, "GET", "/secrets/vaults")
    matches = [vault for vault in vaults if vault.get("site_id") == site_id]
    if len(matches) > 1:
        raise VaultSyncError(f"Plusieurs coffres sont rattachés à {SITE_DOMAIN}")
    return matches[0] if matches else None


def bootstrap_vault(source: Path) -> None:
    source_values = read_dotenv(source)
    values = validate_secrets({key: source_values.get(key, "") for key in SECRET_KEYS})
    identity = site_identity()
    token = issue_local_token(identity, load_jwt_secret())
    if find_site_vault(token, identity["site_id"]) is not None:
        raise VaultSyncError(f"Un coffre existe déjà pour {SITE_DOMAIN}; amorçage refusé")

    vault = api_request(
        token,
        "POST",
        "/secrets/vaults",
        {
            "name": VAULT_NAME,
            "description": "Secrets du portail et de l'agent Gaylémon en production.",
            "site_id": identity["site_id"],
        },
    )
    vault_id = vault["id"]
    try:
        for key in sorted(values):
            secret_type, description = SECRET_DEFINITIONS[key]
            api_request(
                token,
                "POST",
                f"/secrets/vaults/{vault_id}/secrets",
                {
                    "key": key,
                    "value": values[key],
                    "description": description,
                    "secret_type": secret_type,
                    "auto_inject": True,
                },
            )
    except Exception:
        try:
            api_request(token, "DELETE", f"/secrets/vaults/{vault_id}")
        except Exception:
            pass
        raise
    print(f"Coffre {VAULT_NAME} créé avec {len(values)} secrets.")


def pull_vault_values() -> dict[str, str]:
    identity = site_identity()
    token = issue_local_token(identity, load_jwt_secret())
    vault = find_site_vault(token, identity["site_id"])
    if vault is None:
        raise VaultSyncError(f"Aucun coffre n'est rattaché à {SITE_DOMAIN}")
    entries = api_request(token, "GET", f"/secrets/vaults/{vault['id']}/pull")
    values: dict[str, str] = {}
    for entry in entries:
        key = entry.get("key")
        value = entry.get("value")
        if not isinstance(key, str) or not isinstance(value, str) or key in values:
            raise VaultSyncError("Le coffre DockPanel contient une entrée invalide ou dupliquée")
        values[key] = value
    return validate_secrets(values)


def write_atomically(path: Path, content: str) -> bool:
    if path.is_symlink():
        raise VaultSyncError(f"Le fichier cible ne doit pas être un lien symbolique: {path}")
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o750)
    current = path.read_text(encoding="utf-8") if path.exists() else None
    if current == content:
        os.chown(path, 0, 0)
        os.chmod(path, 0o600)
        return False

    file_descriptor, temporary_name = tempfile.mkstemp(prefix=".production.env.", dir=path.parent)
    temporary_path = Path(temporary_name)
    try:
        os.fchmod(file_descriptor, 0o600)
        with os.fdopen(file_descriptor, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.chown(temporary_path, 0, 0)
        os.replace(temporary_path, path)
        os.chmod(path, 0o600)
    finally:
        temporary_path.unlink(missing_ok=True)
    return True


def sync_vault(check_only: bool) -> None:
    expected = render_dotenv(pull_vault_values())
    if check_only:
        if not PRODUCTION_ENV.is_file() or PRODUCTION_ENV.is_symlink():
            raise VaultSyncError(f"{PRODUCTION_ENV} est absent ou invalide")
        metadata = PRODUCTION_ENV.stat()
        if PRODUCTION_ENV.read_text(encoding="utf-8") != expected:
            raise VaultSyncError("production.env ne correspond pas au Vault DockPanel")
        if metadata.st_uid != 0 or metadata.st_gid != 0 or metadata.st_mode & 0o777 != 0o600:
            raise VaultSyncError("production.env doit appartenir à root:root avec le mode 0600")
        print("production.env correspond au Vault DockPanel.")
        return

    changed = write_atomically(PRODUCTION_ENV, expected)
    state = "mis à jour" if changed else "déjà à jour"
    print(f"production.env {state} depuis le Vault DockPanel ({len(SECRET_KEYS)} secrets).")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="action", required=True)
    bootstrap = subparsers.add_parser("bootstrap", help="Créer le coffre depuis l'environnement existant")
    bootstrap.add_argument("--source", type=Path, default=PRODUCTION_ENV)
    subparsers.add_parser("sync", help="Matérialiser le coffre dans production.env")
    subparsers.add_parser("check", help="Vérifier production.env sans le modifier")
    return parser.parse_args()


def main() -> int:
    if os.geteuid() != 0:
        raise VaultSyncError("Cette commande doit être exécutée par root")
    args = parse_args()
    if args.action == "bootstrap":
        bootstrap_vault(args.source)
    else:
        sync_vault(check_only=args.action == "check")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (VaultSyncError, OSError, ValueError) as error:
        print(f"ERREUR: {error}", file=os.sys.stderr)
        raise SystemExit(1)
