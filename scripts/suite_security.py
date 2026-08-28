#!/usr/bin/env python3
"""Validate Full security evidence bound to an exact Git source tree."""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any


POLICY_PATH = "config/full-security-policy-v1.json"


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def git(repository: Path, *arguments: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(repository), *arguments], text=True, encoding="utf-8"
    ).strip()


def artifact(
    repository: Path,
    value: Any,
    label: str,
    declared: list[Any],
    errors: list[str],
) -> Path | None:
    if not isinstance(value, dict) or set(value) != {"path", "bytes", "sha256"}:
        errors.append(f"{label}: path/bytes/sha256 exacts requis")
        return None
    relative = value.get("path")
    if not isinstance(relative, str) or not relative:
        errors.append(f"{label}.path invalide")
        return None
    candidate = (repository / relative).resolve()
    try:
        candidate.relative_to(repository)
    except ValueError:
        errors.append(f"{label}: chemin hors dépôt")
        return None
    if not candidate.is_file():
        errors.append(f"{label}: artefact absent: {relative}")
        return None
    data = candidate.read_bytes()
    if value.get("bytes") != len(data):
        errors.append(f"{label}: taille différente")
    if value.get("sha256") != hashlib.sha256(data).hexdigest():
        errors.append(f"{label}: empreinte différente")
    if value not in declared:
        errors.append(f"{label}: artefact absent de artifacts.files")
    return candidate


def report_has_findings(report: dict[str, Any]) -> bool:
    for result in report.get("Results") or []:
        for key in ("Vulnerabilities", "Misconfigurations", "Secrets"):
            for finding in result.get(key) or []:
                severity = str(finding.get("Severity", "")).upper()
                status = str(finding.get("Status", "FAIL")).upper()
                if severity in {"HIGH", "CRITICAL"} and status not in {"PASS", "PASSED"}:
                    return True
    return False


