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

    def test_public_structured_event_masks_literal_ip_and_url(self):
        EVENTS.add_event(
            self.connection,
            fingerprint="journal:sensitive-update",
            occurred_at="2026-07-13T12:00:00-04:00",
            event_type="maintenance",
            title="Maintenance sur 10.23.45.67",
            message="Détails privés: https://10.23.45.67/admin",
            source="update",
        )
        row = self.connection.execute("SELECT * FROM events").fetchone()
        self.assertIn("10.23.45.67", row["message"])
        exported = EVENTS.public_event(row)
        encoded = json.dumps(exported, ensure_ascii=False)
        self.assertNotIn("10.23.45.67", encoded)
        self.assertNotIn("https://", encoded)
        self.assertIn("masqué", encoded)

    def test_json_formatted_palworld_log_is_parsed_before_text_patterns(self):
        fixture = self.root / "journal-json.jsonl"
        fixture.write_text(json.dumps({
            "__CURSOR": "json-log-1",
            "__REALTIME_TIMESTAMP": "1783958400000000",
            "MESSAGE": json.dumps({
                "timestamp": "2026-07-13T12:34:56-04:00",
                "message": "[2026.07.13-16.34.56] [LOG] Galyk joined the server.",
                "level": "Log",
            }),
        }) + "\n", encoding="utf-8")

        EVENTS.collect_journal(self.connection, fixture)

        row = self.connection.execute(
            "SELECT occurred_at, type, player FROM events"
        ).fetchone()
        self.assertEqual(row["occurred_at"], "2026-07-13T12:34:56-04:00")
        self.assertEqual(row["type"], "join")
        self.assertEqual(row["player"], "Galyk")


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

    def test_world_progress_requires_two_distinct_snapshot_observations(self):
        old = player_state(records={
            "normalDungeonsCleared": 0,
            "fixedDungeonsCleared": 0,
            "oilRigsCleared": 0,
            "campsConquered": 0,
        })
        new = player_state(records={
            "normalDungeonsCleared": 1,
            "fixedDungeonsCleared": 0,
            "oilRigsCleared": 1,
            "campsConquered": 0,
        })
        EVENTS.compare_enriched_progress(
            self.connection,
            old,
            new,
            "2026-07-12T18:00:00-04:00",
            "aventuriere",
            observation_at="2026-07-12T18:00:05-04:00",
        )
        self.assertEqual(
            self.connection.execute("SELECT COUNT(*) FROM events WHERE type = 'adventure'").fetchone()[0],
            0,
        )
        EVENTS.compare_enriched_progress(
            self.connection,
            new,
            new,
            "2026-07-12T18:01:00-04:00",
            "aventuriere",
            observation_at="2026-07-12T18:01:05-04:00",
        )
        row = self.connection.execute(
            "SELECT message, details_json FROM events WHERE type = 'adventure'"
        ).fetchone()
        self.assertIn("1 donjon aléatoire", row["message"])
        self.assertIn("1 plateforme pétrolière", row["message"])
        details = json.loads(row["details_json"])
        self.assertEqual(details["confirmationSnapshots"], 2)

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
        self.assertNotIn("position", rows[0]["details_json"])
        self.assertNotIn("mapX", rows[0]["details_json"])
        public_rows = [EVENTS.public_event(row) for row in self.connection.execute(
            "SELECT * FROM events ORDER BY id"
        ).fetchall()]
        self.assertNotIn("position", json.dumps(public_rows, ensure_ascii=False))

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
                    "structureStates": {
                        "structure_wall_1": {"name": "Mur", "damaged": True},
                        "structure_wall_2": {"name": "Mur", "damaged": True},
                        "structure_removed": {"name": "Mur", "damaged": True},
                    },
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
                    "structureStates": {
                        "structure_wall_1": {"name": "Mur", "damaged": False},
                        "structure_wall_2": {"name": "Mur", "damaged": False},
                        "structure_new_damage": {"name": "Mur", "damaged": True},
                    },
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
        self.assertEqual([row["type"] for row in rows], ["build", "production", "repair"])
        self.assertTrue(all(row["player"] == "Mathieu" for row in rows))
        self.assertTrue(all(row["base"] == "Base principale" for row in rows))
        self.assertNotIn("guid", "\n".join(row["details_json"] or "" for row in rows).lower())
        production = next(row for row in rows if row["type"] == "production")
        self.assertIn("Stock de production observé à Base principale", production["message"])
        self.assertIn("30 ressources supplémentaires sont observées", production["message"])
        self.assertIn("Stock actuel: 40", production["message"])
        production_details = json.loads(production["details_json"])
        self.assertEqual(
            production_details["body"],
            "30 ressources supplémentaires sont observées. Stock actuel: 40.",
        )
        self.assertIn("+30 Lingot", production_details["bullets"])
        self.assertEqual(production_details["total"], 40)

    def test_level_business_key_is_idempotent_across_live_and_backfill_times(self):
        previous = {"players": {"player_alpha": player_state(key="player_alpha", activityKey="aventuriere")}}
        current = {"players": {"player_alpha": player_state(
            key="player_alpha",
            activityKey="aventuriere",
            level=11,
        )}}

        EVENTS.compare_snapshots(
            self.connection,
            previous,
            current,
            "2026-07-12T18:00:00-04:00",
            {"player_alpha"},
        )
        EVENTS.compare_snapshots(
            self.connection,
            previous,
            current,
            "2026-07-12T19:00:00-04:00",
            {"player_alpha"},
        )

        rows = self.connection.execute(
            "SELECT fingerprint, occurred_at FROM events WHERE type = 'level'"
        ).fetchall()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["fingerprint"], "save:level:player_alpha:11")

    def test_base_and_production_business_keys_ignore_replay_time(self):
        previous = {
            "bases": {
                "guild::base": {
                    "name": "Base 1",
                    "guild": "Explorateurs",
                    "players": ["Alex"],
                    "structuresTotal": 10,
                    "structuresDamaged": 0,
                    "structureHighlights": {"mur": {"name": "Mur", "count": 10}},
                    "structureStates": {},
                    "productionItems": {"lingot": {"name": "Lingot", "count": 2}},
                }
            }
        }
        current = {
            "bases": {
                "guild::base": {
                    "name": "Base 1",
                    "guild": "Explorateurs",
                    "players": ["Alex"],
                    "structuresTotal": 11,
                    "structuresDamaged": 0,
                    "structureHighlights": {"mur": {"name": "Mur", "count": 11}},
                    "structureStates": {},
                    "productionItems": {"lingot": {"name": "Lingot", "count": 4}},
                }
            }
        }
        EVENTS.compare_base_events(
            self.connection, previous, current, "2026-07-12T18:00:00-04:00"
        )
        EVENTS.compare_base_events(
            self.connection, previous, current, "2026-07-12T19:00:00-04:00"
        )
        rows = self.connection.execute(
            "SELECT type, fingerprint FROM events WHERE type IN ('build', 'production') ORDER BY type"
        ).fetchall()
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["fingerprint"], "save:build:guild::base:11")
        self.assertTrue(rows[1]["fingerprint"].startswith("save:production:guild::base:"))

    def test_equal_player_names_keep_distinct_public_identities(self):
        previous = EVENTS.snapshot_state({
            "players": [
                {"key": "player_alpha", "name": "Alex", "level": 10, "pals": {}, "progress": {}},
                {"key": "player_beta", "name": "Alex", "level": 20, "pals": {}, "progress": {}},
            ]
        })
        current = EVENTS.snapshot_state({
            "players": [
                {"key": "player_alpha", "name": "Alex", "level": 11, "pals": {}, "progress": {}},
                {"key": "player_beta", "name": "Alex", "level": 21, "pals": {}, "progress": {}},
            ]
        })

        EVENTS.compare_snapshots(
            self.connection,
            previous,
            current,
            "2026-07-12T18:00:00-04:00",
            {"player_alpha", "player_beta"},
        )

        rows = self.connection.execute(
            "SELECT fingerprint FROM events WHERE type = 'level' ORDER BY fingerprint"
        ).fetchall()
        self.assertEqual(
            [row["fingerprint"] for row in rows],
            ["save:level:player_alpha:11", "save:level:player_beta:21"],
        )

    def test_guild_research_is_emitted_once_with_derived_player_attribution(self):
        previous = {
            "guildResearch": {
                "guild_spartans": {
                    "key": "guild_spartans",
                    "guild": "Spartans",
                    "players": ["Mathieu", "Galyk", "Brian"],
                    "completed": 2,
                }
            }
        }
        current = {
            "guildResearch": {
                "guild_spartans": {
                    "key": "guild_spartans",
                    "guild": "Spartans",
                    "players": ["Mathieu", "Galyk", "Brian"],
                    "completed": 3,
                }
            }
        }

        EVENTS.compare_guild_research_events(
            self.connection,
            previous,
            current,
            "2026-07-12T18:00:00-04:00",
            {"galyk": "2026-07-12T17:59:30-04:00"},
        )
        EVENTS.compare_guild_research_events(
            self.connection,
            previous,
            current,
            "2026-07-12T19:00:00-04:00",
            {"galyk": "2026-07-12T18:59:30-04:00"},
        )

        rows = self.connection.execute(
            "SELECT fingerprint, player, base, confidence FROM events WHERE type = 'research'"
        ).fetchall()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["fingerprint"], "save:research:guild_spartans:3")
        self.assertEqual(rows[0]["player"], "Galyk")
        self.assertIsNone(rows[0]["base"])
        self.assertEqual(rows[0]["confidence"], "derived")

    def test_repair_requires_same_stable_structure_and_ignores_disappearance(self):
        base = {
            "name": "Base principale",
            "guild": "Spartans",
            "players": ["Mathieu"],
            "structuresTotal": 2,
            "structuresDamaged": 2,
            "structureHighlights": {},
            "productionItems": {},
            "researchCompleted": 0,
            "structureStates": {
                "structure_repaired": {"name": "Mur", "damaged": True},
                "structure_destroyed": {"name": "Mur", "damaged": True},
            },
        }
        current_base = {
            **base,
            "structuresTotal": 1,
            "structuresDamaged": 0,
            "structureStates": {
                "structure_repaired": {"name": "Mur", "damaged": False},
            },
        }
        previous = {"bases": {"spartans::base": base}}
        current = {"bases": {"spartans::base": current_base}}

        EVENTS.compare_base_events(
            self.connection,
            previous,
            current,
            "2026-07-12T18:00:00-04:00",
        )
        EVENTS.compare_base_events(
            self.connection,
            previous,
            current,
            "2026-07-12T19:00:00-04:00",
        )

        rows = self.connection.execute(
            "SELECT details_json FROM events WHERE type = 'repair'"
        ).fetchall()
        self.assertEqual(len(rows), 1)
        details = json.loads(rows[0]["details_json"])
        self.assertEqual(details["structureKeys"], ["structure_repaired"])
        self.assertNotIn("structure_destroyed", rows[0]["details_json"])

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
        row = self.connection.execute(
            "SELECT type, title, message, details_json FROM events"
        ).fetchone()
        self.assertEqual(row["type"], "base")
        self.assertEqual(row["title"], "Base endommagée")
        self.assertIn("3 structures endommagées en plus", row["message"])
        details = json.loads(row["details_json"])
        self.assertEqual(details["damagedTotal"], 4)
        self.assertIn("+3 structures endommagées", details["bullets"])

    def test_base_state_ignores_world_drop_structure_highlights(self):
        state = EVENTS.base_state({
            "name": "Base 1",
            "guild": "Spartans",
            "structures": {
                "total": 5,
                "highlights": [
                    {"name": "Mur", "count": 2},
                    {"name": "CommonDropItem3D", "count": 3},
                ],
            },
        })

        self.assertEqual(state["structuresTotal"], 2)
        self.assertEqual(state["structureHighlights"], {"mur": {"name": "Mur", "count": 2}})

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
        self.assertEqual(row["fingerprint"], "save:level:aventuriere:11")

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

    def test_settings_changes_are_allowlisted_and_idempotent(self):
        stats = Path(self.temporary.name) / "stats.json"
        stats.write_text(json.dumps({
            "settings": {
                "updatedAt": "2026-07-12T18:00:00-04:00",
                "changes": [{
                    "observedAt": "2026-07-12T18:00:00-04:00",
                    "digest": "rules-1",
                    "fields": {
                        "ExpRate": {"before": 1, "after": 1.5},
                        "PalEggDefaultHatchingTime": {"before": 72, "after": 24},
                        "bEnableFastTravel": {"before": True, "after": False},
                        "PublicIP": {"before": "private", "after": "still-private"},
                    },
                }],
            }
        }), encoding="utf-8")

        self.assertEqual(EVENTS.collect_settings_changes(self.connection, stats), 1)
        self.assertEqual(EVENTS.collect_settings_changes(self.connection, stats), 0)

        row = self.connection.execute(
            "SELECT fingerprint, type, source, confidence, message, details_json FROM events"
        ).fetchone()
        self.assertEqual(row["fingerprint"], "settings:rules-1")
        self.assertEqual((row["type"], row["source"], row["confidence"]), (
            "settings", "server", "confirmed",
        ))
        details = json.loads(row["details_json"])
        self.assertEqual(set(EVENTS.PUBLIC_SETTINGS_LABELS), EVENTS.PUBLIC_SETTINGS_FIELDS)
        self.assertEqual(set(details["fields"]), {
            "ExpRate",
            "PalEggDefaultHatchingTime",
            "bEnableFastTravel",
        })
        self.assertNotIn("PublicIP", row["details_json"])
        self.assertEqual(details["bullets"], [
            "Durée d'incubation des œufs: 72 → 24",
            "Gain d'expérience: 1 → 1.5",
            "Voyage rapide: activé → désactivé",
        ])
        for machine_key in details["fields"]:
            self.assertNotIn(machine_key, row["message"])
            self.assertTrue(all(machine_key not in bullet for bullet in details["bullets"]))
        self.assertIn("durée d'incubation des œufs", row["message"].casefold())
        self.assertIn("gain d'expérience", row["message"].casefold())
        self.assertIn("voyage rapide", row["message"].casefold())


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

    def write_rolling_archive(self, filename, payload):
        path = self.history / "_rolling" / "2026" / "07" / "12" / f"{filename}.json.gz"
        path.parent.mkdir(parents=True, exist_ok=True)
        with gzip.open(path, "wt", encoding="utf-8") as stream:
            json.dump(payload, stream)

    def write_bases_archive(self, hour, payload):
        path = self.bases_history / "2026" / "07" / "12" / f"{hour}.json.gz"
        path.parent.mkdir(parents=True, exist_ok=True)
        with gzip.open(path, "wt", encoding="utf-8") as stream:
            json.dump(payload, stream)

    def test_rolling_archive_hour_is_used_by_watermark_filter(self):
        older = self.history / "_rolling" / "2026" / "07" / "12" / "095959-000001.json.gz"
        current = self.history / "_rolling" / "2026" / "07" / "12" / "100001-000001.json.gz"
        for path in (older, current):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"")

        paths = EVENTS.history_paths_since(self.history, "2026-07-12T10:00:00-04:00")

        self.assertEqual(paths, [current])
        self.assertEqual(EVENTS.archive_hour_key(current, self.history), "2026/07/12/10")

    def test_fifteen_minute_collection_gap_is_rebuilt_once_from_rolling_snapshots(self):
        initial = snapshot_payload("2026-07-12T10:00:00-04:00", 10)
        EVENTS.metadata_set(self.connection, "save_state", EVENTS.snapshot_state(initial))
        EVENTS.metadata_set(self.connection, "last_save_at", initial["updatedAt"])
        EVENTS.metadata_set(self.connection, "projection_watermark", initial["updatedAt"])
        EVENTS.metadata_set(self.connection, "known_players", ["aventuriere"])
        self.connection.commit()

        self.write_rolling_archive(
            "100500-000001",
            snapshot_payload("2026-07-12T10:05:00-04:00", 11),
        )
        self.write_rolling_archive(
            "101000-000002",
            snapshot_payload("2026-07-12T10:10:00-04:00", 12),
        )
        self.snapshot.write_text(
            json.dumps(snapshot_payload("2026-07-12T10:15:00-04:00", 13)),
            encoding="utf-8",
        )

        first = EVENTS.collect_snapshots(self.connection, self.snapshot, self.history)
        self.connection.commit()
        output = self.root / "public-events.json"
        recent = self.root / "public-events-recent.json"
        EVENTS.write_export(self.connection, output, recent)
        first_public = json.loads(recent.read_text(encoding="utf-8"))

        second = EVENTS.collect_snapshots(self.connection, self.snapshot, self.history)
        self.connection.commit()
        second_export = EVENTS.write_export(self.connection, output, recent)
        second_public = json.loads(recent.read_text(encoding="utf-8"))

        self.assertEqual(first["gapSeconds"], 15 * 60)
        self.assertEqual(first["archives"]["imported"], 2)
        self.assertEqual(first["events"]["added"], 3)
        self.assertEqual(second["archives"]["imported"], 0)
        self.assertEqual(second["events"]["added"], 0)
        self.assertEqual(second_export["status"], "unchanged")
        self.assertEqual(first_public, second_public)
        levels = [event for event in first_public["events"] if event["type"] == "level"]
        self.assertEqual(len(levels), 3)
        self.assertEqual(len({event["key"] for event in levels}), 3)
        self.assertEqual(
            [event["message"] for event in reversed(levels)],
            [
                "Aventuriere atteint le niveau 11.",
                "Aventuriere atteint le niveau 12.",
                "Aventuriere atteint le niveau 13.",
            ],
        )

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

    def test_public_order_uses_absolute_time_across_toronto_fall_back(self):
        EVENTS.add_event(
            self.connection,
            fingerprint="server:before-fall-back",
            occurred_at="2026-11-01T01:30:00-04:00",
            event_type="server",
            title="Avant le recul",
            message="05:30 UTC.",
            source="journal",
        )
        EVENTS.add_event(
            self.connection,
            fingerprint="server:after-fall-back",
            occurred_at="2026-11-01T01:15:00-05:00",
            event_type="server",
            title="Après le recul",
            message="06:15 UTC.",
            source="journal",
        )

        events, reconnects = self.public_events()

        self.assertEqual(reconnects, 0)
        self.assertEqual(
            [event["title"] for event in events],
            ["Après le recul", "Avant le recul"],
        )

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
            fingerprint="save:capture:kingpaca",
            occurred_at="2026-07-13T10:02:45-04:00",
            event_type="capture",
            player="Alyross",
            title="Première capture",
            message="Alyross capture Kingpaca pour la première fois.",
            icon="kingpaca.webp",
            source="save",
            details={"pals": [{"name": "Kingpaca", "count": 1, "icon": "kingpaca.webp"}]},
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
        self.assertEqual([event["type"] for event in events], ["craft", "activity", "capture"])
        self.assertEqual(events[0]["title"], "Fabrications terminées")
        activity = events[1]
        capture = events[2]
        self.assertEqual(activity["title"], "Activité relevée")
        self.assertIn("Alyross relève 11 fabrications terminées et 12 ressources produites", activity["message"])
        self.assertIn("Bases touchées: Base 1 et Base 2", activity["message"])
        self.assertNotIn("sur 5 min", activity["message"])
        self.assertEqual(activity["details"]["aggregatedEvents"], 4)
        self.assertEqual(activity["details"]["types"], ["craft", "production"])
        categories = {category["type"]: category for category in activity["details"]["categories"]}
        self.assertEqual(categories["craft"]["added"], 11)
        self.assertEqual(categories["production"]["added"], 12)
        self.assertEqual(activity["details"]["bases"], ["Base 1", "Base 2"])
        self.assertIn("+7 Bois", activity["details"]["bullets"])
        self.assertIn("+7 Salade", activity["details"]["bullets"])
        self.assertIn("+5 Lingot", activity["details"]["bullets"])
        self.assertIn("+4 Pierre", activity["details"]["bullets"])
        self.assertEqual(capture["title"], "Première capture")

    def test_public_export_hides_derived_production_when_craft_reports_same_items(self):
        EVENTS.add_event(
            self.connection,
            fingerprint="save:craft:flour",
            occurred_at="2026-07-13T10:00:00-04:00",
            event_type="craft",
            player="Brian",
            title="Fabrications terminées",
            message="Brian termine 5 fabrications. Total cumulé: 25.",
            icon="flour.webp",
            source="save",
            details={
                "bullets": ["+5 Flour"],
                "items": [{"name": "Flour", "asset": "flour", "added": 5, "count": 25, "icon": "flour.webp"}],
                "total": 25,
            },
        )
        EVENTS.add_event(
            self.connection,
            fingerprint="save:production:flour",
            occurred_at="2026-07-13T10:00:00-04:00",
            event_type="production",
            player="Brian",
            guild="PalaPaly",
            base="Base 1",
            title="Stock de production observé",
            message="Brian relève 5 ressources produites à Base 1. Stock observé: 80.",
            icon="flour.webp",
            source="save",
            confidence="derived",
            details={
                "bullets": ["+5 Flour"],
                "items": [{"name": "Flour", "asset": "flour", "added": 5, "count": 80, "icon": "flour.webp"}],
                "total": 80,
            },
        )

        events, reconnects = self.public_events()

        self.assertEqual(reconnects, 0)
        self.assertEqual([event["type"] for event in events], ["craft"])
        self.assertEqual(events[0]["message"], "Brian termine 5 fabrications. Total cumulé: 25.")

    def test_public_export_groups_fishing_into_five_minute_windows(self):
        EVENTS.add_event(
            self.connection,
            fingerprint="save:fishing:1",
            occurred_at="2026-07-13T10:00:10-04:00",
            event_type="fishing",
            player="Alyross",
            title="Pêche fructueuse",
            message="Alyross ramène 2 prises de pêche. Total cumulé: 7.",
            icon="fish.webp",
            source="save",
            details={
                "bullets": ["+2 Kelpsea"],
                "items": [{"name": "Kelpsea", "asset": "kelpsea", "added": 2, "count": 7, "icon": "fish.webp"}],
                "total": 7,
            },
        )
        EVENTS.add_event(
            self.connection,
            fingerprint="save:fishing:2",
            occurred_at="2026-07-13T10:04:59-04:00",
            event_type="fishing",
            player="Alyross",
            title="Prise de pêche",
            message="Alyross ramène 1 prise de pêche. Total cumulé: 8.",
            icon="fish.webp",
            source="save",
            details={
                "bullets": ["+1 Kelpsea"],
                "items": [{"name": "Kelpsea", "asset": "kelpsea", "added": 1, "count": 8, "icon": "fish.webp"}],
                "total": 8,
            },
        )
        EVENTS.add_event(
            self.connection,
            fingerprint="save:fishing:3",
            occurred_at="2026-07-13T10:06:00-04:00",
            event_type="fishing",
            player="Alyross",
            title="Pêche fructueuse",
            message="Alyross ramène 3 prises de pêche. Total cumulé: 11.",
            icon="fish.webp",
            source="save",
            details={
                "bullets": ["+3 Kelpsea"],
                "items": [{"name": "Kelpsea", "asset": "kelpsea", "added": 3, "count": 11, "icon": "fish.webp"}],
                "total": 11,
            },
        )

        events, reconnects = self.public_events()

        self.assertEqual(reconnects, 0)
        self.assertEqual([event["title"] for event in events], ["Pêche fructueuse", "Pêche ramenée"])
        grouped = events[1]
        self.assertIn("Alyross ramène 3 prises de pêche", grouped["message"])
        self.assertNotIn("sur 5 min", grouped["message"])
        self.assertIn("Total cumulé: 8", grouped["message"])
        self.assertEqual(grouped["details"]["aggregatedEvents"], 2)
        self.assertEqual(grouped["details"]["total"], 8)
        self.assertEqual(grouped["details"]["bullets"], ["+3 Kelpsea"])

    def test_public_export_groups_base_activity_into_five_minute_windows(self):
        samples = [
            (
                "save:build:1",
                "2026-07-13T10:01:00-04:00",
                "build",
                "Base agrandie",
                "Alyross agrandit Base 1. 2 nouvelles structures confirmées.",
                {
                    "bullets": ["+2 Mur"],
                    "structures": [{"name": "Mur", "asset": "wall", "added": 2, "count": 12}],
                    "total": 12,
                },
            ),
            (
                "save:repair:1",
                "2026-07-13T10:02:00-04:00",
                "repair",
                "Réparations confirmées",
                "Alyross remet Base 1 en état: 1 structure réparée.",
                {"bullets": ["-1 structure endommagée"]},
            ),
            (
                "save:base-damage:1",
                "2026-07-13T10:02:30-04:00",
                "base",
                "Base endommagée",
                "Alyross constate des dégâts à Base 1: 2 structures endommagées en plus.",
                {"bullets": ["+2 structures endommagées"], "damagedTotal": 2},
            ),
            (
                "save:research:1",
                "2026-07-13T10:03:00-04:00",
                "research",
                "Recherche terminée",
                "Alyross fait progresser la recherche de guilde: 1 recherche confirmée.",
                {"bullets": ["+1 recherche"]},
            ),
            (
                "save:repair:2",
                "2026-07-13T10:03:20-04:00",
                "repair",
                "Réparations confirmées",
                "Alyross remet Base 1 en état: 2 structures réparées.",
                {"bullets": ["-2 structures endommagées"]},
            ),
            (
                "save:build:2",
                "2026-07-13T10:03:40-04:00",
                "build",
                "Base agrandie",
                "Alyross agrandit Base 1. 3 nouvelles structures confirmées.",
                {
                    "bullets": ["+3 Fondation"],
                    "structures": [{"name": "Fondation", "asset": "foundation", "added": 3, "count": 3}],
                    "total": 15,
                },
            ),
            (
                "save:base-damage:2",
                "2026-07-13T10:04:00-04:00",
                "base",
                "Base endommagée",
                "Alyross constate des dégâts à Base 1: 1 structure endommagée en plus.",
                {"bullets": ["+1 structure endommagée"], "damagedTotal": 3},
            ),
            (
                "save:research:2",
                "2026-07-13T10:04:30-04:00",
                "research",
                "Recherche terminée",
                "Alyross fait progresser la recherche de guilde: 2 recherches confirmées.",
                {"bullets": ["+2 recherches"]},
            ),
        ]
        for fingerprint, occurred_at, event_type, title, message, details in samples:
            EVENTS.add_event(
                self.connection,
                fingerprint=fingerprint,
                occurred_at=occurred_at,
                event_type=event_type,
                player="Alyross",
                guild="PalaPaly",
                base="Base 1",
                title=title,
                message=message,
                source="save",
                details=details,
            )

        events, reconnects = self.public_events()

        self.assertEqual(reconnects, 0)
        by_type = {event["type"]: event for event in events}
        self.assertEqual(set(by_type), {"build", "repair", "base", "research"})
        self.assertEqual(by_type["build"]["title"], "Base agrandie")
        self.assertIn("Alyross ajoute 5 structures à Base 1", by_type["build"]["message"])
        self.assertNotIn("sur 5 min", by_type["build"]["message"])
        self.assertEqual(by_type["build"]["details"]["aggregatedEvents"], 2)
        self.assertEqual(by_type["build"]["details"]["total"], 15)
        self.assertIn("+3 Fondation", by_type["build"]["details"]["bullets"])
        self.assertEqual(by_type["repair"]["title"], "Réparations terminées")
        self.assertIn("Alyross remet 3 structures en état à Base 1", by_type["repair"]["message"])
        self.assertEqual(by_type["base"]["title"], "État de base relevé")
        self.assertIn("Alyross relève 3 structures endommagées à Base 1", by_type["base"]["message"])
        research_events = [event for event in events if event["type"] == "research"]
        self.assertEqual(len(research_events), 2)
        self.assertEqual(
            {event["details"]["total"] for event in research_events},
            {1, 2},
        )
        for event in research_events:
            total = event["details"]["total"]
            self.assertEqual(event["title"], "Recherche de guilde terminée")
            self.assertIn(f"La guilde PalaPaly compte désormais {total}", event["message"])
            self.assertEqual(event["player"], "Alyross")
            self.assertIsNone(event["base"])
            self.assertEqual(event["confidence"], "derived")

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

    def test_player_session_aliases_are_repaired_with_current_display_name(self):
        EVENTS.add_event(
            self.connection,
            fingerprint="players:join:steam_1:2026-07-13T10:00:00-04:00",
            occurred_at="2026-07-13T10:00:00-04:00",
            event_type="join",
            player="gregorymercier97",
            title="Arrivée sur Palpagos",
            message="gregorymercier97 rejoint l'aventure.",
            source="players",
        )
        EVENTS.add_event(
            self.connection,
            fingerprint="journal:leave-alias",
            occurred_at="2026-07-13T11:00:00-04:00",
            event_type="leave",
            player="gregorymercier97",
            title="Fin d'expédition",
            message="gregorymercier97 quitte l'archipel pour l'instant.",
            source="journal",
        )
        stats = self.root / "stats.json"
        stats.write_text(json.dumps({
            "players": {
                "steam_1": {
                    "id": "steam_1",
                    "name": "Galyk",
                    "accountName": "gregorymercier97",
                    "userId": "steam_1",
                    "sessionHistory": [{
                        "startedAt": "2026-07-13T10:00:00-04:00",
                        "endedAt": "2026-07-13T11:00:00-04:00",
                    }],
                },
            },
        }), encoding="utf-8")

        self.assertEqual(EVENTS.collect_player_sessions(self.connection, stats), 0)
        rows = self.connection.execute(
            "SELECT type, player, message FROM events ORDER BY occurred_at"
        ).fetchall()

        self.assertEqual([row["player"] for row in rows], ["Galyk", "Galyk"])
        self.assertEqual(rows[0]["message"], "Galyk rejoint l'aventure.")
        self.assertEqual(
            rows[1]["message"],
            "Galyk quitte l'archipel pour l'instant.",
        )

    def test_player_sessions_accept_a_display_name_that_matches_the_account_name(self):
        stats = self.root / "stats.json"
        stats.write_text(json.dumps({
            "players": {
                "steam_1": {
                    "id": "steam_1",
                    "name": "DukeChicken",
                    "accountName": "DukeChicken",
                    "userId": "steam_1",
                    "sessionHistory": [{
                        "startedAt": "2026-07-13T10:00:00-04:00",
                        "endedAt": None,
                    }],
                },
            },
        }), encoding="utf-8")

        self.assertEqual(EVENTS.collect_player_sessions(self.connection, stats), 1)
        row = self.connection.execute("SELECT type, player FROM events").fetchone()
        self.assertEqual((row["type"], row["player"]), ("join", "DukeChicken"))

    def test_player_sessions_do_not_publish_a_structural_identifier(self):
        stats = self.root / "stats.json"
        stats.write_text(json.dumps({
            "players": {
                "steam_1": {
                    "id": "steam_1",
                    "name": "steam_1",
                    "accountName": "gregorymercier97",
                    "userId": "steam_1",
                    "sessionHistory": [{
                        "startedAt": "2026-07-13T10:00:00-04:00",
                        "endedAt": None,
                    }],
                },
            },
        }), encoding="utf-8")

        self.assertEqual(EVENTS.collect_player_sessions(self.connection, stats), 0)
        self.assertEqual(
            self.connection.execute("SELECT COUNT(*) FROM events").fetchone()[0],
            0,
        )

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
            """
            SELECT fingerprint, occurred_at FROM events
            WHERE NOT EXISTS (
                SELECT 1 FROM event_suppressions
                WHERE event_suppressions.event_id = events.id
            )
            ORDER BY occurred_at, id
            """
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
        report = EVENTS.write_export(self.connection, output, recent)

        payload = json.loads(output.read_text(encoding="utf-8"))
        recent_payload = json.loads(recent.read_text(encoding="utf-8"))
        self.assertFalse(payload["truncated"])
        self.assertEqual(report["status"], "written")
        self.assertEqual(payload["version"], 6)
        self.assertEqual(payload["schemaVersion"], 6)
        self.assertEqual(recent_payload["schemaVersion"], 6)
        self.assertEqual(payload["projection"], "canonical-echoes")
        self.assertEqual(payload["summary"]["events"], 6)
        self.assertEqual(payload["summary"]["totalEvents"], 6)
        self.assertEqual(payload["summary"]["rawEvents"], 6)
        self.assertEqual(payload["summary"]["echoes"], 6)
        self.assertEqual(payload["summary"]["representedEvents"], 6)
        self.assertEqual(payload["projectionWindow"], {
            "mode": "full",
            "replaceFrom": None,
            "complete": True,
            "fromProjectionRevision": None,
            "throughProjectionRevision": payload["projectionRevision"],
        })
        self.assertEqual([event["title"] for event in payload["events"]], [
            "Écho 5",
            "Écho 4",
            "Écho 3",
            "Écho 2",
            "Écho 1",
            "Écho 0",
        ])
        self.assertTrue(recent_payload["recent"])
        self.assertEqual(recent_payload["projectionWindow"], {
            "mode": "replace-tail",
            "replaceFrom": None,
            "complete": True,
            "fromProjectionRevision": None,
            "throughProjectionRevision": recent_payload["projectionRevision"],
        })
        self.assertEqual(recent_payload["summary"]["totalEvents"], 6)

    def test_materialized_projection_masks_ipv6_and_private_address_keys(self):
        EVENTS.add_event(
            self.connection,
            fingerprint="server:sensitive-ipv6",
            occurred_at="2026-07-13T10:00:00-04:00",
            event_type="server",
            player="2001:db8::2",
            title="Diagnostic sur 2001:db8::1",
            message="Adresse interne 2001:db8:0:1::42.",
            source="journal",
            details={
                "ip": "2001:db8::3",
                "ipAddress": "10.51.100.8",
                "address": "adresse interne",
                "serverHost": "palworld.internal",
                "safeNote": "Reprise depuis 2001:db8::4",
            },
        )
        output = self.root / "public-events.json"
        recent = self.root / "public-events-recent.json"
        EVENTS.write_export(self.connection, output, recent)

        materialized = self.connection.execute(
            "SELECT payload_json FROM public_event_projection"
        ).fetchone()["payload_json"]
        exported = output.read_text(encoding="utf-8")
        for payload in (materialized, exported):
            self.assertNotIn("2001:db8", payload)
            self.assertNotIn("10.51.100.8", payload)
            self.assertNotIn('"ip"', payload)
            self.assertNotIn('"ipAddress"', payload)
            self.assertNotIn('"address"', payload)
            self.assertNotIn('"serverHost"', payload)
            self.assertIn("adresse masquée", payload)

    def test_unchanged_canonical_export_is_not_rewritten(self):
        EVENTS.add_event(
            self.connection,
            fingerprint="server:stable",
            occurred_at="2026-07-13T10:00:00-04:00",
            event_type="server",
            title="Écho stable",
            message="Aucun changement.",
            source="journal",
        )
        output = self.root / "public-events.json"
        recent = self.root / "public-events-recent.json"

        first = EVENTS.write_export(self.connection, output, recent)
        output_mtime = output.stat().st_mtime_ns
        recent_mtime = recent.stat().st_mtime_ns
        second = EVENTS.write_export(self.connection, output, recent)

        self.assertEqual(first["status"], "written")
        self.assertEqual(second["status"], "unchanged")
        self.assertEqual(output.stat().st_mtime_ns, output_mtime)
        self.assertEqual(recent.stat().st_mtime_ns, recent_mtime)

    def test_historical_correction_waits_for_explicit_public_reprojection(self):
        EVENTS.add_event(
            self.connection,
            fingerprint="server:historical-correction",
            occurred_at="2026-07-13T10:00:00-04:00",
            event_type="server",
            title="Titre initial",
            message="Contenu initial.",
            source="journal",
        )
        output = self.root / "public-events.json"
        recent = self.root / "public-events-recent.json"
        EVENTS.write_export(self.connection, output, recent)
        first = json.loads(output.read_text(encoding="utf-8"))

        self.connection.execute(
            "UPDATE events SET title = ?, message = ? WHERE fingerprint = ?",
            ("Titre corrigé", "Contenu corrigé.", "server:historical-correction"),
        )
        report = EVENTS.write_export(self.connection, output, recent)
        unchanged = json.loads(output.read_text(encoding="utf-8"))

        self.assertEqual(report["status"], "reprojection-required")
        self.assertEqual(report["reason"], "mutation-of-materialized-event")
        self.assertEqual(unchanged, first)

        rebuilt = EVENTS.write_export(
            self.connection,
            output,
            recent,
            reproject_public=True,
        )
        second = json.loads(output.read_text(encoding="utf-8"))
        self.assertEqual(rebuilt["status"], "written")
        self.assertEqual(rebuilt["projectionSync"], "reprojected")
        self.assertEqual(first["summary"]["events"], second["summary"]["events"])
        self.assertEqual(first["events"][0]["id"], second["events"][0]["id"])
        self.assertGreater(second["projectionRevision"], first["projectionRevision"])
        self.assertNotEqual(second["revision"], first["revision"])
        self.assertEqual(second["events"][0]["title"], "Titre corrigé")

    def test_append_reconciles_only_a_bounded_tail(self):
        for index in range(60):
            EVENTS.add_event(
                self.connection,
                fingerprint=f"server:history:{index}",
                occurred_at=f"2026-07-13T{index // 60:02d}:{index % 60:02d}:00-04:00",
                event_type="server",
                title=f"Écho {index}",
                message=f"Message {index}",
                source="journal",
            )
        output = self.root / "public-events.json"
        recent = self.root / "public-events-recent.json"
        EVENTS.write_export(self.connection, output, recent)

        reconciled_sizes = []
        original = EVENTS.reconcile_public_events

        def tracked_reconcile(rows, *args, **kwargs):
            reconciled_sizes.append(len(rows))
            return original(rows, *args, **kwargs)

        EVENTS.reconcile_public_events = tracked_reconcile
        try:
            EVENTS.add_event(
                self.connection,
                fingerprint="server:append-only",
                occurred_at="2026-07-14T10:00:00-04:00",
                event_type="server",
                title="Nouvel écho",
                message="La queue seule est recalculée.",
                source="journal",
            )
            report = EVENTS.write_export(self.connection, output, recent)
        finally:
            EVENTS.reconcile_public_events = original

        self.assertEqual(report["status"], "written")
        self.assertEqual(report["projectionSync"], "appended")
        self.assertTrue(reconciled_sizes)
        self.assertLess(max(reconciled_sizes), 60)
        self.assertEqual(
            json.loads(recent.read_text(encoding="utf-8"))["events"][0]["title"],
            "Nouvel écho",
        )

    def test_hot_append_reads_limited_projection_and_keeps_full_export_cold(self):
        for index in range(12):
            EVENTS.add_event(
                self.connection,
                fingerprint=f"server:cold-full:{index}",
                occurred_at=f"2026-07-13T10:{index:02d}:00-04:00",
                event_type="server",
                title=f"Écho {index}",
                message=f"Message {index}",
                source="journal",
            )
        output = self.root / "public-events.json"
        recent = self.root / "public-events-recent.json"
        EVENTS.write_export(self.connection, output, recent, recent_limit=5)
        full_before = output.read_bytes()
        full_mtime = output.stat().st_mtime_ns
        recent_before = recent.read_bytes()

        loaded_limits = []
        original = EVENTS.materialized_public_events

        def tracked_materialized(connection, limit=None):
            loaded_limits.append(limit)
            return original(connection, limit)

        EVENTS.materialized_public_events = tracked_materialized
        try:
            EVENTS.add_event(
                self.connection,
                fingerprint="server:cold-full:append",
                occurred_at="2026-07-13T10:12:00-04:00",
                event_type="server",
                title="Append chaud",
                message="Seule la fenêtre récente change.",
                source="journal",
            )
            report = EVENTS.write_export(self.connection, output, recent, recent_limit=5)
        finally:
            EVENTS.materialized_public_events = original

        self.assertEqual(report["fullExport"], "deferred")
        self.assertEqual(report["recentExport"], "written")
        self.assertEqual(loaded_limits, [5])
        self.assertEqual(output.read_bytes(), full_before)
        self.assertEqual(output.stat().st_mtime_ns, full_mtime)
        self.assertNotEqual(recent.read_bytes(), recent_before)
        self.assertEqual(
            json.loads(recent.read_text(encoding="utf-8"))["events"][0]["title"],
            "Append chaud",
        )

    def test_forced_and_due_checkpoints_refresh_full_export(self):
        output = self.root / "public-events.json"
        recent = self.root / "public-events-recent.json"
        EVENTS.add_event(
            self.connection,
            fingerprint="server:checkpoint:first",
            occurred_at="2026-07-13T10:00:00-04:00",
            event_type="server",
            title="Premier",
            message="Premier checkpoint.",
            source="journal",
        )
        EVENTS.write_export(self.connection, output, recent)
        initial = output.read_bytes()
        EVENTS.add_event(
            self.connection,
            fingerprint="server:checkpoint:second",
            occurred_at="2026-07-13T10:10:00-04:00",
            event_type="server",
            title="Deuxième",
            message="Append différé.",
            source="journal",
        )
        EVENTS.write_export(self.connection, output, recent)
        self.assertEqual(output.read_bytes(), initial)

        forced = EVENTS.write_export(
            self.connection,
            output,
            recent,
            write_full_export=True,
        )
        self.assertEqual(forced["fullExport"], "written")
        forced_payload = output.read_bytes()
        self.assertNotEqual(forced_payload, initial)

        EVENTS.add_event(
            self.connection,
            fingerprint="server:checkpoint:third",
            occurred_at="2026-07-13T10:20:00-04:00",
            event_type="server",
            title="Troisième",
            message="Checkpoint arrivé à échéance.",
            source="journal",
        )
        due = EVENTS.write_export(
            self.connection,
            output,
            recent,
            full_export_interval_seconds=0,
        )
        self.assertEqual(due["fullExport"], "written")
        self.assertNotEqual(output.read_bytes(), forced_payload)
        self.assertEqual(
            json.loads(output.read_text(encoding="utf-8"))["summary"]["events"],
            3,
        )

    def test_append_rebuilds_open_bucket_and_tracks_all_echo_members(self):
        common = {
            "event_type": "craft",
            "player": "Alyross",
            "title": "Fabrication terminée",
            "source": "save",
        }
        EVENTS.add_event(
            self.connection,
            fingerprint="save:craft:first",
            occurred_at="2026-07-13T10:01:00-04:00",
            message="Alyross fabrique 2 Bois.",
            details={"items": [{"name": "Bois", "added": 2, "count": 2}]},
            **common,
        )
        output = self.root / "public-events.json"
        recent = self.root / "public-events-recent.json"
        EVENTS.write_export(self.connection, output, recent)
        standalone = json.loads(recent.read_text(encoding="utf-8"))
        standalone_key = standalone["events"][0]["key"]

        EVENTS.add_event(
            self.connection,
            fingerprint="save:craft:second",
            occurred_at="2026-07-13T10:02:00-04:00",
            message="Alyross fabrique 3 Bois.",
            details={"items": [{"name": "Bois", "added": 3, "count": 5}]},
            **common,
        )
        report = EVENTS.write_export(self.connection, output, recent)
        payload = json.loads(recent.read_text(encoding="utf-8"))

        self.assertEqual(report["projectionSync"], "appended")
        self.assertEqual(payload["summary"]["echoes"], 1)
        self.assertEqual(payload["summary"]["representedEvents"], 2)
        self.assertEqual(payload["events"][0]["details"]["aggregatedEvents"], 2)
        self.assertNotEqual(payload["events"][0]["key"], standalone_key)
        self.assertFalse(payload["truncated"])
        self.assertEqual(payload["projectionWindow"], {
            "mode": "replace-tail",
            "replaceFrom": "2026-07-13T10:00:00-04:00",
            "complete": True,
            "fromProjectionRevision": standalone["projectionRevision"],
            "throughProjectionRevision": payload["projectionRevision"],
        })
        members = self.connection.execute(
            "SELECT event_id FROM public_event_projection_members ORDER BY event_id"
        ).fetchall()
        self.assertEqual([int(row["event_id"]) for row in members], [1, 2])

    def test_recent_window_keeps_a_skipped_export_covered(self):
        output = self.root / "public-events.json"
        recent = self.root / "public-events-recent.json"

        def add_server_event(index, occurred_at):
            EVENTS.add_event(
                self.connection,
                fingerprint=f"server:revision-window:{index}",
                occurred_at=occurred_at,
                event_type="server",
                title=f"Écho {index}",
                message=f"Révision {index}.",
                source="journal",
            )
            EVENTS.write_export(self.connection, output, recent)
            return json.loads(recent.read_text(encoding="utf-8"))

        initial = add_server_event(1, "2026-07-13T10:00:00-04:00")
        first_delta = add_server_event(2, "2026-07-13T10:10:00-04:00")
        second_delta = add_server_event(3, "2026-07-13T10:20:00-04:00")

        self.assertEqual(
            first_delta["projectionWindow"]["fromProjectionRevision"],
            initial["projectionRevision"],
        )
        self.assertEqual(
            second_delta["projectionWindow"]["fromProjectionRevision"],
            initial["projectionRevision"],
        )
        self.assertEqual(
            second_delta["projectionWindow"]["throughProjectionRevision"],
            second_delta["projectionRevision"],
        )
        self.assertLessEqual(
            second_delta["projectionWindow"]["fromProjectionRevision"],
            initial["projectionRevision"],
        )
        self.assertLess(
            initial["projectionRevision"],
            second_delta["projectionWindow"]["throughProjectionRevision"],
        )

    def test_recent_window_resets_when_cumulative_boundary_leaves_hot_limit(self):
        output = self.root / "public-events.json"
        recent = self.root / "public-events-recent.json"

        def add_server_event(index, occurred_at):
            EVENTS.add_event(
                self.connection,
                fingerprint=f"server:rolling-reset:{index}",
                occurred_at=occurred_at,
                event_type="server",
                title=f"Écho {index}",
                message=f"Fenêtre {index}.",
                source="journal",
            )
            EVENTS.write_export(
                self.connection,
                output,
                recent,
                recent_limit=2,
            )
            return json.loads(recent.read_text(encoding="utf-8"))

        initial = add_server_event(1, "2026-07-13T10:00:00-04:00")
        first_delta = add_server_event(2, "2026-07-13T10:10:00-04:00")
        second_delta = add_server_event(3, "2026-07-13T10:20:00-04:00")

        self.assertTrue(second_delta["truncated"])
        self.assertTrue(second_delta["projectionWindow"]["complete"])
        self.assertEqual(
            second_delta["projectionWindow"]["fromProjectionRevision"],
            first_delta["projectionRevision"],
        )
        self.assertEqual(
            second_delta["projectionWindow"]["replaceFrom"],
            "2026-07-13T10:15:00-04:00",
        )
        self.assertLess(
            initial["projectionRevision"],
            second_delta["projectionWindow"]["fromProjectionRevision"],
        )

    def test_slightly_late_insert_inside_open_tail_is_incremental(self):
        output = self.root / "public-events.json"
        recent = self.root / "public-events-recent.json"
        EVENTS.add_event(
            self.connection,
            fingerprint="server:tail-latest",
            occurred_at="2026-07-13T10:10:00-04:00",
            event_type="server",
            title="Écho le plus récent",
            message="Premier passage.",
            source="journal",
        )
        EVENTS.write_export(self.connection, output, recent)

        EVENTS.add_event(
            self.connection,
            fingerprint="server:tail-late",
            occurred_at="2026-07-13T10:06:00-04:00",
            event_type="server",
            title="Écho arrivé en retard",
            message="Toujours dans la queue ouverte.",
            source="journal",
        )
        report = EVENTS.write_export(self.connection, output, recent)

        self.assertEqual(report["status"], "written")
        self.assertEqual(report["projectionSync"], "appended")
        self.assertEqual(
            [event["title"] for event in json.loads(
                recent.read_text(encoding="utf-8")
            )["events"]],
            ["Écho le plus récent", "Écho arrivé en retard"],
        )

    def test_projection_watermark_survives_collector_restart(self):
        output = self.root / "public-events.json"
        recent = self.root / "public-events-recent.json"
        EVENTS.add_event(
            self.connection,
            fingerprint="server:before-restart",
            occurred_at="2026-07-13T10:00:00-04:00",
            event_type="server",
            title="Avant la reprise",
            message="Projection persistée.",
            source="journal",
        )
        EVENTS.write_export(self.connection, output, recent)
        self.connection.close()
        self.connection = EVENTS.connect_database(self.root / "events.sqlite3")

        EVENTS.add_event(
            self.connection,
            fingerprint="server:after-restart",
            occurred_at="2026-07-13T10:10:00-04:00",
            event_type="server",
            title="Après la reprise",
            message="Append persistant.",
            source="journal",
        )
        report = EVENTS.write_export(self.connection, output, recent)

        self.assertEqual(report["projectionSync"], "appended")
        self.assertEqual(
            len(json.loads(recent.read_text(encoding="utf-8"))["events"]),
            2,
        )

    def test_historical_backfill_keeps_projection_until_explicit_reprojection(self):
        EVENTS.add_event(
            self.connection,
            fingerprint="server:current",
            occurred_at="2026-07-13T10:00:00-04:00",
            event_type="server",
            title="Écho actuel",
            message="Projection initiale.",
            source="journal",
        )
        output = self.root / "public-events.json"
        recent = self.root / "public-events-recent.json"
        EVENTS.write_export(self.connection, output, recent)
        initial = output.read_text(encoding="utf-8")

        EVENTS.add_event(
            self.connection,
            fingerprint="server:historical-backfill",
            occurred_at="2026-07-12T10:00:00-04:00",
            event_type="server",
            title="Écho retrouvé",
            message="Observation historique.",
            source="journal",
        )
        pending = EVENTS.write_export(self.connection, output, recent)
        self.assertEqual(pending["status"], "reprojection-required")
        self.assertEqual(pending["reason"], "historical-insert-or-backfill")
        self.assertEqual(output.read_text(encoding="utf-8"), initial)

        EVENTS.write_export(
            self.connection,
            output,
            recent,
            reproject_public=True,
        )
        rebuilt = json.loads(output.read_text(encoding="utf-8"))
        self.assertEqual(rebuilt["summary"]["events"], 2)
        self.assertEqual(
            [event["title"] for event in rebuilt["events"]],
            ["Écho actuel", "Écho retrouvé"],
        )

    def test_missing_change_journal_invalidates_without_touching_exports(self):
        output = self.root / "public-events.json"
        recent = self.root / "public-events-recent.json"
        EVENTS.add_event(
            self.connection,
            fingerprint="server:journal-gap:initial",
            occurred_at="2026-07-13T10:00:00-04:00",
            event_type="server",
            title="Projection initiale",
            message="Journal cohérent.",
            source="journal",
        )
        EVENTS.write_export(self.connection, output, recent)
        full_before = output.read_bytes()
        recent_before = recent.read_bytes()

        EVENTS.add_event(
            self.connection,
            fingerprint="server:journal-gap:lost",
            occurred_at="2026-07-13T10:10:00-04:00",
            event_type="server",
            title="Mutation sans journal",
            message="Cette mutation doit être reprojetée.",
            source="journal",
        )
        self.connection.execute("DELETE FROM event_projection_changes")
        report = EVENTS.write_export(self.connection, output, recent)

        self.assertEqual(report["status"], "reprojection-required")
        self.assertEqual(report["reason"], "change-journal-gap")
        self.assertEqual(output.read_bytes(), full_before)
        self.assertEqual(recent.read_bytes(), recent_before)

    def test_observation_timestamp_alone_does_not_rewrite_canonical_export(self):
        EVENTS.add_event(
            self.connection,
            fingerprint="server:stable-provenance",
            occurred_at="2026-07-13T10:00:00-04:00",
            event_type="server",
            title="Écho stable",
            message="Aucun changement métier.",
            source="journal",
        )
        output = self.root / "public-events.json"
        recent = self.root / "public-events-recent.json"
        stats = self.root / "stats.json"
        common = {
            "gameVersion": "v1",
            "steamBuildId": "123",
            "parserCommit": "abc",
            "catalogCommit": "abc",
            "freshness": "current",
            "sourceStatus": "available",
        }
        stats.write_text(
            json.dumps({"provenance": {**common, "observedAt": "2026-07-13T10:00:00Z"}}),
            encoding="utf-8",
        )
        first = EVENTS.write_export(self.connection, output, recent, stats_path=stats)
        output_mtime = output.stat().st_mtime_ns
        stats.write_text(
            json.dumps({"provenance": {**common, "observedAt": "2026-07-13T10:00:20Z"}}),
            encoding="utf-8",
        )
        second = EVENTS.write_export(self.connection, output, recent, stats_path=stats)
        self.assertEqual(first["status"], "written")
        self.assertEqual(second["status"], "unchanged")
        self.assertEqual(output.stat().st_mtime_ns, output_mtime)

    def test_catalog_change_updates_provenance_revision_without_new_event(self):
        EVENTS.add_event(
            self.connection,
            fingerprint="server:stable-catalog-provenance",
            occurred_at="2026-07-13T10:00:00-04:00",
            event_type="server",
            title="Écho stable",
            message="Le contenu métier reste identique.",
            source="journal",
        )
        output = self.root / "public-events.json"
        recent = self.root / "public-events-recent.json"
        stats = self.root / "stats.json"
        common = {
            "gameVersion": "v1",
            "steamBuildId": "123",
            "parserCommit": "abc",
            "freshness": "current",
            "sourceStatus": "available",
        }
        stats.write_text(
            json.dumps({"provenance": {**common, "catalogCommit": "catalog-a"}}),
            encoding="utf-8",
        )
        EVENTS.write_export(self.connection, output, recent, stats_path=stats)
        first = json.loads(output.read_text(encoding="utf-8"))

        stats.write_text(
            json.dumps({"provenance": {**common, "catalogCommit": "catalog-b"}}),
            encoding="utf-8",
        )
        report = EVENTS.write_export(self.connection, output, recent, stats_path=stats)
        second = json.loads(output.read_text(encoding="utf-8"))

        self.assertEqual(report["status"], "written")
        self.assertEqual(first["projectionRevision"], second["projectionRevision"])
        self.assertNotEqual(first["provenanceRevision"], second["provenanceRevision"])
        self.assertNotEqual(first["revision"], second["revision"])

    def test_export_failure_happens_after_database_commit_and_keeps_previous_json(self):
        EVENTS.add_event(
            self.connection,
            fingerprint="server:committed-before-export",
            occurred_at="2026-07-13T10:00:00-04:00",
            event_type="server",
            title="Écho durable",
            message="La base reste valide.",
            source="journal",
        )
        output = self.root / "public-events.json"
        recent = self.root / "public-events-recent.json"
        output.write_text('{"previous":true}\n', encoding="utf-8")
        recent.write_text('{"previous":true}\n', encoding="utf-8")
        original = EVENTS.write_json_atomic

        def fail_export(*_args, **_kwargs):
            raise OSError("publication interrompue")

        EVENTS.write_json_atomic = fail_export
        try:
            with self.assertRaises(OSError):
                EVENTS.write_export(self.connection, output, recent)
        finally:
            EVENTS.write_json_atomic = original

        observer = sqlite3.connect(self.root / "events.sqlite3")
        try:
            self.assertEqual(observer.execute("SELECT COUNT(*) FROM events").fetchone()[0], 1)
        finally:
            observer.close()
        self.assertEqual(output.read_text(encoding="utf-8"), '{"previous":true}\n')
        self.assertEqual(recent.read_text(encoding="utf-8"), '{"previous":true}\n')

    def test_suppressed_duplicate_remains_private_but_is_absent_from_export(self):
        for fingerprint, occurred_at in (
            ("save:2026-07-13T10:00:00-04:00:level:alex:12", "2026-07-13T10:00:00-04:00"),
            ("save:2026-07-13T11:00:00-04:00:level:alex:12", "2026-07-13T11:00:00-04:00"),
        ):
            EVENTS.add_event(
                self.connection,
                fingerprint=fingerprint,
                occurred_at=occurred_at,
                event_type="level",
                player="Alex",
                title="Niveau supérieur",
                message="Alex atteint le niveau 12.",
                source="save",
            )

        report = EVENTS.normalize_business_events(self.connection)
        output = self.root / "public-events.json"
        recent = self.root / "public-events-recent.json"
        EVENTS.write_export(self.connection, output, recent)
        payload = json.loads(output.read_text(encoding="utf-8"))

        self.assertEqual(report["levelDuplicatesRemoved"], 1)
        self.assertEqual(self.connection.execute("SELECT COUNT(*) FROM events").fetchone()[0], 2)
        self.assertEqual(self.connection.execute("SELECT COUNT(*) FROM event_suppressions").fetchone()[0], 1)
        self.assertEqual(len(payload["events"]), 1)
        self.assertEqual(payload["summary"]["rawEvents"], 2)
        self.assertEqual(payload["summary"]["publicEvents"], 1)
        self.assertEqual(payload["summary"]["echoes"], 1)

    def test_legacy_research_is_normalized_only_in_public_projection(self):
        fingerprint = "save:2026-07-13T10:00:00-04:00:research:spartans::base-3:7"
        EVENTS.add_event(
            self.connection,
            fingerprint=fingerprint,
            occurred_at="2026-07-13T10:00:00-04:00",
            event_type="research",
            player="Mathieu",
            guild="Spartans",
            base="Base 3 · Spartans",
            title="Recherche terminée",
            message="Mathieu fait progresser la recherche à Base 3 · Spartans.",
            source="save",
            confidence="confirmed",
            details={
                "headline": "Mathieu fait progresser la recherche à Base 3 · Spartans",
                "body": "Ancienne formulation au niveau de la base.",
                "bullets": ["+2 recherches"],
            },
        )
        raw_before = dict(self.connection.execute(
            "SELECT * FROM events WHERE fingerprint = ?",
            (fingerprint,),
        ).fetchone())
        EVENTS.normalize_business_events(self.connection, {
            "bases": [{
                "guildKey": "guild_spartans",
                "guild": "Spartans",
                "name": "base-3",
            }],
        })

        output = self.root / "public-events.json"
        recent = self.root / "public-events-recent.json"
        report = EVENTS.write_export(self.connection, output, recent)
        raw_after = dict(self.connection.execute(
            "SELECT * FROM events WHERE fingerprint = ?",
            (fingerprint,),
        ).fetchone())
        event = json.loads(output.read_text(encoding="utf-8"))["events"][0]

        self.assertEqual(report["status"], "written")
        self.assertEqual(raw_after, raw_before)
        self.assertEqual(raw_after["confidence"], "confirmed")
        self.assertEqual(raw_after["base"], "Base 3 · Spartans")
        self.assertEqual(event["guild"], "Spartans")
        self.assertEqual(event["player"], "Mathieu")
        self.assertIsNone(event["base"])
        self.assertEqual(event["confidence"], "derived")
        self.assertEqual(event["title"], "Recherche de guilde terminée")
        self.assertEqual(event["message"], "La guilde Spartans compte désormais 7 recherches terminées.")
        self.assertEqual(
            event["key"],
            EVENTS.public_event_key("public:research:guild_spartans:7"),
        )
        self.assertEqual(event["details"]["total"], 7)
        self.assertEqual(event["details"]["attribution"], "rattachée à la guilde")
        self.assertNotIn("Base 3", json.dumps(event["display"], ensure_ascii=False))

    def test_unattributed_canonical_research_stays_confirmed(self):
        EVENTS.add_event(
            self.connection,
            fingerprint="save:research:guild_spartans:1",
            occurred_at="2026-07-13T10:00:00-04:00",
            event_type="research",
            guild="Spartans",
            base="Ancienne base",
            title="Ancienne recherche",
            message="Ancienne formulation.",
            source="save",
            confidence="confirmed",
        )
        row = self.connection.execute("SELECT * FROM events").fetchone()

        event = EVENTS.public_event(row)

        self.assertEqual(event["message"], "La guilde Spartans compte désormais 1 recherche terminée.")
        self.assertEqual(event["details"]["total"], 1)
        self.assertIsNone(event["player"])
        self.assertIsNone(event["base"])
        self.assertEqual(event["confidence"], "confirmed")
        self.assertEqual(
            event["key"],
            EVENTS.public_event_key("public:research:guild_spartans:1"),
        )

    def test_research_deduplication_restores_ambiguous_name_collisions(self):
        samples = (
            (
                "save:2026-07-13T10:00:00-04:00:research:guilde anonyme::base-a:5",
                "Base A",
            ),
            (
                "save:2026-07-13T10:01:00-04:00:research:guilde anonyme::base-b:5",
                "Base B",
            ),
        )
        for index, (fingerprint, base) in enumerate(samples):
            EVENTS.add_event(
                self.connection,
                fingerprint=fingerprint,
                occurred_at=f"2026-07-13T10:0{index}:00-04:00",
                event_type="research",
                guild="Guilde anonyme",
                base=base,
                title="Recherche terminée",
                message=f"Recherche confirmée à {base}.",
                source="save",
            )
        second_id = int(self.connection.execute(
            "SELECT id FROM events ORDER BY id DESC LIMIT 1"
        ).fetchone()["id"])
        EVENTS.suppress_events(self.connection, [second_id], "duplicate-research")

        report = EVENTS.normalize_business_events(self.connection, {
            "bases": [
                {
                    "guildKey": "guild-alpha",
                    "guild": "Guilde anonyme",
                    "name": "base-a",
                },
                {
                    "guildKey": "guild-beta",
                    "guild": "Guilde anonyme",
                    "name": "base-b",
                },
            ],
        })

        self.assertEqual(report["researchSuppressionsRestored"], 1)
        self.assertEqual(report["researchDuplicateSuppressions"], 0)
        self.assertEqual(report["researchIdentityUnresolved"], 0)
        self.assertEqual(self.connection.execute("SELECT COUNT(*) FROM events").fetchone()[0], 2)
        self.assertEqual(
            self.connection.execute(
                "SELECT COUNT(*) FROM event_suppressions WHERE reason = 'duplicate-research'"
            ).fetchone()[0],
            0,
        )

        output = self.root / "public-events.json"
        recent = self.root / "public-events-recent.json"
        EVENTS.write_export(self.connection, output, recent, reproject_public=True)
        first_keys = {
            event["key"]
            for event in json.loads(output.read_text(encoding="utf-8"))["events"]
        }
        EVENTS.write_export(self.connection, output, recent, reproject_public=True)
        second_keys = {
            event["key"]
            for event in json.loads(output.read_text(encoding="utf-8"))["events"]
        }

        self.assertEqual(first_keys, {
            EVENTS.public_event_key("public:research:guild-alpha:5"),
            EVENTS.public_event_key("public:research:guild-beta:5"),
        })
        self.assertEqual(second_keys, first_keys)

    def test_research_deduplication_prefers_canonical_stable_identity(self):
        legacy_fingerprint = (
            "save:2026-07-13T10:00:00-04:00:research:spartans::base-a:4"
        )
        EVENTS.add_event(
            self.connection,
            fingerprint=legacy_fingerprint,
            occurred_at="2026-07-13T10:00:00-04:00",
            event_type="research",
            player="Mathieu",
            guild="Spartans",
            base="Base A",
            title="Recherche terminée",
            message="Ancienne observation de base.",
            source="save",
        )
        EVENTS.add_event(
            self.connection,
            fingerprint="save:research:guild_spartans:4",
            occurred_at="2026-07-13T10:05:00-04:00",
            event_type="research",
            guild="Spartans",
            title="Recherche de guilde terminée",
            message="Observation canonique.",
            source="save",
        )
        legacy_id = int(self.connection.execute(
            "SELECT id FROM events WHERE fingerprint = ?",
            (legacy_fingerprint,),
        ).fetchone()["id"])
        bases_payload = {
            "bases": [{
                "guildKey": "guild_spartans",
                "guild": "Spartans",
                "name": "base-a",
            }],
        }

        first = EVENTS.normalize_business_events(self.connection, bases_payload)
        second = EVENTS.normalize_business_events(self.connection, bases_payload)

        self.assertEqual(first["researchDuplicatesRemoved"], 1)
        self.assertEqual(first["researchDuplicateSuppressions"], 1)
        self.assertEqual(second["researchDuplicatesRemoved"], 0)
        self.assertEqual(second["researchSuppressionsRestored"], 0)
        suppression = self.connection.execute(
            "SELECT event_id, reason FROM event_suppressions"
        ).fetchone()
        self.assertEqual(tuple(suppression), (legacy_id, "duplicate-research"))
        self.assertEqual(self.connection.execute("SELECT COUNT(*) FROM events").fetchone()[0], 2)

    def test_unresolved_legacy_research_is_not_suppressed_and_is_diagnosed(self):
        for index in range(2):
            EVENTS.add_event(
                self.connection,
                fingerprint=(
                    f"save:2026-07-13T10:0{index}:00-04:00:"
                    f"research:guilde anonyme::base-{index}:3"
                ),
                occurred_at=f"2026-07-13T10:0{index}:00-04:00",
                event_type="research",
                guild="Guilde anonyme",
                base=f"Base {index}",
                title="Recherche terminée",
                message="Ancienne observation.",
                source="save",
            )
        second_id = int(self.connection.execute(
            "SELECT id FROM events ORDER BY id DESC LIMIT 1"
        ).fetchone()["id"])
        EVENTS.suppress_events(self.connection, [second_id], "duplicate-research")

        report = EVENTS.normalize_business_events(self.connection)
        diagnostic = EVENTS.metadata_get(
            self.connection,
            "research_identity_diagnostic",
            {},
        )

        self.assertEqual(report["researchSuppressionsRestored"], 1)
        self.assertEqual(report["researchIdentityUnresolved"], 2)
        self.assertEqual(diagnostic["unresolved"], 2)
        self.assertEqual(
            {row["reason"] for row in diagnostic["events"]},
            {"unresolved-base"},
        )
        self.assertEqual(
            self.connection.execute(
                "SELECT COUNT(*) FROM event_suppressions WHERE reason = 'duplicate-research'"
            ).fetchone()[0],
            0,
        )

    def test_projection_schema_change_requires_explicit_research_reprojection(self):
        EVENTS.add_event(
            self.connection,
            fingerprint="save:2026-07-13T10:00:00-04:00:research:spartans::base-1:4",
            occurred_at="2026-07-13T10:00:00-04:00",
            event_type="research",
            player="Galyk",
            guild="Spartans",
            base="Base 1 · Spartans",
            title="Recherche terminée",
            message="Galyk fait progresser la recherche à Base 1 · Spartans.",
            source="save",
            confidence="confirmed",
        )
        EVENTS.normalize_business_events(self.connection, {
            "bases": [{
                "guildKey": "guild_spartans",
                "guild": "Spartans",
                "name": "base-1",
            }],
        })
        output = self.root / "public-events.json"
        recent = self.root / "public-events-recent.json"
        EVENTS.write_export(self.connection, output, recent)
        published_before = output.read_bytes()

        legacy_payload = json.loads(self.connection.execute(
            "SELECT payload_json FROM public_event_projection"
        ).fetchone()["payload_json"])
        legacy_payload.update({
            "base": "Base 1 · Spartans",
            "title": "Recherche terminée",
            "message": "Galyk fait progresser la recherche à Base 1 · Spartans.",
            "confidence": "confirmed",
        })
        self.connection.execute(
            "UPDATE public_event_projection SET payload_json = ?",
            (json.dumps(legacy_payload, ensure_ascii=False),),
        )
        projection_state = EVENTS.metadata_get(self.connection, "public_projection_state", {})
        projection_state["schemaVersion"] = EVENTS.PUBLIC_PROJECTION_SCHEMA_VERSION - 1
        EVENTS.metadata_set(self.connection, "public_projection_state", projection_state)
        self.connection.commit()

        pending = EVENTS.write_export(self.connection, output, recent)

        self.assertEqual(pending["status"], "reprojection-required")
        self.assertEqual(pending["reason"], "projection-schema-change")
        self.assertEqual(output.read_bytes(), published_before)

        request = self.root / "public-reprojection.request"
        request.touch()
        self.assertTrue(EVENTS.public_reprojection_requested(False, request))
        rebuilt = EVENTS.write_export(
            self.connection,
            output,
            recent,
            reproject_public=EVENTS.public_reprojection_requested(False, request),
        )
        late_request = self.root / "late-public-reprojection.request"
        late_request.touch()
        self.assertFalse(EVENTS.consume_public_reprojection_request(late_request, rebuilt, requested=False))
        self.assertTrue(late_request.exists())
        self.assertTrue(EVENTS.consume_public_reprojection_request(request, rebuilt, requested=True))
        self.assertFalse(request.exists())
        materialized = json.loads(self.connection.execute(
            "SELECT payload_json FROM public_event_projection"
        ).fetchone()["payload_json"])
        current_state = EVENTS.metadata_get(self.connection, "public_projection_state", {})

        self.assertEqual(rebuilt["status"], "written")
        self.assertEqual(rebuilt["projectionSync"], "reprojected")
        self.assertEqual(current_state["schemaVersion"], EVENTS.PUBLIC_PROJECTION_SCHEMA_VERSION)
        self.assertIsNone(materialized["base"])
        self.assertEqual(materialized["details"]["total"], 4)
        self.assertEqual(materialized["confidence"], "derived")
        self.assertEqual(
            materialized["key"],
            EVENTS.public_event_key("public:research:guild_spartans:4"),
        )

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
        self.assertTrue(recent_payload["truncated"])
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
            """
            SELECT type, message, details_json FROM events
            WHERE NOT EXISTS (
                SELECT 1 FROM event_suppressions
                WHERE event_suppressions.event_id = events.id
            )
            ORDER BY occurred_at, id
            """
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
            "Stock de production observé à Atelier du nord. "
            "40 ressources supplémentaires sont observées. Stock actuel: 180.",
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

    def test_history_normalization_repairs_unambiguous_research_attribution(self):
        occurred_at = "2026-07-20T10:40:02-04:00"
        EVENTS.add_event(
            self.connection,
            fingerprint="save:research:guild_duke:16",
            occurred_at=occurred_at,
            event_type="research",
            player=None,
            guild="Claque moi la moule",
            title="Recherche de guilde terminée",
            message="La recherche de la guilde Claque moi la moule progresse: 1 recherche terminée.",
            source="save",
            confidence="confirmed",
            details={
                "headline": "Recherche de guilde terminée",
                "body": "Le laboratoire progresse au niveau de la guilde.",
                "bullets": ["+1 recherche"],
                "total": 16,
            },
        )
        stats = self.root / "stats.json"
        stats.write_text(json.dumps({
            "players": {
                "steam_duke": {
                    "id": "steam_duke",
                    "name": "DukeChicken",
                    "accountName": "DukeChicken",
                    "userId": "steam_duke",
                    "sessionHistory": [{
                        "startedAt": "2026-07-20T10:27:38-04:00",
                        "endedAt": None,
                    }],
                },
            },
        }), encoding="utf-8")
        bases_payload = {
            "guildResearch": [{
                "key": "guild_duke",
                "guild": "Claque moi la moule",
                "players": ["DukeChicken"],
                "completed": 16,
            }],
        }

        report = EVENTS.normalize_event_history(self.connection, bases_payload, stats)
        second_report = EVENTS.normalize_event_history(self.connection, bases_payload, stats)
        row = self.connection.execute(
            "SELECT player, confidence, details_json FROM events WHERE type = 'research'"
        ).fetchone()

        self.assertEqual(report["researchAttributionsUpdated"], 1)
        self.assertEqual(second_report["researchAttributionsUpdated"], 0)
        self.assertEqual(row["player"], "DukeChicken")
        self.assertEqual(row["confidence"], "derived")
        self.assertEqual(json.loads(row["details_json"])["attribution"], "membre actif observé")

    def test_history_normalization_keeps_ambiguous_research_unattributed(self):
        occurred_at = "2026-07-20T10:40:02-04:00"
        EVENTS.add_event(
            self.connection,
            fingerprint="save:research:guild_shared:16",
            occurred_at=occurred_at,
            event_type="research",
            player=None,
            guild="Spartans",
            title="Recherche de guilde terminée",
            message="La recherche de la guilde Spartans progresse: 1 recherche terminée.",
            source="save",
            confidence="confirmed",
            details={"total": 16},
        )
        stats = self.root / "stats.json"
        stats.write_text(json.dumps({
            "players": {
                name: {
                    "id": f"steam_{name.casefold()}",
                    "name": name,
                    "accountName": name,
                    "userId": f"steam_{name.casefold()}",
                    "sessionHistory": [{
                        "startedAt": "2026-07-20T10:00:00-04:00",
                        "endedAt": None,
                    }],
                }
                for name in ("Mathieu", "Galyk")
            },
        }), encoding="utf-8")
        bases_payload = {
            "guildResearch": [{
                "key": "guild_shared",
                "guild": "Spartans",
                "players": ["Mathieu", "Galyk"],
                "completed": 16,
            }],
        }

        report = EVENTS.normalize_event_history(self.connection, bases_payload, stats)
        row = self.connection.execute(
            "SELECT player, confidence FROM events WHERE type = 'research'"
        ).fetchone()

        self.assertEqual(report["researchAttributionsUpdated"], 0)
        self.assertIsNone(row["player"])
        self.assertEqual(row["confidence"], "confirmed")

    def test_world_drop_build_noise_is_removed_from_history(self):
        EVENTS.add_event(
            self.connection,
            fingerprint="save:legacy:build:drop-only",
            occurred_at="2026-07-13T10:00:00-04:00",
            event_type="build",
            player="Mathieu",
            guild="Spartans",
            base="Base 1",
            title="Base agrandie",
            message="Mathieu agrandit Base 1. 3 nouvelles structures confirmées.",
            source="save",
            details={
                "headline": "Mathieu agrandit Base 1",
                "body": "3 structures ajoutées.",
                "bullets": ["+3 CommonItemDrop3D"],
                "structures": [{"name": "CommonItemDrop3D", "asset": "CommonItemDrop3D", "added": 3, "count": 3}],
            },
        )
        EVENTS.add_event(
            self.connection,
            fingerprint="save:legacy:build:mixed",
            occurred_at="2026-07-13T10:01:00-04:00",
            event_type="build",
            player="Mathieu",
            guild="Spartans",
            base="Base 1",
            title="Base agrandie",
            message="Mathieu agrandit Base 1. 4 nouvelles structures confirmées.",
            source="save",
            details={
                "headline": "Mathieu agrandit Base 1",
                "body": "4 structures ajoutées.",
                "bullets": ["+2 Mur", "+2 CommonDropItem3D"],
                "structures": [
                    {"name": "Mur", "asset": "Wall", "added": 2, "count": 12},
                    {"name": "CommonDropItem3D", "asset": "CommonDropItem3D", "added": 2, "count": 2},
                ],
            },
        )

        report = EVENTS.normalize_event_history(self.connection)

        self.assertEqual(report["worldDropBuildUpdated"], 1)
        self.assertEqual(report["worldDropBuildRemoved"], 1)
        rows = self.connection.execute(
            """
            SELECT message, details_json FROM events
            WHERE type = 'build'
              AND NOT EXISTS (
                SELECT 1 FROM event_suppressions
                WHERE event_suppressions.event_id = events.id
              )
            """
        ).fetchall()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["message"], "Mathieu agrandit Base 1. 2 nouvelles structures ajoutées.")
        self.assertNotIn("CommonDropItem3D", rows[0]["details_json"])
        self.assertNotIn("CommonItemDrop3D", rows[0]["details_json"])
        details = json.loads(rows[0]["details_json"])
        self.assertEqual(details["bullets"], ["+2 Mur"])

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
                "body": "2 structures ajoutées.",
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
