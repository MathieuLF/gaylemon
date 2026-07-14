import importlib.util
import unittest
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


if __name__ == "__main__":
    unittest.main()
