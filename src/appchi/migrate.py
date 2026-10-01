"""Ordered, checksum-verified SQL migrations; run using a dedicated migration identity."""

import hashlib
import os
from pathlib import Path

import psycopg


def migrate(dsn: str, directory: Path):
    files = sorted(directory.glob("[0-9]*.sql"))
    if not files:
        raise RuntimeError("Migration files are absent from this release")
    with psycopg.connect(dsn) as conn:
        conn.execute("SELECT pg_advisory_xact_lock(418003210)")
        conn.execute(
            "CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, checksum text NOT NULL, applied_at timestamptz NOT NULL DEFAULT clock_timestamp())"
        )
        applied = dict(conn.execute("SELECT name, checksum FROM schema_migrations").fetchall())
        if set(applied) - {file.name for file in files}:
            raise RuntimeError("An applied migration is absent from this release")
        for file in files:
            raw = file.read_bytes()
            checksum = hashlib.sha256(raw).hexdigest()
            if file.name in applied:
                if applied[file.name] != checksum:
                    raise RuntimeError(f"Migration checksum changed: {file.name}")
                continue
            if applied and file.name < max(applied):
                raise RuntimeError("A new migration predates an applied migration")
            conn.execute(raw.decode("utf-8"), prepare=False)
            conn.execute(
                "INSERT INTO schema_migrations (name, checksum) VALUES (%s,%s)",
                (file.name, checksum),
            )


def main():
    migrate(os.environ["APPCHI_MIGRATION_URL"], Path(__file__).resolve().parents[2] / "migrations")


if __name__ == "__main__":
    main()
