#!/usr/bin/env python3
import base64
import hashlib
import json
import re
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

CONFIG_FILE = Path("/srv/storage/steam/servers/palworld/game/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini")
STATS_FILE = Path("/srv/storage/steam/servers/palworld/stats/stats.json")
STEAM_MANIFEST_FILE = Path("/srv/storage/steam/servers/palworld/game/steamapps/appmanifest_2394010.acf")
PARSER_REPO = Path("/home/gaylemon/Gaylemon/vendor/PalworldSaveTools-current")
BASE_URL = "http://127.0.0.1:8212/v1/api"
MAX_INTERVAL_SECONDS = 300
GAME_DATA_INTERVAL_SECONDS = 300
GAME_DATA_FAILURE_BACKOFF_SECONDS = 3600
GAME_DATA_DOCUMENTED_RETRY_SECONDS = 21600
SETTINGS_INTERVAL_SECONDS = 21600
SETTINGS_FAILURE_BACKOFF_SECONDS = 3600
MAX_SESSION_HISTORY = 200
MAX_SOURCE_SAMPLES = 60
MAX_SETTINGS_CHANGES = 50
SCHEMA_VERSION = 2

PUBLIC_SETTINGS_FIELDS = {
    "Difficulty",
    "DayTimeSpeedRate",
    "NightTimeSpeedRate",
    "ExpRate",
    "PalCaptureRate",
    "PalSpawnNumRate",
    "PalDamageRateAttack",
    "PalDamageRateDefense",
    "PlayerDamageRateAttack",
    "PlayerDamageRateDefense",
    "CollectionDropRate",
    "CollectionObjectHpRate",
    "CollectionObjectRespawnSpeedRate",
    "EnemyDropItemRate",
    "DeathPenalty",
    "BaseCampMaxNum",
    "BaseCampWorkerMaxNum",
    "GuildPlayerMaxNum",
    "PalEggDefaultHatchingTime",
    "WorkSpeedRate",
    "AutoSaveSpan",
    "bIsPvP",
    "bEnablePlayerToPlayerDamage",
    "bEnableFriendlyFire",
    "bEnableInvaderEnemy",
    "bEnableFastTravel",
    "bUseBackupSaveData",
    "CrossplayPlatforms",
}


def now_iso():
    return datetime.now(timezone.utc).astimezone().isoformat()


def now_local():
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def duration(seconds):
    seconds = max(0, int(seconds or 0))
    days, rem = divmod(seconds, 86400)
    hours, rem = divmod(rem, 3600)
    minutes, _ = divmod(rem, 60)
    if days:
        return f"{days}j {hours}h"
    if hours:
        return f"{hours}h {minutes}m"
    return f"{minutes}m"


def read_admin_password():
    text = CONFIG_FILE.read_text(encoding="utf-8", errors="ignore")
    match = re.search(r'AdminPassword="([^"]*)"', text)
    if not match or not match.group(1):
        raise RuntimeError("AdminPassword is not configured.")
    return match.group(1)


def percentile_95(values):
    values = sorted(float(value) for value in values if value is not None)
    if not values:
        return 0
    index = max(0, min(len(values) - 1, int((len(values) - 1) * 0.95 + 0.5)))
    return round(values[index], 1)


def record_source_observation(stats, endpoint, observed_at, status, latency_ms, byte_count=0, error=None):
    sources = stats.setdefault("sources", {})
    source = sources.setdefault(endpoint, {
        "status": "unknown",
        "lastObservedAt": None,
        "lastSuccessAt": None,
        "latencyMs": 0,
        "latencyP95Ms": 0,
        "responseBytes": 0,
        "sampleCount": 0,
        "consecutiveFailures": 0,
        "error": None,
        "latencySamples": [],
    })
    samples = list(source.get("latencySamples") or [])
    samples.append(round(float(latency_ms), 1))
    samples = samples[-MAX_SOURCE_SAMPLES:]
    source.update({
        "status": status,
        "lastObservedAt": observed_at,
        "latencyMs": round(float(latency_ms), 1),
        "latencyP95Ms": percentile_95(samples),
        "responseBytes": int(byte_count or 0),
        "sampleCount": int(source.get("sampleCount") or 0) + 1,
        "error": str(error)[:240] if error else None,
        "latencySamples": samples,
    })
    if status == "available":
        source["lastSuccessAt"] = observed_at
        source["consecutiveFailures"] = 0
    else:
        source["consecutiveFailures"] = int(source.get("consecutiveFailures") or 0) + 1


