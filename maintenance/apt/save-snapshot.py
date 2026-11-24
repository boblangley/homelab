import fcntl
import json
import os
import re
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path


def index_updates(snapshot):
    updates = {}
    for row in snapshot["updates"]:
        key = row["package"], row["architecture"]
        if key in updates:
            raise ValueError(f"Duplicate package and architecture: {key}")
        updates[key] = row
    return updates


def previous_snapshot(directory, host, now):
    unreadable = []
    for path in sorted(directory.glob("*.json"), reverse=True):
        try:
            snapshot = json.loads(path.read_text(encoding="utf-8"))
            if snapshot["host"] != host:
                raise ValueError("Snapshot host does not match its directory")
            collected_at = datetime.fromisoformat(snapshot["collected_at"])
            if (
                collected_at.utcoffset() != timezone.utc.utcoffset(None)
                or collected_at.isoformat(timespec="microseconds") != path.stem
                or collected_at > now
            ):
                raise ValueError("Snapshot timestamp is invalid or in the future")
            return path, index_updates(snapshot), unreadable
        except (KeyError, OSError, RecursionError, TypeError, ValueError) as error:
            unreadable.append(path.name)
            print(f"Skipping unreadable snapshot {path.name}: {error}", file=sys.stderr)
    return None, {}, unreadable


def save_snapshot(directory, host, revision, snapshot):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", host):
        raise ValueError(f"Invalid host name: {host}")
    if snapshot["host"] != host:
        raise ValueError(f"Snapshot host does not match inventory host {host}")

    current = index_updates(snapshot)
    directory = directory / host
    directory.mkdir(mode=0o700, exist_ok=True)
    with (directory / ".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        now = datetime.now(timezone.utc)
        previous_path, previous, unreadable = previous_snapshot(directory, host, now)
        snapshot["collected_at"] = now.isoformat(timespec="microseconds")
        snapshot["revision"] = revision or None
        snapshot["previous_snapshot"] = previous_path.name if previous_path else None
        snapshot["unreadable_snapshots"] = unreadable
        snapshot["changes"] = {
            "new": [current[key] for key in sorted(current.keys() - previous.keys())],
            "changed": [
                {"previous": previous[key], "current": current[key]}
                for key in sorted(current.keys() & previous.keys())
                if current[key] != previous[key]
            ],
            "no_longer_listed": [previous[key] for key in sorted(previous.keys() - current.keys())],
        }
        destination = directory / f"{snapshot['collected_at']}.json"
        if destination.exists():
            raise ValueError(f"Snapshot already exists for {snapshot['collected_at']}")
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=directory, delete=False) as handle:
                temporary = Path(handle.name)
                json.dump(snapshot, handle, indent=2)
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
            temporary.replace(destination)
        finally:
            if temporary:
                temporary.unlink(missing_ok=True)
        return destination


if __name__ == "__main__":
    print(save_snapshot(Path(sys.argv[1]), sys.argv[2], sys.argv[3], json.load(sys.stdin)))
