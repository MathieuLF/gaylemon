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
    "profile",
    "application",
    "result",
    "mode",
    "commit",
    "branch",
    "cleanAtStart",
    "cleanAtEnd",
    "routes",
    "tools",
    "checks",
    "artifacts",
    "sbom",
    "scan",
    "signature",
    "validatedAt",
}


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
        "result": "success",
    }
    for key, value in expected.items():
        if receipt.get(key) != value:
            errors.append(f"{key}: attendu {value!r}")

    if "suiteContract" in receipt:
        errors.append("suiteContract est obsolète; utiliser contract")
    if receipt.get("mode") not in {"quick", "full"}:
        errors.append("mode doit être quick ou full")
    if not isinstance(receipt.get("commit"), str) or not re.fullmatch(r"[0-9a-f]{40}", receipt["commit"]):
        errors.append("commit doit être un SHA Git complet")
    for key in ("cleanAtStart", "cleanAtEnd"):
        if not isinstance(receipt.get(key), bool):
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

    if not isinstance(receipt.get("tools"), dict) or not receipt.get("tools"):
        errors.append("tools doit être un objet non vide")
    if not isinstance(receipt.get("checks"), list) or not receipt.get("checks"):
        errors.append("checks doit être une liste non vide")
    if not isinstance(receipt.get("artifacts"), list):
        errors.append("artifacts doit être une liste")
    if not isinstance(receipt.get("sbom"), list):
        errors.append("sbom doit être une liste")

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