def set_source_semantic_status(stats, endpoint, status, error=None):
    source = stats.setdefault("sources", {}).get(endpoint)
    if not isinstance(source, dict):
        return
    source["status"] = status
    if error:
        source["error"] = str(error)[:240]
    if status in {"documented-but-unavailable", "unsupported"}:
        source["consecutiveFailures"] = 0


def api_get(endpoint, password, stats=None, observed_at=None):
    token = base64.b64encode(f"admin:{password}".encode("utf-8")).decode("ascii")
    request = urllib.request.Request(
        f"{BASE_URL}/{endpoint}",
        headers={"Authorization": f"Basic {token}", "Accept": "application/json"},
    )
    started_at = time.perf_counter()
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            payload = response.read()
        if stats is not None:
            record_source_observation(
                stats,
                endpoint,
                observed_at or now_iso(),
                "available",
                (time.perf_counter() - started_at) * 1000,
                len(payload),
            )
        return json.loads(payload.decode("utf-8"))
    except Exception as exc:
        if stats is not None:
            record_source_observation(
                stats,
                endpoint,
                observed_at or now_iso(),
                "error",
                (time.perf_counter() - started_at) * 1000,
                error=exc,
            )
        raise


def future_iso(seconds):
    return datetime.fromtimestamp(time.time() + seconds, tz=timezone.utc).astimezone().isoformat()


def read_steam_build_id():
    try:
        text = STEAM_MANIFEST_FILE.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return None
    match = re.search(r'"buildid"\s+"([0-9]+)"', text)
    return match.group(1) if match else None


def read_git_commit(repository):
    try:
        git_dir = repository.resolve() / ".git"
        head = (git_dir / "HEAD").read_text(encoding="ascii", errors="ignore").strip()
        if head.startswith("ref: "):
            return (git_dir / head[5:]).read_text(encoding="ascii", errors="ignore").strip() or None
        return head or None
    except OSError:
        return None


def game_version_from_info(info):
    if not isinstance(info, dict):
        return None
    return info.get("version") or info.get("Version") or info.get("serverVersion")


def update_provenance(stats, ts, info, steam_build_id):
    parser_commit = read_git_commit(PARSER_REPO)
    provenance = stats.setdefault("provenance", {})
    provenance.update({
        "observedAt": ts,
        "sourceUpdatedAt": ts,
        "gameVersion": game_version_from_info(info),
        "steamBuildId": steam_build_id,
        "parserCommit": parser_commit,
        "catalogCommit": parser_commit,
        "schemaVersion": SCHEMA_VERSION,
        "freshness": "current",
        "sourceStatus": "available",
    })
    return provenance


def public_settings(payload):
    if not isinstance(payload, dict):
        return {}
    if isinstance(payload.get("settings"), dict):
        payload = payload["settings"]
    return {
        field: payload[field]
        for field in sorted(PUBLIC_SETTINGS_FIELDS)
        if field in payload and payload[field] is not None
    }


def canonical_digest(payload):
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def update_settings(stats, payload, ts):
    filtered = public_settings(payload)
    digest = canonical_digest(filtered)
    settings = stats.setdefault("settings", {
        "status": "unknown",
        "updatedAt": None,
        "nextAttemptAt": None,
        "digest": None,
        "current": {},
        "changes": [],
        "error": None,
    })
    previous = settings.get("current") if isinstance(settings.get("current"), dict) else {}
    previous_digest = settings.get("digest")
    if previous_digest and previous_digest != digest:
        changed = {
            key: {"before": previous.get(key), "after": filtered.get(key)}
            for key in sorted(set(previous) | set(filtered))
            if previous.get(key) != filtered.get(key)
        }
        changes = list(settings.get("changes") or [])
        change_digest = canonical_digest({"before": previous_digest, "after": digest, "changed": changed})
        if not any(item.get("digest") == change_digest for item in changes if isinstance(item, dict)):
            changes.append({"observedAt": ts, "digest": change_digest, "fields": changed})
        settings["changes"] = changes[-MAX_SETTINGS_CHANGES:]
    settings.update({
        "status": "available",
        "updatedAt": ts,
        "nextAttemptAt": future_iso(SETTINGS_INTERVAL_SECONDS),
        "digest": digest,
        "current": filtered,
        "error": None,
    })
    return settings


