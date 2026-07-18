#!/usr/bin/env python3
"""Collect privacy-safe Palworld events from journald and save snapshots."""

from __future__ import annotations

import argparse
import base64
import binascii
import gzip
import hashlib
import json
import os
import re
import sqlite3
import subprocess
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path


DEFAULT_DATABASE = Path("/home/gaylemon/Gaylemon/runtime/events/palworld-events.sqlite3")
DEFAULT_OUTPUT = Path("/home/gaylemon/Gaylemon/runtime/public-events.json")
DEFAULT_RECENT_OUTPUT = Path("/home/gaylemon/Gaylemon/runtime/public-events-recent.json")
DEFAULT_SNAPSHOT = Path("/home/gaylemon/Gaylemon/runtime/public-save-snapshot.json")
DEFAULT_BASES_SNAPSHOT = Path("/home/gaylemon/Gaylemon/runtime/public-save-bases.json")
DEFAULT_HISTORY = Path("/home/gaylemon/Gaylemon/runtime/save-snapshot-history")
DEFAULT_BASES_HISTORY = Path("/home/gaylemon/Gaylemon/runtime/save-bases-history")
DEFAULT_STATS = Path("/srv/storage/steam/servers/palworld/stats/stats.json")
DEFAULT_RECOVERY_REPORT = Path(
    "/home/gaylemon/Gaylemon/runtime/events/palworld-events-recovery.json"
)

JOIN_RE = re.compile(r"\] \[LOG\] (?P<player>.+?) joined the server\.")
LEAVE_RE = re.compile(r"\] \[LOG\] (?P<player>.+?) left the server\.")
SESSION_EVENT_TOLERANCE_SECONDS = 120
SAVE_ACTIVITY_TOLERANCE_SECONDS = 0
POST_SESSION_SAVE_GRACE_SECONDS = 180
RECONNECT_WINDOW_SECONDS = 120
JOURNAL_UNITS = ("palworld.service", "palworld-update.service")
STRUCTURED_EVENT_PREFIX = "GAYLEMON_EVENT"
EVENT_TYPE_RE = re.compile(r"^[a-z][a-z0-9_-]{0,31}$")
PUBLIC_EVENT_VERSION = 5
DEFAULT_BACKFILL_FROM = "2026-07-09T00:00:00-04:00"
RECENT_EVENT_LIMIT = 2000
ITEMIZED_EVENT_GROUP_WINDOW_SECONDS = 5 * 60
CAPTURE_FINGERPRINT_RE = re.compile(r":capture:([^:]+):([^:]+):(\d+)$")
SERVER_BASE_NAME_RE = re.compile(r"^Base\s+(?P<number>\d+)(?:\s*[·\-.–—]\s*.+)?$", re.IGNORECASE)
NEW_RECORD_FIELDS = (
    "uniqueItemsPickedUp",
    "notesFound",
    "arenaSoloClears",
    "mutations",
    "palRankups",
    "raidBossDefeats",
    "towerBossDefeats",
)
SESSION_BOUNDARY_EXEMPT_SAVE_TYPES = {"death", "recovery"}
PUBLIC_EVENT_ORDER_SQL = """
    occurred_at DESC,
    CASE
      WHEN type = 'leave' AND source IN ('journal', 'players') THEN 0
      WHEN source = 'save' THEN 1
      WHEN type = 'join' AND source IN ('journal', 'players') THEN 2
      ELSE 1
    END ASC,
    id DESC
"""


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat()


