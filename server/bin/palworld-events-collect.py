#!/usr/bin/env python3
"""Collect privacy-safe Palworld events from journald and save snapshots."""

from __future__ import annotations

import argparse
import base64
import binascii
import gzip
import json
import re
import sqlite3
import subprocess
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path


DEFAULT_DATABASE = Path("/home/gaylemon/Gaylemon/runtime/events/palworld-events.sqlite3")
DEFAULT_OUTPUT = Path("/home/gaylemon/Gaylemon/runtime/public-events.json")
DEFAULT_SNAPSHOT = Path("/home/gaylemon/Gaylemon/runtime/public-save-snapshot.json")
DEFAULT_HISTORY = Path("/home/gaylemon/Gaylemon/runtime/save-snapshot-history")
DEFAULT_STATS = Path("/srv/storage/steam/servers/palworld/stats/stats.json")
DEFAULT_RECOVERY_REPORT = Path(
    "/home/gaylemon/Gaylemon/runtime/events/palworld-events-recovery.json"
)

JOIN_RE = re.compile(r"\] \[LOG\] (?P<player>.+?) joined the server\.")
LEAVE_RE = re.compile(r"\] \[LOG\] (?P<player>.+?) left the server\.")
SESSION_EVENT_TOLERANCE_SECONDS = 60
RECONNECT_WINDOW_SECONDS = 120
JOURNAL_UNITS = ("palworld.service", "palworld-update.service")
STRUCTURED_EVENT_PREFIX = "GAYLEMON_EVENT"
EVENT_TYPE_RE = re.compile(r"^[a-z][a-z0-9_-]{0,31}$")


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
            title TEXT NOT NULL,
            message TEXT NOT NULL,
            icon TEXT,
            source TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS events_occurred_at_idx
            ON events(occurred_at DESC, id DESC);
        CREATE TABLE IF NOT EXISTS metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """
    )
    return connection


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
    icon: str | None = None,
    source: str,
) -> None:
    connection.execute(
        """
        INSERT OR IGNORE INTO events(
            fingerprint, occurred_at, type, player, title, message, icon, source
        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (fingerprint, occurred_at, event_type, player, title, message, icon, source),
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

    players = payload.get("players") or {}
    if not isinstance(players, dict):
        return 0

    added = 0
    for player_key, record in players.items():
        if not isinstance(record, dict):
            continue
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


def public_event(row: sqlite3.Row) -> dict:
    return {
        "id": int(row["id"]),
        "occurredAt": row["occurred_at"],
        "type": row["type"],
        "player": row["player"],
        "title": row["title"],
        "message": row["message"],
        "icon": row["icon"],
        "source": row["source"],
    }


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
    suppressed_ids = set()
    reconnect_ids = set()

    for event in chronological:
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
        reconciled.append(event)
    return reconciled, len(reconnect_ids)


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


def snapshot_state(payload: dict) -> dict:
    players = {}
    for player in payload.get("players") or []:
        if not isinstance(player, dict):
            continue
        state = snapshot_player_state(player)
        players[state["name"].casefold()] = state
    return {"players": players}


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
        catalog[name.casefold()] = {"name": name, "icon": row.get("icon")}
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


def positive_catalog_changes(current: dict, previous: dict) -> list[dict]:
    changes = []
    for key, row in current.items():
        count = int(row.get("count") or 0)
        old_count = int((previous.get(key) or {}).get("count") or 0)
        if count > old_count:
            changes.append({**row, "added": count - old_count, "isNew": old_count == 0})
    return sorted(changes, key=lambda row: str(row.get("name") or "").casefold())


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
                fingerprint=f"save:{occurred_at}:capture:{key}:{species_key}:{count}",
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
                fingerprint=f"save:{occurred_at}:capture-challenge:{key}:{species_key}:{target}",
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


def compare_snapshots(
    connection: sqlite3.Connection,
    previous: dict,
    current: dict,
    occurred_at: str,
    known_players: set[str],
) -> None:
    old_players = previous.get("players") or {}
    new_players = current.get("players") or {}

    for key, player in new_players.items():
        old = old_players.get(key)
        name = player["name"]
        if old is None:
            if key not in known_players:
                add_event(
                    connection,
                    fingerprint=f"save:{occurred_at}:new-player:{key}",
                    occurred_at=occurred_at,
                    event_type="discovery",
                    player=name,
                    title="Nouvel aventurier",
                    message=f"{name} laisse sa première trace dans les chroniques.",
                    source="save",
                )
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

        compare_enriched_progress(connection, old, player, occurred_at, key)

        if player["level"] > old["level"]:
            add_event(
                connection,
                fingerprint=f"save:{occurred_at}:level:{key}:{player['level']}",
                occurred_at=occurred_at,
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
                fingerprint=f"save:{occurred_at}:pals:{key}:{player['pals']}",
                occurred_at=occurred_at,
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
            if quest_delta > 0:
                achievements.append(f"{quest_delta} {plural(quest_delta, 'quête')} terminée{'' if quest_delta == 1 else 's'}")
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
            add_event(
                connection,
                fingerprint=f"save:{occurred_at}:progress:{key}:{player['quests']}:{player['technologies']}",
                occurred_at=occurred_at,
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
            boss_names = french_list([boss["name"] for boss in new_bosses])
            message = (
                f"{name} triomphe de {boss_names}."
                if boss_names and len(new_bosses) == boss_delta
                else f"{name} remporte {boss_delta} nouveau{'' if boss_delta == 1 else 'x'} combat{'' if boss_delta == 1 else 's'} de boss."
            )
            if boss_names and len(new_bosses) != boss_delta:
                message += f" Adversaire{'' if len(new_bosses) == 1 else 's'} identifié{'' if len(new_bosses) == 1 else 's'}: {boss_names}."
            add_event(
                connection,
                fingerprint=f"save:{occurred_at}:boss:{key}:{player['bosses']}",
                occurred_at=occurred_at,
                event_type="discovery",
                player=name,
                title="Boss vaincu",
                message=message,
                icon=new_bosses[0].get("icon") if new_bosses else None,
                source="save",
            )

        new_fast_travel = sorted(
            set(player["fastTravel"]) - set(old.get("fastTravel") or []),
            key=str.casefold,
        )
        if new_fast_travel:
            add_event(
                connection,
                fingerprint=f"save:{occurred_at}:travel:{key}:{len(player['fastTravel'])}",
                occurred_at=occurred_at,
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
                fingerprint=f"save:{occurred_at}:relics:{key}:{sum(item['rank'] for item in player['relicRanks'].values())}",
                occurred_at=occurred_at,
                event_type="progress",
                player=name,
                title="Pouvoir renforcé",
                message=f"{name} améliore {french_list(relic_changes)}.",
                source="save",
            )

        if player["campLevel"] > old["campLevel"]:
            add_event(
                connection,
                fingerprint=f"save:{occurred_at}:camp:{key}:{player['campLevel']}",
                occurred_at=occurred_at,
                event_type="camp",
                player=name,
                title="Camp amélioré",
                message=f"Le camp de {name} atteint le niveau {player['campLevel']}.",
                source="save",
            )
        elif player["bases"] > old["bases"]:
            add_event(
                connection,
                fingerprint=f"save:{occurred_at}:bases:{key}:{player['bases']}",
                occurred_at=occurred_at,
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
    for occurred_at, payload in sorted(
        candidates.items(),
        key=lambda item: parse_timestamp(item[0]) or datetime.min.replace(tzinfo=timezone.utc),
    ):
        current = snapshot_state(payload)
        if previous is not None:
            for key, player in current["players"].items():
                old = (previous.get("players") or {}).get(key)
                if old is not None:
                    compare_enriched_progress(
                        connection,
                        old,
                        player,
                        occurred_at,
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


def collect_snapshots(
    connection: sqlite3.Connection,
    snapshot_path: Path,
    history_path: Path,
) -> dict:
    previous = metadata_get(connection, "save_state")
    previous_last_save_at = str(metadata_get(connection, "last_save_at", ""))
    last_save_at = previous_last_save_at
    last_save_timestamp = parse_timestamp(last_save_at)
    known_players = set(metadata_get(connection, "known_players", []))
    events_before = int(connection.execute("SELECT COUNT(*) FROM events").fetchone()[0])

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
        current = snapshot_state(payload)
        if previous is None:
            known_players.update(current["players"].keys())
        else:
            compare_snapshots(connection, previous, current, occurred_at, known_players)
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


def write_recovery_report(output: Path, payload: dict) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".tmp")
    temporary.write_text(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    temporary.replace(output)


def write_export(connection: sqlite3.Connection, output: Path) -> None:
    rows = connection.execute(
        """
        SELECT id, occurred_at, type, player, title, message, icon, source
        FROM events
        ORDER BY occurred_at DESC, id DESC
        """
    ).fetchall()
    events, reconnects = reconcile_public_events(rows)
    counts = Counter(event["type"] for event in events)
    max_id = max((int(row["id"]) for row in rows), default=0)
    payload = {
        "version": 2,
        "ok": True,
        "revision": f"2:{len(events)}:{max_id}",
        "updatedAt": now_iso(),
        "summary": {
            "events": len(events),
            "firstAt": events[-1]["occurredAt"] if events else None,
            "lastAt": events[0]["occurredAt"] if events else None,
            "types": dict(sorted(counts.items())),
            "reconciledReconnects": reconnects,
        },
        "events": events,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    temporary.replace(output)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", type=Path, default=DEFAULT_DATABASE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--snapshot", type=Path, default=DEFAULT_SNAPSHOT)
    parser.add_argument("--history", type=Path, default=DEFAULT_HISTORY)
    parser.add_argument("--stats", type=Path, default=DEFAULT_STATS)
    parser.add_argument("--recovery-report", type=Path, default=DEFAULT_RECOVERY_REPORT)
    parser.add_argument("--journal-fixture", type=Path)
    parser.add_argument("--skip-journal", action="store_true")
    args = parser.parse_args()

    connection = connect_database(args.database)
    try:
        if not args.skip_journal:
            collect_journal(connection, args.journal_fixture)
        collect_player_sessions(connection, args.stats)
        capture_backfill = backfill_capture_history(connection, args.snapshot, args.history)
        recovery_report = collect_snapshots(connection, args.snapshot, args.history)
        recovery_report["captureBackfill"] = capture_backfill
        write_recovery_report(args.recovery_report, recovery_report)
        write_export(connection, args.output)
        connection.commit()
    finally:
        connection.close()


if __name__ == "__main__":
    main()