def should_read_settings(stats, now=None):
    now = now or datetime.now(timezone.utc).astimezone()
    next_attempt = stats.get("settings", {}).get("nextAttemptAt")
    if not next_attempt:
        return True
    try:
        return now >= datetime.fromisoformat(next_attempt)
    except (TypeError, ValueError):
        return True


def empty_stats(ts):
    return {
        "version": 2,
        "schemaVersion": SCHEMA_VERSION,
        "ok": True,
        "updatedAt": ts,
        "updatedAtLocal": now_local(),
        "provenance": {
            "observedAt": ts,
            "sourceUpdatedAt": ts,
            "gameVersion": None,
            "steamBuildId": None,
            "parserCommit": None,
            "catalogCommit": None,
            "schemaVersion": SCHEMA_VERSION,
            "freshness": "current",
            "sourceStatus": "available",
        },
        "collection": {
            "source": "ubuntu-systemd",
            "firstSampleAt": ts,
            "lastSampleAt": None,
            "lastGameDataAt": None,
            "lastGameDataAttemptAt": None,
            "nextGameDataAttemptAt": None,
            "sampleCount": 0,
            "gameDataStatus": "unknown",
            "gameDataDisabledAt": None,
            "gameDataAvailable": False,
            "gameDataError": None,
            "gameDataCapabilityKey": None,
            "gameDataRestartGeneration": 0,
            "lastServerRestartDetectedAt": None,
            "note": "Les temps et connexions sont estimés par échantillonnage local côté serveur Ubuntu.",
        },
        "server": {
            "totalObservedSeconds": 0,
            "totalObserved": "0m",
            "peakPlayers": 0,
            "peakPlayersAt": None,
            "playerSamples": 0,
            "playerTotal": 0,
            "averagePlayers": 0,
            "fpsSamples": 0,
            "fpsTotal": 0,
            "averageFps": 0,
            "lastPlayers": 0,
            "maxPlayers": 0,
            "lastFps": 0,
            "lastFrameMs": 0,
            "lastBaseCamps": 0,
            "lastDays": 0,
            "lastUptimeSeconds": 0,
            "lastUptime": "0m",
        },
        "players": {},
        "guilds": {},
        "actors": {
            "lastSnapshotAt": None,
            "total": 0,
            "players": 0,
            "palBoxes": 0,
            "baseCampPals": 0,
            "otomoPals": 0,
            "wildPals": 0,
            "npcs": 0,
        },
        "settings": {
            "status": "unknown",
            "updatedAt": None,
            "nextAttemptAt": None,
            "digest": None,
            "current": {},
            "changes": [],
            "error": None,
        },
        "sources": {},
    }


def load_stats(ts):
    if not STATS_FILE.exists():
        return empty_stats(ts)
    try:
        return json.loads(STATS_FILE.read_text(encoding="utf-8"))
    except Exception:
        return empty_stats(ts)


def ensure_collection_defaults(stats):
    stats["version"] = max(2, int(stats.get("version") or 0))
    stats["schemaVersion"] = SCHEMA_VERSION
    collection = stats.setdefault("collection", {})
    collection.setdefault("source", "ubuntu-systemd")
    collection.setdefault("lastGameDataAt", None)
    collection.setdefault("lastGameDataAttemptAt", None)
    collection.setdefault("nextGameDataAttemptAt", None)
    collection.setdefault("gameDataStatus", "unknown")
    collection.setdefault("gameDataDisabledAt", None)
    collection.setdefault("gameDataAvailable", False)
    collection.setdefault("gameDataError", None)
    collection.setdefault("gameDataCapabilityKey", None)
    collection.setdefault("gameDataRestartGeneration", 0)
    collection.setdefault("lastServerRestartDetectedAt", None)

    error = str(collection.get("gameDataError") or "")
    if collection.get("gameDataStatus") == "disabled" or error in {"HTTP 404", "HTTP 405"}:
        collection["gameDataStatus"] = "documented-but-unavailable"
        collection["gameDataDisabledAt"] = collection.get("lastGameDataAt")
        collection["nextGameDataAttemptAt"] = collection.get("nextGameDataAttemptAt") or future_iso(
            GAME_DATA_DOCUMENTED_RETRY_SECONDS
        )

    settings = stats.setdefault("settings", {})
    settings.setdefault("status", "unknown")
    settings.setdefault("updatedAt", None)
    settings.setdefault("nextAttemptAt", None)
    settings.setdefault("digest", None)
    settings.setdefault("current", {})
    settings.setdefault("changes", [])
    settings.setdefault("error", None)
    stats.setdefault("sources", {})

    return collection