def connect_database(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(path)
    connection.row_factory = sqlite3.Row
    connection.executescript(
        """
        PRAGMA journal_mode=WAL;
        PRAGMA synchronous=NORMAL;
        CREATE TABLE IF NOT EXISTS events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            fingerprint TEXT NOT NULL UNIQUE,
            occurred_at TEXT NOT NULL,
            type TEXT NOT NULL,
            player TEXT,
            guild TEXT,
            base TEXT,
            title TEXT NOT NULL,
            message TEXT NOT NULL,
            icon TEXT,
            source TEXT NOT NULL,
            details_json TEXT,
            confidence TEXT NOT NULL DEFAULT 'confirmed'
        );
        CREATE INDEX IF NOT EXISTS events_occurred_at_idx
            ON events(occurred_at DESC, id DESC);
        CREATE INDEX IF NOT EXISTS events_type_occurred_at_idx
            ON events(type, occurred_at DESC);
        CREATE INDEX IF NOT EXISTS events_player_occurred_at_idx
            ON events(player, occurred_at DESC);
        CREATE TABLE IF NOT EXISTS metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """
    )
    ensure_event_columns(connection)
    return connection


def ensure_event_columns(connection: sqlite3.Connection) -> None:
    columns = {
        row["name"]
        for row in connection.execute("PRAGMA table_info(events)").fetchall()
    }
    migrations = {
        "guild": "ALTER TABLE events ADD COLUMN guild TEXT",
        "base": "ALTER TABLE events ADD COLUMN base TEXT",
        "details_json": "ALTER TABLE events ADD COLUMN details_json TEXT",
        "confidence": "ALTER TABLE events ADD COLUMN confidence TEXT NOT NULL DEFAULT 'confirmed'",
    }
    for column, statement in migrations.items():
        if column not in columns:
            connection.execute(statement)


def metadata_get(connection: sqlite3.Connection, key: str, default=None):
    row = connection.execute("SELECT value FROM metadata WHERE key = ?", (key,)).fetchone()
    return json.loads(row["value"]) if row else default


def metadata_set(connection: sqlite3.Connection, key: str, value) -> None:
    connection.execute(
        """
        INSERT INTO metadata(key, value) VALUES(?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """,
        (key, json.dumps(value, ensure_ascii=False, separators=(",", ":"))),
    )


def add_event(
    connection: sqlite3.Connection,
    *,
    fingerprint: str,
    occurred_at: str,
    event_type: str,
    title: str,
    message: str,
    player: str | None = None,
    guild: str | None = None,
    base: str | None = None,
    icon: str | None = None,
    source: str,
    details: dict | None = None,
    confidence: str = "confirmed",
) -> None:
    details_json = None
    if details:
        details_json = details_json_payload(details)
    connection.execute(
        """
        INSERT OR IGNORE INTO events(
            fingerprint, occurred_at, type, player, guild, base, title, message,
            icon, source, details_json, confidence
        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            fingerprint,
            occurred_at,
            event_type,
            player,
            guild,
            base,
            title,
            message,
            icon,
            source,
            details_json,
            confidence if confidence in {"confirmed", "derived"} else "confirmed",
        ),
    )


def journal_timestamp(entry: dict) -> str:
    micros = int(entry.get("__REALTIME_TIMESTAMP") or 0)
    if micros:
        return datetime.fromtimestamp(micros / 1_000_000, timezone.utc).astimezone().isoformat()
    return now_iso()


def journal_command(cursor: str | None = None) -> list[str]:
    command = ["journalctl"]
    for unit in JOURNAL_UNITS:
        command.extend(["-u", unit])
    command.extend(["--no-pager", "-o", "json"])
    if cursor:
        command.extend(["--after-cursor", cursor])
    return command


def decode_structured_event(message: str) -> dict | None:
    parts = message.split("\t", 3)
    if len(parts) != 4 or parts[0] != STRUCTURED_EVENT_PREFIX:
        return None
    event_type, encoded_title, encoded_message = parts[1:]
    if not EVENT_TYPE_RE.fullmatch(event_type):
        return None
    try:
        title = base64.b64decode(encoded_title, validate=True).decode("utf-8").strip()
        details = base64.b64decode(encoded_message, validate=True).decode("utf-8").strip()
    except (binascii.Error, ValueError, UnicodeDecodeError):
        return None
    if not title or not details:
        return None
    return {
        "type": event_type,
        "title": title[:160],
        "message": details[:1000],
    }


def read_journal(cursor: str | None, fixture: Path | None = None) -> list[dict]:
    if fixture:
        lines = fixture.read_text(encoding="utf-8").splitlines()
    else:
        command = journal_command(cursor)
        result = subprocess.run(command, check=False, capture_output=True, text=True, timeout=45)
        if result.returncode and cursor:
            # A cursor can disappear after journal rotation. Re-reading the retained
            # journal is safe because each entry fingerprint is unique in SQLite.
            command = journal_command()
            result = subprocess.run(command, check=False, capture_output=True, text=True, timeout=45)
        result.check_returncode()
        lines = result.stdout.splitlines()

    entries = []
    for line in lines:
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(entry, dict):
            entries.append(entry)
    return entries


def collect_journal(connection: sqlite3.Connection, fixture: Path | None = None) -> None:
    cursor = None if fixture else metadata_get(connection, "journal_cursor")
    entries = read_journal(cursor, fixture)
    last_cursor = cursor

    for entry in entries:
        message = str(entry.get("MESSAGE") or "")
        entry_cursor = str(entry.get("__CURSOR") or "")
        occurred_at = journal_timestamp(entry)
        fingerprint = f"journal:{entry_cursor}" if entry_cursor else f"journal:{occurred_at}:{message}"
        last_cursor = entry_cursor or last_cursor

        structured_event = decode_structured_event(message)
        if structured_event:
            add_event(
                connection,
                fingerprint=fingerprint,
                occurred_at=occurred_at,
                event_type=structured_event["type"],
                title=structured_event["title"],
                message=structured_event["message"],
                source="update",
            )
            continue

        match = JOIN_RE.search(message)
        if match:
            player = match.group("player").strip()
            add_event(
                connection,
                fingerprint=fingerprint,
                occurred_at=occurred_at,
                event_type="join",
                player=player,
                title="Arrivée sur Palpagos",
                message=f"{player} rejoint l'aventure.",
                source="journal",
            )
            continue

        match = LEAVE_RE.search(message)
        if match:
            player = match.group("player").strip()
            add_event(
                connection,
                fingerprint=fingerprint,
                occurred_at=occurred_at,
                event_type="leave",
                player=player,
                title="Fin d'expédition",
                message=f"{player} quitte l'archipel pour l'instant.",
                source="journal",
            )
            continue

        if message.startswith("Started palworld.service"):
            add_event(
                connection,
                fingerprint=fingerprint,
                occurred_at=occurred_at,
                event_type="server",
                title="L'aventure reprend",
                message="Les portes de Palpagos sont ouvertes.",
                source="journal",
            )
        elif message.startswith("Stopped palworld.service"):
            add_event(
                connection,
                fingerprint=fingerprint,
                occurred_at=occurred_at,
                event_type="server",
                title="Pause sur l'archipel",
                message="Palpagos prend une courte pause technique.",
                source="journal",
            )

    if last_cursor and not fixture:
        metadata_set(connection, "journal_cursor", last_cursor)


def load_snapshot(path: Path) -> dict | None:
    try:
        if path.suffix == ".gz":
            with gzip.open(path, "rt", encoding="utf-8") as stream:
                payload = json.load(stream)
        else:
            payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError, TypeError):
        return None
    return payload if isinstance(payload, dict) and payload.get("ok") else None


def parse_timestamp(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(str(value))
    except ValueError:
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def event_exists_near(
    connection: sqlite3.Connection,
    player: str,
    event_type: str,
    occurred_at: str,
    tolerance_seconds: int = SESSION_EVENT_TOLERANCE_SECONDS,
) -> bool:
    target = parse_timestamp(occurred_at)
    if target is None:
        return True
    rows = connection.execute(
        """
        SELECT occurred_at
        FROM events
        WHERE type = ? AND player IS NOT NULL AND lower(player) = lower(?)
        """,
        (event_type, player),
    ).fetchall()
    return any(
        timestamp is not None and abs((timestamp - target).total_seconds()) <= tolerance_seconds
        for row in rows
        if (timestamp := parse_timestamp(row["occurred_at"])) is not None
    )


def collect_player_sessions(connection: sqlite3.Connection, stats_path: Path) -> int:
    try:
        payload = json.loads(stats_path.read_text(encoding="utf-8"))
    except (OSError, ValueError, TypeError):
        return 0

    added = 0
    for player_key, record in iter_player_records(payload):
        player = str(record.get("name") or "").strip()
        sessions = record.get("sessionHistory") or []
        if not player or not isinstance(sessions, list):
            continue
        for session in sessions:
            if not isinstance(session, dict):
                continue
            for event_type, timestamp_field in (("join", "startedAt"), ("leave", "endedAt")):
                occurred_at = str(session.get(timestamp_field) or "")
                if not occurred_at or parse_timestamp(occurred_at) is None:
                    continue
                if event_exists_near(connection, player, event_type, occurred_at):
                    continue
                before = connection.total_changes
                is_join = event_type == "join"
                add_event(
                    connection,
                    fingerprint=f"players:{event_type}:{player_key}:{occurred_at}",
                    occurred_at=occurred_at,
                    event_type=event_type,
                    player=player,
                    title="Arrivée sur Palpagos" if is_join else "Fin d'expédition",
                    message=(
                        f"{player} rejoint l'aventure."
                        if is_join
                        else f"{player} quitte l'archipel pour l'instant."
                    ),
                    source="players",
                )
                if connection.total_changes > before:
                    added += 1
    return added


def iter_player_records(payload: dict):
    players = payload.get("players") if isinstance(payload, dict) else None
    if isinstance(players, dict):
        for player_key, record in players.items():
            if isinstance(record, dict):
                yield str(player_key), record
    elif isinstance(players, list):
        for index, record in enumerate(players):
            if not isinstance(record, dict):
                continue
            player = str(record.get("name") or "").strip()
            player_key = str(record.get("id") or record.get("key") or player or index)
            yield player_key, record


def player_session_index(stats_path: Path) -> dict[str, list[tuple[datetime, datetime | None]]]:
    try:
        payload = json.loads(stats_path.read_text(encoding="utf-8"))
    except (OSError, ValueError, TypeError):
        return {}

    index: dict[str, list[tuple[datetime, datetime | None]]] = {}
    for _player_key, record in iter_player_records(payload):
        player = str(record.get("name") or "").strip()
        if not player:
            continue
        sessions: list[tuple[datetime, datetime | None]] = []
        for session in record.get("sessionHistory") or []:
            if not isinstance(session, dict):
                continue
            started_at = parse_timestamp(str(session.get("startedAt") or ""))
            if started_at is None:
                continue
            ended_at = parse_timestamp(str(session.get("endedAt") or "")) if session.get("endedAt") else None
            sessions.append((started_at, ended_at))

        current_started_at = parse_timestamp(str(record.get("currentSessionStartedAt") or ""))
        if record.get("isOnline") and current_started_at is not None:
            current_is_known = any(
                ended_at is None
                and abs((started_at - current_started_at).total_seconds()) <= SESSION_EVENT_TOLERANCE_SECONDS
                for started_at, ended_at in sessions
            )
            if not current_is_known:
                sessions.append((current_started_at, None))

        if sessions:
            index[player.casefold()] = sessions
    return index


def active_players_at(
    sessions: dict[str, list[tuple[datetime, datetime | None]]],
    occurred_at: str,
    tolerance_seconds: int = SAVE_ACTIVITY_TOLERANCE_SECONDS,
) -> set[str] | None:
    if not sessions:
        return None
    target = parse_timestamp(occurred_at)
    if target is None:
        return None
    tolerance = timedelta(seconds=max(0, tolerance_seconds))
    active = set()
    for player, player_sessions in sessions.items():
        if player_active_at(player_sessions, target, tolerance):
            active.add(player)
    return active


def save_activity_time_for_player(
    connection: sqlite3.Connection,
    sessions: dict[str, list[tuple[datetime, datetime | None]]],
    player: str,
    occurred_at: str,
    grace_seconds: int = POST_SESSION_SAVE_GRACE_SECONDS,
) -> str | None:
    if not sessions:
        return occurred_at
    target = parse_timestamp(occurred_at)
    if target is None:
        return None
    player_key = str(player or "").casefold()
    player_sessions = sessions.get(player_key)
    if not player_sessions:
        return None
    grace = timedelta(seconds=max(0, grace_seconds))
    for started_at, ended_at in player_sessions:
        if target < started_at:
            continue
        if ended_at is None or target <= ended_at:
            return occurred_at
        if target <= ended_at + grace:
            return session_close_time(connection, player_key, target, ended_at, grace)
    return None


def session_activity_times_at(
    connection: sqlite3.Connection,
    sessions: dict[str, list[tuple[datetime, datetime | None]]],
    occurred_at: str,
) -> dict[str, str] | None:
    if not sessions:
        return None
    result = {}
    for player in sessions:
        event_time = save_activity_time_for_player(connection, sessions, player, occurred_at)
        if event_time:
            result[player] = event_time
    return result


def session_close_time(
    connection: sqlite3.Connection,
    player_key: str,
    target: datetime,
    ended_at: datetime,
    grace: timedelta,
) -> str:
    row = connection.execute(
        """
        SELECT occurred_at
        FROM events
        WHERE type = 'leave'
          AND player IS NOT NULL
          AND lower(player) = lower(?)
          AND occurred_at <= ?
        ORDER BY occurred_at DESC, id DESC
        LIMIT 1
        """,
        (player_key, target.isoformat()),
    ).fetchone()
    if row:
        journal_left_at = parse_timestamp(row["occurred_at"])
        if journal_left_at and target - journal_left_at <= grace:
            return journal_left_at.isoformat()
    return ended_at.isoformat()


def player_active_at(
    sessions: list[tuple[datetime, datetime | None]],
    target: datetime,
    tolerance: timedelta,
) -> bool:
    for started_at, ended_at in sessions:
        if target < started_at - tolerance:
            continue
        if ended_at is not None and target > ended_at + tolerance:
            continue
        return True
    return False


def activity_player_keys(activity) -> set[str] | None:
    if activity is None:
        return None
    if isinstance(activity, dict):
        return set(activity)
    return set(activity)


def activity_event_time(activity, player: str | None, default: str) -> str:
    if isinstance(activity, dict) and player:
        return str(activity.get(str(player).casefold()) or default)
    return default


def public_event_key(fingerprint: str) -> str:
    digest = hashlib.sha256(str(fingerprint or "").encode("utf-8")).hexdigest()
    return f"evt_{digest[:20]}"


def public_details(value):
    if isinstance(value, dict):
        result = {}
        for key, item in value.items():
            public_key = str(key)
            if re.search(r"uid|guid|instance|container|account|steam|password|token|dynamic_id", public_key, re.I):
                continue
            cleaned = public_details(item)
            if cleaned not in ({}, [], None, ""):
                result[public_key] = cleaned
        return result
    if isinstance(value, list):
        return [
            cleaned
            for item in value[:50]
            if (cleaned := public_details(item)) not in ({}, [], None, "")
        ]
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    return str(value)


def details_from_row(row: sqlite3.Row) -> dict:
    raw = row["details_json"] if "details_json" in row.keys() else None
    if not raw:
        return {}
    try:
        value = json.loads(raw)
    except (TypeError, ValueError):
        return {}
    return public_details(value) if isinstance(value, dict) else {}


def details_json_payload(details: dict | None) -> str | None:
    if not details:
        return None
    return json.dumps(public_details(details), ensure_ascii=False, separators=(",", ":"))


def event_display(row: sqlite3.Row, details: dict) -> dict:
    bullets = [
        str(item)
        for item in details.get("bullets", [])
        if str(item).strip()
    ] if isinstance(details.get("bullets"), list) else []
    headline = str(details.get("headline") or row["title"])
    body = str(details.get("body") or row["message"])
    return {
        "headline": headline[:160],
        "body": body[:1000],
        "bullets": bullets[:8],
    }


def public_event(row: sqlite3.Row) -> dict:
    details = details_from_row(row)
    fingerprint = row["fingerprint"] if "fingerprint" in row.keys() else f"{row['source']}:{row['id']}"
    return {
        "key": public_event_key(fingerprint),
        "id": int(row["id"]),
        "occurredAt": row["occurred_at"],
        "type": row["type"],
        "player": row["player"],
        "guild": row["guild"] if "guild" in row.keys() else None,
        "base": row["base"] if "base" in row.keys() else None,
        "title": row["title"],
        "message": row["message"],
        "display": event_display(row, details),
        "details": details,
        "confidence": row["confidence"] if "confidence" in row.keys() else "confirmed",
        "icon": row["icon"],
        "source": row["source"],
    }


ITEMIZED_PUBLIC_GROUP_TYPES = {"craft", "production", "build", "repair", "base", "research"}
WORLD_DROP_STRUCTURE_NAMES = {"commondropitem3d", "commonitemdrop3d"}


def is_world_drop_structure_name(value: str | None) -> bool:
    text = str(value or "").strip()
    if not text:
        return False
    tail = re.split(r"[/\\]", text)[-1]
    normalized = re.sub(r"[\s_-]+", "", tail).casefold()
    return normalized in WORLD_DROP_STRUCTURE_NAMES or any(
        marker in normalized for marker in WORLD_DROP_STRUCTURE_NAMES
    )


def public_detail_rows(details: dict, key: str) -> list[dict]:
    rows = details.get(key)
    if isinstance(rows, dict):
        return [rows]
    if isinstance(rows, list):
        return [row for row in rows if isinstance(row, dict)]
    return []


def itemized_public_event_items(event: dict) -> list[dict]:
    details = event.get("details") or {}
    rows = public_detail_rows(details, "items")
    if event.get("type") == "build":
        rows = [*rows, *public_detail_rows(details, "structures")]
    return [
        row for row in rows
        if not (
            is_world_drop_structure_name(row.get("name"))
            or is_world_drop_structure_name(row.get("asset"))
        )
    ]


def itemized_public_event_added(event: dict) -> int:
    return itemized_added_total(event.get("details") or {})


def itemized_public_event_bucket(event: dict) -> datetime | None:
    occurred_at = parse_timestamp(event.get("occurredAt"))
    if occurred_at is None:
        return None
    minute = (occurred_at.minute // 5) * 5
    return occurred_at.replace(minute=minute, second=0, microsecond=0)


def itemized_public_group_owner(event: dict) -> str:
    return str(event.get("player") or event.get("base") or event.get("guild") or "Monde").strip() or "Monde"


def itemized_public_group_key(event: dict) -> tuple[str, str, str] | None:
    if event.get("type") not in ITEMIZED_PUBLIC_GROUP_TYPES or event.get("source") != "save":
        return None
    if int((event.get("details") or {}).get("aggregatedEvents") or 0) > 0:
        return None
    if itemized_public_event_added(event) <= 0:
        return None
    bucket = itemized_public_event_bucket(event)
    if bucket is None:
        return None
    owner = itemized_public_group_owner(event).casefold()
    return event["type"], owner, bucket.isoformat()


def aggregate_itemized_public_items(events: list[dict]) -> list[dict]:
    grouped: dict[str, dict] = {}
    latest_keys: dict[str, tuple[datetime, int]] = {}
    for event in sorted(
        events,
        key=lambda item: (
            parse_timestamp(item.get("occurredAt")) or datetime.min.replace(tzinfo=timezone.utc),
            int(item.get("id") or 0),
        ),
    ):
        event_at = parse_timestamp(event.get("occurredAt")) or datetime.min.replace(tzinfo=timezone.utc)
        event_id = int(event.get("id") or 0)
        for item in itemized_public_event_items(event):
            name = str(item.get("name") or "Objet").strip() or "Objet"
            asset = str(item.get("asset") or "").strip()
            key = (asset or name).casefold()
            added = int(item.get("added") or item.get("count") or 0)
            if added <= 0:
                continue
            current = grouped.setdefault(key, {
                "name": name,
                "asset": asset,
                "icon": item.get("icon"),
                "added": 0,
                "count": 0,
                "isNew": False,
            })
            current["added"] += added
            current["isNew"] = bool(current["isNew"] or item.get("isNew"))
            if not current.get("asset") and asset:
                current["asset"] = asset
            if not current.get("icon") and item.get("icon"):
                current["icon"] = item.get("icon")
            latest_key = latest_keys.get(key)
            if latest_key is None or (event_at, event_id) >= latest_key:
                current["name"] = name
                current["count"] = int(item.get("count") or 0)
                latest_keys[key] = (event_at, event_id)
    return sorted(
        grouped.values(),
        key=lambda item: (-int(item.get("added") or 0), str(item.get("name") or "").casefold()),
    )


def aggregate_itemized_public_bullets(events: list[dict]) -> list[str]:
    bullets = []
    for event in events:
        details = event.get("details") or {}
        for bullet in details.get("bullets") or []:
            text = str(bullet or "").strip()
            if not text or is_world_drop_structure_name(text):
                continue
            bullets.append(text)
    return bullets[:8]


def latest_public_event(events: list[dict]) -> dict:
    return max(
        events,
        key=lambda item: (
            parse_timestamp(item.get("occurredAt")) or datetime.min.replace(tzinfo=timezone.utc),
            int(item.get("id") or 0),
        ),
    )


def aggregate_itemized_public_event(events: list[dict]) -> dict:
    latest = latest_public_event(events)
    event_type = latest["type"]
    player = latest.get("player")
    guild = latest.get("guild")
    owner = itemized_public_group_owner(latest)
    bucket = itemized_public_event_bucket(latest) or parse_timestamp(latest.get("occurredAt"))
    window_end = bucket + timedelta(seconds=ITEMIZED_EVENT_GROUP_WINDOW_SECONDS) if bucket else None
    items = aggregate_itemized_public_items(events)
    added_total = sum(int(item.get("added") or 0) for item in items) or sum(itemized_public_event_added(event) for event in events)
    batches = len(events)
    bases = sorted(
        {str(event.get("base") or "").strip() for event in events if str(event.get("base") or "").strip()},
        key=str.casefold,
    )
    icon = next((item.get("icon") for item in items if item.get("icon")), latest.get("icon"))
    fingerprint = f"public-group:{event_type}:{owner.casefold()}:{bucket.isoformat() if bucket else latest.get('occurredAt')}"

    details = {
        "bullets": quantity_bullets(items) or aggregate_itemized_public_bullets(events),
        "aggregatedEvents": batches,
        "windowMinutes": ITEMIZED_EVENT_GROUP_WINDOW_SECONDS // 60,
    }
    if items:
        if event_type == "build":
            details["structures"] = items
        else:
            details["items"] = items
    if bucket:
        details["windowStart"] = bucket.isoformat()
    if window_end:
        details["windowEnd"] = window_end.isoformat()
    if bases:
        details["bases"] = bases

    def total_observed_by_base() -> int:
        if len(bases) == 1:
            return max(int((event.get("details") or {}).get("total") or 0) for event in events)
        totals_by_base: dict[str, int] = {}
        for grouped_event in events:
            base = str(grouped_event.get("base") or "").strip()
            total = int((grouped_event.get("details") or {}).get("total") or 0)
            if base and total > 0:
                totals_by_base[base] = max(totals_by_base.get(base, 0), total)
        return sum(totals_by_base.values())

    def base_scope_label(single_prefix: str = "à") -> str:
        if len(bases) == 1:
            return f" {single_prefix} {bases[0]}"
        if len(bases) > 1:
            return f" dans {len(bases)} bases"
        return ""

    if event_type == "craft":
        title = "Fabrications compilées"
        total = max(int((event.get("details") or {}).get("total") or 0) for event in events)
        message = (
            f"{owner} termine {added_total} {plural(added_total, 'fabrication')} en 5 min. "
            f"Total cumulé: {total}."
        ) if total > 0 else f"{owner} termine {added_total} {plural(added_total, 'fabrication')} en 5 min."
        body = message
        if total > 0:
            details["total"] = total
    elif event_type == "production":
        title = "Productions compilées"
        base_label = ""
        if len(bases) == 1:
            base_label = f" à {bases[0]}"
            total = max(int((event.get("details") or {}).get("total") or 0) for event in events)
            stock = f" Stock de production actuel: {total}." if total > 0 else ""
            details["total"] = total
        else:
            totals_by_base: dict[str, int] = {}
            for event in events:
                base = str(event.get("base") or "").strip()
                total = int((event.get("details") or {}).get("total") or 0)
                if base and total > 0:
                    totals_by_base[base] = max(totals_by_base.get(base, 0), total)
            total = sum(totals_by_base.values())
            base_label = f" dans {len(bases)} bases" if bases else ""
            stock = f" Stock de production observé: {total}." if total > 0 else ""
            if total > 0:
                details["total"] = total
        message = (
            f"{owner} boucle {batches} {plural(batches, 'production')} en 5 min. "
            f"{added_total} {plural(added_total, 'ressource produite est prête', 'ressources produites sont prêtes')}"
            f"{base_label}.{stock}"
        )
        body = message
    elif event_type == "build":
        title = "Constructions compilées"
        total = total_observed_by_base()
        if total > 0:
            details["total"] = total
        message = (
            f"{owner} confirme {added_total} "
            f"{plural(added_total, 'nouvelle structure confirmée', 'nouvelles structures confirmées')} "
            f"en 5 min{base_scope_label()}."
        )
        body = message
    elif event_type == "repair":
        title = "Réparations compilées"
        message = (
            f"{owner} répare {added_total} {plural(added_total, 'structure')} "
            f"en 5 min{base_scope_label()}."
        )
        body = message
    elif event_type == "research":
        title = "Recherches compilées"
        message = (
            f"{owner} confirme {added_total} {plural(added_total, 'recherche')} "
            f"en 5 min{base_scope_label()}."
        )
        body = message
    else:
        title = "Dégâts de base compilés"
        message = (
            f"{owner} compte {added_total} "
            f"{plural(added_total, 'structure endommagée', 'structures endommagées')} "
            f"en plus en 5 min{base_scope_label()}."
        )
        body = message

    details.update({"headline": title, "body": body})
    return {
        "key": public_event_key(fingerprint),
        "id": int(latest.get("id") or 0),
        "occurredAt": latest.get("occurredAt"),
        "type": event_type,
        "player": player,
        "guild": guild if all(event.get("guild") == guild for event in events) else None,
        "base": bases[0] if len(bases) == 1 else None,
        "title": title,
        "message": message,
        "display": {
            "headline": title,
            "body": body[:1000],
            "bullets": details["bullets"][:8],
        },
        "details": public_details(details),
        "confidence": "confirmed",
        "icon": icon,
        "source": "save",
    }


def group_itemized_public_events(events: list[dict]) -> list[dict]:
    groups: dict[tuple[str, str, str], list[dict]] = {}
    event_keys: dict[int, tuple[str, str, str]] = {}
    for event in events:
        key = itemized_public_group_key(event)
        if key is None:
            continue
        groups.setdefault(key, []).append(event)
        event_keys[int(event["id"])] = key

    emitted = set()
    grouped = []
    for event in events:
        key = event_keys.get(int(event["id"]))
        if key is None or len(groups.get(key, [])) < 2:
            grouped.append(event)
            continue
        if key in emitted:
            continue
        grouped.append(aggregate_itemized_public_event(groups[key]))
        emitted.add(key)
    return grouped


def duplicate_session_event_ids(
    events: list[dict],
    tolerance_seconds: int = SESSION_EVENT_TOLERANCE_SECONDS,
) -> set[int]:
    journal_transitions = []
    player_transitions = []
    for event in events:
        if event.get("type") not in {"join", "leave"} or not event.get("player"):
            continue
        occurred_at = parse_timestamp(event.get("occurredAt"))
        if occurred_at is None:
            continue
        transition = {
            "id": int(event["id"]),
            "player": str(event["player"]).casefold(),
            "type": event["type"],
            "occurredAt": occurred_at,
            "source": event.get("source"),
        }
        if event.get("source") == "journal":
            journal_transitions.append(transition)
        elif event.get("source") == "players":
            player_transitions.append(transition)

    suppressed = set()
    for player_event in player_transitions:
        if any(
            journal_event["player"] == player_event["player"]
            and journal_event["type"] == player_event["type"]
            and abs((journal_event["occurredAt"] - player_event["occurredAt"]).total_seconds())
            <= tolerance_seconds
            for journal_event in journal_transitions
        ):
            suppressed.add(player_event["id"])
    return suppressed


def reconcile_public_events(rows, window_seconds: int = RECONNECT_WINDOW_SECONDS) -> tuple[list[dict], int]:
    events = [public_event(row) for row in rows]
    capture_moments = {
        (event.get("occurredAt"), str(event.get("player") or "").casefold())
        for event in events
        if event.get("type") == "capture" and event.get("player")
    }
    chronological = sorted(
        events,
        key=lambda event: (
            parse_timestamp(event["occurredAt"]) or datetime.min.replace(tzinfo=timezone.utc),
            event["id"],
        ),
    )
    player_states: dict[str, bool] = {}
    pending_orphan_leaves: dict[str, list[dict]] = {}
    suppressed_ids = duplicate_session_event_ids(events)
    reconnect_ids = set()

    for event in chronological:
        if event["id"] in suppressed_ids:
            continue
        if event["type"] == "server":
            player_states = {key: False for key in player_states}
            pending_orphan_leaves.clear()
            continue
        if event["type"] not in {"join", "leave"} or not event.get("player"):
            continue

        key = str(event["player"]).casefold()
        occurred_at = parse_timestamp(event["occurredAt"])
        if occurred_at is None:
            continue

        if event["type"] == "leave":
            if player_states.get(key) is False:
                pending_orphan_leaves.setdefault(key, []).append(event)
            else:
                player_states[key] = False
            continue

        candidates = pending_orphan_leaves.pop(key, [])
        recent = [
            candidate
            for candidate in candidates
            if (candidate_at := parse_timestamp(candidate["occurredAt"])) is not None
            and 0 <= (occurred_at - candidate_at).total_seconds() <= window_seconds
        ]
        if recent:
            suppressed_ids.update(candidate["id"] for candidate in recent)
            reconnect_ids.add(event["id"])
        player_states[key] = True

    reconciled = []
    for event in events:
        if event["id"] in suppressed_ids:
            continue
        if event["type"] == "collection" and (
            event.get("occurredAt"), str(event.get("player") or "").casefold()
        ) in capture_moments:
            continue
        if event["id"] in reconnect_ids:
            event = dict(event)
            event["type"] = "reconnect"
            event["title"] = "Retour sur Palpagos"
            event["message"] = f"{event['player']} rétablit sa connexion et rejoint l'aventure."
            event["display"] = {
                "headline": event["title"],
                "body": event["message"],
                "bullets": [],
            }
        reconciled.append(event)
    return group_itemized_public_events(reconciled), len(reconnect_ids)


def archive_hour_key(path: Path, history_path: Path) -> str | None:
    try:
        year, month, day, filename = path.relative_to(history_path).parts[-4:]
        hour = filename.split(".", 1)[0]
        datetime(int(year), int(month), int(day), int(hour))
    except (ValueError, TypeError, IndexError):
        return None
    return f"{year}/{month}/{day}/{hour}"


def history_paths_since(history_path: Path, last_save_at: str) -> list[Path]:
    paths = sorted(history_path.glob("*/*/*/*.json.gz")) if history_path.exists() else []
    previous = parse_timestamp(last_save_at)
    if previous is None:
        return paths
    minimum_key = previous.strftime("%Y/%m/%d/%H")
    return [
        path
        for path in paths
        if (archive_hour_key(path, history_path) or minimum_key) >= minimum_key
    ]


def snapshot_player_state(player: dict) -> dict:
    pals = player.get("pals") if isinstance(player.get("pals"), dict) else {}
    species = {}
    for pal in pals.get("collection") or []:
        if not isinstance(pal, dict):
            continue
        name = str(pal.get("species") or pal.get("name") or "Pal inconnu")
        key = name.casefold()
        if key not in species:
            species[key] = {"name": name, "count": 0, "icon": pal.get("icon")}
        species[key]["count"] += 1
    progress = player.get("progress") if isinstance(player.get("progress"), dict) else {}
    paldex = progress.get("paldex") if isinstance(progress.get("paldex"), dict) else {}
    capture_details = {}
    for species_row in paldex.get("species") or []:
        if not isinstance(species_row, dict):
            continue
        species_name = str(species_row.get("name") or "Pal inconnu")
        capture_count = int(species_row.get("captureCount") or 0)
        challenge_count = int(species_row.get("challengeCount") or 0)
        if capture_count <= 0 and challenge_count <= 0:
            continue
        capture_details[species_name.casefold()] = {
            "name": species_name,
            "count": capture_count,
            "challengeCount": challenge_count,
            "challengeTarget": int(species_row.get("challengeTarget") or 5),
            "icon": species_row.get("icon"),
        }
    technologies = named_catalog(progress.get("technologies"))
    quests = progress.get("quests") if isinstance(progress.get("quests"), dict) else {}
    challenges = progress.get("challenges") if isinstance(progress.get("challenges"), dict) else {}
    records = progress.get("records") if isinstance(progress.get("records"), dict) else {}
    bosses = progress.get("bosses") if isinstance(progress.get("bosses"), dict) else {}
    exploration = progress.get("exploration") if isinstance(progress.get("exploration"), dict) else {}
    relics = progress.get("relics") if isinstance(progress.get("relics"), dict) else {}
    relic_ranks = {}
    for category in relics.get("categories") or []:
        if not isinstance(category, dict):
            continue
        category_name = str(category.get("name") or "Bonus inconnu")
        relic_ranks[category_name.casefold()] = {
            "name": category_name,
            "rank": int(category.get("rank") or 0),
        }
    return {
        "name": str(player.get("name") or "Aventurier"),
        "level": int(player.get("level") or 0),
        "bases": int(player.get("guildBases") or 0),
        "campLevel": int(player.get("campLevel") or 0),
        "pals": int(pals.get("total") or 0),
        "species": species,
        "captureDetails": capture_details,
        "technologies": int(progress.get("unlockedTechnologies") or 0),
        "technologyDetails": technologies,
        "quests": int(progress.get("completedQuests") or 0),
        "questDetails": named_catalog(quests.get("completed")),
        "challengeDetails": named_catalog(challenges.get("completed")),
        "records": {
            "treasuresFound": int(records.get("treasuresFound") or 0),
            "normalDungeonsCleared": int(records.get("normalDungeonsCleared") or 0),
            "fixedDungeonsCleared": int(records.get("fixedDungeonsCleared") or 0),
            "oilRigsCleared": int(records.get("oilRigsCleared") or 0),
            "campsConquered": int(records.get("campsConquered") or 0),
            "fishCaught": int(records.get("fishCaught") or 0),
            "itemsCrafted": int(records.get("itemsCrafted") or 0),
            "uniqueItemsPickedUp": int(records.get("uniqueItemsPickedUp") or 0),
            "notesFound": int(records.get("notesFound") or 0),
            "arenaSoloClears": int(records.get("arenaSoloClears") or 0),
            "mutations": int(records.get("mutations") or 0),
            "palRankups": int(records.get("palRankups") or 0),
            "raidBossDefeats": int(records.get("raidBossDefeats") or 0),
            "towerBossDefeats": int(records.get("towerBossDefeats") or 0),
        },
        "fishDetails": {
            str(row.get("asset") or row.get("name") or "").casefold(): {
                "name": str(row.get("name") or row.get("asset") or "Poisson inconnu"),
                "asset": str(row.get("asset") or row.get("name") or ""),
                "count": int(row.get("count") or 0),
                "icon": row.get("icon"),
            }
            for row in records.get("fish") or []
            if isinstance(row, dict) and int(row.get("count") or 0) > 0
        },
        "craftDetails": {
            str(row.get("asset") or row.get("name") or "").casefold(): {
                "name": str(row.get("name") or row.get("asset") or "Objet inconnu"),
                "asset": str(row.get("asset") or row.get("name") or ""),
                "count": int(row.get("count") or 0),
                "icon": row.get("icon"),
            }
            for row in records.get("craftedItems") or []
            if isinstance(row, dict) and int(row.get("count") or 0) > 0
        },
        "bosses": int(bosses.get("defeated") or 0),
        "bossDetails": named_catalog(bosses.get("known")),
        "fastTravel": sorted(
            {
                str(point).strip()
                for point in exploration.get("fastTravelPoints") or []
                if str(point).strip()
            },
            key=str.casefold,
        ),
        "relicRanks": relic_ranks,
    }


def base_state(row: dict) -> dict:
    structures = row.get("structures") if isinstance(row.get("structures"), dict) else {}
    production = row.get("production") if isinstance(row.get("production"), dict) else {}
    research = row.get("research") if isinstance(row.get("research"), dict) else {}
    players = [
        str(player)
        for player in row.get("players") or []
        if str(player).strip()
    ]
    structure_highlights = {}
    world_drop_structures = 0
    for item in structures.get("highlights") or []:
        if not isinstance(item, dict):
            continue
        count = int(item.get("count") or 0)
        if count <= 0:
            continue
        name = str(item.get("name") or "Structure")
        if is_world_drop_structure_name(name):
            world_drop_structures += count
            continue
        structure_highlights[name.casefold()] = {
            "name": name,
            "count": count,
        }
    return {
        "name": str(row.get("name") or "Base"),
        "guild": str(row.get("guild") or ""),
        "players": sorted(players, key=str.casefold),
        "structuresTotal": max(0, int(structures.get("total") or 0) - world_drop_structures),
        "structuresDamaged": int(structures.get("damaged") or 0),
        "structuresUnfinished": int(structures.get("unfinished") or 0),
        "structureHighlights": structure_highlights,
        "productionItems": {
            str(item.get("name") or "").casefold(): {
                "name": str(item.get("name") or "Production"),
                "count": int(item.get("count") or 0),
                "icon": item.get("icon"),
            }
            for item in production.get("topItems") or []
            if isinstance(item, dict) and int(item.get("count") or 0) > 0
        },
        "researchCompleted": int(research.get("completed") or 0),
        "researchCurrent": str(research.get("current") or ""),
    }


def bases_state(payload: dict | None) -> dict:
    bases = {}
    if not isinstance(payload, dict):
        return bases
    for row in payload.get("bases") or []:
        if not isinstance(row, dict):
            continue
        state = base_state(row)
        key = f"{state['guild']}::{state['name']}".casefold()
        bases[key] = state
    return bases


def server_base_number(name: str | None) -> int | None:
    match = SERVER_BASE_NAME_RE.match(str(name or "").strip())
    if not match:
        return None
    return int(match.group("number"))


def base_sort_key(base: dict) -> tuple[int, str]:
    number = server_base_number(base.get("name"))
    return (
        number if number is not None else 1_000_000,
        str(base.get("name") or "").casefold(),
    )


def player_base_label_index(bases: dict) -> dict[tuple[str, str], str]:
    grouped: dict[str, list[dict]] = {}
    for base in bases.values():
        if server_base_number(base.get("name")) is None:
            continue
        for player in base.get("players") or []:
            player_key = str(player).casefold()
            grouped.setdefault(player_key, []).append(base)

    labels: dict[tuple[str, str], str] = {}
    for player_key, player_bases in grouped.items():
        for index, base in enumerate(sorted(player_bases, key=base_sort_key), start=1):
            labels[(player_key, str(base.get("name") or "").casefold())] = f"Base {index}"
    return labels


def public_base_name(base: dict, player: str | None, label_index: dict[tuple[str, str], str]) -> str:
    raw_name = str(base.get("name") or "Base")
    if player:
        label = label_index.get((str(player).casefold(), raw_name.casefold()))
        if label:
            return label

    players = [str(item) for item in base.get("players") or [] if str(item).strip()]
    if len(players) == 1:
        label = label_index.get((players[0].casefold(), raw_name.casefold()))
        if label:
            return label

    return raw_name


def base_label_details(details: dict, raw_name: str, public_name: str, player: str | None) -> dict:
    if raw_name == public_name:
        return details
    enriched = dict(details)
    enriched["baseName"] = public_name
    enriched["rawBaseName"] = raw_name
    if player:
        enriched["baseLabelScope"] = player
    return enriched


def death_drops_state(payload: dict | None) -> dict:
    if not isinstance(payload, dict):
        return {}
    world = payload.get("world") if isinstance(payload.get("world"), dict) else {}
    drops = {}
    for row in world.get("deathDrops") or []:
        if not isinstance(row, dict):
            continue
        key = str(row.get("key") or "").strip()
        if not key:
            continue
        drops[key] = {
            "key": key,
            "type": str(row.get("type") or "death-drop"),
            "label": str(row.get("label") or "Sac de récupération"),
            "player": str(row.get("player") or "").strip() or None,
            "position": row.get("position") if isinstance(row.get("position"), dict) else None,
        }
    return drops


def snapshot_state(payload: dict, bases_payload: dict | None = None) -> dict:
    players = {}
    for player in payload.get("players") or []:
        if not isinstance(player, dict):
            continue
        state = snapshot_player_state(player)
        players[state["name"].casefold()] = state
    return {
        "players": players,
        "bases": bases_state(bases_payload or payload),
        "deathDrops": death_drops_state(payload),
    }


def plural(value: int, singular: str, plural_form: str | None = None) -> str:
    return singular if value == 1 else (plural_form or f"{singular}s")


def named_catalog(rows) -> dict:
    catalog = {}
    for row in rows or []:
        if not isinstance(row, dict):
            continue
        name = str(row.get("name") or "").strip()
        if not name:
            continue
        item = {"name": name, "icon": row.get("icon")}
        for field in ("asset", "level", "rank", "type"):
            value = row.get(field)
            if value not in (None, ""):
                item[field] = value
        catalog[name.casefold()] = item
    return catalog


def french_list(values: list[str], limit: int = 5) -> str:
    displayed = values[:limit]
    remaining = len(values) - len(displayed)
    if remaining:
        displayed.append(f"{remaining} autre{'' if remaining == 1 else 's'}")
    if not displayed:
        return ""
    if len(displayed) == 1:
        return displayed[0]
    return f"{', '.join(displayed[:-1])} et {displayed[-1]}"


def boss_public_label(boss: dict) -> str:
    name = str(boss.get("name") or "Boss").strip() or "Boss"
    try:
        level = int(boss.get("level") or 0)
    except (TypeError, ValueError):
        level = 0
    return f"{name} niveau {level}" if level > 0 else name


def positive_catalog_changes(current: dict, previous: dict) -> list[dict]:
    changes = []
    for key, row in current.items():
        count = int(row.get("count") or 0)
        old_count = int((previous.get(key) or {}).get("count") or 0)
        if count > old_count:
            changes.append({**row, "added": count - old_count, "isNew": old_count == 0})
    return sorted(changes, key=lambda row: str(row.get("name") or "").casefold())


def quantity_bullets(rows: list[dict], prefix: str = "+") -> list[str]:
    return [
        f"{prefix}{int(row.get('added') or row.get('count') or 0)} {row.get('name')}"
        for row in rows
        if int(row.get("added") or row.get("count") or 0) > 0 and row.get("name")
    ]


def quantity_total_from_bullets(bullets: list) -> int:
    total = 0
    for bullet in bullets or []:
        match = re.match(r"^[+-]?(\d+)", str(bullet or ""))
        if match:
            total += int(match.group(1))
    return total


def delta_event(
    connection: sqlite3.Connection,
    *,
    occurred_at: str,
    event_type: str,
    player_key: str,
    player_name: str,
    record_key: str,
    old_records: dict,
    records: dict,
    title: str,
    title_plural: str | None = None,
    singular: str,
    plural_label: str | None = None,
    verb: str = "ajoute",
    total_label: str = "Total cumulé",
    confidence: str = "confirmed",
) -> None:
    total = int(records.get(record_key) or 0)
    previous = int(old_records.get(record_key) or 0)
    delta = total - previous
    if delta <= 0:
        return
    label = plural(delta, singular, plural_label)
    display_title = title if delta == 1 else (title_plural or title)
    body = f"{player_name} {verb} {delta} {label}. {total_label}: {total}."
    add_event(
        connection,
        fingerprint=f"save:{occurred_at}:{event_type}:{player_key}:{record_key}:{total}",
        occurred_at=occurred_at,
        event_type=event_type,
        player=player_name,
        title=display_title,
        message=body,
        source="save",
        confidence=confidence,
        details={
            "headline": display_title,
            "body": body,
            "bullets": [f"+{delta} {label}"],
            "total": total,
        },
    )


def detail_items_quantity_total(details: dict, key: str) -> int:
    total = 0
    for collection_key in ("items", "structures"):
        for item in public_detail_rows(details, collection_key):
            if is_world_drop_structure_name(item.get("name")) or is_world_drop_structure_name(item.get("asset")):
                continue
            total += int(item.get(key) or 0)
    return total


def itemized_added_total(details: dict) -> int:
    return detail_items_quantity_total(details, "added") or quantity_total_from_bullets(details.get("bullets") or [])


def production_event_headline(player: str | None, base: str | None, fallback: str) -> str:
    player = str(player or "").strip()
    base = str(base or "").strip()
    if player and base:
        return f"{player} termine une production à {base}"
    if player:
        return f"{player} termine une production"
    if base:
        return f"{base} termine une production"
    return fallback


def normalized_itemized_event(row: sqlite3.Row, details: dict) -> tuple[str, str, str | None] | None:
    event_type = row["type"]
    if event_type not in {"craft", "fishing", "production"}:
        return None

    added = itemized_added_total(details)
    player = str(row["player"] or "").strip()
    if added <= 0:
        return None

    normalized = dict(details)
    if event_type == "craft":
        total = int(normalized.get("total") or 0)
        if not player or total <= 0:
            return None
        title = "Fabrication terminée" if added == 1 else "Fabrications terminées"
        message = (
            f"{player} termine {added} {plural(added, 'fabrication')}. "
            f"Total cumulé: {total}."
        )
        normalized.update({"headline": title, "body": message, "total": total})
        return title, message, details_json_payload(normalized)

    if event_type == "fishing":
        total = int(normalized.get("total") or 0)
        if not player or total <= 0:
            return None
        title = "Prise de pêche" if added == 1 else "Pêche fructueuse"
        message = (
            f"{player} ramène {added} {plural(added, 'prise de pêche', 'prises de pêche')}. "
            f"Total cumulé: {total}."
        )
        normalized.update({"headline": title, "body": message, "total": total})
        return title, message, details_json_payload(normalized)

    total = int(normalized.get("total") or detail_items_quantity_total(normalized, "count"))
    headline = production_event_headline(row["player"], row["base"], str(row["title"] or "Production terminée"))
    ready = (
        "1 ressource produite est prête"
        if added == 1
        else f"{added} ressources produites sont prêtes"
    )
    body = f"{ready}. Stock de production actuel: {total}." if total > 0 else f"{ready}."
    message = f"{headline}. {body}"
    if total > 0:
        normalized["total"] = total
    normalized.update({"headline": headline, "body": body})
    return str(row["title"] or "Production terminée"), message, details_json_payload(normalized)


def compare_enriched_progress(
    connection: sqlite3.Connection,
    old: dict,
    player: dict,
    occurred_at: str,
    key: str,
    capture_only: bool = False,
) -> None:
    name = player["name"]
    old_captures = old.get("captureDetails") or {}
    for species_key, species in (player.get("captureDetails") or {}).items():
        previous = old_captures.get(species_key) or {}
        old_count = int(previous.get("count") or 0)
        count = int(species.get("count") or 0)
        if count > old_count:
            added = count - old_count
            first_capture = old_count == 0
            title = "Première capture" if first_capture else "Capture réussie"
            if first_capture and added == 1:
                message = f"{name} capture {species['name']} pour la première fois."
            elif first_capture:
                message = (
                    f"{name} inscrit {species['name']} dans son Paldex avec {added} captures."
                )
            else:
                message = (
                    f"{name} capture {added} {species['name']}. "
                    f"Total enregistré: {count}."
                )
            add_event(
                connection,
                fingerprint=f"save:capture:{key}:{species_key}:{count}",
                occurred_at=occurred_at,
                event_type="capture",
                player=name,
                title=title,
                message=message,
                icon=species.get("icon"),
                source="save",
            )

        old_challenge = int(previous.get("challengeCount") or 0)
        challenge = int(species.get("challengeCount") or 0)
        target = max(1, int(species.get("challengeTarget") or 5))
        if old_challenge < target <= challenge:
            add_event(
                connection,
                fingerprint=f"save:capture-challenge:{key}:{species_key}:{target}",
                occurred_at=occurred_at,
                event_type="challenge",
                player=name,
                title="Défi de capture réussi",
                message=(
                    f"{name} complète le défi de {species['name']}: "
                    f"{target} captures enregistrées."
                ),
                icon=species.get("icon"),
                source="save",
            )

    if capture_only:
        return

    new_quests = positive_catalog_changes(
        {catalog_key: {**row, "count": 1} for catalog_key, row in (player.get("questDetails") or {}).items()},
        {catalog_key: {**row, "count": 1} for catalog_key, row in (old.get("questDetails") or {}).items()},
    )
    if new_quests:
        quest_names = [row["name"] for row in new_quests]
        add_event(
            connection,
            fingerprint=f"save:{occurred_at}:quests-detailed:{key}:{len(player.get('questDetails') or {})}",
            occurred_at=occurred_at,
            event_type="quest",
            player=name,
            title="Quête terminée" if len(new_quests) == 1 else "Quêtes terminées",
            message=f"{name} termine {french_list(quest_names)}.",
            source="save",
        )

    new_challenges = positive_catalog_changes(
        {catalog_key: {**row, "count": 1} for catalog_key, row in (player.get("challengeDetails") or {}).items()},
        {catalog_key: {**row, "count": 1} for catalog_key, row in (old.get("challengeDetails") or {}).items()},
    )
    if new_challenges:
        challenge_names = [row["name"] for row in new_challenges]
        add_event(
            connection,
            fingerprint=f"save:{occurred_at}:challenges:{key}:{len(player.get('challengeDetails') or {})}",
            occurred_at=occurred_at,
            event_type="challenge",
            player=name,
            title="Défi Palworld réussi" if len(new_challenges) == 1 else "Défis Palworld réussis",
            message=f"{name} débloque {french_list(challenge_names)}.",
            source="save",
        )

    records = player.get("records") or {}
    old_records = old.get("records") or {}
    crafted = positive_catalog_changes(
        player.get("craftDetails") or {},
        old.get("craftDetails") or {},
    )
    if crafted:
        total = int(records.get("itemsCrafted") or 0)
        added_total = sum(int(item["added"]) for item in crafted)
        main = crafted[0]
        title = "Fabrication terminée" if added_total == 1 else "Fabrications terminées"
        message = (
            f"{name} termine {added_total} {plural(added_total, 'fabrication')}. "
            f"Total cumulé: {total}."
        )
        add_event(
            connection,
            fingerprint=f"save:{occurred_at}:craft:{key}:{total}",
            occurred_at=occurred_at,
            event_type="craft",
            player=name,
            title=title,
            message=message,
            icon=main.get("icon"),
            source="save",
            details={
                "headline": title,
                "body": message,
                "bullets": quantity_bullets(crafted),
                "items": crafted,
                "total": total,
            },
        )

    fish = positive_catalog_changes(
        player.get("fishDetails") or {},
        old.get("fishDetails") or {},
    )
    if fish:
        total = int(records.get("fishCaught") or 0)
        added_total = sum(int(item["added"]) for item in fish)
        main = fish[0]
        title = "Prise de pêche" if added_total == 1 else "Pêche fructueuse"
        message = (
            f"{name} ramène {added_total} {plural(added_total, 'prise de pêche', 'prises de pêche')}. "
            f"Total cumulé: {total}."
        )
        add_event(
            connection,
            fingerprint=f"save:{occurred_at}:fishing:{key}:{total}",
            occurred_at=occurred_at,
            event_type="fishing",
            player=name,
            title=title,
            message=message,
            icon=main.get("icon"),
            source="save",
            details={
                "headline": title,
                "body": message,
                "bullets": quantity_bullets(fish),
                "items": fish,
                "total": total,
            },
        )

    treasure_delta = int(records.get("treasuresFound") or 0) - int(
        old_records.get("treasuresFound") or 0
    )
    if treasure_delta > 0:
        add_event(
            connection,
            fingerprint=f"save:{occurred_at}:treasures:{key}:{records.get('treasuresFound', 0)}",
            occurred_at=occurred_at,
            event_type="loot",
            player=name,
            title="Trésor découvert" if treasure_delta == 1 else "Trésors découverts",
            message=(
                f"{name} trouve {treasure_delta} nouveau"
                f"{'' if treasure_delta == 1 else 'x'} trésor{'' if treasure_delta == 1 else 's'}."
            ),
            source="save",
        )

    expedition_labels = (
        ("normalDungeonsCleared", "donjon aléatoire", "donjons aléatoires"),
        ("fixedDungeonsCleared", "donjon majeur", "donjons majeurs"),
        ("oilRigsCleared", "plateforme pétrolière", "plateformes pétrolières"),
        ("campsConquered", "camp ennemi", "camps ennemis"),
    )
    completed = []
    for record_key, label, plural_label in expedition_labels:
        delta = int(records.get(record_key) or 0) - int(old_records.get(record_key) or 0)
        if delta > 0:
            completed.append(f"{delta} {plural(delta, label, plural_label)}")
    if completed:
        add_event(
            connection,
            fingerprint=(
                f"save:{occurred_at}:expeditions:{key}:"
                f"{sum(int(records.get(record_key) or 0) for record_key, _, _ in expedition_labels)}"
            ),
            occurred_at=occurred_at,
            event_type="adventure",
            player=name,
            title="Expédition accomplie",
            message=f"{name} termine {french_list(completed)}.",
            source="save",
        )

    delta_event(
        connection,
        occurred_at=occurred_at,
        event_type="raid",
        player_key=key,
        player_name=name,
        record_key="raidBossDefeats",
        old_records=old_records,
        records=records,
        title="Boss de raid vaincu",
        title_plural="Boss de raid vaincus",
        singular="boss de raid",
        verb="vainc",
    )
    if int(player.get("bosses") or 0) <= int(old.get("bosses") or 0):
        delta_event(
            connection,
            occurred_at=occurred_at,
            event_type="boss",
            player_key=key,
            player_name=name,
            record_key="towerBossDefeats",
            old_records=old_records,
            records=records,
            title="Boss de tour vaincu",
            title_plural="Boss de tour vaincus",
            singular="boss de tour",
            verb="vainc",
        )
    delta_event(
        connection,
        occurred_at=occurred_at,
        event_type="arena",
        player_key=key,
        player_name=name,
        record_key="arenaSoloClears",
        old_records=old_records,
        records=records,
        title="Arène solo terminée",
        title_plural="Arènes solo terminées",
        singular="arène solo",
        plural_label="arènes solo",
        verb="termine",
    )
    delta_event(
        connection,
        occurred_at=occurred_at,
        event_type="note",
        player_key=key,
        player_name=name,
        record_key="notesFound",
        old_records=old_records,
        records=records,
        title="Note trouvée",
        title_plural="Notes trouvées",
        singular="note",
        verb="trouve",
    )
    delta_event(
        connection,
        occurred_at=occurred_at,
        event_type="pal",
        player_key=key,
        player_name=name,
        record_key="palRankups",
        old_records=old_records,
        records=records,
        title="Pal amélioré",
        title_plural="Pals améliorés",
        singular="amélioration de Pal",
        plural_label="améliorations de Pal",
        verb="réalise",
    )
    delta_event(
        connection,
        occurred_at=occurred_at,
        event_type="mutation",
        player_key=key,
        player_name=name,
        record_key="mutations",
        old_records=old_records,
        records=records,
        title="Mutation confirmée",
        title_plural="Mutations confirmées",
        singular="mutation",
        verb="confirme",
    )
    delta_event(
        connection,
        occurred_at=occurred_at,
        event_type="loot",
        player_key=key,
        player_name=name,
        record_key="uniqueItemsPickedUp",
        old_records=old_records,
        records=records,
        title="Objet unique découvert",
        title_plural="Objets uniques découverts",
        singular="type d'objet unique",
        plural_label="types d'objets uniques",
        verb="découvre",
    )


def base_event_player(base: dict, active_players: set[str] | None = None) -> str | None:
    players = base.get("players") or []
    if active_players is not None:
        active_base_players = [
            str(player)
            for player in players
            if str(player).casefold() in active_players
        ]
        return active_base_players[0] if len(active_base_players) == 1 else None
    return players[0] if len(players) == 1 else None


def death_drop_event_details(row: dict, status: str) -> dict:
    details = {
        "headline": str(row.get("label") or "Sac de récupération"),
        "body": "Signal confirmé dans la sauvegarde du monde.",
        "dropType": str(row.get("type") or "death-drop"),
        "status": status,
    }
    if isinstance(row.get("position"), dict):
        details["position"] = row["position"]
    return details


def french_de_name(name: str) -> str:
    stripped = str(name or "").strip()
    if not stripped:
        return ""
    return f"d'{stripped}" if stripped[:1].casefold() in "aeiouyàâäéèêëîïôöùûü" else f"de {stripped}"


def compare_death_drop_events(
    connection: sqlite3.Connection,
    previous: dict,
    current: dict,
    occurred_at: str,
) -> None:
    old_drops = previous.get("deathDrops") or {}
    new_drops = current.get("deathDrops") or {}
    for key, row in new_drops.items():
        if key in old_drops:
            continue
        label = str(row.get("label") or "Sac de récupération")
        player = row.get("player")
        message = (
            f"Le {label.casefold()} {french_de_name(player)} apparaît sur Palpagos."
            if player
            else f"Un {label.casefold()} apparaît sur Palpagos."
        )
        add_event(
            connection,
            fingerprint=f"save:{occurred_at}:death-drop:new:{key}",
            occurred_at=occurred_at,
            event_type="death",
            player=player,
            title=f"{label} détecté",
            message=message,
            source="save",
            confidence="confirmed" if player else "derived",
            details={
                **death_drop_event_details(row, "appeared"),
                "body": message,
            },
        )

    for key, row in old_drops.items():
        if key in new_drops:
            continue
        label = str(row.get("label") or "Sac de récupération")
        player = row.get("player")
        message = (
            f"Le {label.casefold()} {french_de_name(player)} n'est plus présent dans la sauvegarde."
            if player
            else f"Un {label.casefold()} n'est plus présent dans la sauvegarde."
        )
        add_event(
            connection,
            fingerprint=f"save:{occurred_at}:death-drop:cleared:{key}",
            occurred_at=occurred_at,
            event_type="recovery",
            player=player,
            title="Sac récupéré ou disparu",
            message=message,
            source="save",
            confidence="derived",
            details={
                **death_drop_event_details(row, "cleared"),
                "headline": "Sac récupéré ou disparu",
                "body": message,
            },
        )


def compare_base_events(
    connection: sqlite3.Connection,
    previous: dict,
    current: dict,
    occurred_at: str,
    active_players: set[str] | dict[str, str] | None = None,
) -> None:
    old_bases = previous.get("bases") or {}
    new_bases = current.get("bases") or {}
    active_player_keys = activity_player_keys(active_players)
    base_labels = player_base_label_index(new_bases)
    for key, base in new_bases.items():
        old = old_bases.get(key)
        name = base["name"]
        guild = base.get("guild") or None
        player = base_event_player(base, active_player_keys)
        display_name = public_base_name(base, player, base_labels)
        event_occurred_at = activity_event_time(active_players, player, occurred_at)
        if old is None:
            if active_player_keys is not None and player is None:
                continue
            add_event(
                connection,
                fingerprint=f"save:{event_occurred_at}:base:new:{key}",
                occurred_at=event_occurred_at,
                event_type="base",
                player=player,
                guild=guild,
                base=display_name,
                title="Nouvelle base",
                message=f"{display_name} apparaît dans les chroniques de la guilde {guild or 'inconnue'}.",
                source="save",
                details=base_label_details({
                    "headline": f"{player} établit {display_name}" if player else f"{display_name} rejoint l'aventure",
                    "body": f"La guilde {guild or 'inconnue'} compte une nouvelle base suivie.",
                    "bullets": [f"Camp niveau {base.get('campLevel')}"] if base.get("campLevel") else [],
                }, name, display_name, player),
            )
            continue

        structure_changes = positive_catalog_changes(
            base.get("structureHighlights") or {},
            old.get("structureHighlights") or {},
        )
        total_delta = int(base.get("structuresTotal") or 0) - int(old.get("structuresTotal") or 0)
        if total_delta > 0 and structure_changes and (active_player_keys is None or player is not None):
            bullets = quantity_bullets(structure_changes)
            headline = (
                f"{player} agrandit {display_name}"
                if player
                else f"{display_name} s'agrandit"
            )
            message = (
                f"{headline}. "
                f"{total_delta} {plural(total_delta, 'nouvelle structure confirmée', 'nouvelles structures confirmées')}."
            )
            add_event(
                connection,
                fingerprint=f"save:{event_occurred_at}:build:{key}:{base.get('structuresTotal')}",
                occurred_at=event_occurred_at,
                event_type="build",
                player=player,
                guild=guild,
                base=display_name,
                title="Base agrandie",
                message=message,
                source="save",
                details=base_label_details({
                    "headline": headline,
                    "body": "De nouvelles structures sont confirmées dans la sauvegarde.",
                    "bullets": bullets,
                    "structures": structure_changes,
                    "total": base.get("structuresTotal"),
                }, name, display_name, player),
            )

        production_changes = positive_catalog_changes(
            base.get("productionItems") or {},
            old.get("productionItems") or {},
        )
        if production_changes and (active_player_keys is None or player is not None):
            produced = sum(int(item["added"]) for item in production_changes)
            production_total = sum(int(item["count"]) for item in base.get("productionItems", {}).values())
            headline = (
                f"{player} termine une production à {display_name}"
                if player
                else f"{display_name} termine une production"
            )
            ready = (
                "1 ressource produite est prête"
                if produced == 1
                else f"{produced} ressources produites sont prêtes"
            )
            body = f"{ready}. Stock de production actuel: {production_total}."
            message = (
                f"{headline}. "
                f"{body}"
            )
            add_event(
                connection,
                fingerprint=f"save:{event_occurred_at}:production:{key}:{production_total}",
                occurred_at=event_occurred_at,
                event_type="production",
                player=player,
                guild=guild,
                base=display_name,
                title="Production terminée",
                message=message,
                icon=production_changes[0].get("icon"),
                source="save",
                details=base_label_details({
                    "headline": headline,
                    "body": body,
                    "bullets": quantity_bullets(production_changes),
                    "items": production_changes,
                    "total": production_total,
                }, name, display_name, player),
            )

        old_damaged = int(old.get("structuresDamaged") or 0)
        damaged = int(base.get("structuresDamaged") or 0)
        if damaged < old_damaged and (active_player_keys is None or player is not None):
            repaired = old_damaged - damaged
            headline = (
                f"{player} remet {display_name} en état"
                if player
                else f"{display_name} reprend des couleurs"
            )
            add_event(
                connection,
                fingerprint=f"save:{event_occurred_at}:repair:{key}:{damaged}",
                occurred_at=event_occurred_at,
                event_type="repair",
                player=player,
                guild=guild,
                base=display_name,
                title="Réparations confirmées",
                message=f"{headline}: {repaired} structure{'' if repaired == 1 else 's'} réparée{'' if repaired == 1 else 's'}.",
                source="save",
                details=base_label_details({
                    "headline": headline,
                    "body": "La sauvegarde confirme moins de structures endommagées.",
                    "bullets": [f"-{repaired} structure{'' if repaired == 1 else 's'} endommagée{'' if repaired == 1 else 's'}"],
                }, name, display_name, player),
            )
        elif damaged > old_damaged and (active_player_keys is None or player is not None):
            damaged_delta = damaged - old_damaged
            headline = (
                f"{player} constate des dégâts à {display_name}"
                if player
                else f"{display_name} encaisse des dégâts"
            )
            add_event(
                connection,
                fingerprint=f"save:{event_occurred_at}:base-damage:{key}:{damaged}",
                occurred_at=event_occurred_at,
                event_type="base",
                player=player,
                guild=guild,
                base=display_name,
                title="Base endommagée",
                message=(
                    f"{headline}: {damaged_delta} "
                    f"{plural(damaged_delta, 'structure endommagée', 'structures endommagées')} en plus."
                ),
                source="save",
                details=base_label_details({
                    "headline": headline,
                    "body": "La sauvegarde confirme davantage de structures endommagées.",
                    "bullets": [
                        f"+{damaged_delta} "
                        f"{plural(damaged_delta, 'structure endommagée', 'structures endommagées')}"
                    ],
                    "damagedTotal": damaged,
                }, name, display_name, player),
            )

        research_delta = int(base.get("researchCompleted") or 0) - int(old.get("researchCompleted") or 0)
        if research_delta > 0 and (active_player_keys is None or player is not None):
            headline = (
                f"{player} fait progresser la recherche de guilde"
                if player
                else f"La recherche avance à {display_name}"
            )
            add_event(
                connection,
                fingerprint=f"save:{event_occurred_at}:research:{key}:{base.get('researchCompleted')}",
                occurred_at=event_occurred_at,
                event_type="research",
                player=player,
                guild=guild,
                base=display_name,
                title="Recherche terminée",
                message=f"{headline}: {research_delta} recherche{'' if research_delta == 1 else 's'} confirmée{'' if research_delta == 1 else 's'}.",
                source="save",
                details=base_label_details({
                    "headline": headline,
                    "body": "La progression de laboratoire est confirmée dans la sauvegarde.",
                    "bullets": [f"+{research_delta} recherche{'' if research_delta == 1 else 's'}"],
                }, name, display_name, player),
            )


def compare_snapshots(
    connection: sqlite3.Connection,
    previous: dict,
    current: dict,
    occurred_at: str,
    known_players: set[str],
    active_players: set[str] | dict[str, str] | None = None,
) -> None:
    old_players = previous.get("players") or {}
    new_players = current.get("players") or {}
    active_player_keys = activity_player_keys(active_players)
    if "deathDrops" not in previous:
        previous["deathDrops"] = current.get("deathDrops", {})
    else:
        compare_death_drop_events(connection, previous, current, occurred_at)
    compare_base_events(connection, previous, current, occurred_at, active_players)

    for key, player in new_players.items():
        old = old_players.get(key)
        name = player["name"]
        player_active = active_player_keys is None or key in active_player_keys
        player_occurred_at = activity_event_time(active_players, key, occurred_at)
        if old is None:
            if key not in known_players and player_active:
                add_event(
                    connection,
                    fingerprint=f"save:{player_occurred_at}:new-player:{key}",
                    occurred_at=player_occurred_at,
                    event_type="discovery",
                    player=name,
                    title="Nouvel aventurier",
                    message=f"{name} laisse sa première trace dans les chroniques.",
                    source="save",
                )
            known_players.add(key)
            continue
        if not player_active:
            known_players.add(key)
            continue

        # Existing metadata predates some detailed fields. Seed those fields from
        # the current snapshot once, rather than publishing false historical events.
        for field in (
            "technologyDetails",
            "bosses",
            "bossDetails",
            "fastTravel",
            "relicRanks",
            "captureDetails",
            "questDetails",
            "challengeDetails",
            "records",
        ):
            if field not in old:
                old[field] = player.get(field, {})
        old_records = old.get("records") if isinstance(old.get("records"), dict) else {}
        old["records"] = old_records
        current_records = player.get("records") or {}
        for field in NEW_RECORD_FIELDS:
            if field not in old_records:
                old_records[field] = current_records.get(field, 0)

        compare_enriched_progress(connection, old, player, player_occurred_at, key)

        if player["level"] > old["level"]:
            add_event(
                connection,
                fingerprint=f"save:{player_occurred_at}:level:{key}:{player['level']}",
                occurred_at=player_occurred_at,
                event_type="level",
                player=name,
                title="Niveau supérieur",
                message=f"{name} atteint le niveau {player['level']}.",
                source="save",
            )

        pal_delta = player["pals"] - old["pals"]
        if pal_delta > 0:
            additions = positive_catalog_changes(player["species"], old.get("species") or {})
            additions_total = sum(int(item["added"]) for item in additions)
            additions_text = french_list(
                [f"{item['added']} {item['name']}" for item in additions]
            )
            if additions_text and additions_total == pal_delta:
                message = f"{name} accueille {additions_text} dans sa collection."
            elif additions_text:
                message = (
                    f"La collection de {name} compte {pal_delta} "
                    f"{plural(pal_delta, 'Pal')} de plus. Ajouts détectés: {additions_text}."
                )
            else:
                message = (
                    f"{name} accueille {pal_delta} {'nouveau' if pal_delta == 1 else 'nouveaux'} "
                    f"{plural(pal_delta, 'Pal')} dans sa collection."
                )
            new_species = [item for item in additions if item["isNew"]]
            if new_species:
                species_label = "Espèce découverte" if len(new_species) == 1 else "Espèces découvertes"
                message += f" {species_label}: {french_list([item['name'] for item in new_species])}."
            add_event(
                connection,
                fingerprint=f"save:{player_occurred_at}:pals:{key}:{player['pals']}",
                occurred_at=player_occurred_at,
                event_type="collection",
                player=name,
                title="Collection enrichie",
                message=message,
                icon=additions[0].get("icon") if additions else None,
                source="save",
            )

        quest_delta = player["quests"] - old["quests"]
        technology_delta = player["technologies"] - old["technologies"]
        if quest_delta > 0 or technology_delta > 0:
            achievements = []
            new_quest_details = set((player.get("questDetails") or {}).keys())
            old_quest_details = set((old.get("questDetails") or {}).keys())
            detailed_quest_delta = len(new_quest_details - old_quest_details)
            undetailed_quest_delta = max(0, quest_delta - detailed_quest_delta)
            if undetailed_quest_delta > 0:
                achievements.append(
                    f"{undetailed_quest_delta} {plural(undetailed_quest_delta, 'quête')} "
                    f"terminée{'' if undetailed_quest_delta == 1 else 's'}"
                )
            if technology_delta > 0:
                new_technologies = [
                    technology
                    for technology_key, technology in player["technologyDetails"].items()
                    if technology_key not in (old.get("technologyDetails") or {})
                ]
                new_technologies.sort(key=lambda item: item["name"].casefold())
                if new_technologies:
                    achievements.append(
                        f"{technology_delta} {plural(technology_delta, 'technologie')} débloquée"
                        f"{'' if technology_delta == 1 else 's'}: "
                        f"{french_list([item['name'] for item in new_technologies])}"
                    )
                else:
                    achievements.append(
                        f"{technology_delta} nouvelle{'' if technology_delta == 1 else 's'} "
                        f"{plural(technology_delta, 'technologie')}"
                    )
            if achievements:
                add_event(
                    connection,
                    fingerprint=f"save:{player_occurred_at}:progress:{key}:{player['quests']}:{player['technologies']}",
                    occurred_at=player_occurred_at,
                    event_type="progress",
                    player=name,
                    title="Nouvelle avancée",
                    message=f"{name} progresse: {'; '.join(achievements)}.",
                    icon=new_technologies[0].get("icon") if technology_delta > 0 and new_technologies else None,
                    source="save",
                )

        boss_delta = player["bosses"] - int(old.get("bosses") or 0)
        if boss_delta > 0:
            new_bosses = [
                boss
                for boss_key, boss in player["bossDetails"].items()
                if boss_key not in (old.get("bossDetails") or {})
            ]
            new_bosses.sort(key=lambda item: item["name"].casefold())
            boss_labels = [boss_public_label(boss) for boss in new_bosses]
            boss_names = french_list(boss_labels)
            message = (
                f"{name} triomphe de {boss_names}."
                if boss_names and len(new_bosses) == boss_delta
                else f"{name} remporte {boss_delta} nouveau{'' if boss_delta == 1 else 'x'} combat{'' if boss_delta == 1 else 's'} de boss."
            )
            if boss_names and len(new_bosses) != boss_delta:
                message += f" Adversaire{'' if len(new_bosses) == 1 else 's'} identifié{'' if len(new_bosses) == 1 else 's'}: {boss_names}."
            title = "Boss vaincu" if boss_delta == 1 else "Boss vaincus"
            details = {
                "headline": title,
                "body": message,
                "bullets": boss_labels or [f"+{boss_delta} {plural(boss_delta, 'combat de boss', 'combats de boss')}"],
                "total": player["bosses"],
                "identified": len(new_bosses),
            }
            if new_bosses:
                details["bosses"] = new_bosses
            add_event(
                connection,
                fingerprint=f"save:{player_occurred_at}:boss:{key}:{player['bosses']}",
                occurred_at=player_occurred_at,
                event_type="boss",
                player=name,
                title=title,
                message=message,
                icon=new_bosses[0].get("icon") if new_bosses else None,
                source="save",
                details=details,
            )

        new_fast_travel = sorted(
            set(player["fastTravel"]) - set(old.get("fastTravel") or []),
            key=str.casefold,
        )
        if new_fast_travel:
            add_event(
                connection,
                fingerprint=f"save:{player_occurred_at}:travel:{key}:{len(player['fastTravel'])}",
                occurred_at=player_occurred_at,
                event_type="discovery",
                player=name,
                title="Nouveau point de voyage",
                message=f"{name} découvre {french_list(new_fast_travel)}.",
                source="save",
            )

        relic_changes = []
        for relic_key, relic in player["relicRanks"].items():
            old_rank = int(((old.get("relicRanks") or {}).get(relic_key) or {}).get("rank") or 0)
            if relic["rank"] > old_rank:
                relic_changes.append(f"{relic['name']} rang {relic['rank']}")
        relic_changes.sort(key=str.casefold)
        if relic_changes:
            add_event(
                connection,
                fingerprint=f"save:{player_occurred_at}:relics:{key}:{sum(item['rank'] for item in player['relicRanks'].values())}",
                occurred_at=player_occurred_at,
                event_type="progress",
                player=name,
                title="Pouvoir renforcé",
                message=f"{name} améliore {french_list(relic_changes)}.",
                source="save",
            )

        if player["campLevel"] > old["campLevel"]:
            add_event(
                connection,
                fingerprint=f"save:{player_occurred_at}:camp:{key}:{player['campLevel']}",
                occurred_at=player_occurred_at,
                event_type="camp",
                player=name,
                title="Camp amélioré",
                message=f"Le camp de {name} atteint le niveau {player['campLevel']}.",
                source="save",
            )
        elif player["bases"] > old["bases"]:
            add_event(
                connection,
                fingerprint=f"save:{player_occurred_at}:bases:{key}:{player['bases']}",
                occurred_at=player_occurred_at,
                event_type="camp",
                player=name,
                title="Nouvelle base",
                message=f"La guilde de {name} compte maintenant {player['bases']} bases.",
                source="save",
            )


def backfill_capture_history(
    connection: sqlite3.Connection,
    snapshot_path: Path,
    history_path: Path,
    stats_path: Path | None = None,
) -> dict:
    schema_version = 1
    if int(metadata_get(connection, "capture_history_schema", 0) or 0) >= schema_version:
        return {"status": "current", "snapshots": 0, "eventsAdded": 0}

    candidates = {}
    for path in sorted(history_path.glob("*/*/*/*.json.gz")) if history_path.exists() else []:
        payload = load_snapshot(path)
        occurred_at = str(payload.get("updatedAt") or "") if payload else ""
        if occurred_at and parse_timestamp(occurred_at) is not None:
            candidates[occurred_at] = payload
    if snapshot_path.is_file():
        payload = load_snapshot(snapshot_path)
        occurred_at = str(payload.get("updatedAt") or "") if payload else ""
        if occurred_at and parse_timestamp(occurred_at) is not None:
            candidates[occurred_at] = payload

    events_before = int(connection.execute("SELECT COUNT(*) FROM events").fetchone()[0])
    previous = None
    snapshots = 0
    sessions = player_session_index(stats_path) if stats_path is not None else {}
    for occurred_at, payload in sorted(
        candidates.items(),
        key=lambda item: parse_timestamp(item[0]) or datetime.min.replace(tzinfo=timezone.utc),
    ):
        current = snapshot_state(payload)
        active_players = session_activity_times_at(connection, sessions, occurred_at)
        if previous is not None:
            for key, player in current["players"].items():
                if active_players is not None and key not in active_players:
                    continue
                old = (previous.get("players") or {}).get(key)
                if old is not None:
                    player_occurred_at = activity_event_time(active_players, key, occurred_at)
                    compare_enriched_progress(
                        connection,
                        old,
                        player,
                        player_occurred_at,
                        key,
                        capture_only=True,
                    )
        previous = current
        snapshots += 1

    metadata_set(connection, "capture_history_schema", schema_version)
    events_after = int(connection.execute("SELECT COUNT(*) FROM events").fetchone()[0])
    return {
        "status": "complete",
        "snapshots": snapshots,
        "eventsAdded": events_after - events_before,
    }


def backfill_raid_history(
    connection: sqlite3.Connection,
    bases_snapshot_path: Path,
    bases_history_path: Path,
    stats_path: Path | None = None,
) -> dict:
    return {
        "status": "skipped",
        "reason": "derived-raid-backfill-disabled",
        "snapshots": 0,
        "processed": [],
        "eventsAdded": 0,
    }


def collect_snapshots(
    connection: sqlite3.Connection,
    snapshot_path: Path,
    history_path: Path,
    bases_path: Path | None = None,
    stats_path: Path | None = None,
) -> dict:
    previous = metadata_get(connection, "save_state")
    previous_last_save_at = str(metadata_get(connection, "last_save_at", ""))
    last_save_at = previous_last_save_at
    last_save_timestamp = parse_timestamp(last_save_at)
    known_players = set(metadata_get(connection, "known_players", []))
    events_before = int(connection.execute("SELECT COUNT(*) FROM events").fetchone()[0])
    sessions = player_session_index(stats_path) if stats_path is not None else {}

    candidates: dict[str, tuple[dict, str, str | None]] = {}
    archive_hours = set()
    archives_scanned = 0
    for path in history_paths_since(history_path, last_save_at):
        archives_scanned += 1
        payload = load_snapshot(path)
        occurred_at = str(payload.get("updatedAt") or "") if payload else ""
        if not occurred_at or parse_timestamp(occurred_at) is None:
            continue
        hour_key = archive_hour_key(path, history_path)
        if hour_key:
            archive_hours.add(hour_key)
        candidates[occurred_at] = (payload, "archive", hour_key)

    current_snapshot_at = ""
    bases_payload = load_snapshot(bases_path) if bases_path and bases_path.is_file() else None
    if snapshot_path.is_file():
        payload = load_snapshot(snapshot_path)
        if payload and payload.get("updatedAt"):
            current_snapshot_at = str(payload["updatedAt"])
            candidates[current_snapshot_at] = (payload, "current", None)

    imported_archive_hours = []
    archives_imported = 0
    current_snapshot_imported = False
    ordered_candidates = sorted(
        candidates.items(),
        key=lambda item: parse_timestamp(item[0]) or datetime.min.replace(tzinfo=timezone.utc),
    )
    for occurred_at, (payload, source, hour_key) in ordered_candidates:
        occurred_timestamp = parse_timestamp(occurred_at)
        if occurred_timestamp is None or (
            last_save_timestamp is not None and occurred_timestamp <= last_save_timestamp
        ):
            continue
        current = snapshot_state(payload, bases_payload if source == "current" else None)
        active_players = session_activity_times_at(connection, sessions, occurred_at)
        if previous is None:
            known_players.update(current["players"].keys())
        else:
            compare_snapshots(connection, previous, current, occurred_at, known_players, active_players)
        previous = current
        last_save_at = occurred_at
        last_save_timestamp = occurred_timestamp
        if source == "archive":
            archives_imported += 1
            if hour_key:
                imported_archive_hours.append(hour_key)
        else:
            current_snapshot_imported = True

    if previous is not None:
        metadata_set(connection, "save_state", previous)
        metadata_set(connection, "last_save_at", last_save_at)
        metadata_set(connection, "known_players", sorted(known_players))
    metadata_set(connection, "history_backfilled", True)

    missing_hours = []
    previous_timestamp = parse_timestamp(previous_last_save_at)
    current_timestamp = parse_timestamp(current_snapshot_at)
    if previous_timestamp and current_timestamp:
        cursor = previous_timestamp.replace(minute=0, second=0, microsecond=0) + timedelta(hours=1)
        current_hour = current_timestamp.replace(minute=0, second=0, microsecond=0)
        while cursor < current_hour:
            hour_key = cursor.strftime("%Y/%m/%d/%H")
            if hour_key not in archive_hours:
                missing_hours.append(cursor.isoformat(timespec="seconds"))
            cursor += timedelta(hours=1)

    events_after = int(connection.execute("SELECT COUNT(*) FROM events").fetchone()[0])
    last_event_row = connection.execute("SELECT MAX(occurred_at) FROM events").fetchone()
    gap_seconds = None
    if previous_timestamp and current_timestamp:
        gap_seconds = max(0, round((current_timestamp - previous_timestamp).total_seconds()))
    last_backfill = metadata_get(connection, "last_archive_recovery")
    if archives_imported or missing_hours:
        last_backfill = {
            "completedAt": now_iso(),
            "fromSaveAt": previous_last_save_at or None,
            "toSaveAt": last_save_at or None,
            "gapSeconds": gap_seconds,
            "archivesImported": archives_imported,
            "importedHours": sorted(set(imported_archive_hours)),
            "missingHours": missing_hours,
            "eventsAdded": events_after - events_before,
        }
        metadata_set(connection, "last_archive_recovery", last_backfill)
    return {
        "version": 1,
        "ok": True,
        "status": "partial" if missing_hours else "complete",
        "checkedAt": now_iso(),
        "previousLastSaveAt": previous_last_save_at or None,
        "lastSaveAt": last_save_at or None,
        "currentSnapshotAt": current_snapshot_at or None,
        "gapSeconds": gap_seconds,
        "currentSnapshotImported": current_snapshot_imported,
        "archives": {
            "scanned": archives_scanned,
            "imported": archives_imported,
            "importedHours": sorted(set(imported_archive_hours)),
            "missingHours": missing_hours,
        },
        "events": {
            "before": events_before,
            "after": events_after,
            "added": events_after - events_before,
            "lastAt": last_event_row[0] if last_event_row else None,
        },
        "lastBackfill": last_backfill,
    }


def read_server_health(stats_path: Path) -> dict:
    try:
        payload = json.loads(stats_path.read_text(encoding="utf-8"))
    except (OSError, ValueError, TypeError):
        payload = {}
    server = payload.get("server") if isinstance(payload.get("server"), dict) else {}
    load_average = None
    if hasattr(os, "getloadavg"):
        try:
            load_average = float(os.getloadavg()[0])
        except OSError:
            load_average = None
    return {
        "fps": float(server.get("lastFps") or server.get("averageFps") or 0),
        "frameMs": float(server.get("lastFrameMs") or 0),
        "load": load_average,
    }


def backfill_allowed(
    stats_path: Path,
    *,
    min_fps: float,
    max_frame_ms: float,
    max_load: float,
) -> tuple[bool, str | None, dict]:
    health = read_server_health(stats_path)
    if health["fps"] and health["fps"] < min_fps:
        return False, f"fps_below_{min_fps:g}", health
    if health["frameMs"] and health["frameMs"] > max_frame_ms:
        return False, f"frame_ms_above_{max_frame_ms:g}", health
    if health["load"] is not None and health["load"] > max_load:
        return False, f"load_above_{max_load:g}", health
    return True, None, health


def archive_datetime(path: Path, history_path: Path) -> datetime | None:
    key = archive_hour_key(path, history_path)
    if not key:
        return None
    try:
        return datetime.strptime(key, "%Y/%m/%d/%H").replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def backfill_archives_checkpoint(
    connection: sqlite3.Connection,
    history_path: Path,
    stats_path: Path,
    *,
    backfill_from: str,
    budget: int,
    min_fps: float,
    max_frame_ms: float,
    max_load: float,
) -> dict:
    allowed, reason, health = backfill_allowed(
        stats_path,
        min_fps=min_fps,
        max_frame_ms=max_frame_ms,
        max_load=max_load,
    )
    if not allowed:
        return {
            "status": "suspended",
            "reason": reason,
            "health": health,
            "snapshots": 0,
            "eventsAdded": 0,
        }

    minimum = parse_timestamp(backfill_from) or parse_timestamp(DEFAULT_BACKFILL_FROM)
    processed = set(metadata_get(connection, "archive_backfill_processed", []))
    previous = metadata_get(connection, "archive_backfill_state")
    candidates = []
    for path in sorted(history_path.glob("*/*/*/*.json.gz")) if history_path.exists() else []:
        hour_key = archive_hour_key(path, history_path)
        if not hour_key or hour_key in processed:
            continue
        archived_at = archive_datetime(path, history_path)
        if minimum and archived_at and archived_at < minimum.astimezone(timezone.utc):
            processed.add(hour_key)
            continue
        candidates.append((hour_key, path))

    events_before = int(connection.execute("SELECT COUNT(*) FROM events").fetchone()[0])
    imported = []
    sessions = player_session_index(stats_path)
    for hour_key, path in candidates[: max(1, budget)]:
        payload = load_snapshot(path)
        occurred_at = str(payload.get("updatedAt") or "") if payload else ""
        if not payload or parse_timestamp(occurred_at) is None:
            processed.add(hour_key)
            continue
        current = snapshot_state(payload)
        if previous is not None:
            compare_snapshots(
                connection,
                previous,
                current,
                occurred_at,
                set(metadata_get(connection, "known_players", [])),
                session_activity_times_at(connection, sessions, occurred_at),
            )
        previous = current
        processed.add(hour_key)
        imported.append(hour_key)

    if previous is not None:
        metadata_set(connection, "archive_backfill_state", previous)
    metadata_set(connection, "archive_backfill_processed", sorted(processed))
    events_after = int(connection.execute("SELECT COUNT(*) FROM events").fetchone()[0])
    return {
        "status": "complete" if not candidates[len(imported):] else "partial",
        "health": health,
        "snapshots": len(imported),
        "importedHours": imported,
        "eventsAdded": events_after - events_before,
        "remaining": max(0, len(candidates) - len(imported)),
    }


ONE_TIME_DEDUPE_TYPES = {"quest", "challenge", "discovery"}


def duplicate_event_identity(row: sqlite3.Row) -> tuple[str, str, str, str] | None:
    if row["type"] not in ONE_TIME_DEDUPE_TYPES:
        return None
    message = re.sub(r"\s+", " ", str(row["message"] or "").strip()).casefold()
    if not message:
        return None
    return (
        str(row["type"] or ""),
        str(row["player"] or "").casefold(),
        str(row["title"] or "").casefold(),
        message,
    )


def duplicate_capture_identity(row: sqlite3.Row) -> tuple[str, str, int] | None:
    if row["type"] != "capture":
        return None
    match = CAPTURE_FINGERPRINT_RE.search(str(row["fingerprint"] or ""))
    if not match:
        return None
    player_key, species_key, total = match.groups()
    return (player_key.casefold(), species_key.casefold(), int(total))


def capture_species_from_message(message: str) -> str | None:
    text = str(message or "").strip()
    for pattern in (
        r"^.+? capture \d+ (.+?)\. Total enregistré: \d+\.$",
        r"^.+? capture (.+?) pour la première fois\.$",
        r"^.+? inscrit (.+?) dans son Paldex avec \d+ captures\.$",
    ):
        match = re.match(pattern, text)
        if match:
            return match.group(1)
    return None


def normalized_capture_event(
    row: sqlite3.Row,
    previous_total: int,
) -> tuple[str, str] | None:
    identity = duplicate_capture_identity(row)
    if identity is None:
        return None
    _player_key, species_key, total = identity
    if total <= previous_total:
        return None
    species = capture_species_from_message(str(row["message"] or "")) or species_key
    player = str(row["player"] or "").strip()
    if not player:
        return None
    if previous_total == 0 and total == 1:
        title = "Première capture"
        message = f"{player} capture {species} pour la première fois."
    elif previous_total == 0:
        title = "Première capture"
        message = f"{player} inscrit {species} dans son Paldex avec {total} captures."
    else:
        added = total - previous_total
        title = "Capture réussie"
        message = f"{player} capture {added} {species}. Total enregistré: {total}."
    if title == row["title"] and message == row["message"]:
        return None
    return title, message


def cleaned_world_drop_build_details(details: dict) -> tuple[dict, int, int, bool]:
    normalized = dict(details)
    structures = public_detail_rows(normalized, "structures")
    kept_structures = []
    removed_total = 0
    for structure in structures:
        if is_world_drop_structure_name(structure.get("name")) or is_world_drop_structure_name(structure.get("asset")):
            removed_total += max(1, int(structure.get("added") or structure.get("count") or 0))
            continue
        kept_structures.append(structure)

    bullets = [str(bullet).strip() for bullet in normalized.get("bullets") or [] if str(bullet).strip()]
    kept_bullets = [bullet for bullet in bullets if not is_world_drop_structure_name(bullet)]
    changed = removed_total > 0 or kept_bullets != bullets

    if structures:
        if kept_structures:
            normalized["structures"] = kept_structures
            normalized["bullets"] = quantity_bullets(kept_structures)
        else:
            normalized.pop("structures", None)
            normalized["bullets"] = kept_bullets
    elif kept_bullets != bullets:
        normalized["bullets"] = kept_bullets

    kept_total = detail_items_quantity_total(normalized, "added") or quantity_total_from_bullets(
        normalized.get("bullets") or []
    )
    return normalized, kept_total, removed_total, changed


def normalize_world_drop_build_events(connection: sqlite3.Connection) -> tuple[int, int, list[int]]:
    rows = connection.execute(
        """
        SELECT id, fingerprint, occurred_at, type, player, guild, base, title,
               message, icon, source, details_json, confidence
        FROM events
        WHERE source = 'save'
          AND type = 'build'
          AND (
            details_json LIKE '%CommonDropItem3D%'
            OR details_json LIKE '%CommonItemDrop3D%'
            OR message LIKE '%CommonDropItem3D%'
            OR message LIKE '%CommonItemDrop3D%'
          )
        ORDER BY occurred_at ASC, id ASC
        """
    ).fetchall()

    updated = 0
    deleted_ids = []
    for row in rows:
        details = details_from_row(row)
        normalized, kept_total, _removed_total, changed = cleaned_world_drop_build_details(details)
        if not changed:
            continue
        if kept_total <= 0:
            deleted_ids.append(int(row["id"]))
            continue

        headline = str(normalized.get("headline") or "").strip()
        if not headline:
            message = str(row["message"] or "")
            headline = message.split(". ", 1)[0].strip() or str(row["title"] or "Base agrandie")
        normalized["headline"] = headline
        normalized["body"] = "De nouvelles structures sont confirmées dans la sauvegarde."
        message = (
            f"{headline}. {kept_total} "
            f"{plural(kept_total, 'nouvelle structure confirmée', 'nouvelles structures confirmées')}."
        )
        connection.execute(
            """
            UPDATE events
            SET message = ?, details_json = ?
            WHERE id = ?
            """,
            (message, details_json_payload(normalized), row["id"]),
        )
        updated += 1

    if deleted_ids:
        placeholders = ",".join("?" for _ in deleted_ids)
        connection.execute(f"DELETE FROM events WHERE id IN ({placeholders})", deleted_ids)

    return updated, len(deleted_ids), deleted_ids[:25]


def normalize_event_history(connection: sqlite3.Connection) -> dict:
    rows = connection.execute(
        """
        SELECT id, fingerprint, occurred_at, type, player, guild, base, title,
               message, icon, source, details_json, confidence
        FROM events
        ORDER BY occurred_at ASC, id ASC
        """
    ).fetchall()

    itemized_updated = 0
    for row in rows:
        details = details_from_row(row)
        normalized = normalized_itemized_event(row, details)
        if normalized is None:
            continue
        title, message, details_json = normalized
        if title == row["title"] and message == row["message"] and details_json == row["details_json"]:
            continue
        connection.execute(
            """
            UPDATE events
            SET title = ?, message = ?, details_json = ?
            WHERE id = ?
            """,
            (title, message, details_json, row["id"]),
        )
        itemized_updated += 1

    world_drop_updated, world_drop_removed, world_drop_removed_ids = normalize_world_drop_build_events(connection)

    rows = connection.execute(
        """
        SELECT id, fingerprint, occurred_at, type, player, title, message
        FROM events
        WHERE type IN ('quest', 'challenge', 'discovery')
        ORDER BY occurred_at ASC, id ASC
        """
    ).fetchall()
    seen = set()
    duplicate_ids = []
    for row in rows:
        identity = duplicate_event_identity(row)
        if identity is None:
            continue
        if identity in seen:
            duplicate_ids.append(int(row["id"]))
        else:
            seen.add(identity)

    if duplicate_ids:
        placeholders = ",".join("?" for _ in duplicate_ids)
        connection.execute(f"DELETE FROM events WHERE id IN ({placeholders})", duplicate_ids)

    rows = connection.execute(
        """
        SELECT id, fingerprint, occurred_at, type, player, title, message
        FROM events
        WHERE type = 'capture'
        ORDER BY occurred_at ASC, id ASC
        """
    ).fetchall()
    seen_captures = set()
    capture_duplicate_ids = []
    for row in rows:
        identity = duplicate_capture_identity(row)
        if identity is None:
            continue
        if identity in seen_captures:
            capture_duplicate_ids.append(int(row["id"]))
        else:
            seen_captures.add(identity)

    if capture_duplicate_ids:
        placeholders = ",".join("?" for _ in capture_duplicate_ids)
        connection.execute(f"DELETE FROM events WHERE id IN ({placeholders})", capture_duplicate_ids)

    rows = connection.execute(
        """
        SELECT id, fingerprint, occurred_at, type, player, title, message
        FROM events
        WHERE type = 'capture'
        ORDER BY occurred_at ASC, id ASC
        """
    ).fetchall()
    previous_capture_totals: dict[tuple[str, str], int] = {}
    capture_messages_updated = 0
    for row in rows:
        identity = duplicate_capture_identity(row)
        if identity is None:
            continue
        player_key, species_key, total = identity
        key = (player_key, species_key)
        previous_total = previous_capture_totals.get(key, 0)
        normalized = normalized_capture_event(row, previous_total)
        if normalized is not None:
            title, message = normalized
            connection.execute(
                "UPDATE events SET title = ?, message = ? WHERE id = ?",
                (title, message, row["id"]),
            )
            capture_messages_updated += 1
        previous_capture_totals[key] = max(previous_total, total)

    return {
        "status": "complete",
        "itemizedUpdated": itemized_updated,
        "duplicatesRemoved": len(duplicate_ids),
        "duplicateIds": duplicate_ids[:25],
        "captureDuplicatesRemoved": len(capture_duplicate_ids),
        "captureDuplicateIds": capture_duplicate_ids[:25],
        "captureMessagesUpdated": capture_messages_updated,
        "worldDropBuildUpdated": world_drop_updated,
        "worldDropBuildRemoved": world_drop_removed,
        "worldDropBuildRemovedIds": world_drop_removed_ids,
    }


def replace_base_label_text(value: str | None, raw_name: str, public_name: str) -> str | None:
    if value is None or raw_name == public_name:
        return value
    return str(value).replace(raw_name, public_name)


def normalize_base_labels(connection: sqlite3.Connection, bases_payload: dict | None) -> dict:
    bases = bases_state(bases_payload)
    label_index = player_base_label_index(bases)
    if not bases or not label_index:
        return {
            "status": "skipped",
            "reason": "no-current-base-labels",
            "updated": 0,
        }

    bases_by_name = {
        str(base.get("name") or "").casefold(): base
        for base in bases.values()
        if str(base.get("name") or "").strip()
    }
    rows = connection.execute(
        """
        SELECT id, type, player, guild, base, title, message, details_json
        FROM events
        WHERE source = 'save'
          AND type IN ('base', 'build', 'production', 'repair', 'research')
          AND base IS NOT NULL
        ORDER BY occurred_at ASC, id ASC
        """
    ).fetchall()

    updated = 0
    for row in rows:
        raw_name = str(row["base"] or "")
        base = bases_by_name.get(raw_name.casefold())
        if not base:
            continue
        public_name = public_base_name(base, row["player"], label_index)
        if public_name == raw_name:
            continue

        details = details_from_row(row)
        for key in ("headline", "body"):
            if key in details:
                details[key] = replace_base_label_text(details.get(key), raw_name, public_name)
        details = base_label_details(details, raw_name, public_name, row["player"])
        connection.execute(
            """
            UPDATE events
            SET base = ?, title = ?, message = ?, details_json = ?
            WHERE id = ?
            """,
            (
                public_name,
                replace_base_label_text(row["title"], raw_name, public_name),
                replace_base_label_text(row["message"], raw_name, public_name),
                details_json_payload(details),
                row["id"],
            ),
        )
        updated += 1

    return {
        "status": "complete",
        "updated": updated,
        "labels": len(label_index),
    }


def purge_inactive_save_events(connection: sqlite3.Connection, stats_path: Path) -> dict:
    sessions = player_session_index(stats_path)
    if not sessions:
        return {
            "status": "skipped",
            "reason": "no-session-index",
            "removed": 0,
            "reassigned": 0,
            "removedIds": [],
            "reassignedIds": [],
        }

    rows = connection.execute(
        """
        SELECT id, occurred_at, type, player
        FROM events
        WHERE source = 'save' AND player IS NOT NULL
        ORDER BY occurred_at ASC, id ASC
        """
    ).fetchall()
    remove_ids = []
    reassignments = []
    for row in rows:
        if row["type"] in SESSION_BOUNDARY_EXEMPT_SAVE_TYPES:
            continue
        player = str(row["player"] or "")
        if player.casefold() not in sessions:
            continue
        event_time = save_activity_time_for_player(
            connection,
            sessions,
            player,
            str(row["occurred_at"] or ""),
        )
        if event_time is None:
            remove_ids.append(int(row["id"]))
        elif event_time != row["occurred_at"]:
            reassignments.append((event_time, int(row["id"])))

    if remove_ids:
        placeholders = ",".join("?" for _ in remove_ids)
        connection.execute(f"DELETE FROM events WHERE id IN ({placeholders})", remove_ids)
    if reassignments:
        connection.executemany(
            "UPDATE events SET occurred_at = ? WHERE id = ?",
            reassignments,
        )

    return {
        "status": "complete",
        "removed": len(remove_ids),
        "reassigned": len(reassignments),
        "removedIds": remove_ids[:25],
        "reassignedIds": [row_id for _, row_id in reassignments[:25]],
    }


def write_recovery_report(output: Path, payload: dict) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".tmp")
    temporary.write_text(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    temporary.replace(output)


def write_json_atomic(output: Path, payload: dict) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    temporary.replace(output)


def export_payload(
    events: list[dict],
    rows,
    reconnects: int,
    *,
    recent: bool = False,
    total_events: int | None = None,
) -> dict:
    counts = Counter(event["type"] for event in events)
    max_id = max((int(row["id"]) for row in rows), default=0)
    return {
        "version": PUBLIC_EVENT_VERSION,
        "ok": True,
        "revision": f"{PUBLIC_EVENT_VERSION}:{len(events)}:{max_id}",
        "updatedAt": now_iso(),
        "recent": recent,
        "truncated": False,
        "summary": {
            "events": len(events),
            "totalEvents": total_events if total_events is not None else len(events),
            "firstAt": events[-1]["occurredAt"] if events else None,
            "lastAt": events[0]["occurredAt"] if events else None,
            "types": dict(sorted(counts.items())),
            "reconciledReconnects": reconnects,
        },
        "events": events,
    }


def write_export(
    connection: sqlite3.Connection,
    output: Path,
    recent_output: Path,
    recent_limit: int = RECENT_EVENT_LIMIT,
) -> None:
    total_events = int(connection.execute("SELECT COUNT(*) FROM events").fetchone()[0])
    rows = connection.execute(
        f"""
        SELECT id, fingerprint, occurred_at, type, player, guild, base, title,
               message, icon, source, details_json, confidence
        FROM events
        ORDER BY {PUBLIC_EVENT_ORDER_SQL}
        """
    ).fetchall()
    events, reconnects = reconcile_public_events(rows)
    write_json_atomic(
        output,
        export_payload(
            events,
            rows,
            reconnects,
            total_events=total_events,
        ),
    )
    write_json_atomic(
        recent_output,
        export_payload(
            events[:recent_limit],
            rows,
            reconnects,
            recent=True,
            total_events=total_events,
        ),
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", type=Path, default=DEFAULT_DATABASE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--recent-output", type=Path, default=DEFAULT_RECENT_OUTPUT)
    parser.add_argument("--recent-limit", type=int, default=RECENT_EVENT_LIMIT)
    parser.add_argument("--snapshot", type=Path, default=DEFAULT_SNAPSHOT)
    parser.add_argument("--bases-snapshot", type=Path, default=DEFAULT_BASES_SNAPSHOT)
    parser.add_argument("--history", type=Path, default=DEFAULT_HISTORY)
    parser.add_argument("--bases-history", type=Path, default=DEFAULT_BASES_HISTORY)
    parser.add_argument("--stats", type=Path, default=DEFAULT_STATS)
    parser.add_argument("--recovery-report", type=Path, default=DEFAULT_RECOVERY_REPORT)
    parser.add_argument("--journal-fixture", type=Path)
    parser.add_argument("--skip-journal", action="store_true")
    parser.add_argument("--backfill-from", default=DEFAULT_BACKFILL_FROM)
    parser.add_argument("--backfill-budget", type=int, default=1)
    parser.add_argument("--min-backfill-fps", type=float, default=50)
    parser.add_argument("--max-backfill-frame-ms", type=float, default=22)
    parser.add_argument("--max-backfill-load", type=float, default=4.5)
    parser.add_argument("--skip-archive-backfill", action="store_true")
    args = parser.parse_args()
    if args.recent_limit < 1:
        parser.error("--recent-limit doit être supérieur à zéro")

    connection = connect_database(args.database)
    try:
        if not args.skip_journal:
            collect_journal(connection, args.journal_fixture)
        collect_player_sessions(connection, args.stats)
        capture_backfill = backfill_capture_history(connection, args.snapshot, args.history, args.stats)
        raid_backfill = backfill_raid_history(
            connection,
            args.bases_snapshot,
            args.bases_history,
            args.stats,
        )
        archive_backfill = (
            {"status": "skipped", "snapshots": 0, "eventsAdded": 0}
            if args.skip_archive_backfill
            else backfill_archives_checkpoint(
                connection,
                args.history,
                args.stats,
                backfill_from=args.backfill_from,
                budget=args.backfill_budget,
                min_fps=args.min_backfill_fps,
                max_frame_ms=args.max_backfill_frame_ms,
                max_load=args.max_backfill_load,
            )
        )
        recovery_report = collect_snapshots(
            connection,
            args.snapshot,
            args.history,
            args.bases_snapshot,
            args.stats,
        )
        recovery_report["captureBackfill"] = capture_backfill
        recovery_report["raidBackfill"] = raid_backfill
        recovery_report["archiveBackfill"] = archive_backfill
        recovery_report["normalizationBackfill"] = normalize_event_history(connection)
        recovery_report["baseLabelBackfill"] = normalize_base_labels(connection, load_snapshot(args.bases_snapshot))
        recovery_report["inactiveSaveEventCleanup"] = purge_inactive_save_events(connection, args.stats)
        write_recovery_report(args.recovery_report, recovery_report)
        write_export(connection, args.output, args.recent_output, args.recent_limit)
        connection.commit()
    finally:
        connection.close()


if __name__ == "__main__":
    main()
