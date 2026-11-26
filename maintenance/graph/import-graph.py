import filecmp
import json
import sqlite3
import sys
import tempfile
from contextlib import closing
from pathlib import Path


def records(path, fields):
    with path.open() as source:
        for line in source:
            record = json.loads(line)
            yield tuple(record[field] for field in fields)


def import_graph(source, destination):
    with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as handle:
        temporary = Path(handle.name)
    try:
        with closing(sqlite3.connect(temporary)) as db:
            db.execute("PRAGMA foreign_keys = ON")
            with db:
                db.executescript("""
                    BEGIN;
                    CREATE TABLE nodes (
                        id TEXT PRIMARY KEY,
                        name TEXT NOT NULL,
                        kind TEXT NOT NULL
                    ) STRICT;

                    CREATE TABLE dependencies (
                        dependent_id TEXT NOT NULL REFERENCES nodes(id),
                        dependency_id TEXT NOT NULL REFERENCES nodes(id),
                        kind TEXT NOT NULL,
                        reason TEXT NOT NULL CHECK (length(trim(reason)) > 0),
                        PRIMARY KEY (dependent_id, dependency_id, kind),
                        CHECK (dependent_id <> dependency_id)
                    ) STRICT;
                """)
                db.executemany(
                    "INSERT INTO nodes VALUES (?, ?, ?)",
                    records(source / "nodes.jsonl", ("id", "name", "kind")),
                )
                db.executemany(
                    "INSERT INTO dependencies VALUES (?, ?, ?, ?)",
                    records(source / "dependencies.jsonl", ("dependent_id", "dependency_id", "kind", "reason")),
                )
        if destination.exists() and filecmp.cmp(temporary, destination, shallow=False):
            return "Current"
        temporary.replace(destination)
        return "Updated"
    finally:
        temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    print(import_graph(Path(__file__).resolve().parent, Path(sys.argv[1])))