def player_key(player):
    for field in ("userId", "userid", "playerId", "accountName", "name"):
        value = player.get(field)
        if value:
            return str(value)
    return None


def is_technical_player_name(name, *records):
    normalized = str(name or "").strip().casefold()
    if not normalized:
        return False
    for record in records:
        if not isinstance(record, dict):
            continue
        for field in ("accountName", "playerId", "userId", "userid", "id"):
            value = str(record.get(field) or "").strip().casefold()
            if value and value == normalized:
                return True
    return False


def preferred_online_player_name(record, player):
    candidate = str(player.get("name") or "").strip()
    current = str(record.get("name") or "").strip()
    if not candidate:
        return current
    if (
        is_technical_player_name(candidate, record, player)
        and current
        and not is_technical_player_name(current, record, player)
    ):
        return current
    return candidate


def ensure_player(stats, key, ts):
    players = stats.setdefault("players", {})
    if key not in players:
        players[key] = {
            "id": key,
            "name": key,
            "accountName": None,
            "playerId": None,
            "userId": None,
            "firstSeenAt": ts,
            "lastSeenAt": ts,
            "lastOnlineAt": ts,
            "isOnline": False,
            "sessionCount": 0,
            "currentSessionStartedAt": None,
            "lastSessionEndedAt": None,
            "sessionHistory": [],
            "totalOnlineSeconds": 0,
            "totalOnline": "0m",
            "level": None,
            "buildingCount": None,
            "ping": None,
            "location": None,
            "guildId": None,
            "guildName": None,
            "hp": None,
            "maxHp": None,
            "activePalCount": 0,
            "basePalCount": 0,
            "lastSeenSource": "players",
        }
    record = players[key]
    history = record.setdefault("sessionHistory", [])
    if not isinstance(history, list):
        history = []
        record["sessionHistory"] = history
    current_started_at = record.get("currentSessionStartedAt")
    if current_started_at and not any(
        isinstance(session, dict) and session.get("startedAt") == current_started_at
        for session in history
    ):
        history.append({"startedAt": current_started_at, "endedAt": None})
    record["sessionHistory"] = history[-MAX_SESSION_HISTORY:]
    return record


def start_player_session(record, ts):
    history = record.setdefault("sessionHistory", [])
    if not isinstance(history, list):
        history = []
    if not history or not isinstance(history[-1], dict) or history[-1].get("endedAt"):
        history.append({"startedAt": ts, "endedAt": None})
    elif not history[-1].get("startedAt"):
        history[-1]["startedAt"] = ts
    record["sessionHistory"] = history[-MAX_SESSION_HISTORY:]


def end_player_session(record, ts):
    history = record.setdefault("sessionHistory", [])
    if not isinstance(history, list):
        history = []
    for session in reversed(history):
        if isinstance(session, dict) and session.get("startedAt") and not session.get("endedAt"):
            session["endedAt"] = ts
            break
    record["sessionHistory"] = history[-MAX_SESSION_HISTORY:]


