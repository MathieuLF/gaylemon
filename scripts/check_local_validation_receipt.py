#!/usr/bin/env python3
"""Validate the Gaylémon suite.local-validation.v2 receipt."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any


REQUIRED_KEYS = {
    "schema",
    "contract",
    "contractRevision",
    "profile",
    "application",
    "version",
    "result",
    "mode",
    "startedAt",
    "completedAt",
    "git",
    "routes",
    "tools",
    "checks",
    "artifacts",
    "security",
    "lifecycle",
}
FULL_TOOLS = {
    "go",
    "node",
    "powershell",
    "python",
    "git",
    "npm",
    "docker",
    "playwright",
    "axe",
    "deadcode",
    "govulncheck",
    "gitleaks",
    "syft",
    "trivy",
    "cosign",
    "bash",
}
SEMVER = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"
)


def _canonical_routes(routes: list[dict[str, Any]]) -> bytes:
    return json.dumps(routes, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def validate_receipt(receipt: dict[str, Any]) -> None:
    errors: list[str] = []
    missing = sorted(REQUIRED_KEYS - receipt.keys())
    errors.extend(f"clé manquante: {key}" for key in missing)

    expected = {
        "schema": "suite.local-validation.v2",
        "contract": "suite-foundation-v2",
        "application": "gaylemon",
        "profile": "seasonal-go-microsite",
        "contractRevision": "2.2.0",
        "result": "passed",
    }
    for key, value in expected.items():
        if receipt.get(key) != value:
            errors.append(f"{key}: attendu {value!r}")

    if "suiteContract" in receipt:
        errors.append("suiteContract est obsolète; utiliser contract")
    if receipt.get("mode") not in {"quick", "full"}:
        errors.append("mode doit être quick ou full")
    if not isinstance(receipt.get("version"), str) or not SEMVER.fullmatch(receipt.get("version", "")):
        errors.append("version doit être une valeur SemVer sans préfixe v")
    for key in ("startedAt", "completedAt"):
        if not isinstance(receipt.get(key), str) or not receipt.get(key):
            errors.append(f"{key} est requis")
    git = receipt.get("git")
    if not isinstance(git, dict):
        errors.append("git doit être un objet")
        git = {}
    if not isinstance(git.get("commit"), str) or not re.fullmatch(r"[0-9a-f]{40}", git.get("commit", "")):
        errors.append("commit doit être un SHA Git complet")
    for key in ("cleanAtStart", "cleanAtEnd"):
        if not isinstance(git.get(key), bool):
            errors.append(f"{key} doit être booléen")

    route_summary = receipt.get("routes")
    if not isinstance(route_summary, dict):
        errors.append("routes doit être un objet vérifiable")
    else:
        inventory = route_summary.get("inventory")
        count = route_summary.get("count")
        digest = route_summary.get("sha256")
        if not isinstance(inventory, list) or not inventory:
            errors.append("routes.inventory doit être une liste non vide")
        else:
            if count != len(inventory):
                errors.append("routes.count diverge de routes.inventory")
            expected_digest = hashlib.sha256(_canonical_routes(inventory)).hexdigest()
            if digest != expected_digest:
                errors.append("routes.sha256 ne correspond pas à l'inventaire")
            normalized = [
                (route.get("method"), route.get("path"))
                for route in inventory
                if isinstance(route, dict)
            ]
            if len(normalized) != len(inventory) or any(not method or not path for method, path in normalized):
                errors.append("chaque route doit fournir method et path")
            elif normalized != sorted(normalized) or len(normalized) != len(set(normalized)):
                errors.append("l'inventaire des routes doit être trié et sans doublon")

    tools = receipt.get("tools")
    if not isinstance(tools, dict) or not tools:
        errors.append("tools doit être un objet non vide")
    elif any(not isinstance(value, str) or not value.strip() for value in tools.values()):
        errors.append("chaque outil doit fournir une version détectée")
    elif receipt.get("mode") == "full":
        missing_tools = sorted(FULL_TOOLS - tools.keys())
        errors.extend(f"outil Full manquant: {tool}" for tool in missing_tools)
    checks = receipt.get("checks")
    if not isinstance(checks, list) or not checks:
        errors.append("checks doit être une liste non vide")
    else:
        for index, check in enumerate(checks):
            if not isinstance(check, dict) or not check.get("name") or check.get("status") not in {"passed", "failed", "not-applicable"}:
                errors.append(f"checks[{index}] invalide")
    if not isinstance(receipt.get("artifacts"), dict):
        errors.append("artifacts doit être un objet")
    if not isinstance(receipt.get("security"), dict):
        errors.append("security doit être un objet")

    lifecycle = receipt.get("lifecycle")
    if not isinstance(lifecycle, dict):
        errors.append("lifecycle doit être un objet")
    else:
        if lifecycle.get("palworldRestartForbidden") is not True:
            errors.append("lifecycle.palworldRestartForbidden doit être vrai")
        for key in ("agentContracts", "multiSeasonDatabase"):
            check = lifecycle.get(key)
            if not isinstance(check, dict) or check.get("status") not in {"passed", "not-applicable"}:
                errors.append(f"lifecycle.{key} est invalide")
        if receipt.get("mode") == "full" and isinstance(lifecycle.get("multiSeasonDatabase"), dict):
            if lifecycle["multiSeasonDatabase"].get("status") != "passed":
                errors.append("Full exige la validation PostgreSQL multi-saisons")

    if errors:
        raise ValueError("\n".join(errors))


def load_and_validate(path: Path) -> None:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError("la racine du reçu doit être un objet")
    validate_receipt(value)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("receipt", type=Path)
    args = parser.parse_args()
    try:
        load_and_validate(args.receipt)
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"Reçu local invalide: {error}")
        return 1
    print("Reçu local suite.local-validation.v2 valide.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
