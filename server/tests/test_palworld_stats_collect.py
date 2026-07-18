import importlib.util
import unittest
import json
import tempfile
from datetime import datetime
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "bin" / "palworld-stats-collect.py"
SPEC = importlib.util.spec_from_file_location("palworld_stats_collect", MODULE_PATH)
STATS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(STATS)


class PlayerSessionHistoryTests(unittest.TestCase):
    def test_existing_open_session_is_migrated_without_increment(self):
        stats = {"players": {
            "alyross": {
                "name": "Alyross",
                "isOnline": True,
                "sessionCount": 9,
                "currentSessionStartedAt": "2026-07-13T10:23:05-04:00",
            },
        }}

        record = STATS.ensure_player(stats, "alyross", "2026-07-13T12:00:00-04:00")

        self.assertEqual(record["sessionCount"], 9)
        self.assertEqual(record["sessionHistory"], [{
            "startedAt": "2026-07-13T10:23:05-04:00",
            "endedAt": None,
        }])

    def test_session_start_and_end_are_recorded_once(self):
        stats = {"players": {}}
        payload = {"name": "Alyross", "userId": "alyross"}

        STATS.update_player_from_online(stats, payload, "2026-07-13T10:00:00-04:00", 0)
        STATS.update_player_from_online(stats, payload, "2026-07-13T10:00:30-04:00", 30)
        record = stats["players"]["alyross"]
        STATS.end_player_session(record, "2026-07-13T11:00:00-04:00")

        self.assertEqual(record["sessionCount"], 1)
        self.assertEqual(record["sessionHistory"], [{
            "startedAt": "2026-07-13T10:00:00-04:00",
            "endedAt": "2026-07-13T11:00:00-04:00",
        }])

    def test_session_history_is_bounded(self):
        record = {"sessionHistory": [
            {"startedAt": f"session-{index}", "endedAt": f"end-{index}"}
            for index in range(STATS.MAX_SESSION_HISTORY)
        ]}

        STATS.start_player_session(record, "latest")

        self.assertEqual(len(record["sessionHistory"]), STATS.MAX_SESSION_HISTORY)
        self.assertEqual(record["sessionHistory"][-1]["startedAt"], "latest")


