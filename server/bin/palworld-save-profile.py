#!/usr/bin/env python3
"""Measure Palworld save decoder groups without exposing save contents."""

from __future__ import annotations

import argparse
import json
import resource
import shutil
import sys
import tempfile
import time
from collections import Counter
from pathlib import Path


DEFAULT_SAVE_ROOT = Path(
    "/srv/storage/steam/servers/palworld/game/Pal/Saved/SaveGames/0/"
    "91B19CCBB15D48C7A96CB24669B7A525"
)
DEFAULT_PARSER_REPO = Path("/home/gaylemon/Gaylemon/vendor/PalworldSaveTools-current")

CORE_DECODERS = {
    ".worldSaveData.GroupSaveDataMap",
    ".worldSaveData.CharacterSaveParameterMap.Value.RawData",
    ".worldSaveData.ItemContainerSaveData.Value.RawData",
    ".worldSaveData.ItemContainerSaveData.Value.Slots.Slots.RawData",
}

DECODER_GROUPS = {
    "core": set(),
    "bases": {
        ".worldSaveData.BaseCampSaveData.Value.RawData",
        ".worldSaveData.BaseCampSaveData.Value.WorkerDirector.RawData",
        ".worldSaveData.CharacterContainerSaveData.Value.Slots.Slots.RawData",
    },
    "work": {
        ".worldSaveData.BaseCampSaveData.Value.WorkCollection.RawData",
        ".worldSaveData.WorkSaveData",
    },
    "map": {".worldSaveData.MapObjectSaveData"},
    "dynamic": {".worldSaveData.DynamicItemSaveData.DynamicItemSaveData.RawData"},
    "guild": {
        ".worldSaveData.GuildExtraSaveDataMap.Value.GuildItemStorage.RawData",
        ".worldSaveData.GuildExtraSaveDataMap.Value.Lab.RawData",
    },
}
DECODER_GROUPS["full"] = set().union(*DECODER_GROUPS.values())


def choose_backup(save_root: Path, minimum_age: int) -> Path:
    cutoff = time.time() - minimum_age
    candidates = []
    for path in (save_root / "backup" / "world").iterdir():
        level = path / "Level.sav"
        if path.is_dir() and level.is_file() and level.stat().st_mtime <= cutoff:
            candidates.append((level.stat().st_mtime, path))
    if not candidates:
        raise RuntimeError("No completed Palworld backup is old enough")
    return max(candidates)[1]


def nested(mapping, *keys, default=None):
    current = mapping
    for key in keys:
        if not isinstance(current, dict):
            return default
        current = current.get(key)
    return current if current is not None else default


def sequence_count(value) -> int:
    return len(value) if isinstance(value, list) else 0


def decoded_count(entries, *path) -> int:
    return sum(
        1
        for entry in entries if isinstance(nested(entry, *path, default={}), dict)
        and "values" not in nested(entry, *path, default={})
    )


def profile(args) -> dict:
    from palsav.io import load_sav  # pylint: disable=import-outside-toplevel
    from palsav.paltypes import PALWORLD_CUSTOM_PROPERTIES  # pylint: disable=import-outside-toplevel

    backup = choose_backup(args.save_root, args.minimum_age)
    wanted = CORE_DECODERS | DECODER_GROUPS[args.stage]
    custom = {key: value for key, value in PALWORLD_CUSTOM_PROPERTIES.items() if key in wanted}
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="palworld-save-profile-") as tmp:
        staged = Path(tmp) / "Level.sav"
        shutil.copy2(backup / "Level.sav", staged)
        payload = load_sav(staged, custom_properties=custom).dump()
    elapsed_ms = round((time.monotonic() - started) * 1000)

    world = nested(payload, "properties", "worldSaveData", "value", default={})
    bases = nested(world, "BaseCampSaveData", "value", default=[])
    character_containers = nested(world, "CharacterContainerSaveData", "value", default=[])
    map_objects = nested(world, "MapObjectSaveData", "value", "values", default=[])
    work = nested(world, "WorkSaveData", "value", "values", default=[])
    dynamic = nested(world, "DynamicItemSaveData", "value", "values", default=[])
    guild_extra = nested(world, "GuildExtraSaveDataMap", "value", default=[])
    map_object_types = Counter(
        str(nested(entry, "MapObjectId", "value", default="unknown"))
        for entry in map_objects
    )
    module_types = Counter(
        str(module.get("key") or "unknown")
        for entry in map_objects
        for module in nested(entry, "ConcreteModel", "value", "ModuleMap", "value", default=[])
        if isinstance(module, dict)
    )
    work_types = Counter(
        str(nested(entry, "WorkableType", "value", "value", default="unknown"))
        for entry in work
    )

    return {
        "stage": args.stage,
        "decoderCount": len(custom),
        "durationMs": elapsed_ms,
        "peakRssKiB": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
        "levelBytes": (backup / "Level.sav").stat().st_size,
        "counts": {
            "bases": sequence_count(bases),
            "characterContainers": sequence_count(character_containers),
            "itemContainers": sequence_count(nested(world, "ItemContainerSaveData", "value", default=[])),
            "mapObjects": sequence_count(map_objects),
            "workEntries": sequence_count(work),
            "dynamicItems": sequence_count(dynamic),
            "guildExtra": sequence_count(guild_extra),
        },
        "decoded": {
            "bases": decoded_count(bases, "value", "RawData", "value"),
            "workerDirectors": decoded_count(bases, "value", "WorkerDirector", "value", "RawData", "value"),
            "workCollections": decoded_count(bases, "value", "WorkCollection", "value", "RawData", "value"),
            "mapObjects": decoded_count(map_objects, "Model", "value", "RawData", "value"),
            "workEntries": decoded_count(work, "RawData", "value"),
            "dynamicItems": decoded_count(dynamic, "RawData", "value"),
        },
        "histograms": {
            "mapObjectTypes": map_object_types.most_common(80),
            "moduleTypes": module_types.most_common(),
            "workTypes": work_types.most_common(),
        },
    }


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", choices=sorted(DECODER_GROUPS), default="full")
    parser.add_argument("--save-root", type=Path, default=DEFAULT_SAVE_ROOT)
    parser.add_argument("--parser-repo", type=Path, default=DEFAULT_PARSER_REPO)
    parser.add_argument("--minimum-age", type=int, default=15)
    return parser.parse_args()


if __name__ == "__main__":
    try:
        print(json.dumps(profile(parse_args()), ensure_ascii=False, separators=(",", ":")))
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)[:500]}), file=sys.stderr)
        raise
