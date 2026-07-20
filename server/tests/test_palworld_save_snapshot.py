import importlib.util
import gzip
import hashlib
import json
import os
import tempfile
import time
import unittest
from unittest import mock
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "server" / "bin" / "palworld-save-snapshot.py"
SPEC = importlib.util.spec_from_file_location("palworld_save_snapshot", MODULE_PATH)
snapshot = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(snapshot)


class SaveSnapshotContractTests(unittest.TestCase):
    def test_scalar_handles_nested_unreal_values(self):
        self.assertEqual(snapshot.scalar({"value": {"value": 7}}), 7)
        self.assertEqual(snapshot.scalar({"value": {"type": "None", "value": 3}}), 3)
        self.assertIsNone(snapshot.optional_scalar({}, "missing"))

    def test_record_aliases_are_read_in_order(self):
        data = {
            "PlayerCaptureRecordData2": {
                "value": {"PalCaptureCount": {"value": [{"key": "SheepBall", "value": 2}]}}
            }
        }
        sections = snapshot.record_sections(data)
        self.assertEqual(snapshot.integer_map(snapshot.record_property(sections, "PalCaptureCount")), {"SheepBall": 2})

    def test_public_position_omits_precise_world_coordinates(self):
        result = snapshot.public_position({"value": {"x": 1000, "y": 2000, "z": 3000}})
        self.assertEqual(set(result), {"mapX", "mapY", "leftPercent", "topPercent", "mapVisible"})
        self.assertTrue(result["mapVisible"])

    def test_instanced_corner_position_is_not_drawn_on_the_world_map(self):
        result = snapshot.public_position({
            "value": {
                "x": 625 * 725 - 375247,
                "y": -672 * 725 - 18,
            }
        })
        self.assertEqual((result["mapX"], result["mapY"]), (-672, 625))
        self.assertFalse(result["mapVisible"])

    def test_public_privacy_guard_blocks_technical_keys(self):
        for key in ("playerUid", "objectGuid", "instanceId", "containerId", "steamAccount", "apiToken"):
            with self.subTest(key=key):
                with self.assertRaises(ValueError):
                    snapshot.validate_public_payload({key: "secret"})
        snapshot.validate_public_payload({"container": "party"})

    def test_fixture_is_valid_v3_and_keeps_unknown_as_null(self):
        fixture = json.loads(
            (ROOT / "server" / "tests" / "fixtures" / "save-contract-v3.json").read_text(encoding="utf-8")
        )
        snapshot.validate_public_payload(fixture)
        self.assertEqual(fixture["version"], 3)
        self.assertIsNone(fixture["players"][0]["pals"]["collection"][0]["rank"])

    def test_dotnet_ticks_are_converted_only_when_plausible(self):
        acquired = datetime(2026, 7, 10, 4, 0, tzinfo=timezone.utc)
        ticks = int((acquired - datetime(1, 1, 1, tzinfo=timezone.utc)).total_seconds() * 10_000_000)
        self.assertTrue(snapshot.owned_at({"value": ticks}).startswith("2026-07-10T04:00:00"))
        self.assertIsNone(snapshot.owned_at({"value": 10}))

    def test_temporary_cjk_base_names_are_replaced(self):
        self.assertEqual(
            snapshot.base_display_name("新規生成拠点テンプレート名2(仮)", "Explorateurs", 3),
            "Base 3 · Explorateurs",
        )
        self.assertEqual(snapshot.base_display_name("Fort Canard", "Explorateurs", 3), "Fort Canard")

    def test_structure_categories_separate_storage_and_production(self):
        self.assertEqual(snapshot.structure_category("ItemChest_02", {}), "Stockage")
        self.assertEqual(snapshot.structure_category("BlastFurnace", {}), "Production")
        self.assertEqual(snapshot.structure_category("Wooden_foundation", {}), "Construction")

    def test_world_drop_objects_are_not_counted_as_base_structures(self):
        world = {
            "GroupSaveDataMap": {"value": [{
                "key": "guild-1",
                "value": {"RawData": {"value": {
                    "group_type": "EPalGroupType::Guild",
                    "guild_name": "Spartans",
                    "base_camp_level": 12,
                }}},
            }]},
            "CharacterSaveParameterMap": {"value": []},
            "CharacterContainerSaveData": {"value": []},
            "MapObjectSaveData": {"value": {"values": [
                {
                    "MapObjectId": {"value": "CommonItemDrop3D"},
                    "Model": {"value": {"RawData": {"value": {
                        "base_camp_id_belong_to": "base-1",
                        "instance_id": "drop-1",
                        "hp": {"current": 1, "max": 1},
                    }}}},
                },
                {
                    "MapObjectId": {"value": "BuildObject_Wall"},
                    "Model": {"value": {"RawData": {"value": {
                        "base_camp_id_belong_to": "base-1",
                        "instance_id": "wall-1",
                        "hp": {"current": 100, "max": 100},
                    }}}},
                },
            ]}},
            "BaseCampSaveData": {"value": [{
                "key": "base-1",
                "value": {"RawData": {"value": {
                    "group_id_belong_to": "guild-1",
                    "name": "Base 1 · Spartans",
                    "state": 1,
                    "area_range": 100,
                    "transform": {"translation": {"x": 0, "y": 0, "z": 0}},
                }}},
            }]},
        }
        catalogs = {
            "structures": {
                "wall": {"name": "Mur", "type_ui_display": "Construction"},
            },
            "items": {},
        }

        public, _private = snapshot.build_base_snapshots(
            world,
            catalogs,
            "2026-07-13T10:00:00-04:00",
            "backup",
            "parser",
            Counter(),
        )

        self.assertEqual(public["summary"]["structures"], 1)
        self.assertEqual(public["bases"][0]["structures"]["total"], 1)
        self.assertEqual(public["bases"][0]["structures"]["highlights"], [{"name": "Mur", "count": 1}])
        self.assertEqual(len(public["bases"][0]["structures"]["states"]), 1)
        self.assertTrue(public["bases"][0]["structures"]["states"][0]["key"].startswith("structure_"))
        self.assertNotIn("CommonItemDrop3D", json.dumps(public, ensure_ascii=False))

    def test_guild_research_is_exported_once_for_three_bases(self):
        world = {
            "GroupSaveDataMap": {"value": [{
                "key": "guild-1",
                "value": {"RawData": {"value": {
                    "group_type": "EPalGroupType::Guild",
                    "guild_name": "Spartans",
                    "base_camp_level": 12,
                }}},
            }]},
            "CharacterSaveParameterMap": {"value": []},
            "CharacterContainerSaveData": {"value": []},
            "MapObjectSaveData": {"value": {"values": []}},
            "GuildExtraSaveDataMap": {"value": [{
                "key": "guild-1",
                "value": {"Lab": {"value": {"RawData": {"value": {
                    "current_research_id": "Research_4",
                    "research_info": [
                        {"research_id": "Research_1", "work_amount": 1},
                        {"research_id": "Research_2", "work_amount": 1},
                        {"research_id": "Research_3", "work_amount": 1},
                    ],
                }}}}},
            }]},
            "BaseCampSaveData": {"value": [
                {
                    "key": f"base-{index}",
                    "value": {"RawData": {"value": {
                        "group_id_belong_to": "guild-1",
                        "name": f"Base {index} · Spartans",
                        "state": 1,
                        "area_range": 100,
                        "transform": {"translation": {"x": 0, "y": 0, "z": 0}},
                    }}},
                }
                for index in range(1, 4)
            ]},
        }

        public, _private = snapshot.build_base_snapshots(
            world,
            {"structures": {}, "items": {}},
            "2026-07-13T10:00:00-04:00",
            "backup",
            "parser",
            Counter(),
        )

        self.assertEqual(len(public["bases"]), 3)
        self.assertEqual(len(public["guildResearch"]), 1)
        self.assertEqual(public["guildResearch"][0]["completed"], 3)
        self.assertTrue(public["guildResearch"][0]["key"].startswith("guild_"))

    def test_public_item_totals_aggregate_without_technical_ids(self):
        inventories = [
            {"items": [{"asset": "Wood", "name": "Wood", "count": 20, "icon": None, "category": "Material"}]},
            {"items": [{"asset": "Wood", "name": "Wood", "count": 5, "icon": None, "category": "Material"}]},
        ]
        top_items, categories = snapshot.public_item_totals(inventories)
        self.assertEqual(top_items[0]["count"], 25)
        self.assertEqual(categories, [{"name": "Material", "count": 25}])
        snapshot.validate_public_payload({"storage": {"units": 2, "topItems": top_items}})

    def test_public_item_totals_are_complete_unless_a_limit_is_requested(self):
        inventories = [{"items": [
            {"asset": f"Item{index}", "name": f"Item {index}", "count": index, "category": "Material"}
            for index in range(1, 15)
        ]}]
        all_items, _ = snapshot.public_item_totals(inventories)
        limited_items, _ = snapshot.public_item_totals(inventories, limit=12)
        self.assertEqual(len(all_items), 14)
        self.assertEqual(len(limited_items), 12)

    def test_inventory_items_include_unit_and_stack_weight_when_catalogued(self):
        slots = [{
            "RawData": {"value": {
                "item": {"static_id": "Wood"},
                "count": 12,
                "slot_index": 3,
            }}
        }]
        items = snapshot.inventory_items(slots, {
            "wood": {
                "name": "Bois",
                "weight": 0.5,
                "rarity": 1,
                "type_a_display": "Matériau",
            }
        })

        self.assertEqual(items[0]["weight"], 0.5)
        self.assertEqual(items[0]["totalWeight"], 6.0)
        totals, _categories = snapshot.public_item_totals([{
            "items": [{
                "asset": "Wood",
                "name": "Bois",
                "count": 12,
                "weight": 0.5,
                "category": "Matériau",
            }]
        }])
        self.assertEqual(totals[0]["totalWeight"], 6.0)

    def test_catalog_progress_exposes_next_level_friendship_and_learnset(self):
        experience = {
            10: {"TotalEXP": 1000, "PalTotalEXP": 500},
            11: {"TotalEXP": 1300, "PalTotalEXP": 650},
        }
        self.assertEqual(
            snapshot.experience_progress(10, 1120, experience),
            {
                "level": 10,
                "nextLevel": 11,
                "gained": 120,
                "required": 300,
                "remaining": 180,
                "percent": 40.0,
            },
        )
        friendship = snapshot.friendship_progress(
            7000,
            [
                {"rank": 0, "required": 0},
                {"rank": 1, "required": 6000},
                {"rank": 2, "required": 13000},
            ],
        )
        self.assertEqual(friendship["rank"], 1)
        self.assertEqual(friendship["remaining"], 6000)
        learnset = snapshot.upcoming_learnset(
            "Lamball",
            10,
            {
                "learnsets": {
                    "lamball": [
                        {"WazaID": "EPalWazaID::AirCanon", "level": 1},
                        {"WazaID": "EPalWazaID::PowerBall", "level": 15},
                    ]
                },
                "skills": {"powerball": {"name": "Power Ball", "display_power": 35}},
            },
        )
        self.assertEqual(learnset, [{"level": 15, "name": "Power Ball", "description": None, "rank": 0, "power": 35, "cooldown": None, "element": None}])

    def test_private_catalog_drift_is_persistent_and_public_summary_is_aggregate_only(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "private-catalog-drift.json"
            observations = {}
            snapshot.record_catalog_drift(
                observations, "pal-species", "FuturePal", "Aventurière"
            )
            summary = snapshot.update_catalog_drift_report(
                path,
                observations,
                "2026-07-18T12:00:00Z",
                {
                    "gameVersion": "v1",
                    "steamBuildId": "123",
                    "catalogCommit": "abc",
                },
            )
            self.assertEqual(summary, {
                "unknownIdentifiers": 1,
                "categories": {"pal-species": 1},
            })
            report = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(report["entries"][0]["identifier"], "FuturePal")
            self.assertEqual(report["entries"][0]["players"], ["Aventurière"])
            self.assertEqual(report["entries"][0]["firstSeenAt"], "2026-07-18T12:00:00Z")
            self.assertNotIn("FuturePal", json.dumps(summary))

            snapshot.update_catalog_drift_report(
                path,
                {},
                "2026-07-18T12:05:00Z",
                {"catalogCommit": "def"},
            )
            report = json.loads(path.read_text(encoding="utf-8"))
            self.assertFalse(report["entries"][0]["active"])

    def test_public_bases_example_separates_all_stock_sources(self):
        fixture = json.loads(
            (ROOT / "portal" / "data" / "public-save-bases.example.json").read_text(encoding="utf-8")
        )
        snapshot.validate_public_payload(fixture)
        self.assertEqual(fixture["bases"][0]["storage"]["topItems"][0]["name"], "Wood")
        self.assertEqual(fixture["bases"][0]["production"]["topItems"][0]["name"], "Ingot")
        self.assertEqual(fixture["guildStorage"][0]["topItems"][0]["name"], "Stone")
        self.assertIn("fillPercent", fixture["guildStorage"][0])

    def test_guild_member_names_resolve_public_names_without_uids(self):
        raw = {"players": [{"player_uid": "AAA"}, {"player_uid": "BBB"}]}
        self.assertEqual(
            snapshot.guild_member_names(raw, {"aaa": "Zoé", "bbb": "Alice"}),
            ["Alice", "Zoé"],
        )

    def test_paldex_keeps_unknown_species_for_the_complete_visual_catalog(self):
        catalogs = {
            "canonicalPals": {},
            "species": [
                {"asset": "SheepBall", "name": "Lamball", "icon": "lamball.webp", "index": 1},
                {"asset": "PinkCat", "name": "Cattiva", "icon": "cattiva.webp", "index": 2},
            ],
        }
        paldex = snapshot.player_paldex({}, catalogs, Counter())
        self.assertEqual(paldex["totalSpecies"], 2)
        self.assertEqual(len(paldex["species"]), 2)
        self.assertEqual(paldex["species"][0]["index"], 1)
        self.assertFalse(paldex["species"][0]["encountered"])
        self.assertFalse(paldex["species"][0]["captured"])

    def test_paldex_exposes_the_five_capture_challenge(self):
        sections = [{
            "PalCaptureCount": {"value": [{"key": "SheepBall", "value": 7}]},
            "PalCaptureBonusCount": {"value": [{"key": "SheepBall", "value": 5}]},
        }]
        catalogs = {
            "canonicalPals": {
                "sheepball": {"asset": "SheepBall", "name": "Lamball", "icon": "lamball.webp"}
            },
            "species": [
                {"asset": "SheepBall", "name": "Lamball", "icon": "lamball.webp", "index": 1}
            ],
        }
        paldex = snapshot.player_paldex(sections, catalogs, Counter())
        self.assertEqual(paldex["species"][0]["captureCount"], 7)
        self.assertEqual(paldex["species"][0]["challengeCount"], 5)
        self.assertTrue(paldex["species"][0]["challengeComplete"])
        self.assertEqual(paldex["captureChallengesCompleted"], 1)

    def test_quests_and_challenges_are_publicly_named(self):
        player_data = {
            "CompletedQuestArray_FullRelease": {
                "value": {"values": ["Main_CatchPal", "Hidden_InternalTrigger"]}
            },
            "OrderedQuestArray_FullRelease": {
                "value": {"values": [{"QuestName": {"value": "Sub_Farmer01"}}]}
            },
        }
        quests = snapshot.player_quests(player_data)
        self.assertEqual(quests["completedCount"], 2)
        self.assertEqual(quests["completed"], [{"name": "Capturer un Pal"}])
        self.assertEqual(quests["active"][0]["name"], "Mission de l'agriculteur · chapitre 1")

        challenges = snapshot.player_challenges([{
            "NPCAchivementRewardFlag": {"value": [
                {"key": "PalDex_2", "value": True},
                {"key": "Unknown_1", "value": True},
            ]}
        }])
        self.assertEqual(challenges["completedCount"], 1)
        self.assertEqual(challenges["completed"][0]["name"], "Progression du Paldex · palier 2")

    def test_records_include_public_craft_and_fishing_details(self):
        sections = [{
            "CraftItemCount": {"value": [{"key": "Wood", "value": 12}]},
            "FishingCountMap": {"value": [{"key": "Kelpsea", "value": 3}]},
            "ItemPickupObtainForInstanceFlag": {"value": [{"key": "AncientPart", "value": True}]},
            "NoteObtainForInstanceFlag": {"value": [{"key": "Note01", "value": True}]},
            "ArenaSoloClearCount": {"value": 2},
            "MutationCount": {"value": 1},
            "PalRankupCount": {"value": 4},
            "RaidBossDefeatCount": {"value": 1},
            "TowerBossDefeatCount": {"value": 3},
        }]
        catalogs = {
            "items": {
                "wood": {"name": "Bois", "icon": "/icons/items/wood.webp", "type_a_display": "Matériau"},
                "kelpsea": {"name": "Kelpsea", "icon": "/icons/items/fish.webp", "type_a_display": "Pêche"},
            }
        }
        records = snapshot.player_records(sections, catalogs)
        self.assertEqual(records["itemsCrafted"], 12)
        self.assertEqual(records["craftedItems"][0]["name"], "Bois")
        self.assertEqual(records["fishCaught"], 3)
        self.assertEqual(records["fish"][0]["icon"], "assets/game/icons/items/fish.webp")
        self.assertEqual(records["uniqueItemsPickedUp"], 1)
        self.assertEqual(records["notesFound"], 1)
        self.assertEqual(records["arenaSoloClears"], 2)
        self.assertEqual(records["mutations"], 1)
        self.assertEqual(records["palRankups"], 4)
        self.assertEqual(records["raidBossDefeats"], 1)
        self.assertEqual(records["towerBossDefeats"], 3)

    def test_death_drops_are_public_and_non_reversible(self):
        world = {
            "MapObjectSaveData": {
                "value": {
                    "values": [
                        {
                            "MapObjectId": {"value": "DroppedCharacter"},
                            "Model": {"value": {"RawData": {"value": {
                                "instance_id": "model-1",
                                "initital_transform_cache": {
                                    "translation": {"x": 1000, "y": 2000, "z": 3000}
                                },
                            }}}},
                            "ConcreteModel": {"value": {"RawData": {"value": {
                                "instance_id": "concrete-1",
                                "stored_parameter_id": "stored-1",
                                "owner_player_uid": "PLAYER-1",
                            }}}},
                        }
                    ]
                }
            }
        }
        rows = snapshot.death_drop_state(world, {"player1": "Aventurière"})
        self.assertEqual(len(rows), 1)
        self.assertTrue(rows[0]["key"].startswith("drop_"))
        self.assertEqual(rows[0]["type"], "character-drop")
        self.assertEqual(rows[0]["label"], "Sac de récupération")
        self.assertEqual(rows[0]["player"], "Aventurière")
        self.assertIn("mapX", rows[0]["position"])
        snapshot.validate_public_payload({"world": {"deathDrops": rows}})

    def test_existing_snapshot_source_supports_fast_duplicate_detection(self):
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory) / "snapshot.json"
            temporary.write_text(
                json.dumps({
                    "source": {"backup": "2026.07.12-17.00.00"},
                    "parser": {"commit": "abc123"},
                    "projection": {"version": snapshot.PROJECTION_VERSION},
                }),
                encoding="utf-8",
            )
            self.assertEqual(
                snapshot.existing_snapshot_source(temporary),
                ("2026.07.12-17.00.00", "abc123", snapshot.PROJECTION_VERSION),
            )

    def test_hourly_checkpoint_is_immutable_and_rolling_history_is_bounded(self):
        with tempfile.TemporaryDirectory() as directory:
            history = Path(directory) / "history"
            first = {"updatedAt": "2026-07-13T10:00:00-04:00", "value": 1}
            second = {"updatedAt": "2026-07-13T10:05:00-04:00", "value": 2}
            third = {"updatedAt": "2026-07-13T10:10:00-04:00", "value": 3}

            snapshot.archive_hourly(history, first, 30, rolling_minutes=15)
            snapshot.archive_hourly(history, second, 30, rolling_minutes=15)

            hourly = history / "2026" / "07" / "13" / "10.json.gz"
            with gzip.open(hourly, "rt", encoding="utf-8") as stream:
                self.assertEqual(json.load(stream)["value"], 1)
            rolling = sorted((history / "_rolling").glob("*/*/*/*.json.gz"))
            self.assertEqual(len(rolling), 2)

            expired = rolling[0]
            old_time = time.time() - 3600
            os.utime(expired, (old_time, old_time))
            snapshot.archive_hourly(history, third, 30, rolling_minutes=15)

            rolling = sorted((history / "_rolling").glob("*/*/*/*.json.gz"))
            self.assertNotIn(expired, rolling)
            self.assertEqual(len(rolling), 2)

    def test_public_catalogs_are_versioned_hashed_and_manifested(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            resources = root / "parser" / "resources" / "game_data"
            resources.mkdir(parents=True)
            fixtures = {
                "pal_exp_table.json": {"1": {"TotalEXP": 0, "PalTotalEXP": 0}},
                "friendship.json": {"Friendship_Rank_0": {"FriendshipRank": 0, "RequiredPoint": 0}},
                "pals_learnset.json": {"learnset": {"Lamball": [{"level": 2, "WazaID": "Punch"}]}},
                "skills.json": {"skills": [{"asset": "Punch", "name": "Coup de patte"}]},
                "characters.json": {"pals": [{"asset": "Lamball", "name": "Lamball"}]},
                "breedingdata.json": {"pal_info": {"SheepBall": {"name": "Lamball"}}, "unique_combos": []},
            }
            for name, payload in fixtures.items():
                (resources / name).write_text(json.dumps(payload), encoding="utf-8")
            output_root = root / "runtime" / "public-catalogs"
            manifest_path = root / "runtime" / "public-catalogs-manifest.json"

            report = snapshot.publish_public_catalogs(
                root / "parser",
                output_root,
                manifest_path,
                {"parserCommit": "commit/unsafe", "catalogCommit": "commit/unsafe", "gameVersion": "v1"},
                "2026-07-18T12:00:00-04:00",
            )
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            first_bytes = {
                name: (manifest_path.parent / entry["path"]).read_bytes()
                for name, entry in manifest["files"].items()
            }

            with mock.patch.object(Path, "read_bytes", side_effect=AssertionError("catalogues relus")):
                second_report = snapshot.publish_public_catalogs(
                    root / "parser",
                    output_root,
                    manifest_path,
                    {"parserCommit": "commit/unsafe", "catalogCommit": "commit/unsafe", "gameVersion": "v1"},
                    "2026-07-18T13:00:00-04:00",
                )
            second_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

            self.assertTrue(manifest["ok"])
            self.assertNotIn("/", manifest["generationId"])
            self.assertEqual(report["files"], 3)
            self.assertEqual(second_report["generationId"], report["generationId"])
            self.assertEqual(second_report["status"], "unchanged")
            self.assertEqual(second_manifest["generatedAt"], manifest["generatedAt"])
            self.assertEqual(second_manifest["files"], manifest["files"])
            for entry in manifest["files"].values():
                target = manifest_path.parent / entry["path"]
                self.assertTrue(target.is_file())
                self.assertEqual(
                    entry["sha256"],
                    f"sha256:{hashlib.sha256(target.read_bytes()).hexdigest()}",
                )
            self.assertEqual(
                first_bytes,
                {
                    name: (manifest_path.parent / entry["path"]).read_bytes()
                    for name, entry in second_manifest["files"].items()
                },
            )


if __name__ == "__main__":
    unittest.main()
