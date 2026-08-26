import base64
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[2] / "vps" / "gaylemon-vault-sync.py"
SPEC = importlib.util.spec_from_file_location("gaylemon_vault_sync", MODULE_PATH)
VAULT_SYNC = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(VAULT_SYNC)


def complete_values():
    return {
        "GAYLEMON_AGENT_PUBLIC_KEYS": "palworld-ubuntu:abc=",
        "GAYLEMON_DATABASE_URL": "postgresql://gaylemon:p%40ss@db:5432/gaylemon",
        "GAYLEMON_GITHUB_CLIENT_ID": "client-id",
        "GAYLEMON_GITHUB_CLIENT_SECRET": "secret-value",
        "GAYLEMON_RESPONSE_PRIVATE_KEY": "base64-private-key",
    }


class GaylemonVaultSyncTests(unittest.TestCase):
    def test_validate_secrets_requires_exact_allowlist(self):
        self.assertEqual(set(VAULT_SYNC.validate_secrets(complete_values())), VAULT_SYNC.SECRET_KEYS)

        missing = complete_values()
        missing.pop("GAYLEMON_DATABASE_URL")
        with self.assertRaises(VAULT_SYNC.VaultSyncError):
            VAULT_SYNC.validate_secrets(missing)

        unexpected = complete_values() | {"INATTENDU": "valeur"}
        with self.assertRaises(VAULT_SYNC.VaultSyncError):
            VAULT_SYNC.validate_secrets(unexpected)

    def test_render_dotenv_is_sorted_and_quotes_values(self):
        rendered = VAULT_SYNC.render_dotenv(complete_values())
        variables = [line for line in rendered.splitlines() if line and not line.startswith("#")]
        self.assertEqual(variables, sorted(variables))
        self.assertIn("GAYLEMON_DATABASE_URL='postgresql://", rendered)
        self.assertNotIn("secret-value\n", rendered)

    def test_read_dotenv_reads_only_values_without_exposing_comments(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "production.env"
            path.write_text(
                "# commentaire\nCLE_SIMPLE=valeur\nCLE_QUOTEE='valeur avec espace'\n",
                encoding="utf-8",
            )
            self.assertEqual(
                VAULT_SYNC.read_dotenv(path),
                {"CLE_SIMPLE": "valeur", "CLE_QUOTEE": "valeur avec espace"},
            )

    def test_local_token_contains_short_lived_expected_claims(self):
        identity = {
            "user_id": "11111111-1111-1111-1111-111111111111",
            "email": "services@example.test",
            "role": "admin",
        }
        token = VAULT_SYNC.issue_local_token(identity, "x" * 64)
        header, payload, signature = token.split(".")
        padding = "=" * (-len(payload) % 4)
        claims = json.loads(base64.urlsafe_b64decode(payload + padding))
        self.assertEqual(claims["sub"], identity["user_id"])
        self.assertEqual(claims["email"], identity["email"])
        self.assertEqual(claims["role"], "admin")
        self.assertLessEqual(claims["exp"] - claims["iat"], 120)
        self.assertTrue(header)
        self.assertTrue(signature)


if __name__ == "__main__":
    unittest.main()
