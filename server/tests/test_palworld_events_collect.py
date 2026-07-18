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
            bossDetails={"chillette": {"name": "Chillet", "asset": "Chillet", "icon": "chillet.webp", "level": 11}},
            fastTravel=[*old["fastTravel"], "Fort en ruines"],
            relicRanks={"capture": {"name": "Puissance de capture", "rank": 2}},
        )
        self.compare(old, new)
        events = self.events()
        messages = "\n".join(event["message"] for event in events)
        self.assertIn("Pistolet-grappin", messages)
        self.assertIn("Aventuriere triomphe de Chillet niveau 11", messages)
        self.assertIn("Aventuriere découvre Fort en ruines", messages)
        self.assertIn("Puissance de capture rang 2", messages)
        boss_details = json.loads(self.connection.execute(
            "SELECT details_json FROM events WHERE type = 'boss'"
        ).fetchone()["details_json"])
        self.assertEqual(boss_details["bosses"][0]["name"], "Chillet")
        self.assertEqual(boss_details["bosses"][0]["asset"], "Chillet")
        self.assertEqual(boss_details["bosses"][0]["level"], 11)

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
        self.assertIn("termine 5 fabrications", rows[0]["message"])
        self.assertNotIn("Bois", rows[0]["message"])
        self.assertIn("ramène 3 prises de pêche", rows[1]["message"])
        self.assertNotIn("Kelpsea", rows[1]["message"])
        self.assertIn("+5 Bois", rows[0]["details_json"])
        self.assertIn("+3 Kelpsea", rows[1]["details_json"])

    def test_record_counter_events_are_published_with_totals(self):
        old = player_state(records={
            "raidBossDefeats": 0,
            "towerBossDefeats": 1,
            "arenaSoloClears": 0,
            "notesFound": 1,
            "palRankups": 2,
            "mutations": 0,
            "uniqueItemsPickedUp": 3,
        })
        new = player_state(records={
            "raidBossDefeats": 1,
            "towerBossDefeats": 2,
            "arenaSoloClears": 2,
            "notesFound": 4,
            "palRankups": 5,
            "mutations": 1,
            "uniqueItemsPickedUp": 6,
        })
        self.compare(old, new)
        rows = self.connection.execute(
            "SELECT type, title, message, details_json FROM events ORDER BY id"
        ).fetchall()
        self.assertEqual(
            [row["type"] for row in rows],
            ["raid", "boss", "arena", "note", "pal", "mutation", "loot"],
        )
        self.assertIn("vainc 1 boss de raid. Total cumulé: 1.", rows[0]["message"])
        self.assertIn("termine 2 arènes solo. Total cumulé: 2.", rows[2]["message"])
        self.assertIn("trouve 3 notes. Total cumulé: 4.", rows[3]["message"])
        self.assertIn("découvre 3 types d'objets uniques. Total cumulé: 6.", rows[6]["message"])
        self.assertIn("+3 types d'objets uniques", rows[6]["details_json"])

    def test_new_record_fields_are_seeded_without_false_events(self):
        old = player_state(records={"itemsCrafted": 0})
        new = player_state(records={
            "itemsCrafted": 0,
            "raidBossDefeats": 1,
            "towerBossDefeats": 2,
            "arenaSoloClears": 2,
            "notesFound": 4,
            "palRankups": 5,
            "mutations": 1,
            "uniqueItemsPickedUp": 6,
        })
        self.compare(old, new)
        self.assertEqual(self.events(), [])

    def test_death_drop_appearance_and_recovery_are_published_once(self):
        drop = {
            "key": "drop_public_1",
            "type": "character-drop",
            "label": "Sac de récupération",
            "player": "Aventuriere",
            "position": {"mapX": 12, "mapY": 34, "mapVisible": True},
        }
        EVENTS.compare_snapshots(
            self.connection,
            {"players": {}, "bases": {}, "deathDrops": {}},
            {"players": {}, "bases": {}, "deathDrops": {"drop_public_1": drop}},
            "2026-07-12T18:00:00-04:00",
            set(),
        )
        EVENTS.compare_snapshots(
            self.connection,
            {"players": {}, "bases": {}, "deathDrops": {"drop_public_1": drop}},
            {"players": {}, "bases": {}, "deathDrops": {}},
            "2026-07-12T18:05:00-04:00",
            set(),
        )
        rows = self.connection.execute(
            "SELECT type, title, message, player, confidence, details_json FROM events ORDER BY id"
        ).fetchall()
        self.assertEqual([row["type"] for row in rows], ["death", "recovery"])
        self.assertEqual(rows[0]["player"], "Aventuriere")
        self.assertIn("apparaît sur Palpagos", rows[0]["message"])
        self.assertIn("n'est plus présent", rows[1]["message"])
        self.assertNotIn("drop_public_1", rows[0]["details_json"])

    def test_death_drops_are_seeded_without_false_events(self):
        EVENTS.compare_snapshots(
            self.connection,
            {"players": {}, "bases": {}},
            {"players": {}, "bases": {}, "deathDrops": {"drop_public_1": {
                "key": "drop_public_1",
                "label": "Sac de récupération",
            }}},
            "2026-07-12T18:00:00-04:00",
            set(),
        )
        self.assertEqual(self.events(), [])

    def test_detailed_quest_does_not_emit_duplicate_progress(self):
        old = player_state(
            quests=0,
            questDetails={},
            technologies=1,
            technologyDetails={"torch": {"name": "Torche", "icon": "torch.webp"}},
        )
        new = player_state(
            quests=1,
            questDetails={"breeder": {"name": "Mission de l'éleveur · chapitre 1"}},
            technologies=1,
            technologyDetails={"torch": {"name": "Torche", "icon": "torch.webp"}},
        )
        self.compare(old, new)
        events = self.events()
        self.assertEqual([event["type"] for event in events], ["quest"])
        self.assertEqual(
            events[0]["message"],
            "Aventuriere termine Mission de l'éleveur · chapitre 1.",
        )

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
            "SELECT type, player, base, message, details_json FROM events ORDER BY id"
        ).fetchall()
        self.assertEqual([row["type"] for row in rows], ["build", "production", "repair", "research"])
        self.assertTrue(all(row["player"] == "Mathieu" for row in rows))
        self.assertTrue(all(row["base"] == "Base principale" for row in rows))
        self.assertNotIn("guid", "\n".join(row["details_json"] or "" for row in rows).lower())
        production = next(row for row in rows if row["type"] == "production")
        self.assertIn("Mathieu termine une production à Base principale", production["message"])
        self.assertIn("30 ressources produites sont prêtes", production["message"])
        self.assertIn("Stock de production actuel: 40", production["message"])
        production_details = json.loads(production["details_json"])
        self.assertEqual(
            production_details["body"],
            "30 ressources produites sont prêtes. Stock de production actuel: 40.",
        )
        self.assertIn("+30 Lingot", production_details["bullets"])
        self.assertEqual(production_details["total"], 40)

    def test_server_numbered_base_events_use_player_relative_labels(self):
        previous = {
            "bases": {
                "spartans::base 6 · spartans": {
                    "name": "Base 6 · Spartans",
                    "guild": "Spartans",
                    "players": ["Mathieu"],
                    "structuresTotal": 10,
                    "structuresDamaged": 0,
                    "structureHighlights": {"mur": {"name": "Mur", "count": 10}},
                    "productionItems": {},
                    "researchCompleted": 0,
                },
                "spartans::base 17 · spartans": {
                    "name": "Base 17 · Spartans",
                    "guild": "Spartans",
                    "players": ["Mathieu"],
                    "structuresTotal": 4,
                    "structuresDamaged": 0,
                    "structureHighlights": {"mur": {"name": "Mur", "count": 4}},
                    "productionItems": {},
                    "researchCompleted": 0,
                },
            }
        }
        current = {
            "bases": {
                "spartans::base 6 · spartans": {
                    "name": "Base 6 · Spartans",
                    "guild": "Spartans",
                    "players": ["Mathieu"],
                    "structuresTotal": 12,
                    "structuresDamaged": 0,
                    "structureHighlights": {"mur": {"name": "Mur", "count": 12}},
                    "productionItems": {},
                    "researchCompleted": 0,
                },
                "spartans::base 17 · spartans": {
                    "name": "Base 17 · Spartans",
                    "guild": "Spartans",
                    "players": ["Mathieu"],
                    "structuresTotal": 5,
                    "structuresDamaged": 0,
                    "structureHighlights": {"mur": {"name": "Mur", "count": 5}},
                    "productionItems": {},
                    "researchCompleted": 0,
                },
            }
        }

        EVENTS.compare_base_events(
            self.connection,
            previous,
            current,
            "2026-07-12T18:00:00-04:00",
        )
        rows = self.connection.execute(
            "SELECT base, message, details_json FROM events ORDER BY id"
        ).fetchall()

        self.assertEqual([row["base"] for row in rows], ["Base 1", "Base 2"])
        self.assertIn("Mathieu agrandit Base 1", rows[0]["message"])
        self.assertIn("Mathieu agrandit Base 2", rows[1]["message"])
        details = json.loads(rows[0]["details_json"])
        self.assertEqual(details["baseName"], "Base 1")
        self.assertEqual(details["rawBaseName"], "Base 6 · Spartans")
        self.assertEqual(details["baseLabelScope"], "Mathieu")

    def test_base_damage_increase_is_not_reported_as_raid(self):
        previous = {
            "bases": {
                "explorateurs::base principale": {
                    "name": "Base principale",
                    "guild": "Explorateurs",
                    "players": ["Mathieu"],
                    "structuresTotal": 10,
                    "structuresDamaged": 1,
                    "structureHighlights": {},
                    "productionItems": {},
                    "researchCompleted": 0,
                }
            }
        }
        current = {
            "bases": {
                "explorateurs::base principale": {
                    "name": "Base principale",
                    "guild": "Explorateurs",
                    "players": ["Mathieu"],
                    "structuresTotal": 10,
                    "structuresDamaged": 4,
                    "structureHighlights": {},
                    "productionItems": {},
                    "researchCompleted": 0,
                }
            }
        }
        EVENTS.compare_base_events(
            self.connection,
            previous,
            current,
            "2026-07-12T18:00:00-04:00",
        )
        self.assertEqual(
            self.connection.execute("SELECT COUNT(*) FROM events WHERE type = 'raid'").fetchone()[0],
            0,
        )

    def test_inactive_player_snapshot_changes_are_not_published(self):
        EVENTS.compare_snapshots(
            self.connection,
            {"players": {"aventuriere": player_state()}},
            {"players": {"aventuriere": player_state(level=11)}},
            "2026-07-12T18:00:00-04:00",
            {"aventuriere"},
            set(),
        )
        self.connection.commit()

        self.assertEqual(self.events(), [])

    def test_post_session_snapshot_changes_are_published_at_session_close(self):
        EVENTS.compare_snapshots(
            self.connection,
            {"players": {"aventuriere": player_state()}},
            {"players": {"aventuriere": player_state(level=11)}},
            "2026-07-12T18:00:45-04:00",
            {"aventuriere"},
            {"aventuriere": "2026-07-12T18:00:00-04:00"},
        )
        self.connection.commit()

        row = self.connection.execute(
            "SELECT occurred_at, fingerprint, type FROM events"
        ).fetchone()
        self.assertEqual(row["type"], "level")
        self.assertEqual(row["occurred_at"], "2026-07-12T18:00:00-04:00")
        self.assertIn("save:2026-07-12T18:00:00-04:00:level:aventuriere:11", row["fingerprint"])

    def test_inactive_base_changes_are_not_published(self):
        previous = {
            "bases": {
                "explorateurs::base principale": {
                    "name": "Base principale",
                    "guild": "Explorateurs",
                    "players": ["Mathieu"],
                    "structuresTotal": 10,
                    "structuresDamaged": 1,
                    "structureHighlights": {"mur": {"name": "Mur", "count": 10}},
                    "productionItems": {"lingot": {"name": "Lingot", "count": 10}},
                    "researchCompleted": 0,
                }
            }
        }
        current = {
            "bases": {
                "explorateurs::base principale": {
                    "name": "Base principale",
                    "guild": "Explorateurs",
                    "players": ["Mathieu"],
                    "structuresTotal": 11,
                    "structuresDamaged": 4,
                    "structureHighlights": {"mur": {"name": "Mur", "count": 11}},
                    "productionItems": {"lingot": {"name": "Lingot", "count": 11}},
                    "researchCompleted": 0,
                }
            }
        }

        EVENTS.compare_base_events(
            self.connection,
            previous,
            current,
            "2026-07-12T18:00:00-04:00",
            set(),
        )
        row = self.connection.execute(
            "SELECT type, player, message FROM events"
        ).fetchone()

        self.assertIsNone(row)

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
        self.bases_history = self.root / "bases-history"
        self.snapshot = self.root / "current.json"
        self.bases_snapshot = self.root / "current-bases.json"
        self.connection = EVENTS.connect_database(self.root / "events.sqlite3")

    def tearDown(self):
        self.connection.close()
        self.temporary.cleanup()

    def write_archive(self, hour, payload):
        path = self.history / "2026" / "07" / "12" / f"{hour}.json.gz"
        path.parent.mkdir(parents=True, exist_ok=True)
        with gzip.open(path, "wt", encoding="utf-8") as stream:
            json.dump(payload, stream)

    def write_bases_archive(self, hour, payload):
        path = self.bases_history / "2026" / "07" / "12" / f"{hour}.json.gz"
        path.parent.mkdir(parents=True, exist_ok=True)
        with gzip.open(path, "wt", encoding="utf-8") as stream:
            json.dump(payload, stream)

    def bases_payload(self, updated_at, damaged):
        return {
            "ok": True,
            "updatedAt": updated_at,
            "bases": [{
                "name": "Base principale",
                "guild": "Explorateurs",
                "players": ["Mathieu"],
                "structures": {"total": 10, "damaged": damaged, "highlights": []},
                "production": {"topItems": []},
                "research": {"completed": 0},
            }],
        }

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

    def test_raid_history_backfill_is_disabled(self):
        self.write_bases_archive("10", self.bases_payload("2026-07-12T10:15:00-04:00", 1))
        self.write_bases_archive("11", self.bases_payload("2026-07-12T11:15:00-04:00", 4))
        self.bases_snapshot.write_text(
            json.dumps(self.bases_payload("2026-07-12T12:15:00-04:00", 6)),
            encoding="utf-8",
        )

        first = EVENTS.backfill_raid_history(
            self.connection,
            self.bases_snapshot,
            self.bases_history,
        )
        self.connection.commit()
        second = EVENTS.backfill_raid_history(
            self.connection,
            self.bases_snapshot,
            self.bases_history,
        )

        self.assertEqual(first["status"], "skipped")
        self.assertEqual(first["reason"], "derived-raid-backfill-disabled")
        self.assertEqual(first["snapshots"], 0)
        self.assertEqual(first["eventsAdded"], 0)
        self.assertEqual(second["snapshots"], 0)
        self.assertEqual(second["eventsAdded"], 0)
        self.assertEqual(
            self.connection.execute("SELECT COUNT(*) FROM events WHERE type = 'raid'").fetchone()[0],
            0,
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
            f"""
            SELECT id, fingerprint, occurred_at, type, player, guild, base, title,
                   message, icon, source, details_json, confidence
            FROM events
            ORDER BY {EVENTS.PUBLIC_EVENT_ORDER_SQL}
            """
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

    def test_public_order_places_leave_before_same_second_save_activity(self):
        EVENTS.add_event(
            self.connection,
            fingerprint="journal:leave",
            occurred_at="2026-07-13T11:00:00-04:00",
            event_type="leave",
            player="Alyross",
            title="Fin d'expédition",
            message="Alyross quitte l'archipel.",
            source="journal",
        )
        EVENTS.add_event(
            self.connection,
            fingerprint="save:closing",
            occurred_at="2026-07-13T11:00:00-04:00",
            event_type="craft",
            player="Alyross",
            title="Fabrications terminées",
            message="Alyross termine 2 fabrications.",
            source="save",
        )

        events, reconnects = self.public_events()

        self.assertEqual(reconnects, 0)
        self.assertEqual(
            [(event["type"], event["source"]) for event in events],
            [("leave", "journal"), ("craft", "save")],
        )

    def test_public_export_groups_crafts_and_productions_into_five_minute_windows(self):
        EVENTS.add_event(
            self.connection,
            fingerprint="save:craft:1",
            occurred_at="2026-07-13T10:00:10-04:00",
            event_type="craft",
            player="Alyross",
            title="Fabrications terminées",
            message="Alyross termine 7 fabrications. Total cumulé: 7.",
            icon="wood.webp",
            source="save",
            details={
                "bullets": ["+7 Bois"],
                "items": [{"name": "Bois", "asset": "wood", "added": 7, "count": 7, "icon": "wood.webp"}],
                "total": 7,
            },
        )
        EVENTS.add_event(
            self.connection,
            fingerprint="save:production:1",
            occurred_at="2026-07-13T10:01:00-04:00",
            event_type="production",
            player="Alyross",
            guild="PalaPaly",
            base="Base 1",
            title="Production terminée",
            message="Alyross termine une production à Base 1. 5 ressources produites sont prêtes. Stock de production actuel: 8.",
            icon="ingot.webp",
            source="save",
            details={
                "bullets": ["+5 Lingot"],
                "items": [{"name": "Lingot", "asset": "ingot", "added": 5, "count": 8, "icon": "ingot.webp"}],
                "total": 8,
            },
        )
        EVENTS.add_event(
            self.connection,
            fingerprint="save:craft:2",
            occurred_at="2026-07-13T10:02:30-04:00",
            event_type="craft",
            player="Alyross",
            title="Fabrications terminées",
            message="Alyross termine 4 fabrications. Total cumulé: 17.",
            icon="stone.webp",
            source="save",
            details={
                "bullets": ["+4 Pierre"],
                "items": [{"name": "Pierre", "asset": "stone", "added": 4, "count": 4, "icon": "stone.webp"}],
                "total": 17,
            },
        )
        EVENTS.add_event(
            self.connection,
            fingerprint="save:production:2",
            occurred_at="2026-07-13T10:04:59-04:00",
            event_type="production",
            player="Alyross",
            guild="PalaPaly",
            base="Base 2",
            title="Production terminée",
            message="Alyross termine une production à Base 2. 7 ressources produites sont prêtes. Stock de production actuel: 15.",
            icon="salad.webp",
            source="save",
            details={
                "bullets": ["+7 Salade"],
                "items": [{"name": "Salade", "asset": "salad", "added": 7, "count": 15, "icon": "salad.webp"}],
                "total": 15,
            },
        )
        EVENTS.add_event(
            self.connection,
            fingerprint="save:craft:3",
            occurred_at="2026-07-13T10:06:00-04:00",
            event_type="craft",
            player="Alyross",
            title="Fabrications terminées",
            message="Alyross termine 3 fabrications. Total cumulé: 20.",
            icon="wood.webp",
            source="save",
            details={
                "bullets": ["+3 Bois"],
                "items": [{"name": "Bois", "asset": "wood", "added": 3, "count": 10, "icon": "wood.webp"}],
                "total": 20,
            },
        )

        events, reconnects = self.public_events()

        self.assertEqual(reconnects, 0)
        self.assertEqual([event["type"] for event in events], ["craft", "production", "craft"])
        self.assertEqual(events[0]["title"], "Fabrications terminées")
        production = events[1]
        craft = events[2]
        self.assertEqual(production["title"], "Productions compilées")
        self.assertIn("Alyross boucle 2 productions en 5 min", production["message"])
        self.assertIn("12 ressources produites sont prêtes dans 2 bases", production["message"])
        self.assertEqual(production["details"]["aggregatedEvents"], 2)
        self.assertEqual(production["details"]["total"], 23)
        self.assertEqual(production["details"]["bases"], ["Base 1", "Base 2"])
        self.assertIn("+7 Salade", production["details"]["bullets"])
        self.assertIn("+5 Lingot", production["details"]["bullets"])
        self.assertEqual(craft["title"], "Fabrications compilées")
        self.assertIn("Alyross termine 11 fabrications en 5 min", craft["message"])
        self.assertEqual(craft["details"]["aggregatedEvents"], 2)
        self.assertEqual(craft["details"]["total"], 17)
        self.assertIn("+7 Bois", craft["details"]["bullets"])
        self.assertIn("+4 Pierre", craft["details"]["bullets"])

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

    def test_player_sessions_accept_public_player_lists_and_are_strict_after_leave(self):
        stats = self.root / "stats-list.json"
        stats.write_text(json.dumps({
            "players": [{
                "name": "Alyross",
                "sessionHistory": [{
                    "startedAt": "2026-07-13T10:00:00-04:00",
                    "endedAt": "2026-07-13T11:00:00-04:00",
                }],
            }],
        }), encoding="utf-8")

        sessions = EVENTS.player_session_index(stats)

        self.assertEqual(set(sessions), {"alyross"})
        self.assertEqual(
            EVENTS.active_players_at(sessions, "2026-07-13T11:00:00-04:00"),
            {"alyross"},
        )
        self.assertEqual(
            EVENTS.active_players_at(sessions, "2026-07-13T11:00:01-04:00"),
            set(),
        )
        self.assertEqual(EVENTS.collect_player_sessions(self.connection, stats), 2)
        self.assertEqual(
            EVENTS.session_activity_times_at(
                self.connection,
                sessions,
                "2026-07-13T11:00:45-04:00",
            ),
            {"alyross": "2026-07-13T11:00:00-04:00"},
        )

    def test_inactive_save_event_cleanup_reassigns_closing_deltas_and_removes_late_ones(self):
        stats = self.root / "stats.json"
        stats.write_text(json.dumps({
            "players": {
                "steam_1": {
                    "name": "Alyross",
                    "sessionHistory": [{
                        "startedAt": "2026-07-13T10:00:00-04:00",
                        "endedAt": "2026-07-13T11:00:00-04:00",
                    }],
                },
            },
        }), encoding="utf-8")
        EVENTS.add_event(
            self.connection,
            fingerprint="save:active",
            occurred_at="2026-07-13T10:59:59-04:00",
            event_type="craft",
            player="Alyross",
            title="Fabrications terminées",
            message="Alyross termine 2 fabrications.",
            source="save",
        )
        EVENTS.add_event(
            self.connection,
            fingerprint="save:closing",
            occurred_at="2026-07-13T11:00:01-04:00",
            event_type="craft",
            player="Alyross",
            title="Fabrications terminées",
            message="Alyross termine 2 fabrications.",
            source="save",
        )
        EVENTS.add_event(
            self.connection,
            fingerprint="save:inactive",
            occurred_at="2026-07-13T11:04:01-04:00",
            event_type="craft",
            player="Alyross",
            title="Fabrications terminées",
            message="Alyross termine 2 fabrications.",
            source="save",
        )
        EVENTS.add_event(
            self.connection,
            fingerprint="journal:leave",
            occurred_at="2026-07-13T11:00:00-04:00",
            event_type="leave",
            player="Alyross",
            title="Fin d'expédition",
            message="Alyross quitte l'archipel.",
            source="journal",
        )
        EVENTS.add_event(
            self.connection,
            fingerprint="save:death",
            occurred_at="2026-07-13T11:00:01-04:00",
            event_type="death",
            player="Alyross",
            title="Sac de récupération",
            message="Le sac apparaît sur Palpagos.",
            source="save",
            confidence="derived",
        )

        report = EVENTS.purge_inactive_save_events(self.connection, stats)

        self.assertEqual(report["removed"], 1)
        self.assertEqual(report["reassigned"], 1)
        rows = self.connection.execute(
            "SELECT fingerprint, occurred_at FROM events ORDER BY occurred_at, id"
        ).fetchall()
        self.assertEqual(
            [(row["fingerprint"], row["occurred_at"]) for row in rows],
            [
                ("save:active", "2026-07-13T10:59:59-04:00"),
                ("save:closing", "2026-07-13T11:00:00-04:00"),
                ("journal:leave", "2026-07-13T11:00:00-04:00"),
                ("save:death", "2026-07-13T11:00:01-04:00"),
            ],
        )


class PublicExportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.connection = EVENTS.connect_database(self.root / "events.sqlite3")

    def tearDown(self):
        self.connection.close()
        self.temporary.cleanup()

    def test_public_export_keeps_complete_history(self):
        for index in range(6):
            EVENTS.add_event(
                self.connection,
                fingerprint=f"server:event:{index}",
                occurred_at=f"2026-07-13T10:0{index}:00-04:00",
                event_type="server",
                title=f"Écho {index}",
                message=f"Message {index}",
                source="journal",
            )

        output = self.root / "public-events.json"
        recent = self.root / "public-events-recent.json"
        EVENTS.write_export(self.connection, output, recent)

        payload = json.loads(output.read_text(encoding="utf-8"))
        recent_payload = json.loads(recent.read_text(encoding="utf-8"))
        self.assertFalse(payload["truncated"])
        self.assertEqual(payload["summary"]["events"], 6)
        self.assertEqual(payload["summary"]["totalEvents"], 6)
        self.assertEqual([event["title"] for event in payload["events"]], [
            "Écho 5",
            "Écho 4",
            "Écho 3",
            "Écho 2",
            "Écho 1",
            "Écho 0",
        ])
        self.assertTrue(recent_payload["recent"])
        self.assertEqual(recent_payload["summary"]["totalEvents"], 6)

    def test_recent_public_export_keeps_large_hot_window(self):
        total = EVENTS.RECENT_EVENT_LIMIT + 25
        for index in range(total):
            EVENTS.add_event(
                self.connection,
                fingerprint=f"server:hot-window:{index}",
                occurred_at=f"2026-07-13T{10 + index // 3600:02d}:{(index // 60) % 60:02d}:{index % 60:02d}-04:00",
                event_type="server",
                title=f"Écho {index}",
                message=f"Message {index}",
                source="journal",
            )

        output = self.root / "public-events.json"
        recent = self.root / "public-events-recent.json"
        EVENTS.write_export(self.connection, output, recent)

        recent_payload = json.loads(recent.read_text(encoding="utf-8"))
        self.assertTrue(recent_payload["recent"])
        self.assertEqual(recent_payload["summary"]["events"], EVENTS.RECENT_EVENT_LIMIT)
        self.assertEqual(recent_payload["summary"]["totalEvents"], total)
        self.assertEqual(recent_payload["events"][0]["title"], f"Écho {total - 1}")
        self.assertEqual(recent_payload["events"][-1]["title"], f"Écho {total - EVENTS.RECENT_EVENT_LIMIT}")

    def test_normalization_backfill_updates_legacy_itemized_events_and_removes_quest_duplicates(self):
        EVENTS.add_event(
            self.connection,
            fingerprint="save:legacy:craft",
            occurred_at="2026-07-13T10:00:00-04:00",
            event_type="craft",
            player="Galyk",
            title="Fabrication terminée",
            message="Galyk fabrique 5 Bois.",
            source="save",
            details={
                "headline": "Fabrication terminée",
                "body": "Galyk fabrique 5 Bois.",
                "bullets": ["+5 Bois"],
                "items": [{"name": "Bois", "added": 5, "count": 15}],
                "total": 15,
            },
        )
        EVENTS.add_event(
            self.connection,
            fingerprint="save:legacy:production",
            occurred_at="2026-07-13T10:01:00-04:00",
            event_type="production",
            player="Brian",
            guild="Explorateurs",
            base="Atelier du nord",
            title="Production terminée",
            message="Brian termine une nouvelle chaîne de production: 40 Lingot.",
            source="save",
            details={
                "headline": "Brian termine une nouvelle chaîne de production",
                "body": "40 ressources confirmées dans les tampons de production.",
                "bullets": ["+40 Lingot"],
                "items": [{"name": "Lingot", "added": 40, "count": 180}],
            },
        )
        for index in range(2):
            EVENTS.add_event(
                self.connection,
                fingerprint=f"save:legacy:quest:{index}",
                occurred_at=f"2026-07-13T10:0{2 + index}:00-04:00",
                event_type="quest",
                player="Sprince",
                title="Quête terminée",
                message="Sprince termine Mission de l'éleveur · chapitre 1.",
                source="save",
            )
        EVENTS.add_event(
            self.connection,
            fingerprint="save:2026-07-13T10:03:00-04:00:capture:alyross:prunelia:17",
            occurred_at="2026-07-13T10:03:00-04:00",
            event_type="capture",
            player="Alyross",
            title="Capture réussie",
            message="Alyross capture 1 Prunelia. Total enregistré: 17.",
            source="save",
        )
        EVENTS.add_event(
            self.connection,
            fingerprint="save:2026-07-13T10:04:00-04:00:capture:alyross:prunelia:26",
            occurred_at="2026-07-13T10:04:00-04:00",
            event_type="capture",
            player="Alyross",
            title="Capture réussie",
            message="Alyross capture 9 Prunelia. Total enregistré: 26.",
            source="save",
        )
        EVENTS.add_event(
            self.connection,
            fingerprint="save:2026-07-13T11:00:00-04:00:capture:alyross:prunelia:26",
            occurred_at="2026-07-13T11:00:00-04:00",
            event_type="capture",
            player="Alyross",
            title="Capture réussie",
            message="Alyross capture 24 Prunelia. Total enregistré: 26.",
            source="save",
        )
        EVENTS.add_event(
            self.connection,
            fingerprint="save:2026-07-13T12:00:00-04:00:capture:alyross:shroomer noct:2",
            occurred_at="2026-07-13T12:00:00-04:00",
            event_type="capture",
            player="Alyross",
            title="Première capture",
            message="Alyross inscrit Shroomer Noct dans son Paldex avec 2 captures.",
            source="save",
        )
        EVENTS.add_event(
            self.connection,
            fingerprint="save:2026-07-13T12:05:00-04:00:capture:alyross:shroomer noct:4",
            occurred_at="2026-07-13T12:05:00-04:00",
            event_type="capture",
            player="Alyross",
            title="Capture réussie",
            message="Alyross capture 1 Shroomer Noct. Total enregistré: 4.",
            source="save",
        )

        report = EVENTS.normalize_event_history(self.connection)
        second_report = EVENTS.normalize_event_history(self.connection)

        self.assertEqual(report["itemizedUpdated"], 2)
        self.assertEqual(report["duplicatesRemoved"], 1)
        self.assertEqual(report["captureDuplicatesRemoved"], 1)
        self.assertEqual(report["captureMessagesUpdated"], 2)
        self.assertEqual(second_report["itemizedUpdated"], 0)
        self.assertEqual(second_report["duplicatesRemoved"], 0)
        self.assertEqual(second_report["captureDuplicatesRemoved"], 0)
        self.assertEqual(second_report["captureMessagesUpdated"], 0)

        rows = self.connection.execute(
            "SELECT type, message, details_json FROM events ORDER BY occurred_at, id"
        ).fetchall()
        self.assertEqual(
            [row["type"] for row in rows],
            ["craft", "production", "quest", "capture", "capture", "capture", "capture"],
        )
        self.assertEqual(
            rows[0]["message"],
            "Galyk termine 5 fabrications. Total cumulé: 15.",
        )
        self.assertEqual(
            rows[1]["message"],
            "Brian termine une production à Atelier du nord. "
            "40 ressources produites sont prêtes. Stock de production actuel: 180.",
        )
        production_details = json.loads(rows[1]["details_json"])
        self.assertEqual(production_details["total"], 180)
        self.assertEqual(
            rows[2]["message"],
            "Sprince termine Mission de l'éleveur · chapitre 1.",
        )
        self.assertEqual(
            rows[3]["message"],
            "Alyross inscrit Prunelia dans son Paldex avec 17 captures.",
        )
        self.assertEqual(
            rows[4]["message"],
            "Alyross capture 9 Prunelia. Total enregistré: 26.",
        )
        self.assertEqual(
            rows[6]["message"],
            "Alyross capture 2 Shroomer Noct. Total enregistré: 4.",
        )

    def test_base_label_backfill_updates_identifiable_server_numbered_bases(self):
        EVENTS.add_event(
            self.connection,
            fingerprint="save:legacy:build:base6",
            occurred_at="2026-07-13T10:00:00-04:00",
            event_type="build",
            player="Mathieu",
            guild="Spartans",
            base="Base 6 · Spartans",
            title="Base agrandie",
            message="Mathieu agrandit Base 6 · Spartans. 2 nouvelles structures confirmées.",
            source="save",
            details={
                "headline": "Mathieu agrandit Base 6 · Spartans",
                "body": "De nouvelles structures sont confirmées dans la sauvegarde.",
            },
        )
        bases_payload = {
            "ok": True,
            "bases": [
                {"name": "Base 6 · Spartans", "guild": "Spartans", "players": ["Mathieu"]},
                {"name": "Base 17 · Spartans", "guild": "Spartans", "players": ["Mathieu"]},
            ],
        }

        report = EVENTS.normalize_base_labels(self.connection, bases_payload)
        second_report = EVENTS.normalize_base_labels(self.connection, bases_payload)

        self.assertEqual(report["updated"], 1)
        self.assertEqual(second_report["updated"], 0)
        row = self.connection.execute(
            "SELECT base, message, details_json FROM events"
        ).fetchone()
        self.assertEqual(row["base"], "Base 1")
        self.assertEqual(
            row["message"],
            "Mathieu agrandit Base 1. 2 nouvelles structures confirmées.",
        )
        details = json.loads(row["details_json"])
        self.assertEqual(details["headline"], "Mathieu agrandit Base 1")
        self.assertEqual(details["rawBaseName"], "Base 6 · Spartans")


if __name__ == "__main__":
    unittest.main()
