from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("project", Path(__file__).parents[1] / "project.py")
assert SPEC and SPEC.loader
PROJECT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PROJECT)


class DevelopmentChecks(unittest.TestCase):
    def test_child_failure_stops_check(self):
        failure = subprocess.CalledProcessError(9, ["go", "test"])
        with patch.object(PROJECT, "prerequisites"), patch.object(PROJECT, "run", side_effect=failure) as command:
            with self.assertRaises(subprocess.CalledProcessError):
                PROJECT.check_dev()
            self.assertEqual(command.call_count, 1)

    def test_same_git_status_does_not_hide_changed_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.go"
            source.write_text("before")
            def git(*args, **kwargs):
                return "source.go" if "ls-files" in args else " M source.go"
            with patch.object(PROJECT, "ROOT", root), patch.object(PROJECT, "run", side_effect=git):
                before = PROJECT.snapshot()
                source.write_text("after")
                self.assertNotEqual(before, PROJECT.snapshot())
                self.assertEqual(before["git-status"], PROJECT.snapshot()["git-status"])

    def test_failed_integration_still_removes_created_container(self):
        calls = []
        def command(*args, **kwargs):
            calls.append(args)
            if args[:2] == ("docker", "run"):
                return "a" * 64
            if args[:2] == ("docker", "port"):
                return "127.0.0.1:54321"
            return ""
        with patch.object(PROJECT, "run", side_effect=command), patch.object(PROJECT, "wait_postgres"):
            with self.assertRaisesRegex(RuntimeError, "integration"):
                with PROJECT.postgres("docker"):
                    raise RuntimeError("integration failed")
        self.assertEqual(calls[-1], ("docker", "rm", "--force", "a" * 64))


if __name__ == "__main__":
    unittest.main()