class SourceCapabilityTests(unittest.TestCase):
    def test_primary_endpoint_failure_is_persisted_before_exit(self):
        with tempfile.TemporaryDirectory() as directory:
            originals = {
                "STATS_FILE": STATS.STATS_FILE,
                "read_admin_password": STATS.read_admin_password,
                "api_get": STATS.api_get,
            }
            STATS.STATS_FILE = Path(directory) / "stats.json"
            STATS.read_admin_password = lambda: "secret"

            def api_get(endpoint, _password, _stats, _observed_at):
                if endpoint == "metrics":
                    raise RuntimeError("private host:8212 failed")
                return {"version": "v1"} if endpoint == "info" else {"players": []}

            STATS.api_get = api_get
            try:
                with self.assertRaises(RuntimeError):
                    STATS.main()
                payload = json.loads(STATS.STATS_FILE.read_text(encoding="utf-8"))
            finally:
                for name, value in originals.items():
                    setattr(STATS, name, value)

            self.assertFalse(payload["ok"])
            self.assertEqual(payload["error"], "primary-source-unavailable:metrics")
            self.assertEqual(payload["provenance"]["sourceStatus"], "transient-error")
            self.assertEqual(payload["provenance"]["freshness"], "stale")
            self.assertEqual(payload["sources"]["metrics"]["status"], "error")

    def test_disabled_game_data_state_is_migrated_to_retryable_status(self):
        stats = {
            "version": 1,
            "collection": {
                "gameDataStatus": "disabled",
                "gameDataError": "HTTP 404",
                "lastGameDataAt": "2026-07-18T08:00:00-04:00",
            },
        }

        collection = STATS.ensure_collection_defaults(stats)

        self.assertEqual(collection["gameDataStatus"], "documented-but-unavailable")
        self.assertIsNotNone(collection["nextGameDataAttemptAt"])
        self.assertEqual(stats["schemaVersion"], STATS.SCHEMA_VERSION)

    def test_version_change_rearms_game_data_probe(self):
        stats = {
            "collection": {
                "gameDataCapabilityKey": "old-build",
                "gameDataStatus": "documented-but-unavailable",
                "gameDataAvailable": False,
                "gameDataError": "HTTP 404",
                "nextGameDataAttemptAt": "2099-01-01T00:00:00+00:00",
            },
        }

        STATS.refresh_game_data_capability(stats, "new-build")

        self.assertEqual(stats["collection"]["gameDataStatus"], "unknown")
        self.assertIsNone(stats["collection"]["nextGameDataAttemptAt"])
        self.assertTrue(STATS.should_read_game_data(
            stats,
            datetime.fromisoformat("2026-07-18T12:00:00-04:00"),
        ))

    def test_uptime_rollback_rearms_game_data_probe_without_build_change(self):
        stats = {
            "server": {"lastUptimeSeconds": 7200},
            "collection": {
                "gameDataCapabilityKey": "same-build-before-restart",
                "gameDataRestartGeneration": 3,
                "gameDataStatus": "documented-but-unavailable",
                "gameDataAvailable": False,
                "gameDataError": "HTTP 404",
                "nextGameDataAttemptAt": "2099-01-01T00:00:00+00:00",
            },
        }

        generation = STATS.update_game_data_restart_generation(
            stats,
            45,
            "2026-07-18T12:00:00-04:00",
        )
        capability = STATS.canonical_digest({
            "gameVersion": "v0.6.5",
            "steamBuildId": "123456",
            "restartGeneration": generation,
        })
        STATS.refresh_game_data_capability(stats, capability)

        self.assertEqual(generation, 4)
        self.assertEqual(
            stats["collection"]["lastServerRestartDetectedAt"],
            "2026-07-18T12:00:00-04:00",
        )
        self.assertEqual(stats["collection"]["gameDataStatus"], "unknown")
        self.assertIsNone(stats["collection"]["nextGameDataAttemptAt"])

    def test_documented_unavailable_endpoint_waits_until_retry_time(self):
        stats = {"collection": {
            "gameDataStatus": "documented-but-unavailable",
            "lastGameDataAttemptAt": "2026-07-18T08:00:00-04:00",
            "nextGameDataAttemptAt": "2026-07-18T14:00:00-04:00",
        }}

        self.assertFalse(STATS.should_read_game_data(
            stats,
            datetime.fromisoformat("2026-07-18T12:00:00-04:00"),
        ))
        self.assertTrue(STATS.should_read_game_data(
            stats,
            datetime.fromisoformat("2026-07-18T14:00:00-04:00"),
        ))


class SettingsProjectionTests(unittest.TestCase):
    def test_settings_allowlist_excludes_network_and_unknown_fields(self):
        payload = {
            "Difficulty": "Normal",
            "BaseCampWorkerMaxNum": 50,
            "PublicIP": "PRIVATE_IP_SENTINEL",
            "PublicPort": 8211,
            "BanListURL": "https://example.invalid/private.txt",
            "UnknownFutureSetting": "secret",
        }

        filtered = STATS.public_settings(payload)

        self.assertEqual(filtered, {
            "BaseCampWorkerMaxNum": 50,
            "Difficulty": "Normal",
        })

    def test_real_setting_change_is_recorded_once(self):
        stats = {"settings": {
            "status": "available",
            "updatedAt": "2026-07-18T08:00:00-04:00",
            "nextAttemptAt": None,
            "digest": STATS.canonical_digest({"Difficulty": "Normal"}),
            "current": {"Difficulty": "Normal"},
            "changes": [],
            "error": None,
        }}

        STATS.update_settings(stats, {"Difficulty": "Hard"}, "2026-07-18T09:00:00-04:00")
        STATS.update_settings(stats, {"Difficulty": "Hard"}, "2026-07-18T09:05:00-04:00")

        self.assertEqual(len(stats["settings"]["changes"]), 1)
        self.assertEqual(stats["settings"]["changes"][0]["fields"], {
            "Difficulty": {"before": "Normal", "after": "Hard"},
        })


class SourceTelemetryTests(unittest.TestCase):
    def test_source_telemetry_tracks_latency_and_failures_without_secrets(self):
        stats = {}
        STATS.record_source_observation(stats, "metrics", "sample-1", "available", 12.4, 321)
        STATS.record_source_observation(stats, "metrics", "sample-2", "error", 30.1, error="timeout")

        source = stats["sources"]["metrics"]
        self.assertEqual(source["responseBytes"], 0)
        self.assertEqual(source["consecutiveFailures"], 1)
        self.assertEqual(source["error"], "timeout")
        self.assertGreaterEqual(source["latencyP95Ms"], source["latencyMs"])


if __name__ == "__main__":
    unittest.main()
