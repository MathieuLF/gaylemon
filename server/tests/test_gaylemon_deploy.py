import importlib.util
import hashlib
import json
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
    def write_test_stage(self, root: Path) -> tuple[Path, Path]:
        stage = root / "20260810-180000"
        source = stage / "server" / "bin" / "test.sh"
        source.parent.mkdir(parents=True)
        source.write_text("#!/usr/bin/env bash\ntrue\n", encoding="utf-8")
        manifest = {
            "version": 1,
            "backupRoot": "/var/backups/gaylemon-deploy",
            "entries": [
                {
                    "source": "server/bin/test.sh",
                    "sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                    "destination": "/srv/storage/steam/bin/test.sh",
                    "owner": "root",
                    "group": "root",
                    "mode": "0755",
                    "validation": "bash",
                    "restartUnit": None,
                    "restartPolicy": "none",
                }
            ],
            "removals": [],
        }
        manifest_path = stage / "server" / "deployment-manifest.resolved.json"
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        return stage, manifest_path

    def test_manifest_and_each_source_are_digest_bound(self):
        identity = type("Identity", (), {"pw_uid": 0, "gr_gid": 0})()
        with tempfile.TemporaryDirectory() as temporary_directory:
            stage, manifest_path = self.write_test_stage(Path(temporary_directory))
            manifest_digest = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
            DEPLOY.verify_manifest_digest(stage, manifest_digest)
            fake_pwd = mock.Mock(getpwnam=mock.Mock(return_value=identity))
            fake_grp = mock.Mock(getgrnam=mock.Mock(return_value=identity))
            with mock.patch.object(DEPLOY, "pwd", fake_pwd), mock.patch.object(DEPLOY, "grp", fake_grp):
                _, entries, _ = DEPLOY.load_manifest(stage)
                self.assertEqual(len(entries), 1)

                (stage / "server" / "bin" / "test.sh").write_text("tampered\n", encoding="utf-8")
                with self.assertRaises(DEPLOY.DeployError):
                    DEPLOY.load_manifest(stage)

            manifest_path.write_text("{}", encoding="utf-8")
            with self.assertRaises(DEPLOY.DeployError):
                DEPLOY.verify_manifest_digest(stage, manifest_digest)

    def test_event_timer_keeps_a_five_minute_start_cadence(self):
        timer = (MODULE_PATH.parents[1] / "systemd" / "palworld-events.timer").read_text(
            encoding="utf-8"
        )

        self.assertIn("OnBootSec=5min", timer)
        self.assertIn("OnUnitActiveSec=5min", timer)
        self.assertIn("AccuracySec=10s", timer)
        self.assertNotIn("OnUnitInactiveSec", timer)

    def test_destination_allowlist_accepts_only_managed_paths(self):
        accepted = (
            "/srv/storage/steam/bin/palworld-update.sh",
            "/home/gaylemon/Gaylemon/server/bin/palworld-save-snapshot.py",
            "/usr/local/sbin/gaylemon-deploy-install",
            "/usr/local/libexec/gaylemon/gaylemon-deploy",
            "/usr/local/bin/gaylemon",
            "/etc/systemd/system/palworld-stats.timer",
            "/etc/systemd/system/gaylemon-agent.service",
            "/etc/systemd/system/cloudflare-update-dns.service",
            "/etc/sysctl.d/99-palworld-performance.conf",
            "/etc/sudoers.d/palworld-api",
            "/etc/sudoers.d/gaylemon-admin",
        )
        rejected = (
            "/etc/passwd",
            "/etc/systemd/system/other.service",
            "/srv/storage/steam/bin/../servers/palworld/game",
            "/home/gaylemon/.ssh/authorized_keys",
            "/etc/sudoers.d/palworld-console",
            "/etc/sudoers.d/gaylemon-deploy",
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
