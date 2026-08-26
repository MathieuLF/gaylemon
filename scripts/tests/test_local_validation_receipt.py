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
        "profile": "seasonal-go-microsite",
        "application": "gaylemon",
        "result": "success",
        "mode": "full",
        "commit": "a" * 40,
        "branch": "feat/test",
        "cleanAtStart": True,
        "cleanAtEnd": True,
        "routes": {"count": len(routes), "sha256": digest, "inventory": routes},
        "tools": {"go": "go1.27.0"},
        "checks": [{"name": "go-test", "result": "success"}],
        "artifacts": ["gaylemon-local:2026.08.26.1"],
        "sbom": ["release/gaylemon-2026.08.26.1.spdx.json"],
        "scan": {"tool": "trivy", "result": "success"},
        "signature": {"tool": "cosign", "verified": True},
        "validatedAt": "2026-08-26T12:00:00+00:00",
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
        del receipt["cleanAtEnd"]
        with self.assertRaisesRegex(ValueError, "cleanAtEnd"):
            MODULE.validate_receipt(receipt)

    def test_rejects_obsolete_contract_name(self) -> None:
        receipt = copy.deepcopy(valid_receipt())
        receipt["suiteContract"] = receipt.pop("contract")
        with self.assertRaisesRegex(ValueError, "contract"):
            MODULE.validate_receipt(receipt)


if __name__ == "__main__":
    unittest.main()
