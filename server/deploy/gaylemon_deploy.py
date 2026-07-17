#!/usr/bin/env python3
"""Validate and atomically install Gaylemon-managed Ubuntu files."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    import fcntl
    import grp
    import pwd
except ImportError:  # pragma: no cover - deployment runs on Ubuntu.
    fcntl = None
    grp = None
    pwd = None


ALLOWED_DESTINATIONS = (
    re.compile(r"^/srv/storage/steam/bin/[A-Za-z0-9_.-]+$"),
    re.compile(r"^/home/[A-Za-z0-9_.-]+/Gaylemon/server/bin/[A-Za-z0-9_.-]+$"),
    re.compile(r"^/usr/local/sbin/gaylemon-[A-Za-z0-9_.-]+$"),
    re.compile(r"^/etc/systemd/system/(?:palworld|cloudflare-update-dns)[A-Za-z0-9_.@-]*\.(?:service|timer)$"),
    re.compile(r"^/etc/sysctl\.d/[A-Za-z0-9_.-]*palworld[A-Za-z0-9_.-]*\.conf$"),
    re.compile(r"^/etc/sudoers\.d/(?:palworld|gaylemon)[A-Za-z0-9_.-]*$"),
)
VALIDATORS = {"bash", "python", "sudoers", "sysctl", "systemd"}
RESTART_POLICIES = {"none", "recommended", "game"}
LOCK_PATH = Path("/run/lock/gaylemon-deploy.lock")


class DeployError(RuntimeError):
    pass


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def is_allowed_destination(path: str) -> bool:
    return any(pattern.fullmatch(path) for pattern in ALLOWED_DESTINATIONS)


def load_manifest(stage: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    if pwd is None or grp is None:
        raise DeployError("Deployment manifests can only be resolved on a Unix host")
    stage = stage.resolve(strict=True)
    manifest_path = stage / "server" / "deployment-manifest.resolved.json"
    if not manifest_path.is_file() or manifest_path.is_symlink():
        raise DeployError(f"Resolved manifest missing or invalid: {manifest_path}")

    with manifest_path.open("r", encoding="utf-8") as handle:
        manifest = json.load(handle)
    if manifest.get("version") != 1:
        raise DeployError("Unsupported deployment manifest version")
    backup_root = manifest.get("backupRoot")
    if not isinstance(backup_root, str) or not backup_root.startswith("/var/backups/gaylemon-deploy"):
        raise DeployError("Invalid backup root")

    entries: list[dict[str, Any]] = []
    seen_sources: set[str] = set()
    seen_destinations: set[str] = set()
    for raw in manifest.get("entries", []):
        source_name = raw.get("source")
        destination_name = raw.get("destination")
        if not isinstance(source_name, str) or not source_name.startswith("server/"):
            raise DeployError(f"Invalid source in manifest: {source_name!r}")
        if not isinstance(destination_name, str) or not is_allowed_destination(destination_name):
            raise DeployError(f"Destination is outside the allowlist: {destination_name!r}")
        if source_name in seen_sources or destination_name in seen_destinations:
            raise DeployError(f"Duplicate deployment entry: {source_name} -> {destination_name}")

        source = (stage / source_name).resolve(strict=True)
        try:
            source.relative_to(stage)
        except ValueError as exc:
            raise DeployError(f"Source escapes staging directory: {source_name}") from exc
        if not source.is_file() or source.is_symlink():
            raise DeployError(f"Source is not a regular file: {source_name}")

        mode_name = raw.get("mode")
        if not isinstance(mode_name, str) or not re.fullmatch(r"0[0-7]{3}", mode_name):
            raise DeployError(f"Invalid mode for {source_name}: {mode_name!r}")
        validator = raw.get("validation")
        if validator not in VALIDATORS:
            raise DeployError(f"Invalid validator for {source_name}: {validator!r}")
        policy = raw.get("restartPolicy")
        if policy not in RESTART_POLICIES:
            raise DeployError(f"Invalid restart policy for {source_name}: {policy!r}")
        restart_unit = raw.get("restartUnit")
        if restart_unit is not None and (
            not isinstance(restart_unit, str)
            or not re.fullmatch(r"(?:palworld|cloudflare-update-dns)[A-Za-z0-9_.@-]*\.(?:service|timer)", restart_unit)
        ):
            raise DeployError(f"Invalid restart unit for {source_name}: {restart_unit!r}")
        if policy != "none" and not restart_unit:
            raise DeployError(f"Restart policy requires a unit: {source_name}")

        try:
            uid = pwd.getpwnam(str(raw.get("owner"))).pw_uid
            gid = grp.getgrnam(str(raw.get("group"))).gr_gid
        except KeyError as exc:
            raise DeployError(f"Unknown owner or group for {source_name}: {exc}") from exc

        entry = dict(raw)
        entry.update(
            {
                "sourcePath": source,
                "destinationPath": Path(destination_name),
                "modeValue": int(mode_name, 8),
                "uid": uid,
                "gid": gid,
            }
        )
        entries.append(entry)
        seen_sources.add(source_name)
        seen_destinations.add(destination_name)

    if not entries:
        raise DeployError("Deployment manifest is empty")
    return manifest, entries


def run_checked(command: list[str]) -> None:
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        details = (result.stderr or result.stdout).strip()
        raise DeployError(f"Validation failed: {' '.join(command)}\n{details}")


def validate_sources(entries: list[dict[str, Any]]) -> None:
    systemd_sources: list[str] = []
    for entry in entries:
        source = entry["sourcePath"]
        validator = entry["validation"]
        if validator == "bash":
            run_checked(["/usr/bin/bash", "-n", str(source)])
        elif validator == "python":
            try:
                compile(source.read_bytes(), str(source), "exec")
            except SyntaxError as exc:
                raise DeployError(f"Python validation failed for {source}: {exc}") from exc
        elif validator == "sudoers":
            run_checked(["/usr/sbin/visudo", "-cf", str(source)])
        elif validator == "sysctl":
            validate_sysctl(source)
        elif validator == "systemd":
            validate_systemd_structure(source)
            systemd_sources.append(str(source))

    # Full verification follows ExecStart targets and therefore needs root when
    # active scripts are intentionally unreadable by the SSH deployment user.
    if systemd_sources and os.geteuid() == 0:
        run_checked(["/usr/bin/systemd-analyze", "verify", *systemd_sources])


def validate_systemd_structure(path: Path) -> None:
    sections: set[str] = set()
    keys: set[str] = set()
    current_section = ""
    for number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith(("#", ";")):
            continue
        section_match = re.fullmatch(r"\[([A-Za-z][A-Za-z0-9]*)\]", line)
        if section_match:
            current_section = section_match.group(1)
            sections.add(current_section)
            continue
        if not current_section or "=" not in line or not line.split("=", 1)[0].strip():
            raise DeployError(f"Invalid systemd directive in {path}:{number}")
        keys.add(f"{current_section}.{line.split('=', 1)[0].strip()}")

    if "Unit" not in sections:
        raise DeployError(f"Missing [Unit] section in {path}")
    if path.suffix == ".service" and ("Service" not in sections or "Service.ExecStart" not in keys):
        raise DeployError(f"Incomplete service unit: {path}")
    if path.suffix == ".timer" and "Timer" not in sections:
        raise DeployError(f"Incomplete timer unit: {path}")


def validate_sysctl(path: Path) -> None:
    assignment = re.compile(r"^[A-Za-z0-9_.-]+\s*=\s*\S.*$")
    for number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if not assignment.fullmatch(line):
            raise DeployError(f"Invalid sysctl assignment in {path}:{number}")


def inspect_entry(entry: dict[str, Any]) -> dict[str, Any]:
    source = entry["sourcePath"]
    destination = entry["destinationPath"]
    source_hash = sha256(source)
    result: dict[str, Any] = {
        "source": entry["source"],
        "destination": str(destination),
        "sourceSha256": source_hash,
        "status": "create",
        "changed": True,
        "restartUnit": entry.get("restartUnit"),
        "restartPolicy": entry["restartPolicy"],
    }
    if not destination.exists():
        return result
    if destination.is_symlink() or not destination.is_file():
        raise DeployError(f"Active destination is not a regular file: {destination}")

    destination_stat = destination.stat()
    metadata_match = (
        stat.S_IMODE(destination_stat.st_mode) == entry["modeValue"]
        and destination_stat.st_uid == entry["uid"]
        and destination_stat.st_gid == entry["gid"]
    )
    try:
        destination_hash = sha256(destination)
    except PermissionError:
        result.update(
            {
                "status": "protected",
                "changed": None,
                "destinationSha256": None,
                "metadataMatch": metadata_match,
            }
        )
        return result

    changed = source_hash != destination_hash or not metadata_match
    result.update(
        {
            "status": "change" if changed else "unchanged",
            "changed": changed,
            "destinationSha256": destination_hash,
            "metadataMatch": metadata_match,
        }
    )
    return result


def build_plan(entries: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [inspect_entry(entry) for entry in entries]


def print_plan(plan: list[dict[str, Any]], as_json: bool) -> None:
    if as_json:
        print(json.dumps({"entries": plan}, ensure_ascii=False, indent=2))
        return
    for item in plan:
        marker = item["status"].upper()
        print(f"{marker:10} {item['source']} -> {item['destination']}")


def copy_atomically(source: Path, destination: Path, mode: int, uid: int, gid: int) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{destination.name}.", dir=destination.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as output, source.open("rb") as input_handle:
            shutil.copyfileobj(input_handle, output)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, mode)
        os.chown(temporary, uid, gid)
        os.replace(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)


def restore_partial(records: list[dict[str, Any]]) -> None:
    for record in reversed(records):
        destination = Path(record["destination"])
        if record["existed"]:
            copy_atomically(
                Path(record["backup"]),
                destination,
                record["beforeMode"],
                record["beforeUid"],
                record["beforeGid"],
            )
        else:
            destination.unlink(missing_ok=True)


def apply_deployment(
    manifest: dict[str, Any],
    entries: list[dict[str, Any]],
    stage: Path,
    confirmation: str,
    restart_units: list[str],
    allow_game_restart: bool,
) -> Path:
    if os.geteuid() != 0:
        raise DeployError("Installation requires root privileges")
    if confirmation != stage.name:
        raise DeployError("Deployment confirmation does not match the staging release")

    plan = build_plan(entries)
    changed_sources = {item["source"] for item in plan if item["changed"] is True}
    changed_entries = [entry for entry in entries if entry["source"] in changed_sources]
    allowed_restart_units = {
        entry["restartUnit"]: entry["restartPolicy"]
        for entry in entries
        if entry.get("restartUnit")
    }
    for unit in restart_units:
        if unit not in allowed_restart_units:
            raise DeployError(f"Restart is outside the deployment manifest: {unit}")
        if allowed_restart_units[unit] == "game" and not allow_game_restart:
            raise DeployError("palworld.service restart requires --allow-game-restart")

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    backup_directory = Path(manifest["backupRoot"]) / f"{timestamp}-{stage.name}"
    files_directory = backup_directory / "files"
    files_directory.mkdir(parents=True, mode=0o700)
    records: list[dict[str, Any]] = []

    try:
        for entry in changed_entries:
            destination = entry["destinationPath"]
            existed = destination.exists()
            record: dict[str, Any] = {
                "source": entry["source"],
                "destination": str(destination),
                "afterSha256": sha256(entry["sourcePath"]),
                "existed": existed,
                "backup": None,
            }
            if existed:
                if destination.is_symlink() or not destination.is_file():
                    raise DeployError(f"Refusing to replace non-regular destination: {destination}")
                before = destination.stat()
                backup = files_directory / str(destination).lstrip("/")
                backup.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(destination, backup)
                os.chmod(backup, 0o600)
                record.update(
                    {
                        "backup": str(backup),
                        "beforeSha256": sha256(destination),
                        "beforeMode": stat.S_IMODE(before.st_mode),
                        "beforeUid": before.st_uid,
                        "beforeGid": before.st_gid,
                    }
                )
            records.append(record)
            copy_atomically(
                entry["sourcePath"],
                destination,
                entry["modeValue"],
                entry["uid"],
                entry["gid"],
            )
    except Exception:
        restore_partial(records)
        raise

    receipt = {
        "version": 1,
        "installedAt": datetime.now(timezone.utc).isoformat(),
        "stage": str(stage),
        "changedFiles": records,
        "requestedRestarts": restart_units,
        "systemdReloaded": False,
    }
    receipt_path = backup_directory / "receipt.json"
    receipt_path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.chmod(receipt_path, 0o600)

    if any(str(entry["destinationPath"]).startswith("/etc/systemd/system/") for entry in changed_entries):
        run_checked(["/usr/bin/systemctl", "daemon-reload"])
        receipt["systemdReloaded"] = True
        receipt_path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    for unit in restart_units:
        run_checked(["/usr/bin/systemctl", "restart", unit])

    print(f"Receipt: {receipt_path}")
    print(f"Changed files: {len(changed_entries)}")
    suggested_restarts = sorted(
        {
            entry["restartUnit"]
            for entry in changed_entries
            if entry.get("restartUnit") and entry["restartPolicy"] == "recommended"
        }
    )
    if suggested_restarts:
        print(f"Suggested auxiliary restarts: {', '.join(suggested_restarts)}")
    if not restart_units:
        print("No service was restarted.")
    return receipt_path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("plan", "install"))
    parser.add_argument("--stage", required=True, type=Path)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--confirm", default="")
    parser.add_argument("--restart-unit", action="append", default=[])
    parser.add_argument("--allow-game-restart", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    stage = args.stage.resolve(strict=True)
    manifest, entries = load_manifest(stage)
    validate_sources(entries)
    if args.action == "plan":
        print_plan(build_plan(entries), args.json)
        return 0

    if fcntl is None:
        raise DeployError("Installation locking is unavailable on this platform")
    LOCK_PATH.parent.mkdir(parents=True, exist_ok=True)
    with LOCK_PATH.open("w", encoding="utf-8") as lock_handle:
        try:
            fcntl.flock(lock_handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise DeployError("Another Gaylemon deployment is already running") from exc
        apply_deployment(
            manifest,
            entries,
            stage,
            args.confirm,
            args.restart_unit,
            args.allow_game_restart,
        )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (DeployError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
