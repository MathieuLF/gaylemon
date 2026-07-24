#!/usr/bin/env python3
"""Build privacy-filtered public data from a copied Palworld backup."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import math
import re
import shutil
import subprocess
import sys
import tempfile
import time
from collections import Counter
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path

try:
    import fcntl
except ImportError:  # pragma: no cover - the production worker runs on Linux.
    fcntl = None


DEFAULT_SAVE_ROOT = Path(
    "/srv/storage/steam/servers/palworld/game/Pal/Saved/SaveGames/0/"
    "91B19CCBB15D48C7A96CB24669B7A525"
)
DEFAULT_PARSER_REPO = Path("/home/gaylemon/Gaylemon/vendor/PalworldSaveTools-current")
DEFAULT_OUTPUT = Path("/home/gaylemon/Gaylemon/runtime/public-save-snapshot.json")
DEFAULT_BASES_OUTPUT = Path("/home/gaylemon/Gaylemon/runtime/public-save-bases.json")
DEFAULT_PRIVATE_BASES_OUTPUT = Path(
    "/home/gaylemon/Gaylemon/runtime/private-save-bases.json"
)
DEFAULT_DIAGNOSTICS = Path(
    "/home/gaylemon/Gaylemon/runtime/public-save-diagnostics.json"
)
DEFAULT_STATS = Path("/srv/storage/steam/servers/palworld/stats/stats.json")
DEFAULT_CATALOG_DRIFT = Path(
    "/home/gaylemon/Gaylemon/runtime/private-catalog-drift.json"
)
DEFAULT_PUBLIC_CATALOGS_ROOT = Path(
    "/home/gaylemon/Gaylemon/runtime/public-catalogs"
)
DEFAULT_PUBLIC_CATALOGS_MANIFEST = Path(
    "/home/gaylemon/Gaylemon/runtime/public-catalogs-manifest.json"
)
DEFAULT_HISTORY = Path("/home/gaylemon/Gaylemon/runtime/save-snapshot-history")
DEFAULT_BASES_HISTORY = Path("/home/gaylemon/Gaylemon/runtime/save-bases-history")
DEFAULT_LOCK = Path("/home/gaylemon/Gaylemon/runtime/palworld-save-snapshot.lock")
DEFAULT_ROLLING_HISTORY_MINUTES = 20
PROJECTION_VERSION = 5
DEATH_DROP_LABELS = {
    "DroppedCharacter": "Sac de récupération",
    "DeathPenaltyChest": "Coffre de récupération",
}

RECORD_ALIASES = (
    "RecordData",
    "PlayerCaptureRecordData",
    "PlayerCaptureRecordData2",
    "PlayerDefeatBossRecordData",
    "PlayerDiscoverMapData",
    "PlayerExploreMapData",
    "PlayerExploreMapData2",
    "PlayerTechnologyData",
    "PlayerTechnologyData2",
)
FORBIDDEN_PUBLIC_KEY = re.compile(
    r"uid|guid|instance|container|account|steam|password|token|dynamic_id",
    re.IGNORECASE,
)
# This value describes the public location category, never an Unreal container ID.
PUBLIC_KEY_EXCEPTIONS = {"container", "steamBuildId"}

WORK_LABELS = {
    "EmitFlame": "Allumage",
    "Watering": "Arrosage",
    "Seeding": "Plantation",
    "GenerateElectricity": "Électricité",
    "Handcraft": "Travail manuel",
    "Collection": "Récolte",
    "Deforest": "Abattage",
    "Mining": "Extraction minière",
    "OilExtraction": "Extraction pétrolière",
    "ProductMedicine": "Pharmacie",
    "Cool": "Refroidissement",
    "Transport": "Transport",
    "MonsterFarm": "Ferme",
}
RELIC_LABELS = {
    "CapturePower": "Puissance de capture",
    "ClimbSpeed": "Vitesse d'escalade",
    "ExpBonus": "Bonus d'expérience",
    "FoodDecayReduction": "Conservation des aliments",
    "GliderSpeed": "Vitesse de planeur",
    "HungerReduction": "Résistance à la faim",
    "JumpPower": "Puissance de saut",
    "MoveSpeed": "Vitesse de déplacement",
    "RainbowPassiveRate": "Passifs arc-en-ciel",
    "SphereHoming": "Guidage des sphères",
    "StaminaReduction": "Endurance",
    "StatusAilmentResist": "Résistance aux afflictions",
    "SwimSpeed": "Vitesse de nage",
}
QUEST_LABELS = {
    "Main_BuildWorkbench": "Construire un établi",
    "Main_CaptureSheepBall": "Capturer un Lamball",
    "Main_CatchPal": "Capturer un Pal",
    "Main_CollectKeySpheres": "Rassembler les sphères-clés",
    "Main_CraftPalGear": "Fabriquer un équipement de Pal",
    "Main_CraftTools": "Fabriquer des outils",
    "Main_DefeatDesertBoss": "Vaincre le boss du désert",
    "Main_DefeatForestBoss": "Vaincre le boss de la forêt",
    "Main_DefeatSnowyMountainBoss": "Vaincre le boss des montagnes enneigées",
    "Main_DefeatVolcanoBoss": "Vaincre le boss du volcan",
    "Main_EatFood": "Manger un repas",
    "Main_OpenSurvivalGuide": "Consulter le guide de survie",
    "Main_PrepareEquipment": "Préparer son équipement",
    "Main_RayneSyndicate": "Affronter la tour du Syndicat de Rayne",
    "Main_ReturnSmallVillage": "Retourner au petit village",
    "Main_SmallVillage": "Découvrir le petit village",
    "Main_StatusUp": "Améliorer ses caractéristiques",
    "Main_TalkGrassBoss": "Rencontrer la gardienne de la tour",
    "Main_TutorialStart": "Commencer l'aventure",
    "Main_UnlockFastTravel": "Débloquer un voyage rapide",
    "Main_WorkPal": "Faire travailler un Pal",
    "Sub_BossDefeatReward": "Réclamer une récompense de boss",
    "Sub_PalCaptureCountReward": "Réclamer une récompense de capture",
    "Sub_PaldexReward": "Réclamer une récompense du Paldex",
}
QUEST_FAMILIES = {
    "Angler": "Mission du pêcheur",
    "Breeder": "Mission de l'éleveur",
    "Farmer": "Mission de l'agriculteur",
    "LoneWolf": "Mission du loup solitaire",
    "Nomad": "Mission du nomade",
    "PalDisplay": "Présentation de Pals",
    "Ranger": "Mission du garde forestier",
    "Scholar": "Mission de l'érudit",
    "Zoe": "Mission de Zoé",
}
CHALLENGE_LABELS = {
    "BossDefeat": "Boss vaincus",
    "PalCapture": "Captures de Pals",
    "PalDex": "Progression du Paldex",
}


def scalar(prop, default=None):
    if not isinstance(prop, dict):
        return default if prop is None else prop
    value = prop.get("value")
    if value is None:
        return default
    if isinstance(value, dict) and "value" in value:
        return scalar(value, default)
    return value


def optional_scalar(mapping, key, default=None):
    if not isinstance(mapping, dict) or key not in mapping:
        return default
    return scalar(mapping[key], default)


def to_int(value, default=0):
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def guid(value) -> str:
    return str(scalar(value, value) or "")


def uid_key(value) -> str:
    return guid(value).replace("-", "").casefold()


def public_hash(*parts) -> str:
    private = "\0".join(str(part or "") for part in parts)
    digest = hashlib.sha256(private.encode("utf-8")).hexdigest()
    return digest[:24]


def nested(mapping, *keys, default=None):
    current = mapping
    for key in keys:
        if not isinstance(current, dict):
            return default
        current = current.get(key)
    return current if current is not None else default


def save_parameter(entry):
    return nested(
        entry,
        "value",
        "RawData",
        "value",
        "object",
        "SaveParameter",
        "value",
        default={},
    )


def player_uid(entry) -> str:
    return guid(nested(entry, "key", "PlayerUId", default={}))


def is_player(entry) -> bool:
    return bool(scalar(save_parameter(entry).get("IsPlayer"), False))


def container_id(prop) -> str:
    return guid(nested(prop, "value", "ID", default={}))


def array_values(prop):
    values = nested(prop, "value", "values", default=[])
    return values if isinstance(values, list) else []


def array_count(prop) -> int:
    return len(array_values(prop))


def map_entries(prop):
    values = prop.get("value", []) if isinstance(prop, dict) else []
    return values if isinstance(values, list) else []


def true_map_keys(prop):
    return {
        str(row.get("key"))
        for row in map_entries(prop)
        if isinstance(row, dict) and bool(row.get("value")) and row.get("key")
    }


def integer_map(prop):
    result = {}
    for row in map_entries(prop):
        if not isinstance(row, dict) or not row.get("key"):
            continue
        result[str(row["key"])] = to_int(row.get("value"), 0)
    return result


def quest_label(identifier):
    asset = str(identifier or "").strip()
    if not asset or asset.startswith("Hidden_"):
        return None
    if asset in QUEST_LABELS:
        return QUEST_LABELS[asset]

    family_match = re.match(r"^Sub_([A-Za-z]+?)(?:_([A-Z]))?_?(\d+)$", asset)
    if family_match:
        family, group, number = family_match.groups()
        label = QUEST_FAMILIES.get(family, f"Mission {family}")
        suffix = f" {group}" if group else ""
        return f"{label}{suffix} · chapitre {to_int(number, 1)}"

    text = re.sub(r"^(Main|Sub)_", "", asset)
    text = re.sub(r"(?<=[a-zà-ÿ])(?=[A-Z])", " ", text).replace("_", " ")
    return text[:1].upper() + text[1:] if text else None


def player_quests(player_data):
    completed_ids = {
        str(value)
        for value in array_values(player_data.get("CompletedQuestArray_FullRelease", {}))
        if str(value).strip()
    }
    completed = sorted(
        ({"name": label} for identifier in completed_ids if (label := quest_label(identifier))),
        key=lambda row: row["name"].casefold(),
    )

    active = []
    seen = set()
    for row in array_values(player_data.get("OrderedQuestArray_FullRelease", {})):
        if not isinstance(row, dict):
            continue
        identifier = str(scalar(row.get("QuestName"), ""))
        label = quest_label(identifier)
        if not label or identifier in completed_ids or label.casefold() in seen:
            continue
        seen.add(label.casefold())
        active.append({"name": label})
    active.sort(key=lambda row: row["name"].casefold())
    return {
        "completedCount": len(completed_ids),
        "completed": completed,
        "activeCount": len(active),
        "active": active,
    }


def player_challenges(sections):
    flags = sorted(true_map_keys(record_property(sections, "NPCAchivementRewardFlag")))
    completed = []
    for flag in flags:
        match = re.match(r"^([A-Za-z]+)_(\d+)$", flag)
        if not match:
            continue
        category, tier = match.groups()
        label = CHALLENGE_LABELS.get(category)
        if not label:
            continue
        completed.append(
            {
                "name": f"{label} · palier {to_int(tier, 1)}",
                "category": label,
                "tier": to_int(tier, 1),
            }
        )
    completed.sort(key=lambda row: (row["category"].casefold(), row["tier"]))
    return {"completedCount": len(completed), "completed": completed}


def public_catalog_item(asset, catalogs):
    key = str(asset or "")
    info = (catalogs or {}).get("items", {}).get(key.casefold(), {}) if catalogs else {}
    return {
        "asset": key,
        "name": str(info.get("name") or key.replace("_", " ") or "Objet inconnu"),
        "icon": web_icon(info.get("icon")),
        "category": info.get("type_a_display") or info.get("type_b_display"),
    }


def counted_catalog_rows(values, catalogs, drift=None, player_name=None, category="item"):
    rows = []
    for asset, count in values.items():
        amount = max(0, to_int(count, 0))
        if amount <= 0:
            continue
        if not (catalogs or {}).get("items", {}).get(str(asset).casefold()):
            record_catalog_drift(drift, category, asset, player_name)
        rows.append({**public_catalog_item(asset, catalogs), "count": amount})
    rows.sort(key=lambda row: (-row["count"], row["name"].casefold()))
    return rows


def player_records(sections, catalogs=None, drift=None, player_name=None):
    fishing = integer_map(record_property(sections, "FishingCountMap"))
    crafted = integer_map(record_property(sections, "CraftItemCount"))
    fish_rows = counted_catalog_rows(
        fishing, catalogs, drift, player_name, "fishing-item"
    )
    crafted_rows = counted_catalog_rows(
        crafted, catalogs, drift, player_name, "crafted-item"
    )
    return {
        "treasuresFound": to_int(scalar(record_property(sections, "FoundTreasureCount")), 0),
        "normalDungeonsCleared": to_int(
            scalar(record_property(sections, "NormalDungeonClearCount")), 0
        ),
        "fixedDungeonsCleared": to_int(
            scalar(record_property(sections, "FixedDungeonClearCount")), 0
        ),
        "oilRigsCleared": to_int(scalar(record_property(sections, "OilrigClearCount")), 0),
        "campsConquered": to_int(scalar(record_property(sections, "CampConqueredCount")), 0),
        "fishCaught": sum(max(0, count) for count in fishing.values()),
        "fishSpecies": sum(1 for count in fishing.values() if count > 0),
        "fish": fish_rows,
        "itemsCrafted": sum(max(0, count) for count in crafted.values()),
        "craftedItemTypes": sum(1 for count in crafted.values() if count > 0),
        "craftedItems": crafted_rows,
        "uniqueItemsPickedUp": len(
            true_map_keys(record_property(sections, "ItemPickupObtainForInstanceFlag"))
        ),
        "notesFound": len(true_map_keys(record_property(sections, "NoteObtainForInstanceFlag"))),
        "arenaSoloClears": to_int(scalar(record_property(sections, "ArenaSoloClearCount")), 0),
        "mutations": to_int(scalar(record_property(sections, "MutationCount")), 0),
        "palRankups": to_int(scalar(record_property(sections, "PalRankupCount")), 0),
        "raidBossDefeats": to_int(scalar(record_property(sections, "RaidBossDefeatCount")), 0),
        "towerBossDefeats": to_int(scalar(record_property(sections, "TowerBossDefeatCount")), 0),
    }


def record_sections(player_data):
    sections = []
    for alias in RECORD_ALIASES:
        value = nested(player_data, alias, "value", default={})
        if isinstance(value, dict):
            sections.append(value)
    return sections


def record_property(sections, *aliases):
    for section in sections:
        for alias in aliases:
            if alias in section:
                return section[alias]
    return None


def fixed_point(prop):
    raw = scalar(nested(prop, "value", "Value", default={}), 0)
    try:
        return round(float(raw or 0) / 1000, 1)
    except (TypeError, ValueError):
        return 0.0


def catalog_item_weight(info) -> float | None:
    if not isinstance(info, dict):
        return None
    for key in ("weight", "Weight", "item_weight"):
        if info.get(key) is None:
            continue
        try:
            value = float(info[key])
        except (TypeError, ValueError):
            continue
        if value >= 0:
            return round(value, 3)
    return None


def vector(prop):
    value = nested(prop, "value", default={})
    if not isinstance(value, dict):
        return None
    try:
        return {
            "x": round(float(value.get("x", 0)), 1),
            "y": round(float(value.get("y", 0)), 1),
        }
    except (TypeError, ValueError):
        return None


def public_position(prop):
    position = vector(prop)
    if not position:
        return None
    map_x = round((position["y"] + 18) / 725)
    map_y = round((position["x"] + 375247) / 725)
    map_visible = not (abs(map_x) > 550 and abs(map_y) > 550)
    return {
        "mapX": map_x,
        "mapY": map_y,
        "leftPercent": round(max(0, min(100, (map_x + 1000) / 20)), 2),
        "topPercent": round(max(0, min(100, (1000 - map_y) / 20)), 2),
        "mapVisible": map_visible,
    }


def map_object_position(model: dict):
    translation = nested(model, "initital_transform_cache", "translation", default=None)
    if not translation:
        translation = nested(model, "transform", "translation", default=None)
    return public_position({"value": translation}) if isinstance(translation, dict) else None


def player_names_by_uid(characters: list) -> dict:
    return {
        uid_key(player_uid(entry)): str(scalar(save_parameter(entry).get("NickName"), "Joueur"))
        for entry in characters
        if is_player(entry) and uid_key(player_uid(entry))
    }


def death_drop_state(world_data: dict, player_names: dict) -> list[dict]:
    rows = []
    map_objects = nested(world_data, "MapObjectSaveData", "value", "values", default=[])
    for obj in map_objects:
        map_object_id = str(scalar(obj.get("MapObjectId"), "") or "")
        if map_object_id not in DEATH_DROP_LABELS:
            continue
        model = nested(obj, "Model", "value", "RawData", "value", default={})
        concrete = nested(obj, "ConcreteModel", "value", "RawData", "value", default={})
        owner_uid = uid_key(concrete.get("owner_player_uid"))
        row = {
            "key": f"drop_{public_hash(map_object_id, concrete.get('instance_id'), model.get('instance_id'), concrete.get('stored_parameter_id'), concrete.get('owner_player_uid'))}",
            "type": (
                "character-drop"
                if map_object_id == "DroppedCharacter"
                else "death-penalty-chest"
            ),
            "label": DEATH_DROP_LABELS[map_object_id],
        }
        player = player_names.get(owner_uid)
        if player:
            row["player"] = player
        position = map_object_position(model)
        if position:
            row["position"] = position
        rows.append(row)
    rows.sort(key=lambda row: (row.get("type", ""), row.get("player", ""), row["key"]))
    return rows


def choose_backup(save_root: Path, minimum_age: int) -> Path:
    world_backups = save_root / "backup" / "world"
    cutoff = time.time() - minimum_age
    candidates = []
    for candidate in world_backups.iterdir():
        level = candidate / "Level.sav"
        players = candidate / "Players"
        if candidate.is_dir() and level.is_file() and players.is_dir():
            if level.stat().st_mtime <= cutoff:
                candidates.append(candidate)
    if not candidates:
        raise RuntimeError(
            f"No complete backup older than {minimum_age}s in backup/world"
        )
    return max(candidates, key=lambda path: (path.stat().st_mtime, path.name))


def web_icon(path):
    return f"assets/game{path}" if path and str(path).startswith("/icons/") else None


def keyed_catalog(rows):
    return {
        str(item.get("asset")).casefold(): item
        for item in rows
        if item.get("asset")
    }


def record_catalog_drift(observations, category, identifier, players=None):
    """Collect an unknown catalog identifier without adding it to public data."""
    if observations is None:
        return
    identifier = str(identifier or "").strip()
    category = str(category or "unknown").strip()
    if not identifier:
        return
    key = f"{category}:{identifier.casefold()}"
    row = observations.setdefault(
        key,
        {"category": category, "identifier": identifier, "players": set()},
    )
    if isinstance(players, str):
        players = [players]
    for player in players or []:
        name = str(player or "").strip()
        if name:
            row["players"].add(name)


def read_json_object(path: Path) -> dict:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError, TypeError):
        return {}
    return payload if isinstance(payload, dict) else {}


def runtime_provenance(stats_path: Path, parser_sha: str) -> dict:
    stats = read_json_object(stats_path)
    source = stats.get("provenance") if isinstance(stats.get("provenance"), dict) else {}
    return {
        "observedAt": source.get("observedAt"),
        "sourceUpdatedAt": source.get("sourceUpdatedAt"),
        "gameVersion": source.get("gameVersion"),
        "steamBuildId": source.get("steamBuildId"),
        "parserCommit": parser_sha or source.get("parserCommit") or None,
        "catalogCommit": parser_sha or source.get("catalogCommit") or None,
        "freshness": source.get("freshness") or "current",
        "sourceStatus": source.get("sourceStatus") or "available",
    }


def generation_instant(value: str) -> str:
    raw = str(value or "").strip()
    if not raw:
        raise ValueError("Missing save generation timestamp")
    normalized = raw.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        for pattern in ("%Y-%m-%d %H:%M:%S", "%m/%d/%Y %H:%M:%S", "%d/%m/%Y %H:%M:%S"):
            try:
                parsed = datetime.strptime(raw, pattern)
                break
            except ValueError:
                parsed = None
        if parsed is None:
            raise
    if parsed.tzinfo is None:
        parsed = parsed.astimezone()
    parsed_utc = parsed.astimezone(timezone.utc)
    return f"{parsed_utc.strftime('%Y-%m-%dT%H:%M:%S')}.{parsed_utc.microsecond:06d}0Z"


def public_save_generation_id(source_name: str, source_updated_at: str, parser_sha: str, projection_version: int) -> str:
    instant = generation_instant(source_updated_at)
    identity_text = f"{source_name}|{instant}|{parser_sha}|{projection_version}"
    identity_hash = hashlib.sha256(identity_text.encode("utf-8")).hexdigest()[:16]
    safe_instant = instant[:19].replace("-", "").replace(":", "").replace("T", "-")
    return f"save-{safe_instant}-{identity_hash}"


def update_catalog_drift_report(
    path: Path,
    observations: dict,
    observed_at: str,
    provenance: dict,
) -> dict:
    """Persist private catalog drift while keeping public diagnostics aggregate-only."""
    existing = read_json_object(path)
    entries = {
        str(row.get("key") or ""): row
        for row in existing.get("entries") or []
        if isinstance(row, dict) and row.get("key")
    }
    active_keys = set()
    for key, observation in observations.items():
        active_keys.add(key)
        previous = entries.get(key, {})
        players = sorted(
            set(previous.get("players") or []) | set(observation.get("players") or []),
            key=str.casefold,
        )
        entries[key] = {
            "key": key,
            "category": observation["category"],
            "identifier": observation["identifier"],
            "firstSeenAt": previous.get("firstSeenAt") or observed_at,
            "lastSeenAt": observed_at,
            "players": players,
            "gameVersion": provenance.get("gameVersion"),
            "steamBuildId": provenance.get("steamBuildId"),
            "catalogCommit": provenance.get("catalogCommit"),
            "appearances": int(previous.get("appearances") or 0) + 1,
            "active": True,
        }
    for key, row in entries.items():
        if key not in active_keys:
            row["active"] = False
    ordered = sorted(
        entries.values(),
        key=lambda row: (str(row.get("category") or ""), str(row.get("identifier") or "").casefold()),
    )
    report = {
        "version": 1,
        "ok": True,
        "updatedAt": observed_at,
        "warning": "Private catalog diagnostics. Never publish this file.",
        "gameVersion": provenance.get("gameVersion"),
        "steamBuildId": provenance.get("steamBuildId"),
        "catalogCommit": provenance.get("catalogCommit"),
        "entries": ordered,
    }
    write_atomic(path, report)
    categories = Counter(row["category"] for row in observations.values())
    return {
        "unknownIdentifiers": len(observations),
        "categories": dict(sorted(categories.items())),
    }


def technical_pal_asset(asset):
    return bool(
        re.search(r"^(BOSS_|GYM_|RAID_|SUMMON_|PREDATOR_|NPC_|QUEST_)", asset, re.I)
        or re.search(r"(_OILRIG|_RAID|_MAX|_SUMMON|_NPC|_TOWER)$", asset, re.I)
    )


def load_catalogs(parser_repo: Path):
    resources = parser_repo / "resources" / "game_data"
    characters = json.loads((resources / "characters.json").read_text(encoding="utf-8"))
    items = json.loads((resources / "items.json").read_text(encoding="utf-8"))
    skills = json.loads((resources / "skills.json").read_text(encoding="utf-8"))
    boss_mapping = json.loads(
        (resources / "boss_mapping.json").read_text(encoding="utf-8")
    ).get("boss_defeat_flag_map", {})
    fast_travel = json.loads(
        (resources / "fast_travel_points.json").read_text(encoding="utf-8")
    )
    areas = json.loads(
        (resources / "world_map_areas.json").read_text(encoding="utf-8")
    ).get("areas", [])
    relics = json.loads((resources / "relic_data.json").read_text(encoding="utf-8"))
    world = json.loads((resources / "world.json").read_text(encoding="utf-8"))
    experience = json.loads((resources / "pal_exp_table.json").read_text(encoding="utf-8"))
    friendship = json.loads((resources / "friendship.json").read_text(encoding="utf-8"))
    learnsets_payload = json.loads(
        (resources / "pals_learnset.json").read_text(encoding="utf-8")
    )

    pals = keyed_catalog(characters.get("pals", []))
    display_groups = {}
    for pal in characters.get("pals", []):
        index = to_int(nested(pal, "stats", "zukan_index", default=0), 0)
        asset = str(pal.get("asset") or "")
        name = str(pal.get("name") or "")
        if index <= 0 or not pal.get("icon") or technical_pal_asset(asset):
            continue
        key = (index, name.casefold())
        current = display_groups.get(key)
        if current is None or len(asset) < len(str(current.get("asset") or "")):
            display_groups[key] = pal

    canonical_by_asset = {}
    for pal in characters.get("pals", []):
        index = to_int(nested(pal, "stats", "zukan_index", default=0), 0)
        name = str(pal.get("name") or "")
        canonical = display_groups.get((index, name.casefold()))
        if canonical and pal.get("asset"):
            canonical_by_asset[str(pal["asset"]).casefold()] = canonical

    species = sorted(
        (
            {
                "asset": str(row.get("asset")),
                "name": str(row.get("name")),
                "icon": web_icon(row.get("icon")),
                "index": to_int(nested(row, "stats", "zukan_index", default=0), 0),
            }
            for row in display_groups.values()
        ),
        key=lambda row: (row["index"], row["name"].casefold()),
    )

    return {
        "pals": pals,
        "canonicalPals": canonical_by_asset,
        "species": species,
        "items": keyed_catalog(items.get("items", [])),
        "skills": keyed_catalog(skills.get("skills", [])),
        "passives": keyed_catalog(skills.get("passives", [])),
        "bossByFlag": {str(flag): str(reward) for reward, flag in boss_mapping.items()},
        "bossTotal": len(boss_mapping),
        "fastTravel": fast_travel,
        "areas": set(str(area) for area in areas),
        "relics": relics,
        "technology": keyed_catalog(world.get("technology", [])),
        "structures": keyed_catalog(world.get("structures", [])),
        "labResearch": world.get("lab_research", {}),
        "experience": {
            to_int(level, 0): row
            for level, row in experience.items()
            if to_int(level, 0) > 0 and isinstance(row, dict)
        },
        "friendship": sorted(
            (
                {
                    "rank": to_int(row.get("FriendshipRank"), 0),
                    "required": to_int(row.get("RequiredPoint"), 0),
                }
                for row in friendship.values()
                if isinstance(row, dict)
            ),
            key=lambda row: row["required"],
        ),
        "learnsets": {
            key: rows
            for asset, rows in (learnsets_payload.get("learnset") or {}).items()
            if isinstance(rows, list)
            for key in {
                str(asset).casefold(),
                str((pals.get(str(asset).casefold()) or {}).get("name") or asset).casefold(),
            }
        },
    }


def load_parser(parser_repo: Path):
    from palsav.io import load_sav  # pylint: disable=import-outside-toplevel
    from palsav.paltypes import (  # pylint: disable=import-outside-toplevel
        PALWORLD_CUSTOM_PROPERTIES,
    )

    wanted = {
        ".worldSaveData.GroupSaveDataMap",
        ".worldSaveData.CharacterSaveParameterMap.Value.RawData",
        ".worldSaveData.ItemContainerSaveData.Value.RawData",
        ".worldSaveData.ItemContainerSaveData.Value.Slots.Slots.RawData",
        ".worldSaveData.CharacterContainerSaveData.Value.Slots.Slots.RawData",
        ".worldSaveData.BaseCampSaveData.Value.RawData",
        ".worldSaveData.BaseCampSaveData.Value.WorkerDirector.RawData",
        ".worldSaveData.BaseCampSaveData.Value.WorkCollection.RawData",
        ".worldSaveData.WorkSaveData",
        ".worldSaveData.MapObjectSaveData",
        ".worldSaveData.DynamicItemSaveData.DynamicItemSaveData.RawData",
        ".worldSaveData.GuildExtraSaveDataMap.Value.GuildItemStorage.RawData",
        ".worldSaveData.GuildExtraSaveDataMap.Value.Lab.RawData",
    }
    level_properties = {
        key: value for key, value in PALWORLD_CUSTOM_PROPERTIES.items() if key in wanted
    }
    return load_sav, level_properties


def find_player_file(players_dir: Path, uid: str):
    normalized = uid.replace("-", "").upper()
    direct = players_dir / f"{normalized}.sav"
    if direct.is_file():
        return direct
    for path in players_dir.glob("*.sav"):
        if path.stem.replace("-", "").upper() == normalized:
            return path
    return None


def parse_player_save(load_sav, path: Path | None):
    if path is None:
        return {}, "", ""
    payload = load_sav(path).dump()
    save_data = nested(payload, "properties", "SaveData", "value", default={})
    party = container_id(save_data.get("OtomoCharacterContainerId", {}))
    palbox = container_id(save_data.get("PalStorageContainerId", {}))
    return save_data, party, palbox


def item_container_map(world):
    result = {}
    containers = nested(world, "ItemContainerSaveData", "value", default=[])
    for container in containers:
        container_key = guid(nested(container, "key", "ID", default={}))
        if not container_key:
            continue
        slots = nested(container, "value", "Slots", "value", "values", default=[])
        result[container_key] = slots if isinstance(slots, list) else []
    return result


def inventory_items(slots, item_catalog, drift=None, player_name=None):
    grouped = {}
    for slot in slots:
        raw = nested(slot, "RawData", "value", default={})
        item = raw.get("item") if isinstance(raw.get("item"), dict) else {}
        asset = str(item.get("static_id") or "")
        count = to_int(raw.get("count"), 0)
        if not asset or count <= 0:
            continue
        info = item_catalog.get(asset.casefold(), {})
        if not info:
            record_catalog_drift(drift, "inventory-item", asset, player_name)
        key = asset.casefold()
        if key not in grouped:
            weight = catalog_item_weight(info)
            grouped[key] = {
                "name": str(info.get("name") or asset),
                "count": 0,
                "slot": to_int(raw.get("slot_index"), 0),
                "icon": web_icon(info.get("icon")),
                "rarity": to_int(info.get("rarity"), 0),
                "category": info.get("type_a_display") or info.get("type_b_display"),
                **({"weight": weight, "totalWeight": 0.0} if weight is not None else {}),
            }
        grouped[key]["count"] += count
        if "weight" in grouped[key]:
            grouped[key]["totalWeight"] = round(
                grouped[key]["count"] * grouped[key]["weight"],
                3,
            )
        grouped[key]["slot"] = min(
            grouped[key]["slot"], to_int(raw.get("slot_index"), 0)
        )
    return sorted(grouped.values(), key=lambda row: row["slot"])


def player_inventory(player_data, containers, item_catalog, drift=None, player_name=None):
    inventory = nested(player_data, "InventoryInfo", "value", default={})
    sections = (
        ("common", "Sac", "CommonContainerId"),
        ("essential", "Objets importants", "EssentialContainerId"),
        ("weapons", "Armes", "WeaponLoadOutContainerId"),
        ("armor", "Équipement", "PlayerEquipArmorContainerId"),
        ("food", "Nourriture", "FoodEquipContainerId"),
    )
    result = []
    for key, label, property_name in sections:
        identifier = container_id(inventory.get(property_name, {}))
        result.append(
            {
                "key": key,
                "label": label,
                "items": inventory_items(
                    containers.get(identifier, []), item_catalog, drift, player_name
                ),
            }
        )
    return result


def normalized_id(value) -> str:
    return guid(value).replace("-", "").casefold()


def map_position_from_translation(translation):
    if not isinstance(translation, dict):
        return None
    try:
        x_value = float(translation.get("x", 0))
        y_value = float(translation.get("y", 0))
    except (TypeError, ValueError):
        return None
    map_x = round((y_value + 18) / 725)
    map_y = round((x_value + 375247) / 725)
    return {
        "mapX": map_x,
        "mapY": map_y,
        "leftPercent": round(max(0, min(100, (map_x + 1000) / 20)), 2),
        "topPercent": round(max(0, min(100, (1000 - map_y) / 20)), 2),
    }


def dynamic_item_map(world):
    result = {}
    entries = nested(world, "DynamicItemSaveData", "value", "values", default=[])
    for entry in entries:
        raw = nested(entry, "RawData", "value", default={})
        identifier = normalized_id(nested(raw, "id", "local_id_in_created_world", default=""))
        if identifier:
            result[identifier] = raw
    return result


def item_dynamic_details(slot_raw, item_info, dynamic_items, catalogs):
    identifier = normalized_id(
        nested(slot_raw, "item", "dynamic_id", "local_id_in_created_world", default="")
    )
    dynamic = dynamic_items.get(identifier)
    if not isinstance(dynamic, dict):
        return None
    item_type = str(dynamic.get("type") or "unknown")
    maximum = float(item_info.get("durability") or 0)
    current = dynamic.get("durability")
    details = {
        "type": item_type,
        "durability": round(float(current), 1) if current is not None else None,
        "durabilityPercent": (
            round(max(0, min(100, float(current) / maximum * 100)), 1)
            if current is not None and maximum > 0
            else None
        ),
        "remainingBullets": to_int(dynamic.get("remaining_bullets"), 0)
        if "remaining_bullets" in dynamic
        else None,
        "passives": [
            resolve_skill(value, catalogs["passives"])["name"]
            for value in dynamic.get("passive_skill_list", [])
        ],
        "egg": None,
    }
    if item_type == "egg":
        asset = str(dynamic.get("character_id") or "")
        pal = catalogs["pals"].get(asset.casefold(), {})
        details["egg"] = {
            "species": str(pal.get("name") or asset or "Pal inconnu"),
            "icon": web_icon(pal.get("icon")),
        }
    return details


def container_record_map(world):
    result = {}
    for record in nested(world, "ItemContainerSaveData", "value", default=[]):
        identifier = normalized_id(nested(record, "key", "ID", default=""))
        if identifier:
            result[identifier] = record
    return result


def container_inventory(identifier, records, dynamic_items, catalogs):
    record = records.get(normalized_id(identifier))
    if not record:
        return {"capacity": 0, "used": 0, "items": []}
    capacity = to_int(scalar(nested(record, "value", "SlotNum", default={}), 0), 0)
    slots = nested(record, "value", "Slots", "value", "values", default=[])
    items = []
    for slot in slots if isinstance(slots, list) else []:
        raw = nested(slot, "RawData", "value", default={})
        item = raw.get("item") if isinstance(raw.get("item"), dict) else {}
        asset = str(item.get("static_id") or "")
        count = to_int(raw.get("count"), 0)
        if not asset or count <= 0:
            continue
        info = catalogs["items"].get(asset.casefold(), {})
        weight = catalog_item_weight(info)
        items.append(
            {
                "name": str(info.get("name") or asset),
                "asset": asset,
                "count": count,
                "slot": to_int(raw.get("slot_index"), 0),
                "icon": web_icon(info.get("icon")),
                "rarity": to_int(info.get("rarity"), 0),
                **({"weight": weight, "totalWeight": round(weight * count, 3)} if weight is not None else {}),
                "category": str(
                    info.get("type_a_display") or info.get("type_b_display") or "Autres"
                ),
                "condition": item_dynamic_details(raw, info, dynamic_items, catalogs),
            }
        )
    items.sort(key=lambda row: row["slot"])
    return {"capacity": capacity, "used": len(items), "items": items}


def resolve_structure(asset, catalogs):
    raw = str(asset or "")
    candidates = [raw, raw.removeprefix("BuildObject_"), raw.split("/")[-1]]
    for candidate in candidates:
        info = catalogs["structures"].get(candidate.casefold())
        if info:
            return info
    return {}


WORLD_DROP_STRUCTURE_ASSETS = {"commondropitem3d", "commonitemdrop3d"}


def is_world_drop_structure_asset(asset):
    raw = str(asset or "")
    tail = re.split(r"[/\\]", raw)[-1]
    normalized = re.sub(r"[\s_-]+", "", tail).casefold()
    return normalized in WORLD_DROP_STRUCTURE_ASSETS


def structure_category(asset, info):
    text = f"{asset} {info.get('type_ui_display', '')} {info.get('type_a_display', '')}".casefold()
    groups = (
        (("chest", "box", "storage", "container", "foodbox"), "Stockage"),
        (("foundation", "wall", "roof", "stair", "pillar", "door", "window"), "Construction"),
        (("farm", "plantation", "breed", "ranch", "monsterfarm"), "Agriculture"),
        (("factory", "bench", "furnace", "crusher", "mill", "cooking", "medicine", "sphere"), "Production"),
        (("bed", "spa", "medical", "palbox", "hotspring"), "Vie des Pals"),
        (("defense", "machinegun", "missile", "watchtower"), "Défense"),
        (("generator", "power", "electric"), "Énergie"),
    )
    for needles, label in groups:
        if any(needle in text for needle in needles):
            return label
    return "Autres"


def base_display_name(raw_name, guild_name, index):
    name = str(raw_name or "").strip()
    if not name or re.search(r"[\u3040-\u30ff\u3400-\u9fff\uf900-\ufaff]", name):
        return f"Base {index} · {guild_name}"
    return name


def public_item_totals(inventories, limit=None):
    grouped = {}
    categories = Counter()
    for inventory in inventories:
        for item in inventory.get("items", []):
            key = str(item.get("asset") or item.get("name") or "").casefold()
            if not key:
                continue
            current = grouped.setdefault(
                key,
                {
                    "name": item["name"],
                    "count": 0,
                    "icon": item.get("icon"),
                    "category": item.get("category") or "Autres",
                    **(
                        {"weight": item.get("weight"), "totalWeight": 0.0}
                        if item.get("weight") is not None
                        else {}
                    ),
                },
            )
            current["count"] += to_int(item.get("count"), 0)
            if "weight" in current:
                current["totalWeight"] = round(current["count"] * float(current["weight"]), 3)
            categories[current["category"]] += to_int(item.get("count"), 0)
    top_items = sorted(grouped.values(), key=lambda row: (-row["count"], row["name"].casefold()))
    if limit is not None:
        top_items = top_items[:limit]
    return top_items, [
        {"name": name, "count": count}
        for name, count in categories.most_common()
    ]


def guild_member_names(raw, player_names_by_uid):
    members = raw.get("players") if isinstance(raw.get("players"), list) else []
    names = {
        player_names_by_uid.get(uid_key(member.get("player_uid")))
        for member in members
        if isinstance(member, dict)
    }
    return sorted((name for name in names if name), key=str.casefold)


def build_base_snapshots(
    world,
    catalogs,
    captured_at,
    source_name,
    parser_sha,
    counters,
    drift=None,
    source_provenance=None,
    generation_id=None,
):
    source_provenance = source_provenance or {}
    source_updated_at = source_provenance.get("sourceUpdatedAt") or captured_at
    generation_id = generation_id or public_save_generation_id(
        source_name,
        source_updated_at,
        parser_sha,
        PROJECTION_VERSION,
    )
    groups = nested(world, "GroupSaveDataMap", "value", default=[])
    characters = nested(world, "CharacterSaveParameterMap", "value", default=[])
    character_lookup = {
        normalized_id(nested(entry, "key", "InstanceId", default="")): entry
        for entry in characters
        if normalized_id(nested(entry, "key", "InstanceId", default=""))
    }
    player_names_by_uid = {
        uid_key(player_uid(entry)): str(scalar(save_parameter(entry).get("NickName"), "Joueur"))
        for entry in characters
        if is_player(entry) and uid_key(player_uid(entry))
    }
    group_lookup = {}
    for group in groups:
        raw = nested(group, "value", "RawData", "value", default={})
        if raw.get("group_type") != "EPalGroupType::Guild":
            continue
        group_key = normalized_id(group.get("key"))
        group_lookup[group_key] = {
            "key": f"guild_{public_hash(group_key)}",
            "name": str(raw.get("guild_name") or raw.get("group_name") or "Guilde"),
            "campLevel": to_int(raw.get("base_camp_level"), 1),
            "players": guild_member_names(raw, player_names_by_uid),
        }
    character_containers = {}
    for record in nested(world, "CharacterContainerSaveData", "value", default=[]):
        identifier = normalized_id(nested(record, "key", "ID", default=""))
        if identifier:
            character_containers[identifier] = nested(
                record, "value", "Slots", "value", "values", default=[]
            )

    item_records = container_record_map(world)
    dynamic_items = dynamic_item_map(world)
    map_objects = nested(world, "MapObjectSaveData", "value", "values", default=[])
    structures_by_base = {}
    structure_name_by_model = {}
    private_storage_by_base = {}

    for obj in map_objects:
        model = nested(obj, "Model", "value", "RawData", "value", default={})
        base_key = normalized_id(model.get("base_camp_id_belong_to"))
        if not base_key or set(base_key) == {"0"}:
            continue
        asset = str(scalar(obj.get("MapObjectId"), "Structure") or "Structure")
        world_drop = is_world_drop_structure_asset(asset)
        info = {} if world_drop else resolve_structure(asset, catalogs)
        if not world_drop and not info:
            record_catalog_drift(drift, "structure", asset)
        name = "Butin au sol" if world_drop else str(info.get("name") or asset.replace("_", " "))
        if not world_drop:
            structure_name_by_model[normalized_id(model.get("instance_id"))] = name
        build = nested(
            obj, "Model", "value", "BuildProcess", "value", "RawData", "value", default={}
        )
        hp = model.get("hp") if isinstance(model.get("hp"), dict) else {}
        current_hp = to_int(hp.get("current"), 0)
        maximum_hp = to_int(hp.get("max"), 0)
        category = "Butin au sol" if world_drop else structure_category(asset, info)
        row = None
        if not world_drop:
            model_key = normalized_id(model.get("instance_id"))
            row = {
                "name": name,
                "asset": asset,
                "icon": web_icon(info.get("icon")),
                "category": category,
                "completed": to_int(build.get("state"), 0) == 1,
                "damaged": maximum_hp > 0 and current_hp < maximum_hp,
                "healthPercent": round(current_hp / maximum_hp * 100, 1) if maximum_hp else None,
            }
            if model_key:
                row["key"] = f"structure_{public_hash(base_key, model_key)}"
            structures_by_base.setdefault(base_key, []).append(row)

        for module in nested(
            obj, "ConcreteModel", "value", "ModuleMap", "value", default=[]
        ):
            if module.get("key") != "EPalMapObjectConcreteModelModuleType::ItemContainer":
                continue
            module_raw = nested(module, "value", "RawData", "value", default={})
            target = module_raw.get("target_container_id")
            if not target:
                continue
            inventory = container_inventory(target, item_records, dynamic_items, catalogs)
            if world_drop:
                inventory_kind = "world-drop"
            elif category == "Stockage" or asset.startswith("ItemChest"):
                inventory_kind = "storage"
            elif category in {"Production", "Agriculture"}:
                inventory_kind = "production"
            else:
                inventory_kind = "internal"
            private_storage_by_base.setdefault(base_key, []).append(
                {
                    "name": name,
                    "asset": asset,
                    "kind": inventory_kind,
                    "location": nested(
                        model, "initital_transform_cache", "translation", default=None
                    ),
                    **inventory,
                }
            )

    work_entries = nested(world, "WorkSaveData", "value", "values", default=[])
    tasks_by_worker = {}
    works_by_base = {}
    for work in work_entries:
        raw = nested(work, "RawData", "value", default={})
        base_key = normalized_id(raw.get("base_camp_id_belong_to"))
        if not base_key or set(base_key) == {"0"}:
            continue
        work_type = str(nested(work, "WorkableType", "value", "value", default="Travail"))
        owner_name = structure_name_by_model.get(
            normalized_id(raw.get("owner_map_object_model_id")), "Travail de la base"
        )
        required = float(raw.get("required_work_amount") or 0)
        current = float(raw.get("current_work_amount") or 0)
        works_by_base.setdefault(base_key, []).append(
            {
                "name": owner_name,
                "type": work_type.split("::")[-1],
                "progressPercent": (
                    round(max(0, min(100, current / required * 100)), 1)
                    if required > 0
                    else None
                ),
            }
        )
        assignments = nested(work, "WorkAssignMap", "value", default=[])
        for assignment in assignments if isinstance(assignments, list) else []:
            assignment_raw = nested(assignment, "value", "RawData", "value", default={})
            worker_key = normalized_id(
                nested(assignment_raw, "assigned_individual_id", "instance_id", default="")
            )
            if worker_key:
                tasks_by_worker[worker_key] = owner_name

    guild_storage = {}
    research_by_guild = {}
    for entry in nested(world, "GuildExtraSaveDataMap", "value", default=[]):
        group_key = normalized_id(entry.get("key"))
        value = entry.get("value") if isinstance(entry.get("value"), dict) else {}
        storage_id = nested(
            value, "GuildItemStorage", "value", "RawData", "value", "container_id", default=""
        )
        if storage_id:
            guild_storage[group_key] = container_inventory(
                storage_id, item_records, dynamic_items, catalogs
            )
        lab = nested(value, "Lab", "value", "RawData", "value", default={})
        if isinstance(lab, dict) and lab:
            current_id = str(lab.get("current_research_id") or "")
            if current_id.casefold() == "none":
                current_id = ""
            completed = [
                str(row.get("research_id") or "")
                for row in lab.get("research_info", [])
                if isinstance(row, dict) and float(row.get("work_amount") or 0) > 0
            ]
            research_by_guild[group_key] = {
                "current": current_id or None,
                "completed": len([value for value in completed if value]),
            }

    public_bases = []
    private_bases = []
    bases = nested(world, "BaseCampSaveData", "value", default=[])
    for index, base in enumerate(bases, start=1):
        base_key = normalized_id(base.get("key"))
        raw = nested(base, "value", "RawData", "value", default={})
        group_key = normalized_id(raw.get("group_id_belong_to"))
        guild = group_lookup.get(group_key, {
            "key": f"guild_{public_hash(group_key)}",
            "name": "Guilde",
            "campLevel": 1,
            "players": [],
        })
        worker_id = nested(
            base, "value", "WorkerDirector", "value", "RawData", "value", "container_id", default=""
        )
        workers = []
        slots = character_containers.get(normalized_id(worker_id), [])
        for slot in slots if isinstance(slots, list) else []:
            slot_raw = nested(slot, "RawData", "value", default={})
            worker_key = normalized_id(slot_raw.get("instance_id"))
            character = character_lookup.get(worker_key)
            if not character:
                counters["unresolvedBaseWorkers"] += 1
                continue
            params = save_parameter(character)
            worker = pal_details(
                params, "base", catalogs, drift, guild.get("players") or []
            )
            worker["task"] = tasks_by_worker.get(worker_key)
            workers.append(worker)
        workers.sort(key=lambda row: (-row["level"], row["name"].casefold()))

        structures = structures_by_base.get(base_key, [])
        categories = Counter(row["category"] for row in structures)
        highlights = Counter(row["name"] for row in structures)
        all_inventory_units = private_storage_by_base.get(base_key, [])
        private_units = [
            unit for unit in all_inventory_units if unit.get("kind") == "storage"
        ]
        production_units = [
            unit for unit in all_inventory_units if unit.get("kind") == "production"
        ]
        top_items, item_categories = public_item_totals(private_units)
        production_items, production_categories = public_item_totals(production_units)
        capacity = sum(unit["capacity"] for unit in private_units)
        used = sum(unit["used"] for unit in private_units)
        production_capacity = sum(unit["capacity"] for unit in production_units)
        production_used = sum(unit["used"] for unit in production_units)
        work_rows = works_by_base.get(base_key, [])
        active_work = [row for row in work_rows if row["progressPercent"] is not None and row["progressPercent"] < 100]
        position = map_position_from_translation(nested(raw, "transform", "translation", default={}))
        name = base_display_name(raw.get("name"), guild["name"], index)
        public = {
            "name": name,
            "guild": guild["name"],
            "guildKey": guild["key"],
            "players": guild["players"],
            "campLevel": guild["campLevel"],
            "position": position,
            "areaRange": round(float(raw.get("area_range") or 0), 1),
            "state": "active" if to_int(raw.get("state"), 0) == 1 else "inactive",
            "workers": {
                "assigned": len(workers),
                "busy": sum(1 for worker in workers if worker.get("task")),
                "healthy": sum(1 for worker in workers if not worker.get("healthStatus")),
                "unwell": sum(1 for worker in workers if worker.get("healthStatus")),
                "list": workers,
            },
            "structures": {
                "total": len(structures),
                "damaged": sum(1 for row in structures if row["damaged"]),
                "unfinished": sum(1 for row in structures if not row["completed"]),
                "categories": [
                    {"name": category, "count": count}
                    for category, count in categories.most_common()
                ],
                "highlights": [
                    {"name": item_name, "count": count}
                    for item_name, count in highlights.most_common(12)
                ],
                "states": [
                    {
                        "key": row["key"],
                        "name": row["name"],
                        "damaged": row["damaged"],
                        "healthPercent": row["healthPercent"],
                    }
                    for row in structures
                    if row.get("key")
                ],
            },
            "storage": {
                "units": len(private_units),
                "capacity": capacity,
                "used": used,
                "fillPercent": round(used / capacity * 100, 1) if capacity else 0,
                "itemTypes": len(top_items),
                "categories": item_categories,
                "topItems": top_items,
            },
            "production": {
                "units": len(production_units),
                "capacity": production_capacity,
                "used": production_used,
                "fillPercent": (
                    round(production_used / production_capacity * 100, 1)
                    if production_capacity
                    else 0
                ),
                "itemTypes": len(production_items),
                "categories": production_categories,
                "topItems": production_items,
            },
            "work": {
                "total": len(work_rows),
                "active": len(active_work),
                "assignedWorkers": sum(1 for worker in workers if worker.get("task")),
                "bufferedItems": sum(unit["used"] for unit in production_units),
                "jobs": sorted(active_work, key=lambda row: row["name"].casefold())[:12],
            },
            "research": research_by_guild.get(group_key, {"current": None, "completed": 0}),
        }
        public_bases.append(public)
        private_bases.append(
            {
                "name": name,
                "guild": guild["name"],
                "position": nested(raw, "transform", "translation", default=None),
                "storage": {"containers": all_inventory_units},
            }
        )

    public_bases.sort(key=lambda row: (row["guild"].casefold(), row["name"].casefold()))
    private_bases.sort(key=lambda row: (row["guild"].casefold(), row["name"].casefold()))
    shared_storage = []
    private_shared_storage = []
    for group_key, inventory in guild_storage.items():
        guild = group_lookup.get(group_key, {"name": "Guilde", "players": []})
        top_items, categories = public_item_totals([inventory])
        shared_storage.append(
            {
                "guild": guild["name"],
                "players": guild["players"],
                "units": 1,
                "capacity": inventory["capacity"],
                "used": inventory["used"],
                "fillPercent": (
                    round(inventory["used"] / inventory["capacity"] * 100, 1)
                    if inventory["capacity"]
                    else 0
                ),
                "itemTypes": len(top_items),
                "categories": categories,
                "topItems": top_items,
            }
        )
        private_shared_storage.append({"guild": guild["name"], **inventory})

    guild_research = []
    for group_key, research in research_by_guild.items():
        guild = group_lookup.get(group_key, {
            "key": f"guild_{public_hash(group_key)}",
            "name": "Guilde",
            "players": [],
        })
        guild_research.append({
            "key": guild["key"],
            "guild": guild["name"],
            "players": guild["players"],
            "current": research.get("current"),
            "completed": int(research.get("completed") or 0),
        })
    guild_research.sort(key=lambda row: (row["guild"].casefold(), row["key"]))

    provenance = {
        "observedAt": captured_at,
        "sourceUpdatedAt": source_updated_at,
        "gameVersion": source_provenance.get("gameVersion"),
        "steamBuildId": source_provenance.get("steamBuildId"),
        "parserCommit": source_provenance.get("parserCommit") or parser_sha or None,
        "catalogCommit": source_provenance.get("catalogCommit") or parser_sha or None,
        "schemaVersion": PROJECTION_VERSION,
        "freshness": "current",
        "sourceStatus": "available",
    }
    public_payload = {
        "version": 1,
        "ok": True,
        "generationId": generation_id,
        "updatedAt": captured_at,
        "source": {"type": "palworld-built-in-backup", "backup": source_name},
        "parser": {"name": "PalworldSaveTools", "commit": parser_sha},
        "provenance": provenance,
        "summary": {
            "bases": len(public_bases),
            "workers": sum(base["workers"]["assigned"] for base in public_bases),
            "structures": sum(base["structures"]["total"] for base in public_bases),
            "storageUnits": sum(base["storage"]["units"] for base in public_bases),
            "productionUnits": sum(base["production"]["units"] for base in public_bases),
            "guildStorageUnits": len(shared_storage),
            "activeJobs": sum(base["work"]["active"] for base in public_bases),
            "busyWorkers": sum(base["workers"]["busy"] for base in public_bases),
        },
        "bases": public_bases,
        "guildResearch": guild_research,
        "guildStorage": shared_storage,
    }
    private_payload = {
        "version": 1,
        "ok": True,
        "updatedAt": captured_at,
        "warning": "Private operational data. Never publish this file.",
        "bases": private_bases,
        "guildStorage": private_shared_storage,
    }
    validate_public_payload(public_payload)
    return public_payload, private_payload


def resolve_skill(value, catalog, prefix=""):
    asset = str(value or "")
    if prefix and asset.startswith(prefix):
        asset = asset[len(prefix) :]
    info = catalog.get(asset.casefold(), {})
    return {
        "name": str(info.get("name") or asset.replace("_", " ")),
        "description": info.get("description"),
        "rank": to_int(info.get("rank"), 0),
        "power": to_int(info.get("display_power"), 0) or None,
        "cooldown": info.get("cooldown"),
        "element": info.get("element"),
    }


def catalog_contains(value, catalog, prefix=""):
    asset = str(value or "")
    if prefix and asset.startswith(prefix):
        asset = asset[len(prefix) :]
    return bool((catalog or {}).get(asset.casefold()))


def experience_progress(level, experience, table, pal=False):
    level = max(1, to_int(level, 1))
    experience = max(0, to_int(experience, 0))
    current = table.get(level) if isinstance(table, dict) else None
    following = table.get(level + 1) if isinstance(table, dict) else None
    if not isinstance(current, dict) or not isinstance(following, dict):
        return None
    total_key = "PalTotalEXP" if pal else "TotalEXP"
    current_total = max(0, to_int(current.get(total_key), 0))
    next_total = max(current_total, to_int(following.get(total_key), current_total))
    required = next_total - current_total
    if required <= 0:
        return None
    gained = min(required, max(0, experience - current_total))
    return {
        "level": level,
        "nextLevel": level + 1,
        "gained": gained,
        "required": required,
        "remaining": max(0, next_total - experience),
        "percent": round(gained / required * 100, 1),
    }


def friendship_progress(points, thresholds):
    points = to_int(points, 0)
    rows = [row for row in thresholds or [] if isinstance(row, dict)]
    if not rows:
        rank = friendship_rank(points)
        return {"points": points, "rank": rank, "nextRank": None, "remaining": None}
    current = max(
        (row for row in rows if to_int(row.get("required"), 0) <= points),
        key=lambda row: to_int(row.get("required"), 0),
        default=rows[0],
    )
    following = next(
        (row for row in rows if to_int(row.get("required"), 0) > points),
        None,
    )
    current_required = to_int(current.get("required"), 0)
    next_required = to_int(following.get("required"), 0) if following else current_required
    span = max(0, next_required - current_required)
    gained = max(0, points - current_required)
    return {
        "points": points,
        "rank": to_int(current.get("rank"), 0),
        "nextRank": to_int(following.get("rank"), 0) if following else None,
        "remaining": max(0, next_required - points) if following else 0,
        "percent": round(min(span, gained) / span * 100, 1) if span else 100.0,
    }


def upcoming_learnset(species_name, level, catalogs, limit=3):
    rows = (catalogs.get("learnsets") or {}).get(str(species_name or "").casefold(), [])
    upcoming = []
    for row in rows:
        unlock_level = to_int(row.get("level"), 0)
        if unlock_level <= to_int(level, 0):
            continue
        skill = resolve_skill(row.get("WazaID"), catalogs.get("skills") or {}, "EPalWazaID::")
        upcoming.append({"level": unlock_level, **skill})
    upcoming.sort(key=lambda row: (row["level"], row["name"].casefold()))
    return upcoming[: max(0, int(limit))]


def friendship_rank(points):
    thresholds = [0, 6000, 13000, 21000, 30000, 40000, 55000, 80000, 110000, 150000, 200000]
    for rank in range(len(thresholds) - 1, 0, -1):
        if to_int(points, 0) >= thresholds[rank]:
            return rank
    return 0


def passive_stat_bonus(passive_values, catalog, effect_name):
    total = 0.0
    for passive in passive_values:
        info = catalog.get(str(passive).casefold(), {})
        for index in range(1, 5):
            effect = str(info.get(f"efftype{index}") or "")
            target = str(info.get(f"target_type{index}") or "")
            if "ToTrainer" in target and "ToSelf" not in target:
                continue
            if effect_name in effect:
                if effect_name == "Defense" and any(
                    part in effect for part in ("ElementResist", "Resist", "Rate")
                ):
                    continue
                try:
                    total += float(info.get(f"effect{index}") or 0)
                except (TypeError, ValueError):
                    pass
    return total / 100


def computed_pal_stats(params, info, passive_values, passive_catalog):
    if not info:
        return {"attack": None, "defense": None, "workSpeed": None}
    stats = info.get("stats") or info.get("scaling") or {}
    scaling = info.get("scaling") or stats
    level = to_int(scalar(params.get("Level"), 0), 0)
    rank = to_int(scalar(params.get("Rank"), 1), 1)
    rank = max(1, rank)
    condenser = max(0, rank - 1) * 0.05
    trust = friendship_rank(scalar(params.get("FriendshipPoint"), 0))
    awake = bool(scalar(params.get("bIsAwakening"), False))

    talent_attack = to_int(scalar(params.get("Talent_Shot"), 0), 0)
    attack_iv = talent_attack * 0.3 / 100
    shot_scaling = float(stats.get("shot_attack") or 0)
    attack_base = math.floor(
        1.5 * level
        + shot_scaling * 0.075 * level * (1 + attack_iv) * (1 + condenser)
    )
    trust_attack = math.floor(
        level * trust * float(info.get("friendship_shotattack") or 0) / 10.2
    )
    trust_attack += math.floor(trust_attack * condenser)
    awake_attack = math.floor(shot_scaling * level * (1 + attack_iv) * 0.009) if awake else 0
    attack = math.floor(
        (attack_base + trust_attack + awake_attack)
        * (1 + to_int(scalar(params.get("Rank_Attack"), 0), 0) * 0.03)
        * (1 + passive_stat_bonus(passive_values, passive_catalog, "ShotAttack"))
    )

    talent_defense = to_int(scalar(params.get("Talent_Defense"), 0), 0)
    defense_iv = talent_defense * 0.3 / 100
    defense_scaling = float(scaling.get("defense") or 0)
    defense_base = math.floor(
        0.75 * level
        + defense_scaling * 0.075 * level * (1 + defense_iv) * (1 + condenser)
    )
    trust_defense = math.floor(
        level
        * trust
        * float(info.get("friendship_defense") or 0)
        / 10.2
        * (1 + condenser)
    )
    awake_defense = math.floor(defense_scaling * level * (1 + defense_iv) * 0.009) if awake else 0
    defense = math.floor(
        (defense_base + trust_defense + awake_defense)
        * (1 + to_int(scalar(params.get("Rank_Defence"), 0), 0) * 0.03)
        * (1 + passive_stat_bonus(passive_values, passive_catalog, "Defense"))
    )

    craft_speed = float(stats.get("craft_speed") or 100)
    work_base = 70
    if rank > 1:
        work_base += math.floor(craft_speed * condenser * level / 57)
    work_speed = int(
        work_base
        * (1 + to_int(scalar(params.get("Rank_CraftSpeed"), 0), 0) * 0.03)
        * (1 + passive_stat_bonus(passive_values, passive_catalog, "CraftSpeed"))
        + 0.5
    )
    return {"attack": attack, "defense": defense, "workSpeed": work_speed}


def computed_max_hp(params, info, passive_values, passive_catalog):
    if not info:
        return None
    scaling = info.get("scaling") or info.get("stats") or {}
    level = to_int(scalar(params.get("Level"), 0), 0)
    rank = max(1, to_int(scalar(params.get("Rank"), 1), 1))
    condenser = max(0, rank - 1) * 0.05
    talent = to_int(scalar(params.get("Talent_HP"), 0), 0)
    hp_scaling = float(scaling.get("hp") or 0)
    base = math.floor(500 + 5 * level + hp_scaling * 0.5 * level * (1 + talent * 0.3 / 100))
    base = math.floor(base * (1 + condenser))
    trust = friendship_rank(scalar(params.get("FriendshipPoint"), 0))
    trust_bonus = int(
        level * trust * float(info.get("friendship_hp") or 0) * 0.65 * (1 + condenser) + 0.5
    )
    awake_bonus = (
        math.floor(hp_scaling * level * 0.065 * (1 + condenser))
        if bool(scalar(params.get("bIsAwakening"), False))
        else 0
    )
    result = math.floor(
        (base + trust_bonus + awake_bonus)
        * (1 + to_int(scalar(params.get("Rank_HP"), 0), 0) * 0.03)
        * (1 + passive_stat_bonus(passive_values, passive_catalog, "MaxHP"))
    )
    return result


def work_suitabilities(params, info):
    base = dict(info.get("work_suitabilities") or {})
    additions = {}
    for row in array_values(params.get("GotWorkSuitabilityAddRankList", {})):
        work = str(scalar(row.get("WorkSuitability"), "")).split("::")[-1]
        if work:
            additions[work] = to_int(scalar(row.get("Rank"), 0), 0)
    passive_values = array_values(params.get("PassiveSkillList", {}))
    for passive in passive_values:
        text = str(passive)
        if text.startswith("WorkSuitabilityAddRank_"):
            work = text.removeprefix("WorkSuitabilityAddRank_")
            additions[work] = additions.get(work, 0) + 1
    result = []
    for key in sorted(set(base) | set(additions)):
        level = to_int(base.get(key), 0) + to_int(additions.get(key), 0)
        if level <= 0:
            continue
        result.append(
            {
                "name": WORK_LABELS.get(key, key),
                "level": level,
                "bonus": to_int(additions.get(key), 0),
            }
        )
    return result


def health_status(params):
    values = []
    for key in ("WorkerSick", "PhysicalHealth"):
        value = str(scalar(params.get(key), "") or "").split("::")[-1]
        if value and value.casefold() not in {"none", "healthy", "normal"}:
            values.append(value)
    if not values:
        return None
    combined = " ".join(values).casefold()
    labels = (
        ("depression", "Dépression"),
        ("fracture", "Fracture"),
        ("sprain", "Entorse"),
        ("ulcer", "Ulcère"),
        ("cold", "Rhume"),
        ("weak", "Affaibli"),
        ("overfull", "Repus"),
    )
    resolved = [label for key, label in labels if key in combined]
    return " et ".join(resolved) if resolved else "Affecté"


def owned_at(prop):
    ticks = to_int(scalar(prop, 0), 0)
    if ticks <= 0:
        return None
    try:
        acquired = datetime(1, 1, 1, tzinfo=timezone.utc) + timedelta(
            microseconds=ticks // 10
        )
    except (OverflowError, ValueError):
        return None
    now = datetime.now(timezone.utc)
    if acquired.year < 2024 or acquired > now + timedelta(days=1):
        return None
    return acquired.isoformat()


def pal_details(params, container, catalogs, drift=None, player_name=None):
    asset = str(scalar(params.get("CharacterID"), "Pal inconnu"))
    info = catalogs["pals"].get(asset.casefold(), {})
    if not info:
        record_catalog_drift(drift, "pal-species", asset, player_name)
    nickname = str(scalar(params.get("NickName"), "") or "")
    gender = str(scalar(params.get("Gender"), "") or "").replace("EPalGenderType::", "")
    passive_values = array_values(params.get("PassiveSkillList", {}))
    active_values = array_values(params.get("EquipWaza", {}))
    learned_values = array_values(params.get("MasteredWaza", {}))
    for value in passive_values:
        if not catalog_contains(value, catalogs["passives"]):
            record_catalog_drift(drift, "passive-skill", value, player_name)
    for value in [*active_values, *learned_values]:
        if not catalog_contains(value, catalogs["skills"], "EPalWazaID::"):
            record_catalog_drift(drift, "active-skill", value, player_name)
    level = to_int(scalar(params.get("Level"), 0), 0)
    experience = to_int(scalar(params.get("Exp"), 0), 0)
    friendship_points = to_int(scalar(params.get("FriendshipPoint"), 0), 0)
    species_name = str(info.get("name") or asset)
    return {
        "name": nickname or str(info.get("name") or asset),
        "species": species_name,
        "icon": web_icon(info.get("icon")),
        "level": level,
        "experience": experience,
        "experienceProgress": experience_progress(
            level, experience, catalogs.get("experience") or {}, pal=True
        ),
        "nextLearnedSkills": upcoming_learnset(species_name, level, catalogs),
        "gender": gender or None,
        "container": container,
        "hp": fixed_point(params.get("Hp", {})),
        "maxHp": computed_max_hp(params, info, passive_values, catalogs["passives"]),
        "hunger": round(float(scalar(params.get("FullStomach"), 0) or 0), 1),
        "sanity": (
            round(float(scalar(params.get("SanityValue"), 0) or 0), 1)
            if "SanityValue" in params
            else None
        ),
        "friendship": friendship_points,
        "friendshipProgress": friendship_progress(
            friendship_points, catalogs.get("friendship") or []
        ),
        "rarity": to_int(nested(info, "stats", "rarity", default=0), 0) or None,
        "rank": to_int(scalar(params.get("Rank"), 0), 0) if "Rank" in params else None,
        "lucky": bool(scalar(params.get("IsRarePal"), False)),
        "boss": asset.upper().startswith("BOSS_"),
        "awakening": bool(scalar(params.get("bIsAwakening"), False)),
        "favorite": to_int(scalar(params.get("FavoriteIndex"), 0), 0) > 0,
        "imported": bool(scalar(params.get("bImportedCharacter"), False)),
        "talents": {
            "hp": to_int(scalar(params.get("Talent_HP"), 0), 0),
            "attack": to_int(scalar(params.get("Talent_Shot"), 0), 0),
            "defense": to_int(scalar(params.get("Talent_Defense"), 0), 0),
        },
        "souls": {
            "hp": to_int(scalar(params.get("Rank_HP"), 0), 0),
            "attack": to_int(scalar(params.get("Rank_Attack"), 0), 0),
            "defense": to_int(scalar(params.get("Rank_Defence"), 0), 0),
            "workSpeed": to_int(scalar(params.get("Rank_CraftSpeed"), 0), 0),
        },
        "computedStats": computed_pal_stats(
            params, info, passive_values, catalogs["passives"]
        ),
        "passives": [resolve_skill(value, catalogs["passives"]) for value in passive_values],
        "activeSkills": [
            resolve_skill(value, catalogs["skills"], "EPalWazaID::")
            for value in active_values
        ],
        "learnedSkills": [
            resolve_skill(value, catalogs["skills"], "EPalWazaID::")
            for value in learned_values
        ],
        "workSuitabilityBonuses": work_suitabilities(params, info),
        "healthStatus": health_status(params),
        "ownedAt": owned_at(params.get("OwnedTime", {})),
        "position": public_position(params.get("LastJumpedLocation", {})),
    }


def status_allocations(params):
    labels = {
        "最大HP": "Santé",
        "最大SP": "Endurance",
        "攻撃力": "Attaque",
        "所持重量": "Poids",
        "捕獲率": "Capture",
        "作業速度": "Travail",
        "移動速度アップ": "Vitesse",
        "空腹率低減": "Réduction de la faim",
        "泳ぎ速度": "Vitesse de nage",
        "パルスフィアホーミング": "Guidage des sphères",
    }
    result = []
    for row in array_values(params.get("GotStatusPointList", {})):
        name = str(scalar(row.get("StatusName"), "Statistique"))
        public_name = labels.get(name, name)
        if re.search(r"[\u3040-\u30ff\u3400-\u9fff\uf900-\ufaff]", public_name):
            public_name = "Bonus spécial"
        result.append(
            {"name": public_name, "points": to_int(scalar(row.get("StatusPoint"), 0), 0)}
        )
    return result


def canonical_pal(asset, catalogs):
    normalized = str(asset)
    direct = catalogs["canonicalPals"].get(normalized.casefold())
    if direct:
        return direct
    normalized = re.sub(
        r"^(BOSS_|GYM_|RAID_|SUMMON_|PREDATOR_|NPC_)+", "", normalized, flags=re.I
    )
    normalized = re.sub(
        r"(_OILRIG|_RAID|_MAX|_SUMMON|_NPC|_TOWER)+$", "", normalized, flags=re.I
    )
    return catalogs["canonicalPals"].get(normalized.casefold())


def player_paldex(sections, catalogs, counters, drift=None, player_name=None):
    capture_map = integer_map(record_property(sections, "PalCaptureCount"))
    challenge_map = integer_map(record_property(sections, "PalCaptureBonusCount"))
    encountered = true_map_keys(record_property(sections, "PaldeckUnlockFlag"))
    captured_by_species = Counter()
    challenge_by_species = Counter()
    encountered_species = set()
    for asset, count in capture_map.items():
        canonical = canonical_pal(asset, catalogs)
        if canonical:
            captured_by_species[str(canonical.get("asset"))] += count
        else:
            counters["unknownPalCaptureAssets"] += 1
            record_catalog_drift(drift, "pal-capture", asset, player_name)
    for asset, count in challenge_map.items():
        canonical = canonical_pal(asset, catalogs)
        if canonical:
            challenge_by_species[str(canonical.get("asset"))] += count
        else:
            counters["unknownPalChallengeAssets"] += 1
            record_catalog_drift(drift, "pal-capture-challenge", asset, player_name)
    for asset in encountered:
        canonical = canonical_pal(asset, catalogs)
        if canonical:
            encountered_species.add(str(canonical.get("asset")))
        else:
            counters["unknownPaldeckAssets"] += 1
            record_catalog_drift(drift, "paldex", asset, player_name)

    rows = []
    for species in catalogs["species"]:
        asset = species["asset"]
        count = captured_by_species.get(asset, 0)
        challenge_count = min(5, challenge_by_species.get(asset, 0))
        seen = asset in encountered_species or count > 0
        rows.append(
            {
                "index": species["index"],
                "name": species["name"],
                "icon": species["icon"],
                "encountered": seen,
                "captured": count > 0,
                "captureCount": count,
                "challengeCount": challenge_count,
                "challengeTarget": 5,
                "challengeComplete": challenge_count >= 5,
            }
        )
    total_species = len(catalogs["species"])
    captured_species = sum(1 for count in captured_by_species.values() if count > 0)
    return {
        "encounteredSpecies": len(encountered_species | set(captured_by_species)),
        "capturedSpecies": captured_species,
        "totalSpecies": total_species,
        "totalCaptures": sum(captured_by_species.values()),
        "captureChallengesCompleted": sum(
            1 for count in challenge_by_species.values() if count >= 5
        ),
        "completionPercent": round(captured_species / total_species * 100, 1) if total_species else None,
        "species": rows,
    }


def player_bosses(sections, catalogs, counters, drift=None, player_name=None):
    normal_flags = true_map_keys(record_property(sections, "NormalBossDefeatFlag"))
    tower_flags = true_map_keys(record_property(sections, "TowerBossDefeatFlag"))
    defeated = []
    seen = set()
    for flag in normal_flags:
        reward = catalogs["bossByFlag"].get(flag)
        asset = str(reward or "").removeprefix("BossDefeatReward_")
        canonical = canonical_pal(asset, catalogs)
        if not canonical:
            counters["unknownBossFlags"] += 1
            record_catalog_drift(drift, "boss-flag", flag, player_name)
            continue
        name = str(canonical.get("name") or asset)
        if name.casefold() in seen:
            continue
        seen.add(name.casefold())
        defeated.append({
            "name": name,
            "asset": str(canonical.get("asset") or asset),
            "icon": web_icon(canonical.get("icon")),
        })
    defeated.sort(key=lambda row: row["name"].casefold())
    return {
        "defeated": len(normal_flags) + len(tower_flags),
        "normalDefeated": len(normal_flags),
        "normalKnownTotal": catalogs["bossTotal"],
        "towerDefeated": len(tower_flags),
        "known": defeated,
    }


def player_exploration(sections, catalogs, counters, drift=None, player_name=None):
    fast = true_map_keys(record_property(sections, "FastTravelPointUnlockFlag"))
    areas = true_map_keys(record_property(sections, "FindAreaFlagMap"))
    world_maps = true_map_keys(record_property(sections, "UnlockedWorldMapFlags"))
    known_fast = fast & set(catalogs["fastTravel"])
    known_areas = areas & catalogs["areas"]
    counters["unknownFastTravelPoints"] += len(fast - known_fast)
    counters["unknownAreas"] += len(areas - known_areas)
    for identifier in fast - known_fast:
        record_catalog_drift(drift, "fast-travel", identifier, player_name)
    for identifier in areas - known_areas:
        record_catalog_drift(drift, "map-area", identifier, player_name)
    points = sorted(
        {
            str(catalogs["fastTravel"][key].get("localized_name") or "Point de voyage")
            for key in known_fast
        },
        key=str.casefold,
    )
    measured = len(known_fast) + len(known_areas)
    total = len(catalogs["fastTravel"]) + len(catalogs["areas"])
    return {
        "fastTravelUnlocked": len(known_fast),
        "fastTravelTotal": len(catalogs["fastTravel"]),
        "areasDiscovered": len(known_areas),
        "areasTotal": len(catalogs["areas"]),
        "worldMapsUnlocked": len(world_maps),
        "completionPercent": round(measured / total * 100, 1) if total else None,
        "fastTravelPoints": points,
    }


def player_technologies(player_data, catalogs, counters, drift=None, player_name=None):
    unlocked = array_values(player_data.get("UnlockedRecipeTechnologyNames", {}))
    rows = []
    seen = set()
    for asset in unlocked:
        key = str(asset).casefold()
        if key in seen:
            continue
        seen.add(key)
        info = catalogs["technology"].get(key)
        if not info:
            counters["unknownTechnologies"] += 1
            record_catalog_drift(drift, "technology", asset, player_name)
            continue
        rows.append(
            {
                "name": str(info.get("name") or asset),
                "icon": web_icon(info.get("icon")),
                "level": to_int(info.get("level_cap"), 0),
                "tier": to_int(info.get("tier"), 0),
                "type": "ancienne" if info.get("is_boss_tech") else "normale",
            }
        )
    rows.sort(key=lambda row: (row["level"], row["name"].casefold()))
    return rows


def player_relics(sections, catalogs):
    values = integer_map(record_property(sections, "RelicPossessNumMap"))
    rows = []
    for key, rank in values.items():
        info = catalogs["relics"].get(key, {})
        short = key.split("::")[-1]
        rows.append(
            {
                "name": RELIC_LABELS.get(short, short),
                "rank": rank,
                "maxRank": to_int(info.get("max_rank"), 0) or None,
            }
        )
    rows.sort(key=lambda row: row["name"].casefold())
    current = sum(row["rank"] for row in rows)
    maximum = sum(row["maxRank"] or 0 for row in rows)
    return {
        "totalRanks": current,
        "maximumRanks": maximum or None,
        "completionPercent": round(current / maximum * 100, 1) if maximum else None,
        "categories": rows,
    }


def build_snapshot(
    level_payload,
    player_saves,
    catalogs,
    captured_at,
    source_name,
    parser_sha,
    provenance=None,
):
    world_data = nested(level_payload, "properties", "worldSaveData", "value", default={})
    characters = nested(world_data, "CharacterSaveParameterMap", "value", default=[])
    groups = nested(world_data, "GroupSaveDataMap", "value", default=[])
    bases = nested(world_data, "BaseCampSaveData", "value", default=[])
    containers = item_container_map(world_data)
    counters = Counter()
    drift = {}
    provenance = provenance or {}
    public_player_names = player_names_by_uid(characters)

    guild_by_player = {}
    public_guilds = []
    for group in groups:
        raw = nested(group, "value", "RawData", "value", default={})
        if raw.get("group_type") != "EPalGroupType::Guild":
            continue
        members = raw.get("players") if isinstance(raw.get("players"), list) else []
        name = str(raw.get("guild_name") or raw.get("group_name") or "Guilde")
        base_ids = raw.get("base_ids") if isinstance(raw.get("base_ids"), list) else []
        camp_level = to_int(scalar(raw.get("base_camp_level"), 1), 1)
        guild_info = {"name": name, "bases": len(base_ids), "campLevel": camp_level}
        for member in members:
            uid = uid_key(member.get("player_uid"))
            if uid:
                guild_by_player[uid] = guild_info
        public_guilds.append(
            {
                "key": f"guild_{public_hash(normalized_id(group.get('key')))}",
                "name": name,
                "players": len(members),
                "bases": len(base_ids),
                "campLevel": camp_level,
            }
        )

    pal_entries = [entry for entry in characters if not is_player(entry)]
    public_players = []
    known_pal_fields = {
        "CharacterID", "NickName", "Gender", "Level", "Exp", "Hp", "FullStomach",
        "FriendshipPoint", "Talent_HP", "Talent_Shot", "Talent_Defense", "PassiveSkillList",
        "EquipWaza", "MasteredWaza", "Rank", "Rank_HP", "Rank_Attack", "Rank_Defence",
        "Rank_CraftSpeed", "IsRarePal", "bIsAwakening", "FavoriteIndex",
        "bImportedCharacter", "SanityValue", "GotWorkSuitabilityAddRankList", "WorkerSick",
        "PhysicalHealth", "OwnedTime", "LastJumpedLocation", "SlotId", "OwnerPlayerUId",
        "OldOwnerPlayerUIds", "GotStatusPointList", "GotExStatusPointList",
        "LastNickNameModifierPlayerUid", "IsPlayer", "ShieldHP", "UnusedStatusPoint",
    }
    unknown_pal_fields = set()

    for entry in characters:
        if not is_player(entry):
            continue
        params = save_parameter(entry)
        player_name = str(scalar(params.get("NickName"), "Joueur"))
        uid = player_uid(entry)
        normalized_uid = uid_key(uid)
        guild_info = guild_by_player.get(normalized_uid, {})
        player_data, party_id, palbox_id = player_saves.get(uid, ({}, "", ""))
        sections = record_sections(player_data)
        counts = Counter()
        pal_levels = []
        party_count = 0
        palbox_count = 0
        detailed_pals = []
        for pal in pal_entries:
            pal_params = save_parameter(pal)
            slot_container = container_id(
                nested(pal_params, "SlotId", "value", "ContainerId", default={})
            )
            owner = uid_key(pal_params.get("OwnerPlayerUId", {}))
            belongs = (slot_container and slot_container in {party_id, palbox_id}) or owner == normalized_uid
            if not belongs:
                continue
            unknown_pal_fields.update(set(pal_params) - known_pal_fields)
            asset = str(scalar(pal_params.get("CharacterID"), "Pal inconnu"))
            counts[asset] += 1
            pal_levels.append(to_int(scalar(pal_params.get("Level"), 0), 0))
            party_count += int(bool(party_id and slot_container == party_id))
            palbox_count += int(bool(palbox_id and slot_container == palbox_id))
            container = "party" if party_id and slot_container == party_id else (
                "palbox" if palbox_id and slot_container == palbox_id else "other"
            )
            detailed_pals.append(
                pal_details(pal_params, container, catalogs, drift, player_name)
            )

        detailed_pals.sort(
            key=lambda pal: (
                0 if pal["container"] == "party" else 1,
                -pal["level"],
                pal["name"].casefold(),
            )
        )
        top_species = []
        for asset, count in counts.most_common(3):
            info = catalogs["pals"].get(asset.casefold(), {})
            if not info:
                record_catalog_drift(drift, "pal-species", asset, player_name)
            top_species.append(
                {"name": str(info.get("name") or asset), "count": count, "icon": web_icon(info.get("icon"))}
            )

        paldex = player_paldex(sections, catalogs, counters, drift, player_name)
        bosses = player_bosses(sections, catalogs, counters, drift, player_name)
        exploration = player_exploration(
            sections, catalogs, counters, drift, player_name
        )
        technologies = player_technologies(
            player_data, catalogs, counters, drift, player_name
        )
        quests = player_quests(player_data)
        challenges = player_challenges(sections)
        records = player_records(sections, catalogs, drift, player_name)
        player_level = to_int(scalar(params.get("Level"), 0), 0)
        player_experience = to_int(scalar(params.get("Exp"), 0), 0)
        public_players.append(
            {
                "key": f"player_{public_hash(normalized_uid)}",
                "name": player_name,
                "level": player_level,
                "guild": guild_info.get("name"),
                "guildBases": guild_info.get("bases"),
                "campLevel": guild_info.get("campLevel"),
                "position": public_position(params.get("LastJumpedLocation", {})),
                "character": {
                    "experience": to_int(scalar(params.get("Exp"), 0), 0),
                    "experienceProgress": experience_progress(
                        player_level,
                        player_experience,
                        catalogs.get("experience") or {},
                    ),
                    "hp": fixed_point(params.get("Hp", {})),
                    "shield": fixed_point(params.get("ShieldHP", {})),
                    "hunger": round(float(scalar(params.get("FullStomach"), 0) or 0), 1),
                    "unusedStatusPoints": to_int(scalar(params.get("UnusedStatusPoint"), 0), 0),
                    "allocations": status_allocations(params),
                },
                "pals": {
                    "total": sum(counts.values()),
                    "party": party_count,
                    "palbox": palbox_count,
                    "uniqueSpecies": len(counts),
                    "highestLevel": max(pal_levels, default=0),
                    "favorites": top_species,
                    "collection": detailed_pals,
                },
                "inventory": player_inventory(
                    player_data,
                    containers,
                    catalogs["items"],
                    drift,
                    player_name,
                ),
                "progress": {
                    "technologyPoints": to_int(scalar(player_data.get("TechnologyPoint"), 0), 0),
                    "bossTechnologyPoints": to_int(scalar(player_data.get("bossTechnologyPoint"), 0), 0),
                    "unlockedTechnologies": array_count(player_data.get("UnlockedRecipeTechnologyNames", {})),
                    "completedQuests": quests["completedCount"],
                    "quests": quests,
                    "challenges": challenges,
                    "records": records,
                    "paldex": paldex,
                    "bosses": bosses,
                    "exploration": exploration,
                    "technologies": technologies,
                    "relics": player_relics(sections, catalogs),
                },
            }
        )

    counters["unknownPalProperties"] = len(unknown_pal_fields)
    public_players.sort(key=lambda player: (-player["level"], player["name"].casefold()))
    public_guilds.sort(key=lambda guild: guild["name"].casefold())
    source_updated_at = provenance.get("sourceUpdatedAt") or captured_at
    generation_id = public_save_generation_id(
        source_name,
        source_updated_at,
        parser_sha,
        PROJECTION_VERSION,
    )
    snapshot = {
        "version": 3,
        "projection": {"version": PROJECTION_VERSION},
        "ok": True,
        "generationId": generation_id,
        "updatedAt": captured_at,
        "source": {"type": "palworld-built-in-backup", "backup": source_name},
        "parser": {"name": "PalworldSaveTools", "commit": parser_sha},
        "provenance": {
            "observedAt": captured_at,
            "sourceUpdatedAt": source_updated_at,
            "gameVersion": provenance.get("gameVersion"),
            "steamBuildId": provenance.get("steamBuildId"),
            "parserCommit": provenance.get("parserCommit") or parser_sha or None,
            "catalogCommit": provenance.get("catalogCommit") or parser_sha or None,
            "schemaVersion": PROJECTION_VERSION,
            "freshness": "current",
            "sourceStatus": "available",
        },
        "summary": {
            "players": len(public_players),
            "pals": sum(player["pals"]["total"] for player in public_players),
            "guilds": len(public_guilds),
            "bases": len(bases),
        },
        "world": {
            "paldexSpecies": len(catalogs["species"]),
            "fastTravelPoints": len(catalogs["fastTravel"]),
            "discoverableAreas": len(catalogs["areas"]),
            "knownBosses": catalogs["bossTotal"],
            "deathDrops": death_drop_state(world_data, public_player_names),
        },
        # Base details remain intentionally empty until their heavy decoders and
        # public location policy are validated independently.
        "bases": [],
        "guilds": public_guilds,
        "players": public_players,
    }
    public_bases, private_bases = build_base_snapshots(
        world_data,
        catalogs,
        captured_at,
        source_name,
        parser_sha,
        counters,
        drift,
        provenance,
        generation_id,
    )
    validate_public_payload(snapshot)
    return snapshot, counters, public_bases, private_bases, drift


def validate_public_payload(payload, path="$"):
    if isinstance(payload, dict):
        for key, value in payload.items():
            if key not in PUBLIC_KEY_EXCEPTIONS and FORBIDDEN_PUBLIC_KEY.search(str(key)):
                raise ValueError(f"Forbidden public key at {path}.{key}")
            validate_public_payload(value, f"{path}.{key}")
    elif isinstance(payload, list):
        for index, value in enumerate(payload):
            validate_public_payload(value, f"{path}[{index}]")


def parser_commit(parser_repo: Path) -> str:
    try:
        return subprocess.run(
            ["git", "-C", str(parser_repo), "rev-parse", "--short=12", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        ).stdout.strip()
    except Exception:
        return "unknown"


def json_bytes(payload, pretty=True):
    separators = None if pretty else (",", ":")
    indent = 2 if pretty else None
    return (json.dumps(payload, ensure_ascii=False, indent=indent, separators=separators) + "\n").encode("utf-8")


def write_atomic(path: Path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_bytes(json_bytes(payload))
    temporary.replace(path)


def publish_public_catalogs(
    parser_repo: Path,
    output_root: Path,
    manifest_path: Path,
    provenance: dict | None,
    generated_at: str,
):
    provenance = provenance or {}
    catalog_commit = provenance.get("catalogCommit") or provenance.get("parserCommit")
    resources = parser_repo / "resources" / "game_data"
    source_paths = {
        "experience": resources / "pal_exp_table.json",
        "friendship": resources / "friendship.json",
        "learnsets": resources / "pals_learnset.json",
        "skills": resources / "skills.json",
        "characters": resources / "characters.json",
        "breeding": resources / "breedingdata.json",
    }
    source_state = {
        name: {
            "bytes": path.stat().st_size,
            "modifiedNs": path.stat().st_mtime_ns,
        }
        for name, path in source_paths.items()
    }
    generation_context = {
        "gameVersion": provenance.get("gameVersion"),
        "steamBuildId": provenance.get("steamBuildId"),
        "parserCommit": provenance.get("parserCommit"),
        "catalogCommit": catalog_commit,
    }
    try:
        previous_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, ValueError, TypeError):
        previous_manifest = {}
    previous_files = previous_manifest.get("files") if isinstance(previous_manifest.get("files"), dict) else {}

    def previous_file_is_complete(name):
        entry = previous_files.get(name)
        if not isinstance(entry, dict):
            return False
        relative = str(entry.get("path") or "")
        if not re.fullmatch(rf"public-catalogs/[A-Za-z0-9._-]+/{re.escape(name)}\.json", relative):
            return False
        target = manifest_path.parent / relative
        return target.is_file() and target.stat().st_size == int(entry.get("bytes") or -1)

    if (
        previous_manifest.get("sourceState") == source_state
        and previous_manifest.get("generationContext") == generation_context
        and all(previous_file_is_complete(name) for name in ("progression", "learnsets", "breeding"))
    ):
        return {
            "status": "unchanged",
            "generationId": previous_manifest.get("generationId"),
            "manifestBytes": manifest_path.stat().st_size,
            "catalogBytes": sum(int(entry.get("bytes") or 0) for entry in previous_files.values()),
            "files": len(previous_files),
        }

    source_bytes = {name: path.read_bytes() for name, path in source_paths.items()}
    content_digest = hashlib.sha256(
        b"".join(name.encode("utf-8") + b"\0" + source_bytes[name] for name in sorted(source_bytes))
    ).hexdigest()
    context_digest = hashlib.sha256(
        json.dumps(generation_context, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    safe_commit = re.sub(r"[^A-Za-z0-9._-]+", "-", str(catalog_commit or "catalog")).strip("-._")
    generation_id = f"{(safe_commit or 'catalog')[:24]}-{content_digest[:10]}{context_digest[:6]}"
    generation_root = output_root / generation_id
    generation_generated_at = generated_at
    if (
        previous_manifest.get("generationId") == generation_id
        and previous_manifest.get("contentRevision") == content_digest
        and previous_manifest.get("generatedAt")
    ):
        generation_generated_at = str(previous_manifest["generatedAt"])

    experience = json.loads(source_bytes["experience"].decode("utf-8"))
    friendship = json.loads(source_bytes["friendship"].decode("utf-8"))
    learnsets = json.loads(source_bytes["learnsets"].decode("utf-8"))
    skills = json.loads(source_bytes["skills"].decode("utf-8"))
    characters = json.loads(source_bytes["characters"].decode("utf-8"))
    breeding = json.loads(source_bytes["breeding"].decode("utf-8"))
    pal_names = {
        str(row.get("asset") or "").casefold(): str(row.get("name") or row.get("asset") or "")
        for row in characters.get("pals", [])
        if isinstance(row, dict) and row.get("asset")
    }
    public_learnsets = {}
    for asset, rows in (learnsets.get("learnset") or {}).items():
        if not isinstance(rows, list):
            continue
        public_learnsets[pal_names.get(str(asset).casefold(), str(asset))] = rows
    live_common = {
        "schemaVersion": 1,
        "generationId": generation_id,
        "generatedAt": generation_generated_at,
        "observedAt": generated_at,
        "sourceUpdatedAt": provenance.get("sourceUpdatedAt") or generation_generated_at,
        "gameVersion": provenance.get("gameVersion"),
        "steamBuildId": provenance.get("steamBuildId"),
        "parserCommit": provenance.get("parserCommit"),
        "catalogCommit": catalog_commit or content_digest,
        "freshness": provenance.get("freshness") or "current",
        "sourceStatus": provenance.get("sourceStatus") or "available",
    }
    file_common = live_common
    if previous_manifest.get("generationId") == generation_id:
        file_common = {
            key: previous_manifest.get(key, value)
            for key, value in live_common.items()
        }
    payloads = {
        "progression": {
            **file_common,
            "experience": experience,
            "friendship": friendship,
        },
        "learnsets": {
            **file_common,
            "learnset": public_learnsets,
            "skills": skills.get("skills", []),
        },
        "breeding": {
            **file_common,
            **breeding,
        },
    }
    files = {}
    total_bytes = 0
    for name, payload in payloads.items():
        target = generation_root / f"{name}.json"
        encoded = json_bytes(payload)
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.is_file() and target.read_bytes() != encoded:
            raise RuntimeError(f"Immutable catalog generation changed unexpectedly: {target}")
        if not target.is_file():
            temporary = target.with_suffix(target.suffix + ".tmp")
            temporary.write_bytes(encoded)
            temporary.replace(target)
        relative = target.relative_to(manifest_path.parent).as_posix()
        files[name] = {
            "path": relative,
            "sha256": f"sha256:{hashlib.sha256(encoded).hexdigest()}",
            "bytes": len(encoded),
        }
        total_bytes += len(encoded)

    manifest = {
        **live_common,
        "ok": True,
        "contentRevision": content_digest,
        "sourceState": source_state,
        "generationContext": generation_context,
        "files": files,
    }
    write_atomic(manifest_path, manifest)
    return {
        "status": "written",
        "generationId": generation_id,
        "manifestBytes": len(json_bytes(manifest)),
        "catalogBytes": total_bytes,
        "files": len(files),
    }


def write_gzip_atomic(path: Path, payload) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(f"{path}.tmp")
    with gzip.open(temporary, "wt", encoding="utf-8", compresslevel=6) as stream:
        json.dump(payload, stream, ensure_ascii=False, separators=(",", ":"))
    temporary.replace(path)


def archive_hourly(
    history_root: Path,
    payload,
    retention_days: int,
    rolling_minutes: int = DEFAULT_ROLLING_HISTORY_MINUTES,
):
    timestamp = datetime.fromisoformat(payload["updatedAt"])
    archive = history_root / timestamp.strftime("%Y/%m/%d/%H.json.gz")
    if not archive.exists():
        write_gzip_atomic(archive, payload)

    rolling_root = history_root / "_rolling"
    rolling_archive = rolling_root / timestamp.strftime("%Y/%m/%d/%H%M%S-%f.json.gz")
    write_gzip_atomic(rolling_archive, payload)

    cutoff = time.time() - max(1, retention_days) * 86400
    for old_archive in history_root.glob("*/*/*/*.json.gz"):
        if old_archive.stat().st_mtime < cutoff:
            old_archive.unlink()
    rolling_cutoff = time.time() - max(1, int(rolling_minutes)) * 60
    for old_archive in rolling_root.glob("*/*/*/*.json.gz"):
        if old_archive.stat().st_mtime < rolling_cutoff:
            old_archive.unlink()
    return archive.stat().st_size


@contextmanager
def exclusive_lock(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as stream:
        if fcntl is not None:
            try:
                fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as exc:
                raise RuntimeError("Another save snapshot worker is already running") from exc
        stream.write(str(Path("/proc/self").resolve().name if Path("/proc/self").exists() else "worker"))
        stream.flush()
        yield


def backup_metrics(backup: Path):
    player_files = list((backup / "Players").glob("*.sav"))
    level = backup / "Level.sav"
    level_bytes = level.stat().st_size
    level_updated_at = datetime.fromtimestamp(level.stat().st_mtime, timezone.utc).astimezone().isoformat()
    players_bytes = sum(path.stat().st_size for path in player_files)
    return {
        "levelBytes": level_bytes,
        "playerFiles": len(player_files),
        "playersBytes": players_bytes,
        "generationBytes": level_bytes + players_bytes,
        "backupName": backup.name,
        "backupUpdatedAt": level_updated_at,
        "backupAgeSeconds": max(0, round(time.time() - level.stat().st_mtime)),
    }


def existing_snapshot_source(path: Path):
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        return (
            str(nested(payload, "source", "backup", default="")),
            str(nested(payload, "parser", "commit", default="")),
            to_int(nested(payload, "projection", "version", default=0), 0),
            str(payload.get("generationId") or ""),
        )
    except (OSError, ValueError, TypeError):
        return ("", "", 0, "")


def initial_diagnostics(args, started_at):
    return {
        "version": 1,
        "ok": False,
        "updatedAt": started_at,
        "provenance": {
            "observedAt": started_at,
            "sourceUpdatedAt": started_at,
            "gameVersion": None,
            "steamBuildId": None,
            "parserCommit": parser_commit(args.parser_repo),
            "catalogCommit": parser_commit(args.parser_repo),
            "schemaVersion": PROJECTION_VERSION,
            "freshness": "unknown",
            "sourceStatus": "unknown",
        },
        "save": None,
        "parse": {
            "startedAt": started_at,
            "completedAt": None,
            "durationMs": None,
            "status": "running",
            "decoderCount": 13,
            "decodeDurationMs": None,
            "projectionDurationMs": None,
            "warnings": 0,
            "playersParsed": 0,
            "palsParsed": 0,
            "basesParsed": 0,
            "unknownStructures": {},
            "catalogDrift": {"unknownIdentifiers": 0, "categories": {}},
            "error": None,
        },
        "output": {
            "snapshotBytes": None,
            "snapshotGzipBytes": None,
            "basesBytes": None,
            "basesGzipBytes": None,
            "privateBasesBytes": None,
            "historyArchiveBytes": None,
            "basesHistoryArchiveBytes": None,
            "catalogManifestBytes": None,
            "catalogBytes": None,
        },
        "parser": {"name": "PalworldSaveTools", "commit": parser_commit(args.parser_repo)},
    }


def run(args):
    started_monotonic = time.monotonic()
    started_at = datetime.now(timezone.utc).astimezone().isoformat()
    diagnostics = initial_diagnostics(args, started_at)
    with exclusive_lock(args.lock):
        try:
            backup = choose_backup(args.save_root, args.minimum_age)
            diagnostics["save"] = backup_metrics(backup)
            backup_updated_at = diagnostics["save"]["backupUpdatedAt"]
            provenance = runtime_provenance(
                args.stats, diagnostics["parser"]["commit"]
            )
            save_provenance = {**provenance, "sourceUpdatedAt": backup_updated_at}
            diagnostics["provenance"].update({
                "observedAt": started_at,
                "sourceUpdatedAt": backup_updated_at,
                "gameVersion": provenance.get("gameVersion"),
                "steamBuildId": provenance.get("steamBuildId"),
                "parserCommit": provenance.get("parserCommit"),
                "catalogCommit": provenance.get("catalogCommit"),
                "freshness": provenance.get("freshness") or "current",
                "sourceStatus": provenance.get("sourceStatus") or "available",
            })
            catalog_publication = publish_public_catalogs(
                args.parser_repo,
                args.public_catalogs_root,
                args.public_catalogs_manifest,
                provenance,
                started_at,
            )
            if existing_snapshot_source(args.output) == (
                backup.name,
                diagnostics["parser"]["commit"],
                PROJECTION_VERSION,
                public_save_generation_id(
                    backup.name,
                    backup_updated_at,
                    diagnostics["parser"]["commit"],
                    PROJECTION_VERSION,
                ),
            ):
                print(f"Backup {backup.name} already processed; snapshot unchanged")
                return
            load_sav, level_properties = load_parser(args.parser_repo)
            catalogs = load_catalogs(args.parser_repo)
            captured_at = datetime.now(timezone.utc).astimezone().isoformat()
            with tempfile.TemporaryDirectory(prefix="palworld-public-snapshot-") as tmp:
                staged = Path(tmp)
                shutil.copy2(backup / "Level.sav", staged / "Level.sav")
                shutil.copytree(backup / "Players", staged / "Players")
                level_payload = load_sav(
                    staged / "Level.sav", custom_properties=level_properties
                ).dump()
                decoded_at = time.monotonic()
                player_saves = {}
                characters = nested(
                    level_payload,
                    "properties",
                    "worldSaveData",
                    "value",
                    "CharacterSaveParameterMap",
                    "value",
                    default=[],
                )
                for entry in characters:
                    if is_player(entry):
                        uid = player_uid(entry)
                        player_saves[uid] = parse_player_save(
                            load_sav, find_player_file(staged / "Players", uid)
                        )
                (
                    snapshot,
                    counters,
                    bases_snapshot,
                    private_bases_snapshot,
                    catalog_drift,
                ) = build_snapshot(
                    level_payload,
                    player_saves,
                    catalogs,
                    captured_at,
                    backup.name,
                    diagnostics["parser"]["commit"],
                    save_provenance,
                )
                projected_at = time.monotonic()

            catalog_drift_summary = update_catalog_drift_report(
                args.catalog_drift,
                catalog_drift,
                captured_at,
                provenance,
            )
            write_atomic(args.output, snapshot)
            write_atomic(args.bases_output, bases_snapshot)
            write_atomic(args.private_bases_output, private_bases_snapshot)
            snapshot_payload = json_bytes(snapshot)
            bases_payload = json_bytes(bases_snapshot)
            private_bases_payload = json_bytes(private_bases_snapshot)
            history_bytes = None
            bases_history_bytes = None
            if not args.no_archive:
                history_bytes = archive_hourly(
                    args.history,
                    snapshot,
                    args.history_days,
                    args.rolling_history_minutes,
                )
                bases_history_bytes = archive_hourly(
                    args.bases_history,
                    bases_snapshot,
                    args.history_days,
                    args.rolling_history_minutes,
                )
            completed_at = datetime.now(timezone.utc).astimezone().isoformat()
            diagnostics["ok"] = True
            diagnostics["generationId"] = snapshot["generationId"]
            diagnostics["updatedAt"] = completed_at
            diagnostics["provenance"]["sourceUpdatedAt"] = snapshot["provenance"]["sourceUpdatedAt"]
            diagnostics["parse"].update(
                {
                    "completedAt": completed_at,
                    "durationMs": round((time.monotonic() - started_monotonic) * 1000),
                    "decodeDurationMs": round((decoded_at - started_monotonic) * 1000),
                    "projectionDurationMs": round((projected_at - decoded_at) * 1000),
                    "status": "ok",
                    "warnings": sum(counters.values()),
                    "playersParsed": snapshot["summary"]["players"],
                    "palsParsed": snapshot["summary"]["pals"],
                    "basesParsed": snapshot["summary"]["bases"],
                    "unknownStructures": dict(sorted(counters.items())),
                    "catalogDrift": catalog_drift_summary,
                }
            )
            diagnostics["output"].update(
                {
                    "snapshotBytes": len(snapshot_payload),
                    "snapshotGzipBytes": len(gzip.compress(snapshot_payload, compresslevel=6)),
                    "basesBytes": len(bases_payload),
                    "basesGzipBytes": len(gzip.compress(bases_payload, compresslevel=6)),
                    "privateBasesBytes": len(private_bases_payload),
                    "historyArchiveBytes": history_bytes,
                    "basesHistoryArchiveBytes": bases_history_bytes,
                    "catalogManifestBytes": catalog_publication["manifestBytes"],
                    "catalogBytes": catalog_publication["catalogBytes"],
                }
            )
            write_atomic(args.diagnostics, diagnostics)
            print(f"Public save snapshot written to {args.output}")
        except Exception as exc:
            completed_at = datetime.now(timezone.utc).astimezone().isoformat()
            diagnostics["updatedAt"] = completed_at
            diagnostics["provenance"].update({
                "observedAt": completed_at,
                "freshness": "stale",
                "sourceStatus": "transient-error",
            })
            diagnostics["parse"].update(
                {
                    "completedAt": completed_at,
                    "durationMs": round((time.monotonic() - started_monotonic) * 1000),
                    "status": "error",
                    "error": str(exc)[:500],
                }
            )
            write_atomic(args.diagnostics, diagnostics)
            raise


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--save-root", type=Path, default=DEFAULT_SAVE_ROOT)
    parser.add_argument("--parser-repo", type=Path, default=DEFAULT_PARSER_REPO)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--bases-output", type=Path, default=DEFAULT_BASES_OUTPUT)
    parser.add_argument(
        "--private-bases-output", type=Path, default=DEFAULT_PRIVATE_BASES_OUTPUT
    )
    parser.add_argument("--diagnostics", type=Path, default=DEFAULT_DIAGNOSTICS)
    parser.add_argument("--stats", type=Path, default=DEFAULT_STATS)
    parser.add_argument(
        "--catalog-drift", type=Path, default=DEFAULT_CATALOG_DRIFT
    )
    parser.add_argument(
        "--public-catalogs-root", type=Path, default=DEFAULT_PUBLIC_CATALOGS_ROOT
    )
    parser.add_argument(
        "--public-catalogs-manifest",
        type=Path,
        default=DEFAULT_PUBLIC_CATALOGS_MANIFEST,
    )
    parser.add_argument("--history", type=Path, default=DEFAULT_HISTORY)
    parser.add_argument("--bases-history", type=Path, default=DEFAULT_BASES_HISTORY)
    parser.add_argument("--lock", type=Path, default=DEFAULT_LOCK)
    parser.add_argument("--history-days", type=int, default=30)
    parser.add_argument(
        "--rolling-history-minutes",
        type=int,
        default=DEFAULT_ROLLING_HISTORY_MINUTES,
    )
    parser.add_argument("--minimum-age", type=int, default=15)
    parser.add_argument("--no-archive", action="store_true")
    return parser.parse_args()


if __name__ == "__main__":
    try:
        run(parse_args())
    except Exception as exc:  # Last valid public snapshot remains untouched.
        print(f"Public save snapshot failed: {exc}", file=sys.stderr)
        sys.exit(1)
