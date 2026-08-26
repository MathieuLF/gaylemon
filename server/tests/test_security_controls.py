import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class SecurityControlTests(unittest.TestCase):
    def read(self, relative_path: str) -> str:
        return (ROOT / relative_path).read_text(encoding="utf-8")

    def test_privileged_deployer_is_fixed_and_manifest_bound(self):
        wrapper = self.read("server/sbin/gaylemon-deploy-install")

        self.assertIn('/usr/local/libexec/gaylemon/gaylemon-deploy', wrapper)
        self.assertIn('--manifest-sha256', wrapper)
        self.assertNotIn('$stage/server/deploy/gaylemon_deploy.py', wrapper)

    def test_sudoers_do_not_bypass_deployment_or_palworld_approval(self):
        sudoers = "\n".join(
            path.read_text(encoding="utf-8")
            for path in (ROOT / "server" / "sudoers").iterdir()
            if path.is_file()
        )

        self.assertNotIn("NOPASSWD: /usr/local/sbin/gaylemon-deploy-install", sudoers)
        self.assertNotIn("systemctl start palworld-update.service", sudoers)
        self.assertNotIn("systemctl restart palworld.service", sudoers)

        admin = self.read("server/sbin/gaylemon-admin")
        self.assertNotIn("systemctl restart palworld.service", admin)
        self.assertIn("palworld_pid_before=", admin)
        self.assertIn("palworld_pid_after=", admin)
        self.assertIn("palworld_restarts_before=", admin)
        self.assertIn("palworld_restarts_after=", admin)
        self.assertNotIn("release)", admin)
        self.assertIn("trap 'restore_season_timers $?' ERR", admin)
        self.assertIn('restore_season_timers 1', admin)
        self.assertIn('/usr/bin/chattr +i -- "$immutable_backup"', admin)
        self.assertIn('/usr/bin/chattr +i -- "$receipt"', admin)
        self.assertIn('receipt="$receipt_root/$slug-$backup_sha256.json"', admin)
        self.assertIn("immutableBackup", admin)
        self.assertIn("receiptSha256", admin)

        deploy_wrapper = self.read("server/sbin/gaylemon-deploy-install")
        deploy_engine = self.read("server/deploy/gaylemon_deploy.py")
        workstation_deployer = self.read("scripts/deployer-ubuntu.ps1")
        for source in (deploy_wrapper, deploy_engine, workstation_deployer):
            self.assertNotIn("allow-game-restart", source)
        self.assertIn("never restart palworld.service", deploy_engine)

    def test_scheduled_dependency_maintenance_is_report_only(self):
        runner = self.read("scripts/run-palworld-save-tools-maintenance.ps1")
        checker = self.read("scripts/check-palworld-save-tools.ps1")
        updater = self.read("server/bin/palworld-save-tools-update.sh")

        self.assertNotIn('Arguments @("-SyncFork", "-UpdateRemote")', runner)
        self.assertIn("ApprovedCommit", checker)
        self.assertIn("archiveSha256", checker)
        self.assertIn("approved_sha", updater)
        self.assertIn("approved_archive_sha256", updater)
        self.assertIn("sha256sum -c", updater)
        self.assertNotIn("--branch main", updater)
        self.assertNotIn("refs/heads/main", updater)

    def test_runtime_secrets_are_not_expanded_into_curl_arguments(self):
        api = self.read("server/bin/palworld-api.sh")
        backup = self.read("server/bin/palworld-backup.sh")
        cloudflare = self.read("server/bin/cloudflare-update-dns.sh")

        self.assertNotIn('-u "admin:${admin_password}"', api)
        self.assertNotIn('-u "admin:${admin_password}"', backup)
        self.assertNotIn('Authorization: Bearer $CF_API_TOKEN', cloudflare)
        for source in (api, backup, cloudflare):
            self.assertIn('--config "$curl_config"', source)


if __name__ == "__main__":
    unittest.main()