def update_player_from_online(stats, player, ts, interval):
    key = player_key(player)
    if not key:
        return None
    record = ensure_player(stats, key, ts)
    if not record.get("isOnline"):
        record["sessionCount"] = int(record.get("sessionCount") or 0) + 1
        record["currentSessionStartedAt"] = ts
        start_player_session(record, ts)
    if interval > 0:
        record["totalOnlineSeconds"] = int(record.get("totalOnlineSeconds") or 0) + interval
    record["name"] = preferred_online_player_name(record, player)
    record["accountName"] = player.get("accountName") or record.get("accountName")
    record["playerId"] = player.get("playerId") or record.get("playerId")
    record["userId"] = player.get("userId") or record.get("userId")
    record["lastSeenAt"] = ts
    record["lastOnlineAt"] = ts
    record["isOnline"] = True
    record["level"] = player.get("level", record.get("level"))
    record["buildingCount"] = player.get("building_count", record.get("buildingCount"))
    record["ping"] = round(float(player["ping"]), 1) if player.get("ping") is not None else record.get("ping")
    if player.get("location_x") is not None or player.get("location_y") is not None:
        record["location"] = {
            "x": round(float(player["location_x"]), 1) if player.get("location_x") is not None else None,
            "y": round(float(player["location_y"]), 1) if player.get("location_y") is not None else None,
        }
    record["totalOnline"] = duration(record["totalOnlineSeconds"])
    record["lastSeenSource"] = "players"
    return key


def update_game_data(stats, game_data, ts):
    actors = game_data.get("ActorData") or game_data.get("actorData") or []
    stats["collection"]["gameDataAvailable"] = True
    stats["collection"]["gameDataError"] = None
    stats["collection"]["lastGameDataAt"] = ts
    stats["collection"]["lastGameDataAttemptAt"] = ts
    stats["collection"]["nextGameDataAttemptAt"] = future_iso(GAME_DATA_INTERVAL_SECONDS)
    stats["collection"]["gameDataStatus"] = "available"
    stats["collection"]["gameDataDisabledAt"] = None
    stats["actors"] = {
        "lastSnapshotAt": ts,
        "total": len(actors),
        "players": len([a for a in actors if a.get("Type") == "Character" and a.get("UnitType") == "Player"]),
        "palBoxes": len([a for a in actors if a.get("Type") == "PalBox"]),
        "baseCampPals": len([a for a in actors if a.get("UnitType") == "BaseCampPal"]),
        "otomoPals": len([a for a in actors if a.get("UnitType") == "OtomoPal"]),
        "wildPals": len([a for a in actors if a.get("UnitType") == "WildPal"]),
        "npcs": len([a for a in actors if a.get("UnitType") == "NPC"]),
    }

    guilds = {}
    for actor in actors:
        if actor.get("Type") == "PalBox":
            guild_id = actor.get("GuildID") or "unknown"
            guild = guilds.setdefault(guild_id, {
                "id": guild_id,
                "name": actor.get("GuildName") or "Guilde inconnue",
                "baseCount": 0,
                "playerCount": 0,
                "activePlayerCount": 0,
            })
            guild["baseCount"] += 1

        if actor.get("Type") == "Character" and actor.get("UnitType") == "Player":
            key = actor.get("userid") or actor.get("InstanceID")
            if key:
                record = ensure_player(stats, str(key), ts)
                record["name"] = actor.get("NickName") or record.get("name")
                record["userId"] = actor.get("userid") or record.get("userId")
                record["level"] = actor.get("level", record.get("level"))
                record["hp"] = actor.get("HP", record.get("hp"))
                record["maxHp"] = actor.get("MaxHP", record.get("maxHp"))
                record["guildId"] = actor.get("GuildID") or record.get("guildId")
                record["guildName"] = actor.get("GuildName") or record.get("guildName")
                record["lastSeenSource"] = "game-data"
            guild_id = actor.get("GuildID")
            if guild_id:
                guild = guilds.setdefault(guild_id, {
                    "id": guild_id,
                    "name": actor.get("GuildName") or "Guilde inconnue",
                    "baseCount": 0,
                    "playerCount": 0,
                    "activePlayerCount": 0,
                })
                guild["playerCount"] += 1
                if actor.get("IsActive") is True or str(actor.get("IsActive") or "").casefold() == "true":
                    guild["activePlayerCount"] += 1

    stats["guilds"] = guilds


def refresh_game_data_capability(stats, capability_key):
    collection = stats.setdefault("collection", {})
    previous = collection.get("gameDataCapabilityKey")
    if capability_key and previous and previous != capability_key:
        collection["gameDataStatus"] = "unknown"
        collection["gameDataAvailable"] = False
        collection["gameDataError"] = None
        collection["nextGameDataAttemptAt"] = None
    collection["gameDataCapabilityKey"] = capability_key


