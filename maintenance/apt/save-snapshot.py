import fcntl
import json
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


def save_snapshot(directory, snapshot):
    host = snapshot["host"]
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", host):
        raise ValueError(f"Invalid host name: {host}")

    current = index_updates(snapshot)
    directory = directory / host
    directory.mkdir(mode=0o700, exist_ok=True)
    with (directory / ".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        previous_path = max(directory.glob("*.json"), default=None)
        previous = index_updates(json.loads(previous_path.read_text())) if previous_path else {}
        snapshot["collected_at"] = datetime.now(timezone.utc).isoformat(timespec="microseconds")
        snapshot["previous_snapshot"] = previous_path.name if previous_path else None
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
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(mode="w", dir=directory, delete=False) as handle:
                temporary = Path(handle.name)
                json.dump(snapshot, handle, indent=2)
                handle.write("\n")
            temporary.replace(destination)
        finally:
            if temporary:
                temporary.unlink(missing_ok=True)
        return destination


if __name__ == "__main__":
    print(save_snapshot(Path(sys.argv[1]), json.load(sys.stdin)))
