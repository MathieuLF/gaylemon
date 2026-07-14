import importlib.util
import json
import tempfile
import unittest
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


if __name__ == "__main__":
    unittest.main()
