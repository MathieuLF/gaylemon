#!/usr/bin/env python3
"""Run pinned Gitleaks, Trivy FS and Syft gates against the exact Git HEAD."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import tarfile
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def load(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise ValueError(f"{path}: objet JSON attendu")
    return value


def load_any(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def run(arguments: list[str], cwd: Path, environment: dict[str, str] | None = None) -> str:
    completed = subprocess.run(
        arguments,
        cwd=cwd,
        env=environment,
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
    )
    if completed.returncode != 0:
        detail = "\n".join(part.strip() for part in (completed.stdout, completed.stderr) if part.strip())
        raise RuntimeError(f"{' '.join(arguments)} a échoué ({completed.returncode})\n{detail}")
    return completed.stdout.strip()


def descriptor(path: Path, repository: Path) -> dict[str, Any]:
    data = path.read_bytes()
    return {
        "path": path.relative_to(repository).as_posix(),
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
    }


def canonical_write(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
        newline="\n",
    )


def normalize_reports(
    gitleaks_path: Path,
    trivy_path: Path,
    spdx_path: Path,
    cdx_path: Path,
    application: str,
    commit: str,
    source_time: str,
) -> None:
    gitleaks = load_any(gitleaks_path)
    if not isinstance(gitleaks, list) or gitleaks:
        raise ValueError("Gitleaks doit produire une liste vide")
    canonical_write(gitleaks_path, gitleaks)

    trivy = load(trivy_path)
    trivy["ArtifactName"] = "git-archive:HEAD"
    trivy["ReportID"] = str(uuid.uuid5(uuid.NAMESPACE_URL, application + ":" + commit + ":trivy"))
    if "CreatedAt" in trivy:
        trivy["CreatedAt"] = source_time
    canonical_write(trivy_path, trivy)

    spdx = load(spdx_path)
    if spdx.get("spdxVersion") != "SPDX-2.3":
        raise ValueError("Syft n'a pas produit SPDX 2.3")
    spdx["documentNamespace"] = f"https://nethercore.dev/sbom/{application}/{commit}/spdx"
    if isinstance(spdx.get("creationInfo"), dict):
        spdx["creationInfo"]["created"] = source_time
    canonical_write(spdx_path, spdx)

    cdx = load(cdx_path)
    if cdx.get("bomFormat") != "CycloneDX":
        raise ValueError("Syft n'a pas produit CycloneDX")
    cdx["serialNumber"] = f"urn:uuid:{uuid.uuid5(uuid.NAMESPACE_URL, application + ':' + commit)}"
    if isinstance(cdx.get("metadata"), dict):
        cdx["metadata"]["timestamp"] = source_time
        if isinstance(cdx["metadata"].get("component"), dict):
            cdx["metadata"]["component"]["bom-ref"] = hashlib.sha256(
                f"{application}:{commit}:source".encode()
            ).hexdigest()[:16]
    canonical_write(cdx_path, cdx)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", type=Path, default=Path.cwd())
    args = parser.parse_args()
    repository = args.repository.resolve()
    policy = load(repository / "config" / "full-security-policy-v1.json")
    profile = load(repository / "config" / "suite-profile-v2.json")
    tools = policy["tools"]

    gitleaks_version = run(["gitleaks", "version"], repository).splitlines()[-1].strip()
    trivy_output = run(["trivy", "--version"], repository)
    syft_output = run(["syft", "version"], repository)
    trivy_match = re.search(r"^Version:\s*(\S+)", trivy_output, re.MULTILINE)
    syft_match = re.search(r"^Version:\s*(\S+)", syft_output, re.MULTILINE)
    actual_versions = {
        "gitleaks": gitleaks_version.removeprefix("v"),
        "trivy": trivy_match.group(1).removeprefix("v") if trivy_match else "",
        "syft": syft_match.group(1).removeprefix("v") if syft_match else "",
    }
    expected_versions = {name: value["version"] for name, value in tools.items()}
    if actual_versions != expected_versions:
        raise RuntimeError(f"versions sécurité différentes: {actual_versions!r} != {expected_versions!r}")

    commit = run(["git", "rev-parse", "HEAD"], repository)
    tree = run(["git", "rev-parse", "HEAD^{tree}"], repository)
    commit_epoch = int(run(["git", "show", "-s", "--format=%ct", "HEAD"], repository))
    source_time = datetime.fromtimestamp(commit_epoch, tz=timezone.utc).isoformat().replace("+00:00", "Z")
    application = profile["application"]

    evidence_directory = repository / "release" / "evidence"
    sbom_directory = repository / "release" / "sbom"
    evidence_directory.mkdir(parents=True, exist_ok=True)
    sbom_directory.mkdir(parents=True, exist_ok=True)
    final_paths = {
        "gitleaks": evidence_directory / "gitleaks.json",
        "trivy": evidence_directory / "trivy-fs.json",
        "spdx": sbom_directory / "source.spdx.json",
        "cycloneDx": sbom_directory / "source.cyclonedx.json",
    }

    with tempfile.TemporaryDirectory(prefix=f"{application}-security-") as temporary:
        temporary_root = Path(temporary)
        archive = temporary_root / "source.tar"
        source = temporary_root / "source"
        source.mkdir()
        run(["git", "archive", "--format=tar", f"--output={archive}", "HEAD"], repository)
        with tarfile.open(archive) as source_tar:
            source_tar.extractall(source, filter="data")

        temporary_paths = {
            "gitleaks": temporary_root / "gitleaks.json",
            "trivy": temporary_root / "trivy-fs.json",
            "spdx": temporary_root / "source.spdx.json",
            "cycloneDx": temporary_root / "source.cyclonedx.json",
        }
        run(
            [
                "gitleaks", "git", ".", "--no-banner", "--no-color", "--redact",
                "--report-format", "json", "--report-path", str(temporary_paths["gitleaks"]),
            ],
            repository,
        )
        trivy_policy = tools["trivy"]
        run(
            [
                "trivy", "fs", "--scanners", ",".join(trivy_policy["scanners"]),
                "--severity", ",".join(trivy_policy["severity"]), "--exit-code", "1",
                "--format", "json", "--output", str(temporary_paths["trivy"]), str(source),
            ],
            repository,
        )
        syft_environment = os.environ.copy()
        syft_environment["SOURCE_DATE_EPOCH"] = str(commit_epoch)
        run(
            [
                "syft", "scan", f"dir:{source}", "--source-name", application,
                "--source-version", commit,
                "--output", f"spdx-json={temporary_paths['spdx']}",
                "--output", f"cyclonedx-json={temporary_paths['cycloneDx']}", "--quiet",
            ],
            repository,
            syft_environment,
        )
        normalize_reports(
            temporary_paths["gitleaks"], temporary_paths["trivy"],
            temporary_paths["spdx"], temporary_paths["cycloneDx"],
            application, commit, source_time,
        )
        for name, temporary_path in temporary_paths.items():
            shutil.copyfile(temporary_path, final_paths[name])

    controls = {
        "gitleaks": {
            "result": "passed",
            "scope": tools["gitleaks"]["scope"],
            "verifier": {"name": "gitleaks", "command": "gitleaks git .", "exitCode": 0},
            "report": descriptor(final_paths["gitleaks"], repository),
        },
        "trivyFilesystem": {
            "result": "passed",
            "scope": tools["trivy"]["scope"],
            "scanners": tools["trivy"]["scanners"],
            "severity": tools["trivy"]["severity"],
            "verifier": {"name": "trivy", "command": "trivy fs git-archive:HEAD", "exitCode": 0},
            "report": descriptor(final_paths["trivy"], repository),
        },
        "sbom": {
            "result": "passed",
            "scope": tools["syft"]["scope"],
            "verifier": {"name": "syft", "command": "syft scan dir:git-archive:HEAD", "exitCode": 0},
            "spdx": descriptor(final_paths["spdx"], repository),
            "cycloneDx": descriptor(final_paths["cycloneDx"], repository),
        },
    }
    manifest = {
        "schema": "suite.full-security-evidence.v1",
        "application": application,
        "profile": profile["profile"],
        "source": {"kind": "git-archive", "commit": commit, "tree": tree},
        "tools": actual_versions,
        "controls": controls,
        "result": "passed",
    }
    manifest_path = evidence_directory / "full-security.json"
    canonical_write(manifest_path, manifest)
    receipt_security = {**manifest, "evidence": descriptor(manifest_path, repository)}
    print(json.dumps(receipt_security, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