def validate_full_security(repository: Path, receipt: dict[str, Any], errors: list[str]) -> None:
    if receipt.get("mode") != "full":
        return
    try:
        policy = load_json(repository / POLICY_PATH)
    except (OSError, json.JSONDecodeError) as error:
        errors.append(f"politique Full sécurité illisible: {error}")
        return
    if policy.get("schema") != "suite.full-security-policy.v1":
        errors.append("schéma de politique Full sécurité invalide")
        return

    checks = receipt.get("checks")
    passed_checks = {
        item.get("name")
        for item in checks or []
        if isinstance(item, dict) and item.get("status") == "passed"
    }
    required_checks = policy.get("requiredChecks")
    if not isinstance(required_checks, list):
        errors.append("requiredChecks de sécurité invalide")
        required_checks = []
    missing_checks = sorted(set(required_checks) - passed_checks)
    if missing_checks:
        errors.append(f"contrôles Full sécurité omis: {', '.join(missing_checks)}")

    security = receipt.get("security")
    security_keys = {
        "schema", "application", "profile", "source", "tools", "controls", "evidence", "result"
    }
    if not isinstance(security, dict) or set(security) != security_keys:
        errors.append("security Full doit avoir les clés exactes du contrat")
        return
    expected_top = {
        "schema": "suite.full-security-evidence.v1",
        "application": receipt.get("application"),
        "profile": receipt.get("profile"),
        "result": "passed",
    }
    for key, expected in expected_top.items():
        if security.get(key) != expected:
            errors.append(f"security.{key}: valeur inattendue")

    head = git(repository, "rev-parse", "HEAD")
    tree = git(repository, "rev-parse", "HEAD^{tree}")
    if security.get("source") != {"kind": "git-archive", "commit": head, "tree": tree}:
        errors.append("security.source n'est pas lié au commit/arbre courant")

    policy_tools = policy.get("tools")
    expected_versions = {
        name: value.get("version")
        for name, value in (policy_tools or {}).items()
        if isinstance(value, dict)
    }
    if security.get("tools") != expected_versions:
        errors.append("security.tools ne correspond pas aux versions verrouillées")
    receipt_tools = receipt.get("tools")
    if not isinstance(receipt_tools, dict) or any(
        receipt_tools.get(name) != version for name, version in expected_versions.items()
    ):
        errors.append("tools omet une version de sécurité verrouillée")

    declared = []
    artifacts = receipt.get("artifacts")
    if isinstance(artifacts, dict) and isinstance(artifacts.get("files"), list):
        declared = artifacts["files"]
    controls = security.get("controls")
    if not isinstance(controls, dict) or set(controls) != {"gitleaks", "trivyFilesystem", "sbom"}:
        errors.append("security.controls incomplet")
        return

    gitleaks = controls.get("gitleaks")
    if not isinstance(gitleaks, dict) or set(gitleaks) != {"result", "scope", "verifier", "report"}:
        errors.append("contrôle Gitleaks invalide")
    else:
        expected = policy_tools["gitleaks"]
        if gitleaks.get("result") != "passed" or gitleaks.get("scope") != expected.get("scope"):
            errors.append("contrôle Gitleaks non réussi ou portée différente")
        if gitleaks.get("verifier") != {"name": "gitleaks", "command": "gitleaks git .", "exitCode": 0}:
            errors.append("vérificateur Gitleaks invalide")
        path = artifact(repository, gitleaks.get("report"), "security.gitleaks.report", declared, errors)
        if path:
            try:
                findings = load_json(path)
                if not isinstance(findings, list) or findings:
                    errors.append("rapport Gitleaks non vide ou invalide")
            except (OSError, json.JSONDecodeError):
                errors.append("rapport Gitleaks illisible")

    trivy = controls.get("trivyFilesystem")
    trivy_keys = {"result", "scope", "scanners", "severity", "verifier", "report"}
    if not isinstance(trivy, dict) or set(trivy) != trivy_keys:
        errors.append("contrôle Trivy filesystem invalide")
    else:
        expected = policy_tools["trivy"]
        if (
            trivy.get("result") != "passed"
            or trivy.get("scope") != expected.get("scope")
            or trivy.get("scanners") != expected.get("scanners")
            or trivy.get("severity") != expected.get("severity")
        ):
            errors.append("contrôle Trivy non conforme à la politique")
        if trivy.get("verifier") != {"name": "trivy", "command": "trivy fs git-archive:HEAD", "exitCode": 0}:
            errors.append("vérificateur Trivy invalide")
        path = artifact(repository, trivy.get("report"), "security.trivyFilesystem.report", declared, errors)
        if path:
            try:
                report = load_json(path)
                if not isinstance(report, dict) or report_has_findings(report):
                    errors.append("rapport Trivy contient un échec HIGH/CRITICAL")
            except (OSError, json.JSONDecodeError):
                errors.append("rapport Trivy illisible")

    sbom = controls.get("sbom")
    if not isinstance(sbom, dict) or set(sbom) != {"result", "scope", "verifier", "spdx", "cycloneDx"}:
        errors.append("contrôle SBOM invalide")
    else:
        expected = policy_tools["syft"]
        if sbom.get("result") != "passed" or sbom.get("scope") != expected.get("scope"):
            errors.append("contrôle SBOM non conforme à la politique")
        if sbom.get("verifier") != {"name": "syft", "command": "syft scan dir:git-archive:HEAD", "exitCode": 0}:
            errors.append("vérificateur Syft invalide")
        spdx_path = artifact(repository, sbom.get("spdx"), "security.sbom.spdx", declared, errors)
        cdx_path = artifact(repository, sbom.get("cycloneDx"), "security.sbom.cycloneDx", declared, errors)
        if spdx_path:
            try:
                spdx = load_json(spdx_path)
                if not isinstance(spdx, dict) or spdx.get("spdxVersion") != "SPDX-2.3":
                    errors.append("SBOM SPDX 2.3 invalide")
            except (OSError, json.JSONDecodeError):
                errors.append("SBOM SPDX illisible")
        if cdx_path:
            try:
                cdx = load_json(cdx_path)
                if not isinstance(cdx, dict) or cdx.get("bomFormat") != "CycloneDX":
                    errors.append("SBOM CycloneDX invalide")
            except (OSError, json.JSONDecodeError):
                errors.append("SBOM CycloneDX illisible")

    evidence_path = artifact(repository, security.get("evidence"), "security.evidence", declared, errors)
    if evidence_path:
        try:
            manifest = load_json(evidence_path)
            expected_manifest = {key: value for key, value in security.items() if key != "evidence"}
            if manifest != expected_manifest:
                errors.append("manifeste Full sécurité différent du reçu")
        except (OSError, json.JSONDecodeError):
            errors.append("manifeste Full sécurité illisible")

