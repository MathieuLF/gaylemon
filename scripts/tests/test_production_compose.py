import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("compose_contract", ROOT / "scripts/check_production_compose.py")
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ProductionManifest(unittest.TestCase):
    def test_versioned_contract(self):
        MODULE.validate(ROOT / "compose.production.yaml")

    def test_inline_secret_is_rejected_without_disclosure(self):
        source = (ROOT / "compose.production.yaml").read_text()
        import re
        source = re.sub(r"(GAYLEMON_GITHUB_CLIENT_SECRET:)\s*[^\n]+", r"\1 synthetic-secret", source)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "compose.yaml"
            path.write_text(source)
            with self.assertRaises(ValueError) as failure:
                MODULE.validate(path)
            self.assertNotIn("synthetic-secret", str(failure.exception))

    def test_public_port_is_rejected(self):
        source = (ROOT / "compose.production.yaml").read_text().replace("127.0.0.1:", "0.0.0.0:")
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "compose.yaml"
            path.write_text(source)
            with self.assertRaises(ValueError):
                MODULE.validate(path)
