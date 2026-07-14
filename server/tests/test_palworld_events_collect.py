import importlib.util
import base64
import gzip
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "bin" / "palworld-events-collect.py"
SPEC = importlib.util.spec_from_file_location("palworld_events_collect", MODULE_PATH)
EVENTS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EVENTS)


def player_state(**overrides):
    state = {
        "name": "Aventuriere",
        "level": 10,
        "bases": 1,
        "campLevel": 3,
        "pals": 2,
        "species": {
            "cattiva": {"name": "Cattiva", "count": 2, "icon": "cattiva.webp"},
        },
        "technologies": 1,
        "technologyDetails": {"torch": {"name": "Torche", "icon": "torch.webp"}},
        "quests": 1,
        "bosses": 0,
        "bossDetails": {},
        "fastTravel": ["Plateau initial"],
        "relicRanks": {},
    }
    state.update(overrides)
    return state


def snapshot_payload(updated_at, level):
    return {
        "ok": True,
        "updatedAt": updated_at,
        "players": [
            {
                "name": "Aventuriere",
                "level": level,
                "guildBases": 1,
                "campLevel": 3,
                "pals": {
                    "total": 2,
                    "collection": [
                        {"species": "Cattiva", "icon": "cattiva.webp"},
                        {"species": "Cattiva", "icon": "cattiva.webp"},
                    ],
                },
                "progress": {
                    "unlockedTechnologies": 1,
                    "technologies": [{"name": "Torche", "icon": "torch.webp"}],
                    "completedQuests": 1,
                    "bosses": {"defeated": 0, "known": []},
                    "exploration": {"fastTravelPoints": ["Plateau initial"]},
                    "relics": {"categories": []},
                },
            }
        ],
    }


def encoded_event(event_type, title, message):
    encode = lambda value: base64.b64encode(value.encode("utf-8")).decode("ascii")
    return f"GAYLEMON_EVENT\t{event_type}\t{encode(title)}\t{encode(message)}"


class JournalEventTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.connection = EVENTS.connect_database(self.root / "events.sqlite3")

    def tearDown(self):
        self.connection.close()
        self.temporary.cleanup()

    def test_journal_command_reads_game_and_update_units(self):
        command = EVENTS.journal_command("cursor-1")
        self.assertEqual(command.count("-u"), 2)
        self.assertIn("palworld.service", command)
        self.assertIn("palworld-update.service", command)
        self.assertEqual(command[-2:], ["--after-cursor", "cursor-1"])

    def test_structured_maintenance_event_is_decoded(self):
        event = EVENTS.decode_structured_event(encoded_event(
            "maintenance",
            "Maintenance dans 5 minutes",
            "La sauvegarde du monde commencera bientôt.",
        ))
        self.assertEqual(event, {
            "type": "maintenance",
            "title": "Maintenance dans 5 minutes",
            "message": "La sauvegarde du monde commencera bientôt.",
        })

    def test_invalid_structured_event_is_ignored(self):
        self.assertIsNone(EVENTS.decode_structured_event("GAYLEMON_EVENT\tmaintenance\t!\t!"))
        self.assertIsNone(EVENTS.decode_structured_event("message ordinaire"))

    def test_structured_event_from_journal_fixture_is_persisted(self):
        fixture = self.root / "journal.jsonl"
        fixture.write_text(json.dumps({
            "__CURSOR": "maintenance-cursor-1",
            "__REALTIME_TIMESTAMP": "1783958400000000",
            "MESSAGE": encoded_event(
                "maintenance",
                "Mise à jour disponible",
                "Une nouvelle build est prête.",
            ),
        }, ensure_ascii=False) + "\n", encoding="utf-8")

        EVENTS.collect_journal(self.connection, fixture)
        row = self.connection.execute(
            "SELECT type, title, message, source FROM events"
        ).fetchone()
        self.assertEqual(tuple(row), (
            "maintenance",
            "Mise à jour disponible",
            "Une nouvelle build est prête.",
            "update",
        ))


class EventDetailsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.connection = EVENTS.connect_database(Path(self.temporary.name) / "events.sqlite3")

    def tearDown(self):
        self.connection.close()
        self.temporary.cleanup()

    def compare(self, old_player, new_player):
        EVENTS.compare_snapshots(
            self.connection,
            {"players": {"aventuriere": old_player}},
            {"players": {"aventuriere": new_player}},
            "2026-07-12T18:00:00-04:00",
            {"aventuriere"},
        )
        self.connection.commit()

    def events(self):
        return self.connection.execute(
            "SELECT type, title, message, icon FROM events ORDER BY id"
        ).fetchall()

    def test_existing_species_is_named_with_quantity(self):
        old = player_state()
        new = player_state(
            pals=3,
            species={"cattiva": {"name": "Cattiva", "count": 3, "icon": "cattiva.webp"}},
        )
        self.compare(old, new)
        event = self.events()[0]
        self.assertEqual(event["message"], "Aventuriere accueille 1 Cattiva dans sa collection.")
        self.assertEqual(event["icon"], "cattiva.webp")

    def test_multiple_pals_and_new_species_are_detailed(self):
        old = player_state()
        new = player_state(
            pals=5,
            species={
                "cattiva": {"name": "Cattiva", "count": 4, "icon": "cattiva.webp"},
                "vixy": {"name": "Vixy", "count": 1, "icon": "vixy.webp"},
            },
        )
        self.compare(old, new)
        event = self.events()[0]
        self.assertIn("2 Cattiva et 1 Vixy", event["message"])
        self.assertIn("Espèce découverte: Vixy", event["message"])

    def test_technologies_bosses_travel_and_relics_are_named(self):
        old = player_state()
        new = player_state(
            technologies=2,
            technologyDetails={
                **old["technologyDetails"],
                "grappling gun": {"name": "Pistolet-grappin", "icon": "grapple.webp"},
            },
            bosses=1,
            bossDetails={"chillette": {"name": "Chillet", "icon": "chillet.webp"}},
            fastTravel=[*old["fastTravel"], "Fort en ruines"],
            relicRanks={"capture": {"name": "Puissance de capture", "rank": 2}},
        )
        self.compare(old, new)
        events = self.events()
        messages = "\n".join(event["message"] for event in events)
        self.assertIn("Pistolet-grappin", messages)
        self.assertIn("Aventuriere triomphe de Chillet", messages)
        self.assertIn("Aventuriere découvre Fort en ruines", messages)
        self.assertIn("Puissance de capture rang 2", messages)

    def test_capture_and_five_capture_challenge_are_detailed(self):
        old = player_state(
            captureDetails={
                "cattiva": {
                    "name": "Cattiva",
                    "count": 4,
                    "challengeCount": 4,
                    "challengeTarget": 5,
                    "icon": "cattiva.webp",
                }
            },
            questDetails={},
            challengeDetails={},
            records={},
        )
        new = player_state(
            captureDetails={
                "cattiva": {
                    "name": "Cattiva",
                    "count": 5,
                    "challengeCount": 5,
                    "challengeTarget": 5,
                    "icon": "cattiva.webp",
                }
            },
            questDetails={},
            challengeDetails={},
            records={},
        )
        self.compare(old, new)
        events = self.events()
        self.assertEqual([event["type"] for event in events], ["capture", "challenge"])
        self.assertIn("Total enregistré: 5", events[0]["message"])
        self.assertIn("5 captures enregistrées", events[1]["message"])

    def test_craft_and_fishing_events_are_detailed(self):
        old = player_state(
            records={"itemsCrafted": 10, "fishCaught": 2},
            craftDetails={"wood": {"name": "Bois", "count": 10, "icon": "wood.webp"}},
            fishDetails={"kelpsea": {"name": "Kelpsea", "count": 2, "icon": "fish.webp"}},
        )
        new = player_state(
            records={"itemsCrafted": 15, "fishCaught": 5},
            craftDetails={"wood": {"name": "Bois", "count": 15, "icon": "wood.webp"}},
            fishDetails={"kelpsea": {"name": "Kelpsea", "count": 5, "icon": "fish.webp"}},
        )
        self.compare(old, new)
        rows = self.connection.execute(
            "SELECT type, message, details_json FROM events ORDER BY id"
        ).fetchall()
        self.assertEqual([row["type"] for row in rows], ["craft", "fishing"])
        self.assertIn("fabrique 5 Bois", rows[0]["message"])
        self.assertIn("pêche 3 Kelpsea", rows[1]["message"])
        self.assertIn("+5 Bois", rows[0]["details_json"])

    def test_base_events_are_grouped_without_ambiguous_private_ids(self):
        previous = {
            "bases": {
                "explorateurs::base principale": {
                    "name": "Base principale",
                    "guild": "Explorateurs",
                    "players": ["Mathieu"],
                    "structuresTotal": 10,
                    "structuresDamaged": 3,
                    "structureHighlights": {"mur": {"name": "Mur", "count": 10}},
                    "productionItems": {"lingot": {"name": "Lingot", "count": 10}},
                    "researchCompleted": 1,
                }
            }
        }
        current = {
            "bases": {
                "explorateurs::base principale": {
                    "name": "Base principale",
                    "guild": "Explorateurs",
                    "players": ["Mathieu"],
                    "structuresTotal": 34,
                    "structuresDamaged": 1,
                    "structureHighlights": {
                        "mur": {"name": "Mur", "count": 30},
                        "fondation": {"name": "Fondation", "count": 4},
                    },
                    "productionItems": {"lingot": {"name": "Lingot", "count": 40}},
                    "researchCompleted": 2,
                }
            }
        }
        EVENTS.compare_base_events(
            self.connection,
            previous,
            current,
            "2026-07-12T18:00:00-04:00",
        )
        rows = self.connection.execute(
            "SELECT type, player, base, details_json FROM events ORDER BY id"
        ).fetchall()
        self.assertEqual([row["type"] for row in rows], ["build", "production", "repair", "research"])
        self.assertTrue(all(row["player"] == "Mathieu" for row in rows))
        self.assertTrue(all(row["base"] == "Base principale" for row in rows))
        self.assertNotIn("guid", "\n".join(row["details_json"] or "" for row in rows).lower())

    def test_legacy_state_is_seeded_without_false_events(self):
        old = player_state()
        for field in ("technologyDetails", "bosses", "bossDetails", "fastTravel", "relicRanks"):
            old.pop(field)
        self.compare(old, player_state())
        self.assertEqual(self.events(), [])


class RecoveryBackfillTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.history = self.root / "history"
        self.snapshot = self.root / "current.json"
        self.connection = EVENTS.connect_database(self.root / "events.sqlite3")

    def tearDown(self):
        self.connection.close()
        self.temporary.cleanup()

    def write_archive(self, hour, payload):
        path = self.history / "2026" / "07" / "12" / f"{hour}.json.gz"
        path.parent.mkdir(parents=True, exist_ok=True)
        with gzip.open(path, "wt", encoding="utf-8") as stream:
            json.dump(payload, stream)

    def test_new_hourly_archives_are_replayed_after_initial_backfill(self):
        initial = snapshot_payload("2026-07-12T10:15:00-04:00", 10)
        EVENTS.metadata_set(self.connection, "save_state", EVENTS.snapshot_state(initial))
        EVENTS.metadata_set(self.connection, "last_save_at", initial["updatedAt"])
        EVENTS.metadata_set(self.connection, "known_players", ["aventuriere"])
        EVENTS.metadata_set(self.connection, "history_backfilled", True)
        self.connection.commit()

        self.write_archive("10", snapshot_payload("2026-07-12T10:55:00-04:00", 11))
        self.write_archive("11", snapshot_payload("2026-07-12T11:55:00-04:00", 12))
        self.snapshot.write_text(
            json.dumps(snapshot_payload("2026-07-12T13:05:00-04:00", 13)),
            encoding="utf-8",
        )

        report = EVENTS.collect_snapshots(self.connection, self.snapshot, self.history)
        self.connection.commit()

        self.assertEqual(report["archives"]["imported"], 2)
        self.assertEqual(report["archives"]["importedHours"], ["2026/07/12/10", "2026/07/12/11"])
        self.assertEqual(report["archives"]["missingHours"], ["2026-07-12T12:00:00-04:00"])
        self.assertEqual(report["events"]["added"], 3)
        self.assertEqual(report["status"], "partial")
        self.assertEqual(report["lastBackfill"]["archivesImported"], 2)
        self.assertEqual(report["lastBackfill"]["eventsAdded"], 3)
        levels = self.connection.execute(
            "SELECT occurred_at, message FROM events WHERE type = 'level' ORDER BY occurred_at"
        ).fetchall()
        self.assertEqual([row["occurred_at"] for row in levels], [
            "2026-07-12T10:55:00-04:00",
            "2026-07-12T11:55:00-04:00",
            "2026-07-12T13:05:00-04:00",
        ])

        second_report = EVENTS.collect_snapshots(self.connection, self.snapshot, self.history)
        self.assertEqual(second_report["archives"]["imported"], 0)
        self.assertFalse(second_report["currentSnapshotImported"])
        self.assertEqual(second_report["events"]["added"], 0)
        self.assertEqual(second_report["status"], "complete")
        self.assertEqual(second_report["lastBackfill"], report["lastBackfill"])

    def test_capture_history_is_backfilled_once(self):
        first = snapshot_payload("2026-07-12T10:15:00-04:00", 10)
        second = snapshot_payload("2026-07-12T11:15:00-04:00", 10)
        first["players"][0]["progress"]["paldex"] = {
            "species": [{"name": "Cattiva", "captureCount": 1, "icon": "cattiva.webp"}]
        }
        second["players"][0]["progress"]["paldex"] = {
            "species": [{"name": "Cattiva", "captureCount": 3, "icon": "cattiva.webp"}]
        }
        self.write_archive("10", first)
        self.write_archive("11", second)

        report = EVENTS.backfill_capture_history(self.connection, self.snapshot, self.history)
        self.connection.commit()
        self.assertEqual(report["snapshots"], 2)
        self.assertEqual(report["eventsAdded"], 1)
        event = self.connection.execute(
            "SELECT type, message FROM events WHERE type = 'capture'"
        ).fetchone()
        self.assertIn("capture 2 Cattiva", event["message"])

        second_report = EVENTS.backfill_capture_history(self.connection, self.snapshot, self.history)
        self.assertEqual(second_report["status"], "current")
        self.assertEqual(second_report["eventsAdded"], 0)

    def test_checkpoint_backfill_suspends_when_server_health_is_low(self):
        stats = self.root / "stats.json"
        stats.write_text(json.dumps({"server": {"lastFps": 45, "lastFrameMs": 18}}), encoding="utf-8")
        self.write_archive("10", snapshot_payload("2026-07-12T10:15:00-04:00", 10))

        report = EVENTS.backfill_archives_checkpoint(
            self.connection,
            self.history,
            stats,
            backfill_from="2026-07-09T00:00:00-04:00",
            budget=1,
            min_fps=50,
            max_frame_ms=22,
            max_load=99,
        )

        self.assertEqual(report["status"], "suspended")
        self.assertEqual(report["snapshots"], 0)

    def test_checkpoint_backfill_processes_one_archive_without_duplicates(self):
        stats = self.root / "stats.json"
        stats.write_text(json.dumps({"server": {"lastFps": 60, "lastFrameMs": 16.7}}), encoding="utf-8")
        self.write_archive("10", snapshot_payload("2026-07-12T10:15:00-04:00", 10))
        self.write_archive("11", snapshot_payload("2026-07-12T11:15:00-04:00", 11))

        first = EVENTS.backfill_archives_checkpoint(
            self.connection,
            self.history,
            stats,
            backfill_from="2026-07-09T00:00:00-04:00",
            budget=1,
            min_fps=50,
            max_frame_ms=22,
            max_load=99,
        )
        second = EVENTS.backfill_archives_checkpoint(
            self.connection,
            self.history,
            stats,
            backfill_from="2026-07-09T00:00:00-04:00",
            budget=1,
            min_fps=50,
            max_frame_ms=22,
            max_load=99,
        )
        third = EVENTS.backfill_archives_checkpoint(
            self.connection,
            self.history,
            stats,
            backfill_from="2026-07-09T00:00:00-04:00",
            budget=1,
            min_fps=50,
            max_frame_ms=22,
            max_load=99,
        )

        self.assertEqual(first["snapshots"], 1)
        self.assertEqual(second["snapshots"], 1)
        self.assertEqual(third["eventsAdded"], 0)
        self.assertEqual(
            self.connection.execute("SELECT COUNT(*) FROM events WHERE type = 'level'").fetchone()[0],
            1,
        )


class SessionReconciliationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.connection = EVENTS.connect_database(self.root / "events.sqlite3")

    def tearDown(self):
        self.connection.close()
        self.temporary.cleanup()

    def add_transition(self, occurred_at, event_type, source="journal"):
        is_join = event_type == "join"
        EVENTS.add_event(
            self.connection,
            fingerprint=f"{source}:{event_type}:{occurred_at}",
            occurred_at=occurred_at,
            event_type=event_type,
            player="Alyross",
            title="Arrivée sur Palpagos" if is_join else "Fin d'expédition",
            message="Alyross rejoint l'aventure." if is_join else "Alyross quitte l'archipel.",
            source=source,
        )

    def public_events(self):
        rows = self.connection.execute(
            "SELECT id, occurred_at, type, player, title, message, icon, source "
            "FROM events ORDER BY occurred_at DESC, id DESC"
        ).fetchall()
        return EVENTS.reconcile_public_events(rows)

    def test_orphan_leave_followed_by_quick_join_becomes_reconnect(self):
        self.add_transition("2026-07-13T09:00:00-04:00", "join")
        self.add_transition("2026-07-13T09:30:00-04:00", "leave")
        self.add_transition("2026-07-13T10:22:11-04:00", "leave")
        self.add_transition("2026-07-13T10:23:03-04:00", "join")

        events, reconnects = self.public_events()

        self.assertEqual(reconnects, 1)
        self.assertEqual([event["type"] for event in events], ["reconnect", "leave", "join"])
        self.assertIn("rétablit sa connexion", events[0]["message"])

    def test_real_leave_and_quick_return_remain_two_events(self):
        self.add_transition("2026-07-13T09:00:00-04:00", "join")
        self.add_transition("2026-07-13T10:22:11-04:00", "leave")
        self.add_transition("2026-07-13T10:23:03-04:00", "join")

        events, reconnects = self.public_events()

        self.assertEqual(reconnects, 0)
        self.assertEqual([event["type"] for event in events], ["join", "leave", "join"])

    def test_rest_session_duplicate_is_hidden_when_journal_transition_exists(self):
        self.add_transition("2026-07-13T10:00:25-04:00", "join", source="players")
        self.add_transition("2026-07-13T10:01:30-04:00", "join", source="journal")
        self.add_transition("2026-07-13T11:00:00-04:00", "leave", source="players")
        self.add_transition("2026-07-13T11:00:42-04:00", "leave", source="journal")

        events, reconnects = self.public_events()

        self.assertEqual(reconnects, 0)
        self.assertEqual(
            [(event["type"], event["source"]) for event in events],
            [("leave", "journal"), ("join", "journal")],
        )

    def test_old_orphan_leave_is_not_hidden(self):
        self.add_transition("2026-07-13T09:00:00-04:00", "join")
        self.add_transition("2026-07-13T09:30:00-04:00", "leave")
        self.add_transition("2026-07-13T10:00:00-04:00", "leave")
        self.add_transition("2026-07-13T10:05:00-04:00", "join")

        events, reconnects = self.public_events()

        self.assertEqual(reconnects, 0)
        self.assertEqual([event["type"] for event in events], ["join", "leave", "leave", "join"])

    def test_rest_sessions_only_fill_missing_journal_transitions(self):
        self.add_transition("2026-07-13T10:00:00-04:00", "join")
        stats = self.root / "stats.json"
        stats.write_text(json.dumps({
            "players": {
                "alyross-id": {
                    "name": "Alyross",
                    "sessionHistory": [{
                        "startedAt": "2026-07-13T10:00:25-04:00",
                        "endedAt": "2026-07-13T11:00:00-04:00",
                    }],
                },
            },
        }), encoding="utf-8")

        self.assertEqual(EVENTS.collect_player_sessions(self.connection, stats), 1)
        self.assertEqual(EVENTS.collect_player_sessions(self.connection, stats), 0)
        rows = self.connection.execute(
            "SELECT type, source FROM events ORDER BY occurred_at"
        ).fetchall()
        self.assertEqual([(row["type"], row["source"]) for row in rows], [
            ("join", "journal"),
            ("leave", "players"),
        ])


if __name__ == "__main__":
    unittest.main()
