from __future__ import annotations

import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "validate_release_evidence", ROOT / "scripts" / "validate-release-evidence.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class ReleaseEvidenceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.repository = Path(self.temporary.name)
        (self.repository / "release").mkdir()
        self.binding = {
            "application": "gaylemon",
            "version": "1.2.3",
            "commit": "a" * 40,
            "artifactDigest": "sha256:" + "b" * 64,
        }

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def envelope(self, name: str, predicate: str) -> dict[str, str]:
        relative = f"release/{name}.json"
        path = self.repository / relative
        path.write_text(
            json.dumps({
                "schema": "suite.attestation-evidence.v1",
                "predicateType": predicate,
                **self.binding,
                "result": "passed",
                "verifier": {"name": "Cosign", "command": "cosign verify", "exitCode": 0},
            }),
            encoding="utf-8",
        )
        return {"path": relative, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}

    def receipt(self, predicates: list[str]) -> Path:
        attestations = [self.envelope(f"attestation-{index}", predicate) for index, predicate in enumerate(predicates)]
        receipt = {**self.binding, "attestations": attestations}
        path = self.repository / "release" / "release.json"
        path.write_text(json.dumps(receipt), encoding="utf-8")
        return path

    def test_accepts_deep_roundtrip_with_three_bound_attestations(self) -> None:
        path = self.receipt(sorted(MODULE.REQUIRED_PREDICATES))
        result = MODULE.validate(self.repository, path)
        self.assertEqual(sorted(MODULE.REQUIRED_PREDICATES), result["predicates"])
        roundtrip = json.loads(path.read_text(encoding="utf-8"))
        self.assertIsInstance(roundtrip["attestations"], list)
        self.assertTrue(all(isinstance(item, dict) for item in roundtrip["attestations"]))

    def test_rejects_missing_spdx_predicate(self) -> None:
        predicates = MODULE.REQUIRED_PREDICATES - {"https://spdx.dev/Document"}
        with self.assertRaisesRegex(ValueError, "spdx.dev"):
            MODULE.validate(self.repository, self.receipt(sorted(predicates)))

    def test_rejects_wrong_spdx_predicate_type(self) -> None:
        predicates = (MODULE.REQUIRED_PREDICATES - {"https://spdx.dev/Document"}) | {"release-manifest"}
        with self.assertRaisesRegex(ValueError, "spdx.dev"):
            MODULE.validate(self.repository, self.receipt(sorted(predicates)))

    def test_rejects_stringified_attestation_descriptor(self) -> None:
        path = self.receipt(sorted(MODULE.REQUIRED_PREDICATES))
        receipt = json.loads(path.read_text(encoding="utf-8"))
        receipt["attestations"][1] = "@{path=release/proof.json; sha256=deadbeef}"
        path.write_text(json.dumps(receipt), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "descripteur"):
            MODULE.validate(self.repository, path)


if __name__ == "__main__":
    unittest.main()
