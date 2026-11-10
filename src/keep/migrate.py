"""Alembic migrations with immutable SQL and verified legacy-history adoption."""

from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path

from alembic import command, op
from alembic.config import Config
from alembic.script import ScriptDirectory
import psycopg
from sqlalchemy import create_engine
from sqlalchemy.pool import NullPool


@dataclass(frozen=True)
class Migration:
    revision: str
    name: str
    checksum: str
    raw: bytes


def migration_directory():
    """SQL and checksum manifest bundled in both the wheel and checkout."""
    return Path(__file__).resolve().parent / "migration_sql"


def alembic_config(directory: Path | None = None):
    config = Config()
    scripts = Path(__file__).resolve().parent / "migration_alembic"
    config.set_main_option("script_location", str(scripts).replace("%", "%%"))
    config.attributes["migration_directory"] = directory or migration_directory()
    return config


def migration_chain(config):
    """Require one linear revision chain with exactly one immutable SQL file per step."""
    scripts = ScriptDirectory.from_config(config)
    if len(scripts.get_heads()) != 1:
        raise RuntimeError("Migrations require exactly one Alembic head")
    directory = Path(config.attributes.get("migration_directory", migration_directory()))
    files = {path.name: path for path in directory.glob("[0-9]*.sql")}
    if not files:
        raise RuntimeError("Migration files are absent from this release")
    checksums = json.loads((migration_directory() / "checksums.json").read_text())
    chain = []
    previous = None
    for step in reversed(list(scripts.walk_revisions())):
        if step.down_revision != previous or step.dependencies or step.branch_labels:
            raise RuntimeError("Migrations must form one ordered Alembic chain")
        name = step.module.sql_file
        if name not in files:
            raise RuntimeError(f"Migration file is absent from this release: {name}")
        if name.split("_", 1)[0] != step.revision:
            raise RuntimeError(f"Migration filename and revision disagree: {name}")
        raw = files[name].read_bytes()
        checksum = hashlib.sha256(raw).hexdigest()
        if checksums.get(name) != checksum:
            raise RuntimeError(f"Migration checksum changed: {name}")
        chain.append(Migration(step.revision, name, checksum, raw))
        previous = step.revision
    names = [step.name for step in chain]
    if names != sorted(files) or set(names) != set(checksums):
        raise RuntimeError("SQL files, checksum manifest and Alembic revisions disagree")
    return chain


def table_exists(connection, name):
    return (
        connection.exec_driver_sql("SELECT to_regclass(%s)", ("public." + name,)).scalar()
        is not None
    )


def verified_history(connection, chain):
    if not table_exists(connection, "schema_migrations"):
        return []
    applied = dict(connection.exec_driver_sql("SELECT name, checksum FROM schema_migrations").all())
    known = {step.name: step for step in chain}
    if set(applied) - known.keys():
        raise RuntimeError("An applied migration is absent from this release")
    for name, checksum in applied.items():
        if checksum != known[name].checksum:
            raise RuntimeError(f"Migration checksum changed: {name}")
    prefix = chain[: len(applied)]
    if set(applied) != {step.name for step in prefix}:
        raise RuntimeError(
            "Migration history has a gap or a new migration predates an applied migration"
        )
    return prefix


def verify_head(migration_context, applied):
    expected = (applied[-1].revision,) if applied else ()
    if migration_context.get_current_heads() != expected:
        raise RuntimeError("Alembic revision and checksum history disagree")


def apply_sql(name):
    """Execute reviewed SQL without rewriting percent signs, binds or PL/pgSQL bodies."""
    migration = op.get_context().opts["keep_migrations"][name]
    connection = op.get_bind()
    with connection.connection.driver_connection.cursor() as cursor:
        cursor.execute(migration.raw.decode("utf-8"), prepare=False)
    connection.exec_driver_sql(
        "INSERT INTO schema_migrations (name, checksum) VALUES (%s,%s)",
        (migration.name, migration.checksum),
    )


def run_environment(context):
    """Use the same lock and transaction for adoption, SQL, ledger and Alembic version."""
    config = context.config
    action = config.attributes.get("action")
    if action is None and config.cmd_opts is not None:
        action = config.cmd_opts.cmd[0].__name__
    if context.is_offline_mode() or action not in {"upgrade", "current"}:
        raise RuntimeError(
            "Use online upgrade or current; stamp, downgrade and offline SQL are unsupported"
        )
    chain = migration_chain(config)
    dsn = config.attributes.get("dsn") or os.environ["KEEP_MIGRATION_URL"]
    engine = create_engine(
        "postgresql+psycopg://",
        creator=lambda: psycopg.connect(dsn),
        poolclass=NullPool,
    )
    try:
        with engine.begin() as connection:
            connection.exec_driver_sql("SET LOCAL search_path TO public")
            connection.exec_driver_sql("SELECT pg_advisory_xact_lock(418003210)")
            context.configure(
                connection=connection,
                target_metadata=None,
                version_table_schema="public",
                keep_migrations={step.name: step for step in chain},
            )
            migration_context = context.get_context()
            applied = verified_history(connection, chain)
            legacy = bool(applied) and not table_exists(connection, "alembic_version")
            if not legacy:
                verify_head(migration_context, applied)
            if action == "current":
                if legacy:
                    config.print_stdout(
                        "Verified legacy revision %s; run upgrade head to adopt it.",
                        applied[-1].revision,
                    )
                context.run_migrations()
                return
            connection.exec_driver_sql(
                "CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, "
                "checksum text NOT NULL, applied_at timestamptz NOT NULL DEFAULT clock_timestamp())"
            )
            if legacy:
                migration_context.stamp(ScriptDirectory.from_config(config), applied[-1].revision)
            context.run_migrations()
            verify_head(migration_context, verified_history(connection, chain))
            # Foundation grants all existing tables. Neither ledger may inherit those grants.
            connection.exec_driver_sql(
                "REVOKE ALL ON schema_migrations, alembic_version FROM PUBLIC, keep_api, keep_worker"
            )
    finally:
        engine.dispose()


def migrate(dsn: str, directory: Path | None = None):
    config = alembic_config(directory)
    config.attributes.update(dsn=dsn, action="upgrade")
    command.upgrade(config, "head")


def main():
    migrate(os.environ["KEEP_MIGRATION_URL"])


if __name__ == "__main__":
    main()
