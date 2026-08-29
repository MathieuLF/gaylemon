from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from test_local_validation_receipt import MODULE, valid_receipt


class FullSecurityReceiptTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.repository = Path(self.temporary.name)
        (self.repository / "config").mkdir()
        (self.repository / "config" / "full-security-policy-v1.json").write_text(
            json.dumps({
                "schema": "suite.full-security-policy.v1",
                "tools": {
                    "gitleaks": {"version": "8.30.1", "scope": "git-history:HEAD"},
                    "trivy": {"version": "0.74.0", "scope": "git-archive:HEAD", "scanners": ["vuln", "misconfig", "secret"], "severity": ["HIGH", "CRITICAL"]},
                    "syft": {"version": "1.51.0", "scope": "dir:git-archive:HEAD", "formats": ["spdx-json", "cyclonedx-json"]},
                },
                "requiredChecks": ["gitleaks", "trivy-filesystem", "sbom-spdx", "sbom-cyclonedx"],
            }),
            encoding="utf-8",
        )
        evidence = self.repository / "release" / "evidence"
        sbom = self.repository / "release" / "sbom"
        evidence.mkdir(parents=True)
        sbom.mkdir(parents=True)

        def write(path: Path, value: object) -> dict[str, object]:
            path.write_text(json.dumps(value), encoding="utf-8")
            data = path.read_bytes()
            return {"path": path.relative_to(self.repository).as_posix(), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}

        gitleaks = write(evidence / "gitleaks.json", [])
        trivy = write(evidence / "trivy-fs.json", {"Results": []})
        spdx = write(sbom / "source.spdx.json", {"spdxVersion": "SPDX-2.3"})
        cyclone = write(sbom / "source.cyclonedx.json", {"bomFormat": "CycloneDX"})
        controls = {
            "gitleaks": {"result": "passed", "scope": "git-history:HEAD", "verifier": {"name": "gitleaks", "command": "gitleaks git . --log-opts=HEAD", "exitCode": 0}, "report": gitleaks},
            "trivyFilesystem": {"result": "passed", "scope": "git-archive:HEAD", "scanners": ["vuln", "misconfig", "secret"], "severity": ["HIGH", "CRITICAL"], "verifier": {"name": "trivy", "command": "trivy fs git-archive:HEAD", "exitCode": 0}, "report": trivy},
            "sbom": {"result": "passed", "scope": "dir:git-archive:HEAD", "verifier": {"name": "syft", "command": "syft scan dir:git-archive:HEAD", "exitCode": 0}, "spdx": spdx, "cycloneDx": cyclone},
        }
        manifest = {
            "schema": "suite.full-security-evidence.v1", "application": "gaylemon",
            "profile": "seasonal-go-microsite", "source": {"kind": "git-archive", "commit": "a" * 40, "tree": "b" * 40},
            "tools": {"gitleaks": "8.30.1", "trivy": "0.74.0", "syft": "1.51.0"},
            "controls": controls, "result": "passed",
        }
        manifest_descriptor = write(evidence / "full-security.json", manifest)
        self.receipt = valid_receipt()
        self.receipt["checks"] = [{"name": name, "status": "passed"} for name in (
            "gitleaks", "trivy-filesystem", "sbom-spdx", "sbom-cyclonedx"
        )]
        self.receipt["tools"].update(manifest["tools"])
        self.receipt["artifacts"] = {"files": [gitleaks, trivy, spdx, cyclone, manifest_descriptor], "sbom": []}
        self.receipt["security"] = {**manifest, "evidence": manifest_descriptor}

    def tearDown(self) -> None:
        self.temporary.cleanup()

    @staticmethod
    def fake_git(_repository: Path, *arguments: str) -> str:
        return "b" * 40 if arguments[:2] == ("rev-parse", "HEAD^{tree}") else "a" * 40

    def validate(self) -> list[str]:
        errors: list[str] = []
        with mock.patch.object(MODULE.SUITE_SECURITY, "git", side_effect=self.fake_git):
            MODULE.SUITE_SECURITY.validate_full_security(self.repository, self.receipt, errors)
        return errors

    def test_accepts_bound_security_artifacts(self) -> None:
        self.assertEqual([], self.validate())

    def test_rejects_omitted_required_gate(self) -> None:
        self.receipt["checks"].pop()
        self.assertTrue(any("contrôles Full sécurité omis" in error for error in self.validate()))

    def test_rejects_self_declared_tool_version(self) -> None:
        self.receipt["tools"]["trivy"] = "999.0.0"
        self.assertTrue(any("version de sécurité verrouillée" in error for error in self.validate()))

    def test_rejects_unbounded_gitleaks_history(self) -> None:
        self.receipt["security"]["controls"]["gitleaks"]["verifier"]["command"] = "gitleaks git ."
        self.assertTrue(any("vérificateur Gitleaks invalide" in error for error in self.validate()))


if __name__ == "__main__":
    unittest.main()
