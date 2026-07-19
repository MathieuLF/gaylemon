#!/usr/bin/env python3
"""Collect privacy-safe Palworld events from journald and save snapshots."""

from __future__ import annotations

import argparse
import base64
import binascii
import gzip
import hashlib
import ipaddress
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
DEFAULT_PUBLIC_REPROJECTION_REQUEST = Path(
    "/home/gaylemon/Gaylemon/runtime/events/public-reprojection.request"
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
PUBLIC_IPV4_RE = re.compile(
    r"(?<![A-Za-z0-9.])(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)(?![A-Za-z0-9.])"
)
PUBLIC_IPV6_CANDIDATE_RE = re.compile(
    r"(?<![0-9A-Fa-f:])(?:[0-9A-Fa-f]{0,4}:){2,7}[0-9A-Fa-f]{0,4}(?![0-9A-Fa-f:])"
)
PUBLIC_URL_RE = re.compile(r"https?://\S+", re.IGNORECASE)
PUBLIC_EVENT_VERSION = 6
PUBLIC_PROJECTION_SCHEMA_VERSION = 2
DEFAULT_BACKFILL_FROM = "2026-07-09T00:00:00-04:00"
RECENT_EVENT_LIMIT = 2000
DEFAULT_FULL_EXPORT_INTERVAL_SECONDS = 15 * 60
ITEMIZED_EVENT_GROUP_WINDOW_SECONDS = 5 * 60
PUBLIC_PROJECTION_CONTEXT_SECONDS = max(
    ITEMIZED_EVENT_GROUP_WINDOW_SECONDS,
    SESSION_EVENT_TOLERANCE_SECONDS,
    RECONNECT_WINDOW_SECONDS,
)
CAPTURE_FINGERPRINT_RE = re.compile(r":capture:([^:]+):([^:]+):(\d+)$")
LEVEL_FINGERPRINT_RE = re.compile(r"^save:level:(?P<player>.+):(?P<level>\d+)$")
LEGACY_LEVEL_FINGERPRINT_RE = re.compile(r":level:(?P<player>[^:]+):(?P<level>\d+)$")
RESEARCH_FINGERPRINT_RE = re.compile(r"^save:research:(?P<guild>.+):(?P<total>\d+)$")
LEGACY_RESEARCH_FINGERPRINT_RE = re.compile(
    r"^save:.+:research:(?P<base>.+):(?P<total>\d+)$"
)
PUBLIC_SETTINGS_LABELS = {
    "Difficulty": "Difficulté",
    "DayTimeSpeedRate": "Vitesse du jour",
    "NightTimeSpeedRate": "Vitesse de la nuit",
    "ExpRate": "Gain d'expérience",
    "PalCaptureRate": "Chance de capture des Pals",
    "PalSpawnNumRate": "Présence des Pals sauvages",
    "PalDamageRateAttack": "Dégâts infligés par les Pals",
    "PalDamageRateDefense": "Dégâts reçus par les Pals",
    "PlayerDamageRateAttack": "Dégâts infligés par les joueurs",
    "PlayerDamageRateDefense": "Dégâts reçus par les joueurs",
    "CollectionDropRate": "Quantité de ressources récoltées",
    "CollectionObjectHpRate": "Résistance des ressources",
    "CollectionObjectRespawnSpeedRate": "Vitesse de réapparition des ressources",
    "EnemyDropItemRate": "Butin laissé par les ennemis",
    "DeathPenalty": "Pénalité à la mort",
    "BaseCampMaxNum": "Nombre maximal de bases",
    "BaseCampWorkerMaxNum": "Travailleurs par base",
    "GuildPlayerMaxNum": "Joueurs par guilde",
    "PalEggDefaultHatchingTime": "Durée d'incubation des œufs",
    "WorkSpeedRate": "Vitesse de travail",
    "AutoSaveSpan": "Fréquence des sauvegardes automatiques",
    "bIsPvP": "Mode joueur contre joueur",
    "bEnablePlayerToPlayerDamage": "Dégâts entre joueurs",
    "bEnableFriendlyFire": "Tirs alliés",
    "bEnableInvaderEnemy": "Invasions ennemies",
    "bEnableFastTravel": "Voyage rapide",
    "bUseBackupSaveData": "Sauvegardes de secours",
    "CrossplayPlatforms": "Plateformes de jeu croisé",
}
PUBLIC_SETTINGS_FIELDS = set(PUBLIC_SETTINGS_LABELS)
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
    julianday(occurred_at) DESC,
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
        CREATE TABLE IF NOT EXISTS event_suppressions (
            event_id INTEGER PRIMARY KEY,
            reason TEXT NOT NULL,
            suppressed_at TEXT NOT NULL,
            FOREIGN KEY(event_id) REFERENCES events(id)
        );
        CREATE INDEX IF NOT EXISTS events_occurred_julian_idx
            ON events(julianday(occurred_at), id);
        CREATE TABLE IF NOT EXISTS event_projection_changes (
            seq INTEGER PRIMARY KEY AUTOINCREMENT,
            event_id INTEGER NOT NULL,
            change_kind TEXT NOT NULL,
            occurred_at TEXT,
            changed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        CREATE INDEX IF NOT EXISTS event_projection_changes_event_idx
            ON event_projection_changes(event_id, seq);
        CREATE TABLE IF NOT EXISTS public_event_projection (
            echo_key TEXT PRIMARY KEY,
            event_id INTEGER NOT NULL,
            occurred_at TEXT NOT NULL,
            order_rank INTEGER NOT NULL,
            payload_json TEXT NOT NULL,
            represented_events INTEGER NOT NULL DEFAULT 1,
            reconciled_reconnect INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS public_event_projection_order_idx
            ON public_event_projection(julianday(occurred_at) DESC, order_rank, event_id DESC);
        CREATE TABLE IF NOT EXISTS public_event_projection_members (
            event_id INTEGER PRIMARY KEY,
            echo_key TEXT NOT NULL,
            FOREIGN KEY(echo_key) REFERENCES public_event_projection(echo_key)
                ON DELETE CASCADE
        );
        CREATE TRIGGER IF NOT EXISTS events_projection_insert
        AFTER INSERT ON events
        BEGIN
            INSERT INTO metadata(key, value) VALUES('events_projection_revision', '1')
            ON CONFLICT(key) DO UPDATE SET value = CAST(CAST(value AS INTEGER) + 1 AS TEXT);
        END;
        CREATE TRIGGER IF NOT EXISTS events_projection_update
        AFTER UPDATE ON events
        BEGIN
            INSERT INTO metadata(key, value) VALUES('events_projection_revision', '1')
            ON CONFLICT(key) DO UPDATE SET value = CAST(CAST(value AS INTEGER) + 1 AS TEXT);
        END;
        CREATE TRIGGER IF NOT EXISTS events_projection_delete
        AFTER DELETE ON events
        BEGIN
            INSERT INTO metadata(key, value) VALUES('events_projection_revision', '1')
            ON CONFLICT(key) DO UPDATE SET value = CAST(CAST(value AS INTEGER) + 1 AS TEXT);
        END;
        CREATE TRIGGER IF NOT EXISTS event_suppressions_projection_insert
        AFTER INSERT ON event_suppressions
        BEGIN
            INSERT INTO metadata(key, value) VALUES('events_projection_revision', '1')
            ON CONFLICT(key) DO UPDATE SET value = CAST(CAST(value AS INTEGER) + 1 AS TEXT);
        END;
        CREATE TRIGGER IF NOT EXISTS event_suppressions_projection_delete
        AFTER DELETE ON event_suppressions
        BEGIN
            INSERT INTO metadata(key, value) VALUES('events_projection_revision', '1')
            ON CONFLICT(key) DO UPDATE SET value = CAST(CAST(value AS INTEGER) + 1 AS TEXT);
        END;
        CREATE TRIGGER IF NOT EXISTS events_projection_change_insert
        AFTER INSERT ON events
        BEGIN
            INSERT INTO event_projection_changes(event_id, change_kind, occurred_at)
            VALUES(NEW.id, 'insert', NEW.occurred_at);
        END;
        CREATE TRIGGER IF NOT EXISTS events_projection_change_update
        AFTER UPDATE ON events
        BEGIN
            INSERT INTO event_projection_changes(event_id, change_kind, occurred_at)
            VALUES(NEW.id, 'update', NEW.occurred_at);
        END;
        CREATE TRIGGER IF NOT EXISTS events_projection_change_delete
        AFTER DELETE ON events
        BEGIN
            INSERT INTO event_projection_changes(event_id, change_kind, occurred_at)
            VALUES(OLD.id, 'delete', OLD.occurred_at);
        END;
        CREATE TRIGGER IF NOT EXISTS event_suppressions_projection_change_insert
        AFTER INSERT ON event_suppressions
        BEGIN
            INSERT INTO event_projection_changes(event_id, change_kind, occurred_at)
            SELECT NEW.event_id, 'suppress', occurred_at FROM events WHERE id = NEW.event_id;
        END;
        CREATE TRIGGER IF NOT EXISTS event_suppressions_projection_change_delete
        AFTER DELETE ON event_suppressions
        BEGIN
            INSERT INTO event_projection_changes(event_id, change_kind, occurred_at)
            SELECT OLD.event_id, 'unsuppress', occurred_at FROM events WHERE id = OLD.event_id;
        END;
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


def suppress_events(
    connection: sqlite3.Connection,
    event_ids: list[int],
    reason: str,
) -> int:
    before = int(connection.execute("SELECT COUNT(*) FROM event_suppressions").fetchone()[0])
    suppressed_at = now_iso()
    connection.executemany(
        """
        INSERT OR IGNORE INTO event_suppressions(event_id, reason, suppressed_at)
        VALUES(?, ?, ?)
        """,
        [(int(event_id), reason, suppressed_at) for event_id in event_ids],
    )
    after = int(connection.execute("SELECT COUNT(*) FROM event_suppressions").fetchone()[0])
    return after - before


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


def decode_json_log_message(message: str) -> tuple[str, str | None]:
    text = str(message or "").strip()
    if not text.startswith("{"):
        return text, None
    try:
        payload = json.loads(text)
    except (json.JSONDecodeError, TypeError):
        return text, None
    if not isinstance(payload, dict):
        return text, None
    decoded = next(
        (
            str(payload[key]).strip()
            for key in ("message", "Message", "msg", "text", "Text", "log")
            if payload.get(key) not in (None, "")
        ),
        text,
    )
    timestamp = next(
        (
            payload[key]
            for key in ("timestamp", "Timestamp", "time", "Time", "ts")
            if payload.get(key) not in (None, "")
        ),
        None,
    )
    occurred_at = None
    if timestamp is not None:
        if isinstance(timestamp, (int, float)):
            seconds = float(timestamp)
            if seconds > 10_000_000_000:
                seconds /= 1000
            try:
                occurred_at = datetime.fromtimestamp(seconds, timezone.utc).astimezone().isoformat()
            except (ValueError, OSError, OverflowError):
                occurred_at = None
        elif parse_timestamp(str(timestamp)) is not None:
            occurred_at = str(timestamp)
    return decoded, occurred_at


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
        message, json_occurred_at = decode_json_log_message(str(entry.get("MESSAGE") or ""))
        entry_cursor = str(entry.get("__CURSOR") or "")
        occurred_at = json_occurred_at or journal_timestamp(entry)
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


def read_stats_payload(stats_path: Path) -> dict:
    try:
        payload = json.loads(stats_path.read_text(encoding="utf-8"))
    except (OSError, ValueError, TypeError):
        return {}
    return payload if isinstance(payload, dict) else {}


def setting_value_text(value) -> str:
    if value is None:
        return "non défini"
    if isinstance(value, bool):
        return "activé" if value else "désactivé"
    if isinstance(value, (list, tuple)):
        return ", ".join(str(item) for item in value)[:160]
    return str(value)[:160]


def collect_settings_changes(connection: sqlite3.Connection, stats_path: Path) -> int:
    payload = read_stats_payload(stats_path)
    settings = payload.get("settings") if isinstance(payload.get("settings"), dict) else {}
    added_before = int(connection.execute("SELECT COUNT(*) FROM events").fetchone()[0])
    for change in settings.get("changes") or []:
        if not isinstance(change, dict):
            continue
        fields = change.get("fields") if isinstance(change.get("fields"), dict) else {}
        public_fields = {
            key: {
                "before": public_details(value.get("before")),
                "after": public_details(value.get("after")),
            }
            for key, value in fields.items()
            if key in PUBLIC_SETTINGS_FIELDS and isinstance(value, dict)
        }
        if not public_fields:
            continue
        digest = str(change.get("digest") or "").strip().casefold()
        if not digest:
            digest = hashlib.sha256(
                json.dumps(public_fields, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
            ).hexdigest()
        occurred_at = str(change.get("observedAt") or settings.get("updatedAt") or now_iso())
        if parse_timestamp(occurred_at) is None:
            occurred_at = now_iso()
        labels = sorted(
            (PUBLIC_SETTINGS_LABELS[key] for key in public_fields),
            key=str.casefold,
        )
        bullets = [
            f"{PUBLIC_SETTINGS_LABELS[key]}: "
            f"{setting_value_text(values.get('before'))} → "
            f"{setting_value_text(values.get('after'))}"
            for key, values in sorted(
                public_fields.items(),
                key=lambda item: PUBLIC_SETTINGS_LABELS[item[0]].casefold(),
            )
        ]
        message = f"Les règles de Palpagos ont été ajustées: {french_list(labels)}."
        add_event(
            connection,
            fingerprint=f"settings:{digest}",
            occurred_at=occurred_at,
            event_type="settings",
            title="Règles du monde ajustées",
            message=message,
            source="server",
            confidence="confirmed",
            details={
                "headline": "Règles du monde ajustées",
                "body": message,
                "bullets": bullets,
                "fields": public_fields,
            },
        )
    added_after = int(connection.execute("SELECT COUNT(*) FROM events").fetchone()[0])
    return added_after - added_before


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


def private_public_detail_key(value: str) -> bool:
    normalized = re.sub(r"(?<!^)(?=[A-Z])", "_", str(value or ""))
    normalized = re.sub(r"[^a-z0-9]+", "_", normalized.casefold()).strip("_")
    tokens = set(normalized.split("_"))
    if tokens.intersection({
        "ip", "ipaddress", "address", "host", "hostname", "port",
        "endpoint", "url", "uri",
    }):
        return True
    if tokens.intersection({"map", "world"}) and tokens.intersection({"x", "y", "z"}):
        return True
    return bool(re.search(
        r"uid|guid|instance|container|account|steam|password|token|dynamic_id|"
        r"position|coordinates?|map[xyz]|world[xyz]",
        normalized,
        re.I,
    ))


def public_details(value):
    if isinstance(value, dict):
        result = {}
        for key, item in value.items():
            public_key = str(key)
            if private_public_detail_key(public_key):
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
    if isinstance(value, str):
        return public_text(value)
    if isinstance(value, (int, float, bool)) or value is None:
        return value
    return str(value)


def public_text(value) -> str:
    text = str(value or "")
    text = PUBLIC_IPV4_RE.sub("[adresse masquée]", text)
    text = PUBLIC_IPV6_CANDIDATE_RE.sub(mask_public_ipv6, text)
    return PUBLIC_URL_RE.sub("[lien masqué]", text)


def mask_public_ipv6(match: re.Match) -> str:
    candidate = match.group(0)
    try:
        address = ipaddress.ip_address(candidate)
    except ValueError:
        return candidate
    return "[adresse masquée]" if address.version == 6 else candidate


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
    headline = public_text(details.get("headline") or row["title"])
    body = public_text(details.get("body") or row["message"])
    return {
        "headline": headline[:160],
        "body": body[:1000],
        "bullets": bullets[:8],
    }


def research_total_from_fingerprint(fingerprint: str | None) -> int | None:
    text = str(fingerprint or "").strip()
    canonical = RESEARCH_FINGERPRINT_RE.match(text)
    if canonical:
        return int(canonical.group("total"))
    legacy = re.search(r"(?:^|:)research:(?:.*:)?(?P<total>\d+)$", text)
    return int(legacy.group("total")) if legacy else None


def normalize_public_research_event(
    event: dict,
    fingerprint: str,
    business_identity: tuple[str, int] | None = None,
) -> dict:
    guild = str(event.get("guild") or "").strip()
    guild_subject = "La guilde" if not guild or guild.casefold() == "guilde" else f"La guilde {guild}"
    total = research_total_from_fingerprint(fingerprint)
    title = "Recherche de guilde terminée"
    if total is None:
        message = f"{guild_subject} avance dans ses recherches."
        bullets = []
    else:
        label = "recherche terminée" if total == 1 else "recherches terminées"
        message = f"{guild_subject} compte désormais {total} {label}."
        bullets = [f"Total de la guilde: {total} {label}"]
    body = "Le laboratoire progresse pour l'ensemble de la guilde."
    details = {
        "headline": title,
        "body": body,
        "bullets": bullets,
    }
    if total is not None:
        details["total"] = total
    if event.get("player"):
        details["attribution"] = "rattachée à la guilde"

    normalized = dict(event)
    normalized.update({
        "base": None,
        "title": title,
        "message": message,
        "display": {
            "headline": title,
            "body": body,
            "bullets": bullets,
        },
        "details": details,
        "confidence": "derived" if event.get("player") else event.get("confidence", "confirmed"),
    })
    if business_identity is not None and total is not None:
        stable_guild_key, identity_total = business_identity
        if identity_total == total:
            normalized["key"] = public_event_key(
                f"public:research:{stable_guild_key.casefold()}:{total}"
            )
    return normalized


def public_event(
    row: sqlite3.Row,
    research_guild_keys_by_base: dict[str, set[str]] | None = None,
) -> dict:
    details = details_from_row(row)
    fingerprint = row["fingerprint"] if "fingerprint" in row.keys() else f"{row['source']}:{row['id']}"
    event = {
        "key": public_event_key(fingerprint),
        "id": int(row["id"]),
        "occurredAt": row["occurred_at"],
        "type": row["type"],
        "player": public_text(row["player"]) if row["player"] is not None else None,
        "guild": (
            public_text(row["guild"])
            if "guild" in row.keys() and row["guild"] is not None
            else None
        ),
        "base": (
            public_text(row["base"])
            if "base" in row.keys() and row["base"] is not None
            else None
        ),
        "title": public_text(row["title"]),
        "message": public_text(row["message"]),
        "display": event_display(row, details),
        "details": details,
        "confidence": row["confidence"] if "confidence" in row.keys() else "confirmed",
        "icon": public_text(row["icon"]) if row["icon"] is not None else None,
        "source": row["source"],
    }
    if event["type"] == "research":
        return normalize_public_research_event(
            event,
            fingerprint,
            research_business_identity(row, research_guild_keys_by_base),
        )
    return event


ITEMIZED_PUBLIC_GROUP_TYPES = {"craft", "fishing", "production", "build", "repair", "base"}
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
        title = "Fabrications terminées"
        total = max(int((event.get("details") or {}).get("total") or 0) for event in events)
        message = (
            f"{owner} termine {added_total} {plural(added_total, 'fabrication')}. "
            f"Total cumulé: {total}."
        ) if total > 0 else f"{owner} termine {added_total} {plural(added_total, 'fabrication')}."
        body = message
        if total > 0:
            details["total"] = total
    elif event_type == "fishing":
        title = "Pêche ramenée"
        total = max(int((event.get("details") or {}).get("total") or 0) for event in events)
        message = (
            f"{owner} ramène {added_total} "
            f"{plural(added_total, 'prise de pêche', 'prises de pêche')}. "
            f"Total cumulé: {total}."
        ) if total > 0 else (
            f"{owner} ramène {added_total} "
            f"{plural(added_total, 'prise de pêche', 'prises de pêche')}."
        )
        body = message
        if total > 0:
            details["total"] = total
    elif event_type == "production":
        title = "Ressources produites relevées"
        base_label = ""
        if len(bases) == 1:
            base_label = f" à {bases[0]}"
            total = max(int((event.get("details") or {}).get("total") or 0) for event in events)
            stock = f" Stock observé: {total}." if total > 0 else ""
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
            stock = f" Stock observé: {total}." if total > 0 else ""
            if total > 0:
                details["total"] = total
        message = (
            f"{owner} relève {added_total} "
            f"{plural(added_total, 'ressource produite', 'ressources produites')}"
            f"{base_label}.{stock}"
        )
        body = message
    elif event_type == "build":
        title = "Base agrandie"
        total = total_observed_by_base()
        if total > 0:
            details["total"] = total
        message = (
            f"{owner} ajoute {added_total} "
            f"{plural(added_total, 'structure', 'structures')}"
            f"{base_scope_label()}{f'. Total suivi: {total}.' if total > 0 else '.'}"
        )
        body = message
    elif event_type == "repair":
        title = "Réparations terminées"
        message = (
            f"{owner} remet {added_total} {plural(added_total, 'structure')} "
            f"en état{base_scope_label()}."
        )
        body = message
    elif event_type == "research":
        title = "Recherches avancées"
        message = (
            f"{owner} avance {added_total} {plural(added_total, 'recherche')}"
            f"{base_scope_label()}."
        )
        body = message
    else:
        title = "État de base relevé"
        message = (
            f"{owner} relève {added_total} "
            f"{plural(added_total, 'structure endommagée', 'structures endommagées')}"
            f"{base_scope_label()}."
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
        "confidence": "derived" if any(event.get("confidence") == "derived" for event in events) else "confirmed",
        "icon": icon,
        "source": "save",
    }


def group_itemized_public_projection(events: list[dict]) -> tuple[list[dict], dict[str, list[int]]]:
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
    members: dict[str, list[int]] = {}
    for event in events:
        key = event_keys.get(int(event["id"]))
        if key is None or len(groups.get(key, [])) < 2:
            grouped.append(event)
            members[event["key"]] = [int(event["id"])]
            continue
        if key in emitted:
            continue
        aggregate = aggregate_itemized_public_event(groups[key])
        grouped.append(aggregate)
        members[aggregate["key"]] = sorted(int(item["id"]) for item in groups[key])
        emitted.add(key)
    return grouped, members


def group_itemized_public_events(events: list[dict]) -> list[dict]:
    return group_itemized_public_projection(events)[0]


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


def reconcile_public_events(
    rows,
    window_seconds: int = RECONNECT_WINDOW_SECONDS,
    *,
    initial_player_states: dict[str, bool] | None = None,
    include_members: bool = False,
    research_guild_keys_by_base: dict[str, set[str]] | None = None,
):
    events = [
        public_event(row, research_guild_keys_by_base)
        for row in rows
    ]
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
    player_states: dict[str, bool] = dict(initial_player_states or {})
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
    grouped, members = group_itemized_public_projection(reconciled)
    if include_members:
        return grouped, len(reconnect_ids), members
    return grouped, len(reconnect_ids)


def archive_hour_key(path: Path, history_path: Path) -> str | None:
    try:
        year, month, day, filename = path.relative_to(history_path).parts[-4:]
        stem = filename.split(".", 1)[0]
        if not re.match(r"^\d{2}(?:$|\d{4}-\d{6}$)", stem):
            return None
        hour = stem[:2]
        datetime(int(year), int(month), int(day), int(hour))
    except (ValueError, TypeError, IndexError):
        return None
    return f"{year}/{month}/{day}/{hour}"


def history_paths_since(history_path: Path, last_save_at: str) -> list[Path]:
    paths = []
    if history_path.exists():
        paths = sorted({
            *history_path.glob("*/*/*/*.json.gz"),
            *(history_path / "_rolling").glob("*/*/*/*.json.gz"),
        })
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
        "key": str(player.get("key") or "").strip() or str(player.get("name") or "Aventurier").casefold(),
        "activityKey": str(player.get("name") or "Aventurier").casefold(),
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
    structure_states = {}
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
    for item in structures.get("states") or []:
        if not isinstance(item, dict):
            continue
        structure_key = str(item.get("key") or "").strip()
        name = str(item.get("name") or "Structure")
        if not structure_key or is_world_drop_structure_name(name):
            continue
        structure_states[structure_key] = {
            "name": name,
            "damaged": bool(item.get("damaged")),
            "healthPercent": item.get("healthPercent"),
        }
    return {
        "name": str(row.get("name") or "Base"),
        "guild": str(row.get("guild") or ""),
        "guildKey": str(row.get("guildKey") or row.get("guild") or "").strip().casefold(),
        "players": sorted(players, key=str.casefold),
        "structuresTotal": max(0, int(structures.get("total") or 0) - world_drop_structures),
        "structuresDamaged": int(structures.get("damaged") or 0),
        "structuresUnfinished": int(structures.get("unfinished") or 0),
        "structureHighlights": structure_highlights,
        "structureStates": structure_states,
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


def guild_research_state(payload: dict | None) -> dict:
    if not isinstance(payload, dict):
        return {}
    guilds = {}
    rows = payload.get("guildResearch")
    if not isinstance(rows, list):
        rows = []
        for base in payload.get("bases") or []:
            if not isinstance(base, dict):
                continue
            research = base.get("research") if isinstance(base.get("research"), dict) else {}
            if not research:
                continue
            rows.append({
                "key": base.get("guildKey"),
                "guild": base.get("guild"),
                "players": base.get("players"),
                "current": research.get("current"),
                "completed": research.get("completed"),
            })

    for row in rows:
        if not isinstance(row, dict):
            continue
        guild = str(row.get("guild") or "Guilde").strip() or "Guilde"
        key = str(row.get("key") or guild).strip().casefold()
        current = str(row.get("current") or "")
        completed = int(row.get("completed") or 0)
        players = sorted(
            {str(player) for player in row.get("players") or [] if str(player).strip()},
            key=str.casefold,
        )
        existing = guilds.get(key)
        if existing is None:
            guilds[key] = {
                "key": key,
                "guild": guild,
                "players": players,
                "current": current,
                "completed": completed,
            }
            continue
        existing["players"] = sorted(set(existing["players"]) | set(players), key=str.casefold)
        if completed >= int(existing.get("completed") or 0):
            existing["completed"] = completed
            existing["current"] = current or existing.get("current", "")
    return guilds


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
        players[state["key"]] = state
    bases_source = bases_payload or payload
    return {
        "players": players,
        "bases": bases_state(bases_source),
        "guildResearch": guild_research_state(bases_source),
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


def confirmed_monotone_record_deltas(
    connection: sqlite3.Connection,
    *,
    player_key: str,
    records: dict,
    old_records: dict,
    occurred_at: str,
    record_keys: tuple[str, ...],
) -> dict[str, dict]:
    """Confirm monotone counters on two distinct snapshots before publication."""
    state = metadata_get(
        connection,
        "confirmed_world_progress_v1",
        {"players": {}},
    )
    if not isinstance(state, dict):
        state = {"players": {}}
    players = state.setdefault("players", {})
    player_state = players.setdefault(player_key, {"confirmed": {}, "pending": {}})
    confirmed = player_state.setdefault("confirmed", {})
    pending = player_state.setdefault("pending", {})
    result = {}

    for record_key in record_keys:
        previous_total = int(old_records.get(record_key) or 0)
        current_total = int(records.get(record_key) or 0)
        confirmed_total = int(confirmed.setdefault(record_key, previous_total) or 0)
        candidate = pending.get(record_key)

        if current_total <= confirmed_total:
            pending.pop(record_key, None)
            continue
        if not isinstance(candidate, dict):
            pending[record_key] = {
                "total": current_total,
                "observations": 1,
                "firstObservedAt": occurred_at,
                "lastObservedAt": occurred_at,
            }
            continue

        candidate_total = int(candidate.get("total") or 0)
        if current_total < candidate_total:
            pending[record_key] = {
                "total": current_total,
                "observations": 1,
                "firstObservedAt": occurred_at,
                "lastObservedAt": occurred_at,
            }
            continue

        if str(candidate.get("lastObservedAt") or "") != occurred_at:
            candidate["observations"] = int(candidate.get("observations") or 1) + 1
            candidate["lastObservedAt"] = occurred_at
        if int(candidate.get("observations") or 0) < 2:
            continue

        confirmed_to = min(current_total, candidate_total)
        if confirmed_to > confirmed_total:
            result[record_key] = {
                "delta": confirmed_to - confirmed_total,
                "total": confirmed_to,
                "firstObservedAt": candidate.get("firstObservedAt"),
                "confirmedAt": occurred_at,
            }
            confirmed[record_key] = confirmed_to
        if current_total > confirmed_to:
            pending[record_key] = {
                "total": current_total,
                "observations": 1,
                "firstObservedAt": occurred_at,
                "lastObservedAt": occurred_at,
            }
        else:
            pending.pop(record_key, None)

    metadata_set(connection, "confirmed_world_progress_v1", state)
    return result


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
    if base:
        return f"Stock de production observé à {base}"
    if player:
        return f"Stock de production observé pour {player}"
    return fallback or "Stock de production observé"


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
    headline = production_event_headline(row["player"], row["base"], "Stock de production observé")
    observed = (
        "1 ressource supplémentaire est observée"
        if added == 1
        else f"{added} ressources supplémentaires sont observées"
    )
    body = f"{observed}. Stock actuel: {total}." if total > 0 else f"{observed}."
    message = f"{headline}. {body}"
    if total > 0:
        normalized["total"] = total
    normalized.update({"headline": headline, "body": body})
    return "Stock de production observé", message, details_json_payload(normalized)


def compare_enriched_progress(
    connection: sqlite3.Connection,
    old: dict,
    player: dict,
    occurred_at: str,
    key: str,
    capture_only: bool = False,
    observation_at: str | None = None,
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
    confirmed_expeditions = confirmed_monotone_record_deltas(
        connection,
        player_key=key,
        records=records,
        old_records=old_records,
        occurred_at=observation_at or occurred_at,
        record_keys=tuple(record_key for record_key, _, _ in expedition_labels),
    )
    completed = []
    for record_key, label, plural_label in expedition_labels:
        confirmation = confirmed_expeditions.get(record_key)
        if confirmation:
            delta = int(confirmation["delta"])
            completed.append(f"{delta} {plural(delta, label, plural_label)}")
    if completed:
        confirmed_totals = {
            record_key: int(confirmation["total"])
            for record_key, confirmation in confirmed_expeditions.items()
        }
        add_event(
            connection,
            fingerprint=(
                f"save:expeditions:{key}:"
                f"{hashlib.sha256(json.dumps(confirmed_totals, sort_keys=True).encode('utf-8')).hexdigest()[:20]}"
            ),
            occurred_at=occurred_at,
            event_type="adventure",
            player=name,
            title="Expédition accomplie",
            message=f"{name} termine {french_list(completed)}.",
            source="save",
            details={
                "headline": "Expédition accomplie",
                "body": "La progression reste présente dans deux sauvegardes successives.",
                "bullets": completed,
                "confirmedTotals": confirmed_totals,
                "confirmationSnapshots": 2,
            },
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
        title="Mutation relevée",
        title_plural="Mutations relevées",
        singular="mutation",
        verb="relève",
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
    return {
        "headline": str(row.get("label") or "Sac de récupération"),
        "body": "Signal relevé dans la sauvegarde du monde.",
        "dropType": str(row.get("type") or "death-drop"),
        "status": status,
    }


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


def base_attribution_confidence(player: str | None) -> str:
    return "derived" if player else "confirmed"


def eligible_structure_transition_keys(
    connection: sqlite3.Connection,
    structure_keys: list[str],
    event_type: str,
) -> list[str]:
    pending = set(structure_keys)
    if not pending:
        return []
    latest_by_structure = {}
    rows = connection.execute(
        """
        SELECT type, details_json
        FROM events
        WHERE source = 'save' AND type IN ('base', 'repair')
        ORDER BY occurred_at DESC, id DESC
        """
    ).fetchall()
    for row in rows:
        details = details_from_row(row)
        for structure_key in details.get("structureKeys") or []:
            structure_key = str(structure_key or "")
            if structure_key in pending and structure_key not in latest_by_structure:
                latest_by_structure[structure_key] = row["type"]
        if len(latest_by_structure) == len(pending):
            break
    return sorted(
        (key for key in pending if latest_by_structure.get(key) != event_type),
        key=str.casefold,
    )


def compare_guild_research_events(
    connection: sqlite3.Connection,
    previous: dict,
    current: dict,
    occurred_at: str,
    active_players: set[str] | dict[str, str] | None = None,
) -> None:
    old_guilds = previous.get("guildResearch") or {}
    new_guilds = current.get("guildResearch") or {}
    if not old_guilds:
        old_guilds = guild_research_from_base_states(previous.get("bases") or {})
    if not new_guilds:
        new_guilds = guild_research_from_base_states(current.get("bases") or {})
    active_player_keys = activity_player_keys(active_players)
    for key, guild_state in new_guilds.items():
        old = old_guilds.get(key)
        if old is None:
            same_name = [
                candidate
                for candidate in old_guilds.values()
                if str(candidate.get("guild") or "").casefold()
                == str(guild_state.get("guild") or "").casefold()
            ]
            old = same_name[0] if len(same_name) == 1 else None
        if old is None:
            continue
        completed = int(guild_state.get("completed") or 0)
        previous_completed = int(old.get("completed") or 0)
        delta = completed - previous_completed
        if delta <= 0:
            continue

        active_members = []
        if active_player_keys is not None:
            active_members = [
                str(player)
                for player in guild_state.get("players") or []
                if str(player).casefold() in active_player_keys
            ]
        player = active_members[0] if len(active_members) == 1 else None
        event_occurred_at = activity_event_time(
            active_players,
            str(player or "").casefold(),
            occurred_at,
        ) if player else occurred_at
        guild = str(guild_state.get("guild") or "Guilde")
        message = (
            f"La recherche de la guilde {guild} progresse: {delta} "
            f"{plural(delta, 'recherche terminée', 'recherches terminées')}."
        )
        details = {
            "headline": "Recherche de guilde terminée",
            "body": "Le laboratoire progresse au niveau de la guilde.",
            "bullets": [f"+{delta} {plural(delta, 'recherche') }"],
            "total": completed,
        }
        if player:
            details["attribution"] = "membre actif observé"
        add_event(
            connection,
            fingerprint=f"save:research:{key}:{completed}",
            occurred_at=event_occurred_at,
            event_type="research",
            player=player,
            guild=guild,
            title="Recherche de guilde terminée",
            message=message,
            source="save",
            confidence=base_attribution_confidence(player),
            details=details,
        )


def guild_research_from_base_states(bases: dict) -> dict:
    guilds = {}
    for base in bases.values():
        guild = str(base.get("guild") or "Guilde")
        key = str(base.get("guildKey") or guild).casefold()
        completed = int(base.get("researchCompleted") or 0)
        existing = guilds.setdefault(key, {
            "key": key,
            "guild": guild,
            "players": [],
            "current": str(base.get("researchCurrent") or ""),
            "completed": completed,
        })
        existing["players"] = sorted(
            set(existing["players"]) | {str(player) for player in base.get("players") or []},
            key=str.casefold,
        )
        if completed >= int(existing.get("completed") or 0):
            existing["completed"] = completed
            existing["current"] = str(base.get("researchCurrent") or existing.get("current") or "")
    return guilds


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
                fingerprint=f"save:base:new:{key}",
                occurred_at=event_occurred_at,
                event_type="base",
                player=player,
                guild=guild,
                base=display_name,
                title="Nouvelle base",
                message=f"{display_name} apparaît dans les chroniques de la guilde {guild or 'inconnue'}.",
                source="save",
                confidence=base_attribution_confidence(player),
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
                f"{total_delta} {plural(total_delta, 'nouvelle structure ajoutée', 'nouvelles structures ajoutées')}."
            )
            add_event(
                connection,
                fingerprint=f"save:build:{key}:{base.get('structuresTotal')}",
                occurred_at=event_occurred_at,
                event_type="build",
                player=player,
                guild=guild,
                base=display_name,
                title="Base agrandie",
                message=message,
                source="save",
                confidence=base_attribution_confidence(player),
                details=base_label_details({
                    "headline": headline,
                    "body": f"{total_delta} {plural(total_delta, 'structure ajoutée', 'structures ajoutées')}.",
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
            headline = f"Stock de production observé à {display_name}"
            observed = (
                "1 ressource supplémentaire est observée"
                if produced == 1
                else f"{produced} ressources supplémentaires sont observées"
            )
            body = f"{observed}. Stock actuel: {production_total}."
            message = f"{headline}. {body}"
            production_state = [
                {
                    "key": str(item.get("asset") or item.get("name") or "").casefold(),
                    "count": int(item.get("count") or 0),
                }
                for item in sorted(
                    base.get("productionItems", {}).values(),
                    key=lambda item: str(item.get("asset") or item.get("name") or "").casefold(),
                )
            ]
            production_state_hash = hashlib.sha256(
                json.dumps(production_state, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            ).hexdigest()[:20]
            add_event(
                connection,
                fingerprint=f"save:production:{key}:{production_state_hash}",
                occurred_at=event_occurred_at,
                event_type="production",
                player=player,
                guild=guild,
                base=display_name,
                title="Stock de production observé",
                message=message,
                icon=production_changes[0].get("icon"),
                source="save",
                confidence=base_attribution_confidence(player),
                details=base_label_details({
                    "headline": headline,
                    "body": body,
                    "bullets": quantity_bullets(production_changes),
                    "items": production_changes,
                    "total": production_total,
                }, name, display_name, player),
            )

        old_states = old.get("structureStates") or {}
        new_states = base.get("structureStates") or {}
        repaired_keys = [
            structure_key
            for structure_key in set(old_states) & set(new_states)
            if bool(old_states[structure_key].get("damaged"))
            and not bool(new_states[structure_key].get("damaged"))
        ]
        repaired_keys = eligible_structure_transition_keys(connection, repaired_keys, "repair")
        if repaired_keys and (active_player_keys is None or player is not None):
            repaired = len(repaired_keys)
            headline = (
                f"{player} remet {display_name} en état"
                if player
                else f"{display_name} reprend des couleurs"
            )
            add_event(
                connection,
                fingerprint=(
                    f"save:{event_occurred_at}:repair:{key}:"
                    f"{hashlib.sha256('|'.join(repaired_keys).encode('utf-8')).hexdigest()[:16]}"
                ),
                occurred_at=event_occurred_at,
                event_type="repair",
                player=player,
                guild=guild,
                base=display_name,
                title="Réparations terminées",
                message=f"{headline}: {repaired} structure{'' if repaired == 1 else 's'} réparée{'' if repaired == 1 else 's'}.",
                source="save",
                confidence=base_attribution_confidence(player),
                details=base_label_details({
                    "headline": headline,
                    "body": "La base retrouve un meilleur état.",
                    "bullets": [f"-{repaired} structure{'' if repaired == 1 else 's'} endommagée{'' if repaired == 1 else 's'}"],
                    "structureKeys": repaired_keys,
                }, name, display_name, player),
            )

        old_damaged = int(old.get("structuresDamaged") or 0)
        damaged = int(base.get("structuresDamaged") or 0)
        damaged_keys = [
            structure_key
            for structure_key in set(old_states) & set(new_states)
            if not bool(old_states[structure_key].get("damaged"))
            and bool(new_states[structure_key].get("damaged"))
        ]
        damaged_keys = eligible_structure_transition_keys(connection, damaged_keys, "base")
        damaged_delta = len(damaged_keys) if old_states and new_states else max(0, damaged - old_damaged)
        if damaged_delta > 0 and (active_player_keys is None or player is not None):
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
                confidence=base_attribution_confidence(player),
                details=base_label_details({
                    "headline": headline,
                    "body": "La base encaisse de nouveaux dégâts.",
                    "bullets": [
                        f"+{damaged_delta} "
                        f"{plural(damaged_delta, 'structure endommagée', 'structures endommagées')}"
                    ],
                    "damagedTotal": damaged,
                    **({"structureKeys": damaged_keys} if damaged_keys else {}),
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
    compare_guild_research_events(connection, previous, current, occurred_at, active_players)

    for key, player in new_players.items():
        old = old_players.get(key)
        if old is None:
            same_name = [
                candidate
                for candidate in old_players.values()
                if str(candidate.get("name") or "").casefold() == str(player.get("name") or "").casefold()
            ]
            if len(same_name) == 1:
                old = same_name[0]
        name = player["name"]
        activity_key = str(player.get("activityKey") or name).casefold()
        player_active = active_player_keys is None or activity_key in active_player_keys
        player_occurred_at = activity_event_time(active_players, activity_key, occurred_at)
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

        compare_enriched_progress(
            connection,
            old,
            player,
            player_occurred_at,
            key,
            observation_at=occurred_at,
        )

        if player["level"] > old["level"]:
            add_event(
                connection,
                fingerprint=f"save:level:{key}:{player['level']}",
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
                activity_key = str(player.get("activityKey") or player.get("name") or "").casefold()
                if active_players is not None and activity_key not in active_players:
                    continue
                old = (previous.get("players") or {}).get(key)
                if old is None:
                    same_name = [
                        candidate
                        for candidate in (previous.get("players") or {}).values()
                        if str(candidate.get("name") or "").casefold()
                        == str(player.get("name") or "").casefold()
                    ]
                    old = same_name[0] if len(same_name) == 1 else None
                if old is not None:
                    player_occurred_at = activity_event_time(active_players, activity_key, occurred_at)
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
    previous_last_save_at = str(
        metadata_get(
            connection,
            "projection_watermark",
            metadata_get(connection, "last_save_at", ""),
        ) or ""
    )
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

    initial_live_at = str(metadata_get(connection, "projection_initial_live_at", "") or "")
    if not initial_live_at and current_snapshot_at:
        initial_live_at = previous_last_save_at or current_snapshot_at
        metadata_set(connection, "projection_initial_live_at", initial_live_at)

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
        metadata_set(connection, "projection_watermark", last_save_at)
        metadata_set(connection, "known_players", sorted(known_players))
    if imported_archive_hours:
        processed_archives = set(metadata_get(connection, "archive_backfill_processed", []))
        processed_archives.update(imported_archive_hours)
        metadata_set(connection, "archive_backfill_processed", sorted(processed_archives))
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
    live_cutoff_text = str(metadata_get(connection, "projection_initial_live_at", "") or "")
    if not live_cutoff_text and metadata_get(connection, "history_backfilled", False):
        live_cutoff_text = str(
            metadata_get(
                connection,
                "projection_watermark",
                metadata_get(connection, "last_save_at", ""),
            ) or ""
        )
    live_cutoff = parse_timestamp(live_cutoff_text)
    if live_cutoff and not metadata_get(connection, "projection_initial_live_at"):
        metadata_set(connection, "projection_initial_live_at", live_cutoff_text)
    previous = metadata_get(connection, "archive_backfill_state")
    candidates = []
    overlap_skipped = []
    for path in sorted(history_path.glob("*/*/*/*.json.gz")) if history_path.exists() else []:
        hour_key = archive_hour_key(path, history_path)
        if not hour_key or hour_key in processed:
            continue
        archived_at = archive_datetime(path, history_path)
        if minimum and archived_at and archived_at < minimum.astimezone(timezone.utc):
            processed.add(hour_key)
            continue
        if live_cutoff and archived_at and archived_at > live_cutoff.astimezone(timezone.utc).replace(
            minute=0, second=0, microsecond=0
        ):
            processed.add(hour_key)
            overlap_skipped.append(hour_key)
            continue
        candidates.append((hour_key, path))

    events_before = int(connection.execute("SELECT COUNT(*) FROM events").fetchone()[0])
    imported = []
    last_imported_at = ""
    sessions = player_session_index(stats_path)
    for hour_key, path in candidates[: max(1, budget)]:
        payload = load_snapshot(path)
        occurred_at = str(payload.get("updatedAt") or "") if payload else ""
        if not payload or parse_timestamp(occurred_at) is None:
            processed.add(hour_key)
            continue
        if live_cutoff and parse_timestamp(occurred_at) >= live_cutoff:
            processed.add(hour_key)
            overlap_skipped.append(hour_key)
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
        last_imported_at = occurred_at
        processed.add(hour_key)
        imported.append(hour_key)

    if previous is not None:
        metadata_set(connection, "archive_backfill_state", previous)
        if metadata_get(connection, "save_state") is None and last_imported_at:
            metadata_set(connection, "save_state", previous)
            metadata_set(connection, "last_save_at", last_imported_at)
            metadata_set(connection, "projection_watermark", last_imported_at)
            metadata_set(connection, "known_players", sorted((previous.get("players") or {}).keys()))
    metadata_set(connection, "archive_backfill_processed", sorted(processed))
    events_after = int(connection.execute("SELECT COUNT(*) FROM events").fetchone()[0])
    return {
        "status": "complete" if not candidates[len(imported):] else "partial",
        "health": health,
        "snapshots": len(imported),
        "importedHours": imported,
        "overlapSkippedHours": sorted(set(overlap_skipped)),
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


def level_business_identity(row: sqlite3.Row) -> tuple[str, int] | None:
    if row["type"] != "level":
        return None
    fingerprint = str(row["fingerprint"] or "")
    match = LEVEL_FINGERPRINT_RE.match(fingerprint)
    if match:
        return match.group("player").casefold(), int(match.group("level"))
    match = LEGACY_LEVEL_FINGERPRINT_RE.search(fingerprint)
    if match:
        return str(row["player"] or match.group("player")).casefold(), int(match.group("level"))
    match = re.search(r"niveau\s+(\d+)", str(row["message"] or ""), re.IGNORECASE)
    if not match:
        return None
    return str(row["player"] or "").casefold(), int(match.group(1))


def research_stable_guild_index(
    connection: sqlite3.Connection,
    bases_payload: dict | None = None,
) -> dict[str, set[str]]:
    candidates: dict[str, set[str]] = {}
    persisted = metadata_get(connection, "research_base_guild_candidates", {})
    if isinstance(persisted, dict):
        for base_key, guild_keys in persisted.items():
            values = guild_keys if isinstance(guild_keys, list) else [guild_keys]
            candidates.setdefault(str(base_key).casefold(), set()).update(
                str(value).strip().casefold()
                for value in values
                if str(value).strip()
            )

    canonical_guild_keys = {
        match.group("guild").casefold()
        for row in connection.execute(
            "SELECT fingerprint FROM events WHERE source = 'save' AND type = 'research'"
        ).fetchall()
        if (match := RESEARCH_FINGERPRINT_RE.match(str(row["fingerprint"] or "")))
    }

    def add_candidate(base_key: str | None, guild_key: str | None) -> None:
        base_identity = str(base_key or "").strip().casefold()
        guild_identity = str(guild_key or "").strip().casefold()
        if base_identity and guild_identity:
            candidates.setdefault(base_identity, set()).add(guild_identity)

    def add_payload(payload: dict | None, *, explicit_keys: bool) -> None:
        if not isinstance(payload, dict):
            return
        bases = payload.get("bases")
        if isinstance(bases, list):
            rows = [(None, row) for row in bases if isinstance(row, dict)]
        elif isinstance(bases, dict):
            rows = [(str(base_key), row) for base_key, row in bases.items() if isinstance(row, dict)]
        else:
            rows = []
        for stored_key, row in rows:
            guild_key = str(row.get("guildKey") or "").strip()
            guild = str(row.get("guild") or "").strip()
            if not guild_key:
                continue
            if not explicit_keys and (
                guild_key.casefold() == guild.casefold()
                and guild_key.casefold() not in canonical_guild_keys
            ):
                continue
            name = str(row.get("name") or "").strip()
            add_candidate(stored_key, guild_key)
            if guild and name:
                add_candidate(f"{guild}::{name}", guild_key)

    add_payload(bases_payload, explicit_keys=True)
    add_payload(metadata_get(connection, "save_state", {}), explicit_keys=False)
    add_payload(metadata_get(connection, "archive_backfill_state", {}), explicit_keys=False)
    return candidates


def research_identity_resolution(
    row: sqlite3.Row,
    stable_guilds_by_base: dict[str, set[str]] | None = None,
) -> tuple[tuple[str, int] | None, str]:
    if row["type"] != "research":
        return None, "not-research"
    fingerprint = str(row["fingerprint"] or "")
    canonical = RESEARCH_FINGERPRINT_RE.match(fingerprint)
    if canonical:
        return (
            canonical.group("guild").casefold(),
            int(canonical.group("total")),
        ), "canonical"

    legacy = LEGACY_RESEARCH_FINGERPRINT_RE.match(fingerprint)
    if not legacy:
        return None, "invalid-fingerprint"
    total = int(legacy.group("total"))
    details = details_from_row(row)
    details_guild_key = str(
        details.get("stableGuildKey") or details.get("guildKey") or ""
    ).strip().casefold()
    if details_guild_key:
        return (details_guild_key, total), "event-details"

    base_key = legacy.group("base").strip().casefold()
    candidates = (stable_guilds_by_base or {}).get(base_key, set())
    if len(candidates) == 1:
        return (next(iter(candidates)), total), "base-snapshot"
    if len(candidates) > 1:
        return None, "ambiguous-base"
    return None, "unresolved-base"


def research_business_identity(
    row: sqlite3.Row,
    stable_guilds_by_base: dict[str, set[str]] | None = None,
) -> tuple[str, int] | None:
    identity, _reason = research_identity_resolution(row, stable_guilds_by_base)
    return identity


def normalize_business_events(
    connection: sqlite3.Connection,
    bases_payload: dict | None = None,
) -> dict:
    rows = connection.execute(
        """
        SELECT id, fingerprint, occurred_at, type, player, guild, base, message, details_json
        FROM events
        WHERE source = 'save' AND type IN ('level', 'repair')
          AND NOT EXISTS (
            SELECT 1 FROM event_suppressions
            WHERE event_suppressions.event_id = events.id
          )
        ORDER BY occurred_at ASC, id ASC
        """
    ).fetchall()
    seen_levels = set()
    duplicate_level_ids = []
    ambiguous_repair_ids = []
    for row in rows:
        if row["type"] == "level":
            identity = level_business_identity(row)
            if identity is not None:
                if identity in seen_levels:
                    duplicate_level_ids.append(int(row["id"]))
                else:
                    seen_levels.add(identity)
        elif not (details_from_row(row).get("structureKeys") or []):
            ambiguous_repair_ids.append(int(row["id"]))

    stable_guilds_by_base = research_stable_guild_index(connection, bases_payload)
    metadata_set(connection, "research_base_guild_candidates", {
        key: sorted(values)
        for key, values in sorted(stable_guilds_by_base.items())
    })
    research_rows = connection.execute(
        """
        SELECT events.id, events.fingerprint, events.occurred_at, events.type,
               events.player, events.guild, events.base, events.message,
               events.details_json, event_suppressions.reason AS suppression_reason
        FROM events
        LEFT JOIN event_suppressions ON event_suppressions.event_id = events.id
        WHERE events.source = 'save'
          AND events.type = 'research'
          AND (
            event_suppressions.event_id IS NULL
            OR event_suppressions.reason = 'duplicate-research'
          )
        ORDER BY julianday(events.occurred_at) ASC, events.id ASC
        """
    ).fetchall()
    research_groups: dict[tuple[str, int], list[sqlite3.Row]] = {}
    unresolved_research = []
    for row in research_rows:
        identity, reason = research_identity_resolution(row, stable_guilds_by_base)
        if identity is None:
            unresolved_research.append({
                "eventId": int(row["id"]),
                "reason": reason,
                "fingerprint": str(row["fingerprint"] or ""),
                "guild": str(row["guild"] or "") or None,
                "base": str(row["base"] or "") or None,
                "total": research_total_from_fingerprint(row["fingerprint"]),
            })
            continue
        research_groups.setdefault(identity, []).append(row)

    desired_duplicate_research_ids = set()
    for grouped_rows in research_groups.values():
        survivor = min(
            grouped_rows,
            key=lambda row: (
                0 if RESEARCH_FINGERPRINT_RE.match(str(row["fingerprint"] or "")) else 1,
                parse_timestamp(row["occurred_at"]) or datetime.max.replace(tzinfo=timezone.utc),
                int(row["id"]),
            ),
        )
        desired_duplicate_research_ids.update(
            int(row["id"])
            for row in grouped_rows
            if int(row["id"]) != int(survivor["id"])
        )

    existing_duplicate_research_ids = {
        int(row["event_id"])
        for row in connection.execute(
            "SELECT event_id FROM event_suppressions WHERE reason = 'duplicate-research'"
        ).fetchall()
    }
    restored_research_ids = sorted(
        existing_duplicate_research_ids - desired_duplicate_research_ids
    )
    new_duplicate_research_ids = sorted(
        desired_duplicate_research_ids - existing_duplicate_research_ids
    )
    if restored_research_ids:
        connection.executemany(
            "DELETE FROM event_suppressions WHERE event_id = ? AND reason = 'duplicate-research'",
            [(event_id,) for event_id in restored_research_ids],
        )

    diagnostic = {
        "schemaVersion": 1,
        "unresolved": len(unresolved_research),
        "events": unresolved_research[:100],
    }
    metadata_set(connection, "research_identity_diagnostic", diagnostic)

    suppressed_ids = duplicate_level_ids + new_duplicate_research_ids + ambiguous_repair_ids
    suppress_events(connection, duplicate_level_ids, "duplicate-level")
    suppress_events(connection, new_duplicate_research_ids, "duplicate-research")
    suppress_events(connection, ambiguous_repair_ids, "ambiguous-repair")
    return {
        "levelDuplicatesRemoved": len(duplicate_level_ids),
        "researchDuplicatesRemoved": len(new_duplicate_research_ids),
        "researchDuplicateSuppressions": len(desired_duplicate_research_ids),
        "researchSuppressionsRestored": len(restored_research_ids),
        "researchIdentityUnresolved": len(unresolved_research),
        "researchUnresolvedIds": [row["eventId"] for row in unresolved_research[:25]],
        "ambiguousRepairsRemoved": len(ambiguous_repair_ids),
        "suppressedIds": suppressed_ids[:25],
    }


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
          AND NOT EXISTS (
            SELECT 1 FROM event_suppressions
            WHERE event_suppressions.event_id = events.id
          )
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
        normalized["body"] = f"{kept_total} {plural(kept_total, 'structure ajoutée', 'structures ajoutées')}."
        message = (
            f"{headline}. {kept_total} "
            f"{plural(kept_total, 'nouvelle structure ajoutée', 'nouvelles structures ajoutées')}."
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
        suppress_events(connection, deleted_ids, "world-drop-build")

    return updated, len(deleted_ids), deleted_ids[:25]


def normalized_public_language_event(row: sqlite3.Row, details: dict) -> tuple[str, str, str | None] | None:
    event_type = str(row["type"] or "")
    title = str(row["title"] or "")
    message = str(row["message"] or "")
    normalized = dict(details or {})
    changed = False

    def replace(value: str | None, replacements: tuple[tuple[str, str], ...]) -> str | None:
        nonlocal changed
        if value is None:
            return value
        text = str(value)
        updated = text
        for old, new in replacements:
            updated = updated.replace(old, new)
        if updated != text:
            changed = True
        return updated

    if event_type == "repair":
        title = replace(title, (("Réparations confirmées", "Réparations terminées"),)) or title
        normalized["body"] = replace(
            normalized.get("body"),
            (("La sauvegarde confirme moins de structures endommagées.", "La base retrouve un meilleur état."),),
        )
    elif event_type == "build":
        replacements = (
            ("nouvelle structure confirmée", "nouvelle structure ajoutée"),
            ("nouvelles structures confirmées", "nouvelles structures ajoutées"),
            ("De nouvelles structures sont confirmées dans la sauvegarde.", "La base s'agrandit."),
        )
        message = replace(message, replacements) or message
        normalized["body"] = replace(normalized.get("body"), replacements)
    elif event_type == "research":
        replacements = (
            ("confirme une nouvelle progression de recherche", "avance dans ses recherches"),
            ("recherche confirmée", "recherche terminée"),
            ("recherches confirmées", "recherches terminées"),
            ("La progression du laboratoire est confirmée pour l'ensemble de la guilde.", "Le laboratoire progresse pour l'ensemble de la guilde."),
            ("La progression du laboratoire est confirmée au niveau de la guilde.", "Le laboratoire progresse au niveau de la guilde."),
            ("déduite", "rattachée à la guilde"),
            ("seul membre actif observé", "membre actif observé"),
        )
        message = replace(message, replacements) or message
        normalized["body"] = replace(normalized.get("body"), replacements)
        normalized["attribution"] = replace(normalized.get("attribution"), replacements)
    elif event_type == "base":
        normalized["body"] = replace(
            normalized.get("body"),
            (("La sauvegarde confirme davantage de structures endommagées.", "La base encaisse de nouveaux dégâts."),),
        )
    elif event_type == "mutation":
        title = replace(
            title,
            (
                ("Mutation confirmée", "Mutation relevée"),
                ("Mutations confirmées", "Mutations relevées"),
            ),
        ) or title
        message = replace(message, ((" confirme ", " relève "),)) or message
        normalized["body"] = replace(normalized.get("body"), ((" confirme ", " relève "),))
    elif event_type == "recovery":
        normalized["body"] = replace(
            normalized.get("body"),
            (("Signal confirmé dans la sauvegarde du monde.", "Signal relevé dans la sauvegarde du monde."),),
        )

    if not changed:
        return None
    if normalized.get("headline") == row["title"]:
        normalized["headline"] = title
    return title, message, details_json_payload(normalized)


def empty_history_normalization_report(status: str = "current") -> dict:
    return {
        "status": status,
        "itemizedUpdated": 0,
        "publicLanguageUpdated": 0,
        "duplicatesRemoved": 0,
        "duplicateIds": [],
        "captureDuplicatesRemoved": 0,
        "captureDuplicateIds": [],
        "captureMessagesUpdated": 0,
        "worldDropBuildUpdated": 0,
        "worldDropBuildRemoved": 0,
        "worldDropBuildRemovedIds": [],
        "levelDuplicatesRemoved": 0,
        "researchDuplicatesRemoved": 0,
        "researchDuplicateSuppressions": 0,
        "researchSuppressionsRestored": 0,
        "researchIdentityUnresolved": 0,
        "researchUnresolvedIds": [],
        "ambiguousRepairsRemoved": 0,
        "suppressedIds": [],
    }


def normalize_event_history(
    connection: sqlite3.Connection,
    bases_payload: dict | None = None,
) -> dict:
    max_event_id = int(connection.execute("SELECT COALESCE(MAX(id), 0) FROM events").fetchone()[0])
    projection_revision = int(metadata_get(connection, "events_projection_revision", 0) or 0)
    state = metadata_get(connection, "event_history_normalization_state", {})
    if (
        isinstance(state, dict)
        and int(state.get("schemaVersion") or 0) == 5
        and int(state.get("lastEventId") or 0) == max_event_id
        and int(state.get("projectionRevision") or 0) == projection_revision
    ):
        return empty_history_normalization_report()

    rows = connection.execute(
        """
        SELECT id, fingerprint, occurred_at, type, player, guild, base, title,
               message, icon, source, details_json, confidence
        FROM events
        WHERE NOT EXISTS (
            SELECT 1 FROM event_suppressions
            WHERE event_suppressions.event_id = events.id
        )
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

    public_language_updated = 0
    rows = connection.execute(
        """
        SELECT id, type, title, message, details_json
        FROM events
        WHERE type IN ('base', 'build', 'mutation', 'recovery', 'repair', 'research')
          AND NOT EXISTS (
              SELECT 1 FROM event_suppressions
              WHERE event_suppressions.event_id = events.id
          )
        ORDER BY occurred_at ASC, id ASC
        """
    ).fetchall()
    for row in rows:
        normalized = normalized_public_language_event(row, details_from_row(row))
        if normalized is None:
            continue
        title, message, details_json = normalized
        connection.execute(
            """
            UPDATE events
            SET title = ?, message = ?, details_json = ?
            WHERE id = ?
            """,
            (title, message, details_json, row["id"]),
        )
        public_language_updated += 1

    rows = connection.execute(
        """
        SELECT id, fingerprint, occurred_at, type, player, title, message
        FROM events
        WHERE type IN ('quest', 'challenge', 'discovery')
          AND NOT EXISTS (
            SELECT 1 FROM event_suppressions
            WHERE event_suppressions.event_id = events.id
          )
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
        suppress_events(connection, duplicate_ids, "duplicate-one-time-event")

    rows = connection.execute(
        """
        SELECT id, fingerprint, occurred_at, type, player, title, message
        FROM events
        WHERE type = 'capture'
          AND NOT EXISTS (
            SELECT 1 FROM event_suppressions
            WHERE event_suppressions.event_id = events.id
          )
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
        suppress_events(connection, capture_duplicate_ids, "duplicate-capture")

    rows = connection.execute(
        """
        SELECT id, fingerprint, occurred_at, type, player, title, message
        FROM events
        WHERE type = 'capture'
          AND NOT EXISTS (
            SELECT 1 FROM event_suppressions
            WHERE event_suppressions.event_id = events.id
          )
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

    business_normalization = normalize_business_events(connection, bases_payload)
    metadata_set(connection, "event_history_normalization_state", {
        "schemaVersion": 5,
        "lastEventId": max_event_id,
        "projectionRevision": int(metadata_get(connection, "events_projection_revision", 0) or 0),
    })
    return {
        "status": "complete",
        "itemizedUpdated": itemized_updated,
        "duplicatesRemoved": len(duplicate_ids),
        "duplicateIds": duplicate_ids[:25],
        "captureDuplicatesRemoved": len(capture_duplicate_ids),
        "captureDuplicateIds": capture_duplicate_ids[:25],
        "captureMessagesUpdated": capture_messages_updated,
        "publicLanguageUpdated": public_language_updated,
        "worldDropBuildUpdated": world_drop_updated,
        "worldDropBuildRemoved": world_drop_removed,
        "worldDropBuildRemovedIds": world_drop_removed_ids,
        **business_normalization,
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

    label_digest = hashlib.sha256(json.dumps(
        sorted((player, base, label) for (player, base), label in label_index.items()),
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")).hexdigest()
    max_event_id = int(connection.execute("SELECT COALESCE(MAX(id), 0) FROM events").fetchone()[0])
    projection_revision = int(metadata_get(connection, "events_projection_revision", 0) or 0)
    state = metadata_get(connection, "base_label_normalization_state", {})
    if (
        isinstance(state, dict)
        and int(state.get("schemaVersion") or 0) == 2
        and state.get("labelDigest") == label_digest
        and int(state.get("lastEventId") or 0) == max_event_id
        and int(state.get("projectionRevision") or 0) == projection_revision
    ):
        return {"status": "current", "updated": 0, "labels": len(label_index)}

    lower_bound = 0
    if (
        isinstance(state, dict)
        and int(state.get("schemaVersion") or 0) == 2
        and state.get("labelDigest") == label_digest
        and max_event_id > int(state.get("lastEventId") or 0)
    ):
        lower_bound = int(state.get("lastEventId") or 0)

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
          AND id > ?
        ORDER BY occurred_at ASC, id ASC
        """,
        (lower_bound,),
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

    metadata_set(connection, "base_label_normalization_state", {
        "schemaVersion": 2,
        "labelDigest": label_digest,
        "lastEventId": max_event_id,
        "projectionRevision": int(metadata_get(connection, "events_projection_revision", 0) or 0),
    })
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

    sessions_digest = hashlib.sha256(json.dumps([
        [player, [[started.isoformat(), ended.isoformat() if ended else None] for started, ended in player_sessions]]
        for player, player_sessions in sorted(sessions.items())
    ], ensure_ascii=False, separators=(",", ":")).encode("utf-8")).hexdigest()
    max_event_id = int(connection.execute("SELECT COALESCE(MAX(id), 0) FROM events").fetchone()[0])
    projection_revision = int(metadata_get(connection, "events_projection_revision", 0) or 0)
    state = metadata_get(connection, "inactive_save_cleanup_state", {})
    if (
        isinstance(state, dict)
        and int(state.get("schemaVersion") or 0) == 2
        and state.get("sessionsDigest") == sessions_digest
        and int(state.get("lastEventId") or 0) == max_event_id
        and int(state.get("projectionRevision") or 0) == projection_revision
    ):
        return {
            "status": "current",
            "removed": 0,
            "reassigned": 0,
            "removedIds": [],
            "reassignedIds": [],
        }

    lower_bound = 0
    if (
        isinstance(state, dict)
        and int(state.get("schemaVersion") or 0) == 2
        and state.get("sessionsDigest") == sessions_digest
        and max_event_id > int(state.get("lastEventId") or 0)
    ):
        lower_bound = int(state.get("lastEventId") or 0)

    rows = connection.execute(
        """
        SELECT id, occurred_at, type, player
        FROM events
        WHERE source = 'save' AND player IS NOT NULL AND id > ?
        ORDER BY occurred_at ASC, id ASC
        """,
        (lower_bound,),
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
        suppress_events(connection, remove_ids, "inactive-save-event")
    if reassignments:
        connection.executemany(
            "UPDATE events SET occurred_at = ? WHERE id = ?",
            reassignments,
        )

    metadata_set(connection, "inactive_save_cleanup_state", {
        "schemaVersion": 2,
        "sessionsDigest": sessions_digest,
        "lastEventId": max_event_id,
        "projectionRevision": int(metadata_get(connection, "events_projection_revision", 0) or 0),
    })
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


def metadata_delete(connection: sqlite3.Connection, key: str) -> None:
    connection.execute("DELETE FROM metadata WHERE key = ?", (key,))


def public_projection_change_seq(connection: sqlite3.Connection) -> int:
    return int(connection.execute(
        "SELECT COALESCE(MAX(seq), 0) FROM event_projection_changes"
    ).fetchone()[0])


def public_projection_source_bounds(connection: sqlite3.Connection) -> tuple[int, str]:
    row = connection.execute(
        """
        SELECT id, occurred_at
        FROM events
        ORDER BY julianday(occurred_at) DESC, id DESC
        LIMIT 1
        """
    ).fetchone()
    max_id = int(connection.execute("SELECT COALESCE(MAX(id), 0) FROM events").fetchone()[0])
    return max_id, str(row["occurred_at"] or "") if row else ""


def public_projection_order_rank(event: dict) -> int:
    event_type = str(event.get("type") or "")
    source = str(event.get("source") or "")
    if event_type == "leave" and source in {"journal", "players"}:
        return 0
    if source == "save":
        return 1
    if event_type in {"join", "reconnect"} and source in {"journal", "players"}:
        return 2
    return 1


def insert_public_projection_events(
    connection: sqlite3.Connection,
    events: list[dict],
    members: dict[str, list[int]],
    raw_types: dict[int, str],
) -> None:
    for event in events:
        echo_key = str(event["key"])
        event_id = int(event["id"])
        connection.execute(
            "DELETE FROM public_event_projection_members WHERE echo_key = ?",
            (echo_key,),
        )
        connection.execute(
            """
            INSERT INTO public_event_projection(
                echo_key, event_id, occurred_at, order_rank, payload_json,
                represented_events, reconciled_reconnect
            ) VALUES(?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(echo_key) DO UPDATE SET
                event_id = excluded.event_id,
                occurred_at = excluded.occurred_at,
                order_rank = excluded.order_rank,
                payload_json = excluded.payload_json,
                represented_events = excluded.represented_events,
                reconciled_reconnect = excluded.reconciled_reconnect
            """,
            (
                echo_key,
                event_id,
                event["occurredAt"],
                public_projection_order_rank(event),
                json.dumps(event, ensure_ascii=False, separators=(",", ":")),
                max(1, int((event.get("details") or {}).get("aggregatedEvents") or 1)),
                int(event.get("type") == "reconnect" and raw_types.get(event_id) != "reconnect"),
            ),
        )
        connection.executemany(
            """
            INSERT INTO public_event_projection_members(event_id, echo_key)
            VALUES(?, ?)
            ON CONFLICT(event_id) DO UPDATE SET echo_key = excluded.echo_key
            """,
            [(int(source_id), echo_key) for source_id in members.get(echo_key, [event_id])],
        )


def public_projection_state_payload(
    connection: sqlite3.Connection,
    *,
    change_seq: int,
) -> dict:
    source_max_id, source_max_occurred_at = public_projection_source_bounds(connection)
    latest = parse_timestamp(source_max_occurred_at)
    open_from = None
    if latest is not None:
        open_from_at = latest - timedelta(seconds=SESSION_EVENT_TOLERANCE_SECONDS)
        open_from = open_from_at.replace(
            minute=(open_from_at.minute // 5) * 5,
            second=0,
            microsecond=0,
        ).isoformat()
    return {
        "schemaVersion": PUBLIC_PROJECTION_SCHEMA_VERSION,
        "changeSeq": int(change_seq),
        "sourceMaxId": source_max_id,
        "sourceMaxOccurredAt": source_max_occurred_at,
        "openFrom": open_from,
        "projectionRevision": int(metadata_get(connection, "events_projection_revision", 0) or 0),
        "echoes": int(connection.execute(
            "SELECT COUNT(*) FROM public_event_projection"
        ).fetchone()[0]),
        "updatedAt": now_iso(),
    }


def prune_public_projection_changes(connection: sqlite3.Connection, change_seq: int) -> None:
    connection.execute(
        "DELETE FROM event_projection_changes WHERE seq <= ?",
        (int(change_seq),),
    )


def rebuild_public_projection(connection: sqlite3.Connection) -> dict:
    previous_state = metadata_get(connection, "public_projection_state", {})
    rows = connection.execute(
        f"""
        SELECT id, fingerprint, occurred_at, type, player, guild, base, title,
               message, icon, source, details_json, confidence
        FROM events
        WHERE NOT EXISTS (
            SELECT 1 FROM event_suppressions
            WHERE event_suppressions.event_id = events.id
        )
        ORDER BY {PUBLIC_EVENT_ORDER_SQL}
        """
    ).fetchall()
    events, reconnects, members = reconcile_public_events(
        rows,
        include_members=True,
        research_guild_keys_by_base=research_stable_guild_index(connection),
    )
    raw_types = {int(row["id"]): str(row["type"] or "") for row in rows}
    connection.execute("DELETE FROM public_event_projection_members")
    connection.execute("DELETE FROM public_event_projection")
    insert_public_projection_events(connection, events, members, raw_types)
    change_seq = max(
        public_projection_change_seq(connection),
        int((previous_state or {}).get("changeSeq") or 0),
    )
    state = public_projection_state_payload(connection, change_seq=change_seq)
    metadata_set(connection, "public_projection_state", state)
    metadata_delete(connection, "public_projection_pending")
    prune_public_projection_changes(connection, change_seq)
    return {
        "status": "reprojected",
        "sourceRowsReconciled": len(rows),
        "echoes": len(events),
        "reconciledReconnects": reconnects,
        **state,
    }


def session_player_states_before(
    connection: sqlite3.Connection,
    before_at: str,
) -> dict[str, bool]:
    server = connection.execute(
        """
        SELECT id, occurred_at
        FROM events
        WHERE type = 'server'
          AND julianday(occurred_at) < julianday(?)
          AND NOT EXISTS (
            SELECT 1 FROM event_suppressions
            WHERE event_suppressions.event_id = events.id
          )
        ORDER BY julianday(occurred_at) DESC, id DESC
        LIMIT 1
        """,
        (before_at,),
    ).fetchone()
    server_key = None
    if server:
        server_key = (parse_timestamp(server["occurred_at"]), int(server["id"]))

    rows = connection.execute(
        """
        WITH ranked AS (
            SELECT id, occurred_at, type, player,
                   ROW_NUMBER() OVER (
                       PARTITION BY lower(player)
                       ORDER BY julianday(occurred_at) DESC, id DESC
                   ) AS position
            FROM events
            WHERE type IN ('join', 'leave')
              AND player IS NOT NULL
              AND julianday(occurred_at) < julianday(?)
              AND NOT EXISTS (
                SELECT 1 FROM event_suppressions
                WHERE event_suppressions.event_id = events.id
              )
        )
        SELECT id, occurred_at, type, player
        FROM ranked
        WHERE position = 1
        """,
        (before_at,),
    ).fetchall()
    states = {}
    for row in rows:
        transition_key = (parse_timestamp(row["occurred_at"]), int(row["id"]))
        after_server = not server_key or (
            transition_key[0] is not None
            and server_key[0] is not None
            and transition_key > server_key
        )
        states[str(row["player"] or "").casefold()] = bool(
            after_server and row["type"] == "join"
        )
    return states


def mark_public_projection_pending(
    connection: sqlite3.Connection,
    state: dict,
    changes,
    reason: str,
) -> dict:
    existing = metadata_get(connection, "public_projection_pending", {})
    pending = {
        "status": "reprojection-required",
        "reason": str((existing or {}).get("reason") or reason),
        "detectedAt": str((existing or {}).get("detectedAt") or now_iso()),
        "firstChangeSeq": int((existing or {}).get("firstChangeSeq") or changes[0]["seq"]),
        "latestChangeSeq": int(changes[-1]["seq"]),
        "materializedChangeSeq": int(state.get("changeSeq") or 0),
        "materializedProjectionRevision": int(state.get("projectionRevision") or 0),
        "sourceProjectionRevision": int(metadata_get(connection, "events_projection_revision", 0) or 0),
    }
    metadata_set(connection, "public_projection_pending", pending)
    return pending


def increment_public_projection(connection: sqlite3.Connection, state: dict) -> dict:
    changes = connection.execute(
        """
        SELECT seq, event_id, change_kind, occurred_at
        FROM event_projection_changes
        WHERE seq > ?
        ORDER BY seq
        """,
        (int(state.get("changeSeq") or 0),),
    ).fetchall()
    if not changes:
        source_revision = int(metadata_get(connection, "events_projection_revision", 0) or 0)
        if source_revision != int(state.get("projectionRevision") or 0):
            synthetic_change = [{
                "seq": int(state.get("changeSeq") or 0),
                "event_id": int(state.get("sourceMaxId") or 0),
                "change_kind": "missing",
                "occurred_at": state.get("sourceMaxOccurredAt"),
            }]
            return mark_public_projection_pending(
                connection,
                state,
                synthetic_change,
                "change-journal-gap",
            )
        return {"status": "current", **state}

    source_max_id = int(state.get("sourceMaxId") or 0)
    if any(int(change["event_id"]) <= source_max_id for change in changes):
        return mark_public_projection_pending(
            connection,
            state,
            changes,
            "mutation-of-materialized-event",
        )

    changed_at = [parse_timestamp(change["occurred_at"]) for change in changes]
    if any(value is None for value in changed_at):
        return mark_public_projection_pending(
            connection,
            state,
            changes,
            "unusable-event-timestamp",
        )
    earliest_change = min(value for value in changed_at if value is not None)
    open_from = parse_timestamp(state.get("openFrom") or state.get("sourceMaxOccurredAt"))
    if open_from is not None and earliest_change < open_from:
        return mark_public_projection_pending(
            connection,
            state,
            changes,
            "historical-insert-or-backfill",
        )

    affected_at = earliest_change - timedelta(seconds=SESSION_EVENT_TOLERANCE_SECONDS)
    affected_at = affected_at.replace(
        minute=(affected_at.minute // 5) * 5,
        second=0,
        microsecond=0,
    )
    context_at = affected_at - timedelta(seconds=PUBLIC_PROJECTION_CONTEXT_SECONDS)
    context_text = context_at.isoformat()
    initial_states = session_player_states_before(connection, context_text)
    rows = connection.execute(
        f"""
        SELECT id, fingerprint, occurred_at, type, player, guild, base, title,
               message, icon, source, details_json, confidence
        FROM events
        WHERE julianday(occurred_at) >= julianday(?)
          AND NOT EXISTS (
            SELECT 1 FROM event_suppressions
            WHERE event_suppressions.event_id = events.id
          )
        ORDER BY {PUBLIC_EVENT_ORDER_SQL}
        """,
        (context_text,),
    ).fetchall()
    projected, _reconnects, members = reconcile_public_events(
        rows,
        initial_player_states=initial_states,
        include_members=True,
        research_guild_keys_by_base=research_stable_guild_index(connection),
    )
    affected_events = [
        event for event in projected
        if (parse_timestamp(event.get("occurredAt")) or datetime.min.replace(tzinfo=timezone.utc)) >= affected_at
    ]
    affected_keys = [
        row["echo_key"]
        for row in connection.execute(
            """
            SELECT echo_key
            FROM public_event_projection
            WHERE julianday(occurred_at) >= julianday(?)
            """,
            (affected_at.isoformat(),),
        ).fetchall()
    ]
    if affected_keys:
        connection.executemany(
            "DELETE FROM public_event_projection_members WHERE echo_key = ?",
            [(key,) for key in affected_keys],
        )
        connection.executemany(
            "DELETE FROM public_event_projection WHERE echo_key = ?",
            [(key,) for key in affected_keys],
        )
    raw_types = {int(row["id"]): str(row["type"] or "") for row in rows}
    insert_public_projection_events(connection, affected_events, members, raw_types)
    change_seq = int(changes[-1]["seq"])
    next_state = public_projection_state_payload(connection, change_seq=change_seq)
    recent_export_state = metadata_get(connection, "canonical_recent_export_state", {})
    recent_signature = (
        recent_export_state.get("signature")
        if isinstance(recent_export_state, dict)
        and isinstance(recent_export_state.get("signature"), dict)
        else {}
    )
    published_revision = recent_signature.get("projectionRevision")
    published_revision = int(published_revision) if published_revision is not None else None
    replace_boundaries = [affected_at.isoformat()]
    if state.get("recentWindowReplaceFrom"):
        replace_boundaries.append(str(state["recentWindowReplaceFrom"]))
    parsed_boundaries = [
        (parse_timestamp(boundary), boundary)
        for boundary in replace_boundaries
        if parse_timestamp(boundary) is not None
    ]
    next_state.update({
        "recentWindowFromProjectionRevision": (
            int(state["recentWindowFromProjectionRevision"])
            if state.get("recentWindowFromProjectionRevision") is not None
            and state.get("recentWindowReplaceFrom")
            else published_revision
        ),
        "recentWindowThroughProjectionRevision": int(next_state.get("projectionRevision") or 0),
        "recentWindowReplaceFrom": min(parsed_boundaries)[1] if parsed_boundaries else None,
        "recentWindowCurrentFromProjectionRevision": published_revision,
        "recentWindowCurrentReplaceFrom": affected_at.isoformat(),
    })
    metadata_set(connection, "public_projection_state", next_state)
    metadata_delete(connection, "public_projection_pending")
    prune_public_projection_changes(connection, change_seq)
    return {
        "status": "appended",
        "sourceRowsReconciled": len(rows),
        "replacedEchoes": len(affected_keys),
        "writtenEchoes": len(affected_events),
        "affectedFrom": affected_at.isoformat(),
        **next_state,
    }


def synchronize_public_projection(
    connection: sqlite3.Connection,
    *,
    reproject_public: bool = False,
) -> dict:
    state = metadata_get(connection, "public_projection_state", {})
    projection_exists = bool(connection.execute(
        "SELECT 1 FROM public_event_projection LIMIT 1"
    ).fetchone())
    if reproject_public:
        return rebuild_public_projection(connection)
    if not isinstance(state, dict) or int(state.get("schemaVersion") or 0) != PUBLIC_PROJECTION_SCHEMA_VERSION:
        if not state and not projection_exists:
            report = rebuild_public_projection(connection)
            report["status"] = "bootstrapped"
            return report
        changes = connection.execute(
            "SELECT seq, event_id, change_kind, occurred_at FROM event_projection_changes ORDER BY seq"
        ).fetchall()
        if not changes:
            changes = [{"seq": 0}]
        return mark_public_projection_pending(
            connection,
            state if isinstance(state, dict) else {},
            changes,
            "projection-schema-change",
        )
    pending = metadata_get(connection, "public_projection_pending", {})
    if isinstance(pending, dict) and pending.get("status") == "reprojection-required":
        return pending
    return increment_public_projection(connection, state)


def materialized_public_events(
    connection: sqlite3.Connection,
    limit: int | None = None,
) -> list[dict]:
    query = """
        SELECT payload_json, reconciled_reconnect
        FROM public_event_projection
        ORDER BY julianday(occurred_at) DESC, order_rank ASC, event_id DESC
    """
    parameters = ()
    if limit is not None:
        query += " LIMIT ?"
        parameters = (max(1, int(limit)),)
    rows = connection.execute(query, parameters).fetchall()
    return [json.loads(row["payload_json"]) for row in rows]


def represented_event_count(events: list[dict]) -> int:
    return sum(
        max(1, int((event.get("details") or {}).get("aggregatedEvents") or 1))
        for event in events
    )


def event_export_provenance(stats_path: Path, events: list[dict]) -> dict:
    stats = read_stats_payload(stats_path)
    source = stats.get("provenance") if isinstance(stats.get("provenance"), dict) else {}
    return {
        "observedAt": now_iso(),
        "sourceUpdatedAt": source.get("sourceUpdatedAt") or (events[0].get("occurredAt") if events else None),
        "gameVersion": source.get("gameVersion"),
        "steamBuildId": source.get("steamBuildId"),
        "parserCommit": source.get("parserCommit"),
        "catalogCommit": source.get("catalogCommit"),
        "schemaVersion": PUBLIC_EVENT_VERSION,
        "freshness": source.get("freshness") or "current",
        "sourceStatus": source.get("sourceStatus") or ("available" if stats else "unknown"),
    }


def recent_projection_window(
    events: list[dict],
    total_echoes: int,
    projection_sync: dict,
    projection_state: dict,
    previous_projection_revision: int | None,
) -> dict:
    replace_from = (
        str(
            projection_state.get("recentWindowReplaceFrom")
            or projection_sync.get("affectedFrom")
            or ""
        ) or None
    )
    through_revision = int(projection_state.get("projectionRevision") or 0)
    from_revision = projection_state.get("recentWindowFromProjectionRevision")
    if from_revision is None:
        from_revision = previous_projection_revision
    from_revision = int(from_revision) if from_revision is not None else None
    complete = recent_projection_window_complete(events, total_echoes, replace_from)
    if not complete and projection_state.get("recentWindowCurrentReplaceFrom"):
        current_replace_from = str(projection_state["recentWindowCurrentReplaceFrom"])
        current_complete = recent_projection_window_complete(
            events,
            total_echoes,
            current_replace_from,
        )
        if current_complete:
            replace_from = current_replace_from
            current_from = projection_state.get("recentWindowCurrentFromProjectionRevision")
            from_revision = int(current_from) if current_from is not None else None
            complete = True
    return {
        "mode": "replace-tail",
        "replaceFrom": replace_from,
        "complete": complete,
        "fromProjectionRevision": from_revision,
        "throughProjectionRevision": through_revision,
    }


def recent_projection_window_complete(
    events: list[dict],
    total_echoes: int,
    replace_from: str | None,
) -> bool:
    complete = int(total_echoes) <= len(events)
    if not complete and replace_from:
        replace_timestamp = parse_timestamp(replace_from)
        oldest_timestamp = min(
            (
                timestamp
                for event in events
                if (timestamp := parse_timestamp(event.get("occurredAt"))) is not None
            ),
            default=None,
        )
        complete = bool(
            replace_timestamp is not None
            and oldest_timestamp is not None
            and oldest_timestamp < replace_timestamp
        )
    return complete


def export_payload(
    events: list[dict],
    rows,
    reconnects: int,
    *,
    recent: bool = False,
    total_events: int | None = None,
    total_public_events: int | None = None,
    total_echoes: int | None = None,
    total_represented_events: int | None = None,
    projection_revision: int = 0,
    provenance_revision: str = "",
    provenance: dict | None = None,
    max_event_id: int | None = None,
    projection_window: dict | None = None,
) -> dict:
    counts = Counter(event["type"] for event in events)
    max_id = (
        int(max_event_id)
        if max_event_id is not None
        else max((int(row["id"]) for row in rows), default=0)
    )
    represented_events = represented_event_count(events)
    raw_events = total_events if total_events is not None else len(rows)
    all_echoes = total_echoes if total_echoes is not None else len(events)
    return {
        "version": PUBLIC_EVENT_VERSION,
        "schemaVersion": PUBLIC_EVENT_VERSION,
        "ok": True,
        "projection": "canonical-echoes",
        "revision": (
            f"{PUBLIC_EVENT_VERSION}:{projection_revision}:"
            f"{provenance_revision[:16]}:{len(events)}:{max_id}"
        ),
        "projectionRevision": projection_revision,
        "provenanceRevision": provenance_revision,
        "updatedAt": now_iso(),
        "provenance": provenance or {},
        "projectionWindow": projection_window,
        "recent": recent,
        "truncated": bool(recent and all_echoes > len(events)),
        "summary": {
            "events": len(events),
            "totalEvents": raw_events,
            "rawEvents": raw_events,
            "publicEvents": total_public_events if total_public_events is not None else len(rows),
            "echoes": len(events),
            "representedEvents": represented_events,
            "totalEchoes": total_echoes if total_echoes is not None else len(events),
            "totalRepresentedEvents": (
                total_represented_events
                if total_represented_events is not None
                else represented_events
            ),
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
    stats_path: Path = DEFAULT_STATS,
    *,
    reproject_public: bool = False,
    write_full_export: bool = False,
    full_export_interval_seconds: int = DEFAULT_FULL_EXPORT_INTERVAL_SECONDS,
) -> dict:
    connection.commit()
    try:
        connection.execute("BEGIN IMMEDIATE")
        projection_sync = synchronize_public_projection(
            connection,
            reproject_public=reproject_public,
        )
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    if projection_sync.get("status") == "reprojection-required":
        return projection_sync

    projection_state = metadata_get(connection, "public_projection_state", {})
    projection_revision = int(projection_state.get("projectionRevision") or 0)
    stats = read_stats_payload(stats_path)
    provenance_source = stats.get("provenance") if isinstance(stats.get("provenance"), dict) else {}
    stable_provenance = {
        key: provenance_source.get(key)
        for key in (
            "gameVersion",
            "steamBuildId",
            "parserCommit",
            "catalogCommit",
            "freshness",
            "sourceStatus",
        )
    }
    provenance_digest = hashlib.sha256(
        json.dumps(stable_provenance, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    common_signature = {
        "version": PUBLIC_EVENT_VERSION,
        "projectionRevision": projection_revision,
        "projectionChangeSeq": int(projection_state.get("changeSeq") or 0),
        "provenanceDigest": provenance_digest,
    }
    recent_signature = {**common_signature, "recentLimit": int(recent_limit)}
    full_signature = dict(common_signature)
    recent_state = metadata_get(connection, "canonical_recent_export_state", {})
    full_state = metadata_get(connection, "canonical_full_export_state", {})
    previous_recent_signature = (
        recent_state.get("signature")
        if isinstance(recent_state, dict) and isinstance(recent_state.get("signature"), dict)
        else {}
    )
    recent_current = (
        previous_recent_signature == recent_signature
        and recent_output.is_file()
    )
    previous_full_signature = (
        full_state.get("signature")
        if isinstance(full_state, dict) and isinstance(full_state.get("signature"), dict)
        else {}
    )
    last_full_at = parse_timestamp(
        full_state.get("writtenAt") if isinstance(full_state, dict) else None
    )
    full_due = bool(
        write_full_export
        or reproject_public
        or projection_sync.get("status") in {"bootstrapped", "reprojected"}
        or not output.is_file()
        or not previous_full_signature
        or previous_full_signature.get("provenanceDigest") != provenance_digest
        or last_full_at is None
        or (
            datetime.now(timezone.utc).astimezone() - last_full_at
        ).total_seconds() >= max(0, int(full_export_interval_seconds))
    )
    if recent_current and not full_due:
        return {"status": "unchanged", **recent_signature}

    total_events = int(connection.execute("SELECT COUNT(*) FROM events").fetchone()[0])
    total_public_events, max_public_event_id = connection.execute(
        """
        SELECT COUNT(*), COALESCE(MAX(id), 0)
        FROM events
        WHERE NOT EXISTS (
            SELECT 1 FROM event_suppressions
            WHERE event_suppressions.event_id = events.id
        )
        """
    ).fetchone()
    total_public_events = int(total_public_events)
    max_public_event_id = int(max_public_event_id)
    total_echoes, total_represented_events, reconnects = connection.execute(
        """
        SELECT COUNT(*), COALESCE(SUM(represented_events), 0),
               COALESCE(SUM(reconciled_reconnect), 0)
        FROM public_event_projection
        """
    ).fetchone()
    total_echoes = int(total_echoes)
    total_represented_events = int(total_represented_events)
    reconnects = int(reconnects)

    full_events = materialized_public_events(connection) if full_due else None
    recent_events = (
        full_events[:recent_limit]
        if full_events is not None
        else materialized_public_events(connection, recent_limit)
    )
    projection_window = recent_projection_window(
        recent_events,
        total_echoes,
        projection_sync,
        projection_state,
        (
            int(previous_recent_signature["projectionRevision"])
            if previous_recent_signature.get("projectionRevision") is not None
            else None
        ),
    )
    provenance = event_export_provenance(stats_path, recent_events)
    written_at = now_iso()
    if full_due:
        write_json_atomic(
            output,
            export_payload(
                full_events or [],
                [],
                reconnects,
                total_events=total_events,
                total_public_events=total_public_events,
                total_echoes=total_echoes,
                total_represented_events=total_represented_events,
                projection_revision=projection_revision,
                provenance_revision=provenance_digest,
                provenance=provenance,
                max_event_id=max_public_event_id,
                projection_window={
                    "mode": "full",
                    "replaceFrom": None,
                    "complete": True,
                    "fromProjectionRevision": None,
                    "throughProjectionRevision": projection_revision,
                },
            ),
        )
        metadata_set(connection, "canonical_full_export_state", {
            "signature": full_signature,
            "writtenAt": written_at,
        })
    if not recent_current:
        write_json_atomic(
            recent_output,
            export_payload(
                recent_events,
                [],
                reconnects,
                recent=True,
                total_events=total_events,
                total_public_events=total_public_events,
                total_echoes=total_echoes,
                total_represented_events=total_represented_events,
                projection_revision=projection_revision,
                provenance_revision=provenance_digest,
                provenance=provenance,
                max_event_id=max_public_event_id,
                projection_window=projection_window,
            ),
        )
        metadata_set(connection, "canonical_recent_export_state", {
            "signature": recent_signature,
            "writtenAt": written_at,
        })
        projection_state.update({
            "recentWindowFromProjectionRevision": projection_window.get("fromProjectionRevision"),
            "recentWindowThroughProjectionRevision": projection_window.get("throughProjectionRevision"),
            "recentWindowReplaceFrom": projection_window.get("replaceFrom"),
        })
        for key in (
            "recentWindowCurrentFromProjectionRevision",
            "recentWindowCurrentReplaceFrom",
        ):
            projection_state.pop(key, None)
        metadata_set(connection, "public_projection_state", projection_state)
    metadata_set(connection, "canonical_export_state", recent_signature)
    connection.commit()
    return {
        "status": "written",
        **recent_signature,
        "rawEvents": total_events,
        "publicEvents": total_public_events,
        "echoes": total_echoes,
        "representedEvents": total_represented_events,
        "projectionSync": projection_sync.get("status"),
        "recentExport": "unchanged" if recent_current else "written",
        "fullExport": "written" if full_due else "deferred",
        "fullExportIntervalSeconds": int(full_export_interval_seconds),
    }


def public_reprojection_requested(explicit: bool, request_path: Path) -> bool:
    return bool(explicit or request_path.is_file())


def consume_public_reprojection_request(request_path: Path, report: dict, requested: bool = False) -> bool:
    if not requested or not request_path.is_file() or report.get("status") == "reprojection-required":
        return False
    request_path.unlink(missing_ok=True)
    return True


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
    parser.add_argument(
        "--public-reprojection-request",
        type=Path,
        default=DEFAULT_PUBLIC_REPROJECTION_REQUEST,
        help="Fichier de demande consommé après une reprojection publique réussie.",
    )
    parser.add_argument("--journal-fixture", type=Path)
    parser.add_argument("--skip-journal", action="store_true")
    parser.add_argument("--backfill-from", default=DEFAULT_BACKFILL_FROM)
    parser.add_argument("--backfill-budget", type=int, default=1)
    parser.add_argument("--min-backfill-fps", type=float, default=50)
    parser.add_argument("--max-backfill-frame-ms", type=float, default=22)
    parser.add_argument("--max-backfill-load", type=float, default=4.5)
    parser.add_argument("--skip-archive-backfill", action="store_true")
    parser.add_argument(
        "--reproject-public",
        action="store_true",
        help="Reconstruit explicitement la projection publique canonique depuis les observations privées.",
    )
    parser.add_argument(
        "--write-full-export",
        action="store_true",
        help="Régénère aussi l'export public complet froid pendant ce passage.",
    )
    parser.add_argument(
        "--full-export-interval",
        type=int,
        default=DEFAULT_FULL_EXPORT_INTERVAL_SECONDS,
        help="Cadence maximale en secondes de l'export complet froid (900 par défaut).",
    )
    args = parser.parse_args()
    if args.recent_limit < 1:
        parser.error("--recent-limit doit être supérieur à zéro")
    if args.full_export_interval < 0:
        parser.error("--full-export-interval ne peut pas être négatif")

    reproject_public = public_reprojection_requested(
        args.reproject_public,
        args.public_reprojection_request,
    )

    connection = connect_database(args.database)
    try:
        if not args.skip_journal:
            collect_journal(connection, args.journal_fixture)
        collect_player_sessions(connection, args.stats)
        settings_events_added = collect_settings_changes(connection, args.stats)
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
        recovery_report["settingsEventsAdded"] = settings_events_added
        bases_payload = load_snapshot(args.bases_snapshot)
        recovery_report["normalizationBackfill"] = normalize_event_history(
            connection,
            bases_payload,
        )
        recovery_report["baseLabelBackfill"] = normalize_base_labels(connection, bases_payload)
        recovery_report["inactiveSaveEventCleanup"] = purge_inactive_save_events(connection, args.stats)
        connection.commit()
        recovery_report["canonicalExport"] = write_export(
            connection,
            args.output,
            args.recent_output,
            args.recent_limit,
            args.stats,
            reproject_public=reproject_public,
            write_full_export=args.write_full_export,
            full_export_interval_seconds=args.full_export_interval,
        )
        recovery_report["canonicalExport"]["reprojectionRequestConsumed"] = (
            consume_public_reprojection_request(
                args.public_reprojection_request,
                recovery_report["canonicalExport"],
                requested=reproject_public,
            )
        )
        write_recovery_report(args.recovery_report, recovery_report)
    finally:
        connection.close()


if __name__ == "__main__":
    main()
