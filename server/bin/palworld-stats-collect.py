#!/usr/bin/env python3
import base64
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
BASE_URL = "http://127.0.0.1:8212/v1/api"
MAX_INTERVAL_SECONDS = 300
GAME_DATA_INTERVAL_SECONDS = 300
GAME_DATA_FAILURE_BACKOFF_SECONDS = 3600
GAME_DATA_DISABLED_HTTP_CODES = {404, 405}
MAX_SESSION_HISTORY = 200


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


def api_get(endpoint, password):
    token = base64.b64encode(f"admin:{password}".encode("utf-8")).decode("ascii")
    request = urllib.request.Request(
        f"{BASE_URL}/{endpoint}",
        headers={"Authorization": f"Basic {token}", "Accept": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        return json.loads(response.read().decode("utf-8"))


def empty_stats(ts):
    return {
        "version": 1,
        "ok": True,
        "updatedAt": ts,
        "updatedAtLocal": now_local(),
        "collection": {
            "source": "ubuntu-systemd",
            "firstSampleAt": ts,
            "lastSampleAt": None,
            "lastGameDataAt": None,
            "nextGameDataAttemptAt": None,
            "sampleCount": 0,
            "gameDataStatus": "unknown",
            "gameDataDisabledAt": None,
            "gameDataAvailable": False,
            "gameDataError": None,
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
    }


def load_stats(ts):
    if not STATS_FILE.exists():
        return empty_stats(ts)
    try:
        return json.loads(STATS_FILE.read_text(encoding="utf-8"))
    except Exception:
        return empty_stats(ts)


def ensure_collection_defaults(stats):
    collection = stats.setdefault("collection", {})
    collection.setdefault("source", "ubuntu-systemd")
    collection.setdefault("lastGameDataAt", None)
    collection.setdefault("nextGameDataAttemptAt", None)
    collection.setdefault("gameDataStatus", "unknown")
    collection.setdefault("gameDataDisabledAt", None)
    collection.setdefault("gameDataAvailable", False)
    collection.setdefault("gameDataError", None)

    error = str(collection.get("gameDataError") or "")
    if collection.get("gameDataStatus") != "disabled" and error in {"HTTP 404", "HTTP 405"}:
        collection["gameDataStatus"] = "disabled"
        collection["gameDataDisabledAt"] = collection.get("lastGameDataAt")
        collection["nextGameDataAttemptAt"] = None

    return collection


def player_key(player):
    for field in ("userId", "userid", "playerId", "accountName", "name"):
        value = player.get(field)
        if value:
            return str(value)
    return None


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
    record["name"] = player.get("name") or record.get("name")
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
    actors = game_data.get("ActorData") or []
    stats["collection"]["gameDataAvailable"] = True
    stats["collection"]["gameDataError"] = None
    stats["collection"]["lastGameDataAt"] = ts
    stats["collection"]["nextGameDataAttemptAt"] = None
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
                if actor.get("IsActive") == "true":
                    guild["activePlayerCount"] += 1

    stats["guilds"] = guilds


def should_read_game_data(stats):
    if stats.get("collection", {}).get("gameDataStatus") == "disabled":
        return False

    next_attempt = stats.get("collection", {}).get("nextGameDataAttemptAt")
    if next_attempt:
        try:
            if datetime.now(timezone.utc).astimezone() < datetime.fromisoformat(next_attempt):
                return False
        except ValueError:
            pass

    last = stats.get("collection", {}).get("lastGameDataAt")
    if not last:
        return True
    try:
        last_ts = datetime.fromisoformat(last)
    except ValueError:
        return True
    return (datetime.now(timezone.utc).astimezone() - last_ts).total_seconds() >= GAME_DATA_INTERVAL_SECONDS


def main():
    ts = now_iso()
    stats = load_stats(ts)
    ensure_collection_defaults(stats)
    password = read_admin_password()
    metrics = api_get("metrics", password)
    players_payload = api_get("players", password)

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
    server["lastUptimeSeconds"] = int(metrics.get("uptime") or 0)
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
        try:
            update_game_data(stats, api_get("game-data", password), ts)
        except urllib.error.HTTPError as exc:
            stats["collection"]["gameDataAvailable"] = False
            stats["collection"]["gameDataError"] = f"HTTP {exc.code}"
            stats["collection"]["lastGameDataAt"] = ts
            if exc.code in GAME_DATA_DISABLED_HTTP_CODES:
                stats["collection"]["gameDataStatus"] = "disabled"
                stats["collection"]["gameDataDisabledAt"] = ts
                stats["collection"]["nextGameDataAttemptAt"] = None
            else:
                stats["collection"]["gameDataStatus"] = "error"
                stats["collection"]["nextGameDataAttemptAt"] = datetime.fromtimestamp(
                    time.time() + GAME_DATA_FAILURE_BACKOFF_SECONDS,
                    tz=timezone.utc,
                ).astimezone().isoformat()
        except Exception as exc:
            stats["collection"]["gameDataAvailable"] = False
            stats["collection"]["gameDataError"] = str(exc)
            stats["collection"]["lastGameDataAt"] = ts
            stats["collection"]["gameDataStatus"] = "error"
            stats["collection"]["nextGameDataAttemptAt"] = datetime.fromtimestamp(
                time.time() + GAME_DATA_FAILURE_BACKOFF_SECONDS,
                tz=timezone.utc,
            ).astimezone().isoformat()

    stats["ok"] = True
    stats["updatedAt"] = ts
    stats["updatedAtLocal"] = now_local()
    stats["collection"]["lastSampleAt"] = ts
    stats["collection"]["sampleCount"] = int(stats["collection"].get("sampleCount") or 0) + 1

    STATS_FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp_file = STATS_FILE.with_suffix(".json.tmp")
    tmp_file.write_text(json.dumps(stats, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp_file.replace(STATS_FILE)
    print(f"Stats written to {STATS_FILE}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"Stats collection failed: {exc}", file=sys.stderr)
        sys.exit(1)
