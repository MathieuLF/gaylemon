import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(__file__).resolve().parents[1] / "deploy" / "gaylemon_deploy.py"
SPEC = importlib.util.spec_from_file_location("gaylemon_deploy", MODULE_PATH)
DEPLOY = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(DEPLOY)


class GaylemonDeployTests(unittest.TestCase):
    def test_destination_allowlist_accepts_only_managed_paths(self):
        accepted = (
            "/srv/storage/steam/bin/palworld-update.sh",
            "/home/gaylemon/Gaylemon/server/bin/palworld-save-snapshot.py",
            "/usr/local/sbin/gaylemon-deploy-install",
            "/usr/local/bin/gaylemon",
            "/etc/systemd/system/palworld-stats.timer",
            "/etc/systemd/system/gaylemon-agent.service",
            "/etc/systemd/system/cloudflare-update-dns.service",
            "/etc/sysctl.d/99-palworld-performance.conf",
            "/etc/sudoers.d/palworld-console",
            "/etc/sudoers.d/gaylemon-deploy",
        )
        rejected = (
            "/etc/passwd",
            "/etc/systemd/system/other.service",
            "/srv/storage/steam/bin/../servers/palworld/game",
            "/home/gaylemon/.ssh/authorized_keys",
        )

        for path in accepted:
            with self.subTest(path=path):
                self.assertTrue(DEPLOY.is_allowed_destination(path))
        for path in rejected:
            with self.subTest(path=path):
                self.assertFalse(DEPLOY.is_allowed_destination(path))

    def test_sysctl_validation_is_non_mutating(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            valid = Path(temporary_directory) / "valid.conf"
            valid.write_text("# comment\nvm.swappiness = 10\n", encoding="utf-8")
            DEPLOY.validate_sysctl(valid)

            invalid = Path(temporary_directory) / "invalid.conf"
            invalid.write_text("this is not an assignment\n", encoding="utf-8")
            with self.assertRaises(DEPLOY.DeployError):
                DEPLOY.validate_sysctl(invalid)

    def test_systemd_structure_requires_expected_sections(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            service = Path(temporary_directory) / "test.service"
            service.write_text(
                "[Unit]\nDescription=Test\n[Service]\nExecStart=/bin/true\n",
                encoding="utf-8",
            )
            DEPLOY.validate_systemd_structure(service)

            invalid = Path(temporary_directory) / "invalid.timer"
            invalid.write_text("[Unit]\nDescription=Invalid\n", encoding="utf-8")
            with self.assertRaises(DEPLOY.DeployError):
                DEPLOY.validate_systemd_structure(invalid)

    def test_systemd_verify_accepts_missing_binary_from_same_first_install(self):
        result = subprocess.CompletedProcess(
            args=[],
            returncode=1,
            stdout="",
            stderr=(
                "unit.service: Command /usr/local/bin/gaylemon is not executable: "
                "No such file or directory\n"
            ),
        )
        entries = [
            {
                "validation": "binary",
                "destinationPath": Path("/usr/local/bin/gaylemon"),
            }
        ]
        with mock.patch.object(DEPLOY.subprocess, "run", return_value=result):
            DEPLOY.validate_systemd_sources(["unit.service"], entries)

    def test_systemd_verify_rejects_missing_unmanaged_executable(self):
        result = subprocess.CompletedProcess(
            args=[],
            returncode=1,
            stdout="",
            stderr=(
                "unit.service: Command /usr/local/bin/inconnu is not executable: "
                "No such file or directory\n"
            ),
        )
        with mock.patch.object(DEPLOY.subprocess, "run", return_value=result):
            with self.assertRaises(DEPLOY.DeployError):
                DEPLOY.validate_systemd_sources(["unit.service"], [])


if __name__ == "__main__":
    unittest.main()