def update_game_data_restart_generation(stats, current_uptime, observed_at=None):
    collection = stats.setdefault("collection", {})
    server = stats.setdefault("server", {})
    generation = int(collection.get("gameDataRestartGeneration") or 0)
    previous_uptime = int(server.get("lastUptimeSeconds") or 0)
    current_uptime = max(0, int(current_uptime or 0))
    if previous_uptime >= 60 and current_uptime + 30 < previous_uptime:
        generation += 1
        collection["lastServerRestartDetectedAt"] = observed_at or now_iso()
    collection["gameDataRestartGeneration"] = generation
    return generation


def should_read_game_data(stats, now=None):
    now = now or datetime.now(timezone.utc).astimezone()

    next_attempt = stats.get("collection", {}).get("nextGameDataAttemptAt")
    if next_attempt:
        try:
            if now < datetime.fromisoformat(next_attempt):
                return False
        except (TypeError, ValueError):
            pass

    last = stats.get("collection", {}).get("lastGameDataAttemptAt") or stats.get("collection", {}).get("lastGameDataAt")
    if not last:
        return True
    try:
        last_ts = datetime.fromisoformat(last)
    except ValueError:
        return True
    return (now - last_ts).total_seconds() >= GAME_DATA_INTERVAL_SECONDS


def write_stats_atomic(stats):
    STATS_FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp_file = STATS_FILE.with_suffix(".json.tmp")
    tmp_file.write_text(json.dumps(stats, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp_file.replace(STATS_FILE)


def persist_primary_source_failure(stats, endpoint, observed_at, error):
    source = stats.setdefault("sources", {}).get(endpoint)
    if not isinstance(source, dict) or source.get("lastObservedAt") != observed_at or source.get("status") != "error":
        record_source_observation(stats, endpoint, observed_at, "error", 0, error=error)
    provenance = stats.setdefault("provenance", {})
    provenance.update({
        "observedAt": observed_at,
        "schemaVersion": SCHEMA_VERSION,
        "freshness": "stale",
        "sourceStatus": "transient-error",
    })
    stats["ok"] = False
    stats["updatedAt"] = observed_at
    stats["updatedAtLocal"] = now_local()
    stats["error"] = f"primary-source-unavailable:{endpoint}"
    write_stats_atomic(stats)


def main():
    ts = now_iso()
    stats = load_stats(ts)
    ensure_collection_defaults(stats)
    password = read_admin_password()
    primary_payloads = {}
    for endpoint in ("info", "metrics", "players"):
        try:
            primary_payloads[endpoint] = api_get(endpoint, password, stats, ts)
        except Exception as exc:
            persist_primary_source_failure(stats, endpoint, ts, exc)
            raise
    info = primary_payloads["info"]
    metrics = primary_payloads["metrics"]
    players_payload = primary_payloads["players"]
    steam_build_id = read_steam_build_id()
    provenance = update_provenance(stats, ts, info, steam_build_id)
    current_uptime = int(metrics.get("uptime") or 0)
    restart_generation = update_game_data_restart_generation(stats, current_uptime, ts)
    capability_key = canonical_digest({
        "gameVersion": provenance.get("gameVersion"),
        "steamBuildId": steam_build_id,
        "restartGeneration": restart_generation,
    })
    refresh_game_data_capability(stats, capability_key)

    if should_read_settings(stats):
        try:
            update_settings(stats, api_get("settings", password, stats, ts), ts)
        except Exception as exc:
            settings = stats.setdefault("settings", {})
            settings["status"] = "transient-error"
            settings["error"] = str(exc)[:240]
            settings["nextAttemptAt"] = future_iso(SETTINGS_FAILURE_BACKOFF_SECONDS)

    last_sample = stats.get("collection", {}).get("lastSampleAt")
    interval = 0
    if last_sample:
        try:
            interval = min(MAX_INTERVAL_SECONDS, max(0, int(time.time() - datetime.fromisoformat(last_sample).timestamp())))
        except ValueError:
            interval = 0

    for key, record in stats.get("players", {}).items():
        ensure_player(stats, key, ts)
        record["activePalCount"] = 0
        record["basePalCount"] = 0

    online_keys = set()
    for player in players_payload.get("players", []):
        key = update_player_from_online(stats, player, ts, interval)
        if key:
            online_keys.add(key)

    for key, record in stats.get("players", {}).items():
        if key not in online_keys and record.get("isOnline"):
            record["isOnline"] = False
            record["lastSessionEndedAt"] = ts
            end_player_session(record, ts)
            record["currentSessionStartedAt"] = None
        record["totalOnline"] = duration(record.get("totalOnlineSeconds") or 0)

    server = stats["server"]
    current_players = int(metrics.get("currentplayernum") or 0)
    server["lastPlayers"] = current_players
    server["maxPlayers"] = int(metrics.get("maxplayernum") or 0)
    server["lastFps"] = int(metrics.get("serverfps") or 0)
    server["lastFrameMs"] = round(float(metrics.get("serverframetime") or 0), 1)
    server["lastBaseCamps"] = int(metrics.get("basecampnum") or 0)
    server["lastDays"] = int(metrics.get("days") or 0)
    server["lastUptimeSeconds"] = current_uptime
    server["lastUptime"] = duration(server["lastUptimeSeconds"])
    server["totalObservedSeconds"] = int(server.get("totalObservedSeconds") or 0) + interval
    server["totalObserved"] = duration(server["totalObservedSeconds"])
    server["playerSamples"] = int(server.get("playerSamples") or 0) + 1
    server["playerTotal"] = int(server.get("playerTotal") or 0) + current_players
    server["averagePlayers"] = round(server["playerTotal"] / max(1, server["playerSamples"]), 2)
    server["fpsSamples"] = int(server.get("fpsSamples") or 0) + 1
    server["fpsTotal"] = float(server.get("fpsTotal") or 0) + float(metrics.get("serverfps") or 0)
    server["averageFps"] = round(server["fpsTotal"] / max(1, server["fpsSamples"]), 1)
    if current_players > int(server.get("peakPlayers") or 0):
        server["peakPlayers"] = current_players
        server["peakPlayersAt"] = ts

    if should_read_game_data(stats):
        stats["collection"]["lastGameDataAttemptAt"] = ts
        try:
            update_game_data(stats, api_get("game-data", password, stats, ts), ts)
        except urllib.error.HTTPError as exc:
            stats["collection"]["gameDataAvailable"] = False
            stats["collection"]["gameDataError"] = f"HTTP {exc.code}"
            if exc.code in {404, 405}:
                stats["collection"]["gameDataStatus"] = "documented-but-unavailable"
                stats["collection"]["gameDataDisabledAt"] = ts
                stats["collection"]["nextGameDataAttemptAt"] = future_iso(
                    GAME_DATA_DOCUMENTED_RETRY_SECONDS
                )
                set_source_semantic_status(stats, "game-data", "documented-but-unavailable", f"HTTP {exc.code}")
            elif exc.code in {400, 501}:
                stats["collection"]["gameDataStatus"] = "unsupported"
                stats["collection"]["nextGameDataAttemptAt"] = future_iso(
                    GAME_DATA_DOCUMENTED_RETRY_SECONDS
                )
                set_source_semantic_status(stats, "game-data", "unsupported", f"HTTP {exc.code}")
            else:
                stats["collection"]["gameDataStatus"] = "transient-error"
                stats["collection"]["nextGameDataAttemptAt"] = future_iso(
                    GAME_DATA_FAILURE_BACKOFF_SECONDS
                )
                set_source_semantic_status(stats, "game-data", "transient-error", f"HTTP {exc.code}")
        except Exception as exc:
            stats["collection"]["gameDataAvailable"] = False
            stats["collection"]["gameDataError"] = str(exc)
            stats["collection"]["gameDataStatus"] = "transient-error"
            stats["collection"]["nextGameDataAttemptAt"] = future_iso(
                GAME_DATA_FAILURE_BACKOFF_SECONDS
            )
            set_source_semantic_status(stats, "game-data", "transient-error", exc)

    stats["ok"] = True
    stats["error"] = None
    stats["updatedAt"] = ts
    stats["updatedAtLocal"] = now_local()
    stats["collection"]["lastSampleAt"] = ts
    stats["collection"]["sampleCount"] = int(stats["collection"].get("sampleCount") or 0) + 1

    write_stats_atomic(stats)
    print(f"Stats written to {STATS_FILE}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"Stats collection failed: {exc}", file=sys.stderr)
        sys.exit(1)
