#!/usr/bin/env python3
"""Fail-closed validation for Gaylémon release attestation envelopes."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any


SHA256 = re.compile(r"^[0-9a-f]{64}$")
EXPECTED_RELEASE_PREDICATE = "urn:gaylemon:attestation:release-manifest:v1"
STATIC_REQUIRED_PREDICATES = {
    "https://spdx.dev/Document",
    "cyclonedx",
}
ENVELOPE_KEYS = {
    "schema", "predicateType", "application", "version", "commit",
    "artifactDigest", "result", "verifier",
}


def load(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise ValueError(f"{path}: objet JSON attendu")
    return value


def validate(repository: Path, receipt_path: Path) -> dict[str, Any]:
    repository = repository.resolve()
    receipt = load(receipt_path)
    profile = load(repository / "config" / "suite-profile-v2.json")
    release = profile.get("release")
    release_predicate = release.get("releasePredicate") if isinstance(release, dict) else None
    if not isinstance(release_predicate, str) or not release_predicate.strip():
        raise ValueError("profil local: release.releasePredicate requis pour signed-oci")
    if release_predicate != EXPECTED_RELEASE_PREDICATE:
        raise ValueError("profil local: release.releasePredicate diffère du registre central")
    required_predicates = STATIC_REQUIRED_PREDICATES | {release_predicate}
    binding = {
        "application": receipt.get("application"),
        "version": receipt.get("version"),
        "commit": receipt.get("commit"),
        "artifactDigest": receipt.get("artifactDigest"),
    }
    attestations = receipt.get("attestations")
    if not isinstance(attestations, list) or not attestations:
        raise ValueError("attestations: liste non vide requise")
    predicates: set[str] = set()
    for index, descriptor in enumerate(attestations):
        label = f"attestations[{index}]"
        if not isinstance(descriptor, dict) or set(descriptor) != {"path", "sha256"}:
            raise ValueError(f"{label}: descripteur path/sha256 exact requis")
        relative = descriptor.get("path")
        digest = descriptor.get("sha256")
        if not isinstance(relative, str) or not relative:
            raise ValueError(f"{label}.path: chemin requis")
        path = (repository / relative).resolve()
        try:
            path.relative_to(repository)
        except ValueError as error:
            raise ValueError(f"{label}.path: hors dépôt") from error
        if not path.is_file():
            raise ValueError(f"{label}: preuve absente")
        if not isinstance(digest, str) or not SHA256.fullmatch(digest):
            raise ValueError(f"{label}.sha256: empreinte invalide")
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError(f"{label}: empreinte différente")
        envelope = load(path)
        if set(envelope) != ENVELOPE_KEYS:
            raise ValueError(f"{label}: clés exactes de l’enveloppe requises")
        expected = {
            "schema": "suite.attestation-evidence.v1",
            **binding,
            "result": "passed",
        }
        for key, value in expected.items():
            if envelope.get(key) != value:
                raise ValueError(f"{label}.{key}: binding différent")
        verifier = envelope.get("verifier")
        if not isinstance(verifier, dict) or set(verifier) != {"name", "command", "exitCode"}:
            raise ValueError(f"{label}.verifier: clés exactes requises")
        if verifier.get("exitCode") != 0 or not all(
            isinstance(verifier.get(key), str) and verifier[key].strip()
            for key in ("name", "command")
        ):
            raise ValueError(f"{label}.verifier: vérification réussie requise")
        predicate = envelope.get("predicateType")
        if not isinstance(predicate, str) or not predicate:
            raise ValueError(f"{label}.predicateType: requis")
        predicates.add(predicate)
    missing = required_predicates - predicates
    if missing:
        raise ValueError(f"predicates attestés absents: {sorted(missing)}")
    return {"application": binding["application"], "predicates": sorted(predicates), "result": "passed"}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", type=Path, required=True)
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(validate(args.repository, args.receipt), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
