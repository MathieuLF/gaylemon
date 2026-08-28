from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "check_local_validation_receipt.py"
SPEC = importlib.util.spec_from_file_location("check_local_validation_receipt", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def valid_receipt() -> dict[str, object]:
    routes = [
        {"method": "GET", "path": "/"},
        {"method": "POST", "path": "/ops/api/seasons"},
    ]
    digest = hashlib.sha256(
        json.dumps(routes, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    return {
        "schema": "suite.local-validation.v2",
        "contract": "suite-foundation-v2",
        "contractRevision": "2.2.0",
        "profile": "seasonal-go-microsite",
        "application": "gaylemon",
        "version": "1.0.0",
        "result": "passed",
        "mode": "full",
        "startedAt": "2026-08-28T12:00:00+00:00",
        "completedAt": "2026-08-28T12:01:00+00:00",
        "git": {
            "commit": "a" * 40,
            "branch": "feat/test",
            "upstream": "origin/feat/test",
            "ahead": 0,
            "behind": 0,
            "cleanAtStart": True,
            "cleanAtEnd": True,
        },
        "routes": {"count": len(routes), "sha256": digest, "inventory": routes},
        "tools": {
            "go": "go1.27.0",
            "node": "v24.19.0",
            "powershell": "7.6.4",
            "python": "Python 3.14.7",
            "git": "git version 2.55.0.windows.3",
            "npm": "12.0.2",
            "docker": "29.7.2",
            "playwright": "1.62.1",
            "axe": "4.13.0",
            "deadcode": "v0.49.0",
            "govulncheck": "v1.7.0",
            "gitleaks": "8.30.1",
            "syft": "1.51.0",
            "trivy": "0.74.0",
            "cosign": "3.1.3",
            "bash": "5.2.37(1)-release",
        },
        "checks": [{"name": "go-test", "status": "passed"}],
        "artifacts": {
            "files": ["gaylemon-local:1.0.0"],
            "sbom": ["release/gaylemon-1.0.0.spdx.json"],
        },
        "security": {
            "sbom": {"status": "passed"},
            "vulnerabilityScan": {"status": "passed", "tool": "trivy"},
            "signature": {"status": "passed", "tool": "cosign"},
        },
        "lifecycle": {
            "palworldRestartForbidden": True,
            "agentContracts": {"status": "passed"},
            "multiSeasonDatabase": {"status": "passed"},
        },
    }


class LocalValidationReceiptTests(unittest.TestCase):
    def test_accepts_verifiable_v2_receipt(self) -> None:
        MODULE.validate_receipt(valid_receipt())

    def test_rejects_route_hash_mismatch(self) -> None:
        receipt = valid_receipt()
        receipt["routes"]["sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "routes.sha256"):
            MODULE.validate_receipt(receipt)

    def test_rejects_missing_end_cleanliness(self) -> None:
        receipt = valid_receipt()
        del receipt["git"]["cleanAtEnd"]
        with self.assertRaisesRegex(ValueError, "cleanAtEnd"):
            MODULE.validate_receipt(receipt)

    def test_rejects_obsolete_contract_name(self) -> None:
        receipt = copy.deepcopy(valid_receipt())
        receipt["suiteContract"] = receipt.pop("contract")
        with self.assertRaisesRegex(ValueError, "contract"):
            MODULE.validate_receipt(receipt)

    def test_rejects_incomplete_full_tool_inventory(self) -> None:
        receipt = valid_receipt()
        del receipt["tools"]["cosign"]
        with self.assertRaisesRegex(ValueError, "outil Full manquant: cosign"):
            MODULE.validate_receipt(receipt)

    def test_rejects_full_without_multi_season_database_proof(self) -> None:
        receipt = valid_receipt()
        receipt["lifecycle"]["multiSeasonDatabase"] = {
            "status": "not-applicable",
            "reason": "absent",
        }
        with self.assertRaisesRegex(ValueError, "Full exige"):
            MODULE.validate_receipt(receipt)

    def test_rejects_missing_palworld_restart_invariant(self) -> None:
        receipt = valid_receipt()
        receipt["lifecycle"]["palworldRestartForbidden"] = False
        with self.assertRaisesRegex(ValueError, "palworldRestartForbidden"):
            MODULE.validate_receipt(receipt)


if __name__ == "__main__":
    unittest.main()
