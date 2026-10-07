"""Migration adoption and failure safety on a disposable PostgreSQL cluster."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from uuid import uuid4

import psycopg
from psycopg import sql
from psycopg.conninfo import make_conninfo
import pytest

from appchi.migrate import migrate, migration_directory

pytestmark = pytest.mark.integration
ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture
def migration_db():
    admin = os.environ.get("APPCHI_MIGRATION_TEST_ADMIN_URL")
    if not admin:
        pytest.skip("Set APPCHI_MIGRATION_TEST_ADMIN_URL to a disposable PostgreSQL cluster")
    name = "appchi_migration_test_" + uuid4().hex
    with psycopg.connect(admin, autocommit=True) as conn:
        conn.execute(sql.SQL("CREATE DATABASE {}").format(sql.Identifier(name)))
    try:
        yield make_conninfo(admin, dbname=name)
    finally:
        with psycopg.connect(admin, autocommit=True) as conn:
            conn.execute(sql.SQL("DROP DATABASE {} WITH (FORCE)").format(sql.Identifier(name)))


def legacy_install(dsn, through):
    """Reproduce the old runner, including its original ledger timestamps."""
    with psycopg.connect(dsn) as conn:
        conn.execute("SELECT pg_advisory_xact_lock(418003210)")
        conn.execute(
            "CREATE TABLE schema_migrations (name text PRIMARY KEY, checksum text NOT NULL, "
            "applied_at timestamptz NOT NULL DEFAULT clock_timestamp())"
        )
        for path in sorted(migration_directory().glob("*.sql")):
            if path.name[:4] > through:
                break
            raw = path.read_bytes()
            conn.execute(raw.decode(), prepare=False)
            conn.execute(
                "INSERT INTO schema_migrations(name, checksum) VALUES (%s,%s)",
                (path.name, hashlib.sha256(raw).hexdigest()),
            )


def ledger(dsn):
    with psycopg.connect(dsn) as conn:
        return conn.execute("SELECT * FROM schema_migrations ORDER BY name").fetchall()


def cli(dsn, *args):
    return subprocess.run(
        [sys.executable, "-m", "alembic", *args],
        cwd=ROOT,
        env={**os.environ, "APPCHI_MIGRATION_URL": dsn},
        capture_output=True,
        text=True,
        timeout=60,
    )


def assert_head_and_privileges(dsn):
    with psycopg.connect(dsn) as conn:
        assert conn.execute("SELECT version_num FROM alembic_version").fetchall() == [("0050",)]
        for role in ("appchi_api", "appchi_worker"):
            for table in ("schema_migrations", "alembic_version"):
                for privilege in ("SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE"):
                    assert not conn.execute(
                        "SELECT has_table_privilege(%s,%s,%s)", (role, table, privilege)
                    ).fetchone()[0]
        conn.execute("SET LOCAL ROLE appchi_api")
        assert conn.execute("SELECT count(*) FROM alerts").fetchone() == (0,)


def test_fresh_install_and_repeat(migration_db):
    migrate(migration_db)
    before = ledger(migration_db)
    assert len(before) == 47
    migrate(migration_db)
    assert ledger(migration_db) == before
    assert_head_and_privileges(migration_db)


@pytest.mark.parametrize("through", ["0001", "0039", "0046", "0047", "0048", "0049"])
def test_adopt_legacy_without_replaying_sql(migration_db, through):
    legacy_install(migration_db, through)
    before = ledger(migration_db)
    with psycopg.connect(migration_db) as conn:
        conn.execute(
            "INSERT INTO tenants(kind,name,name_key) VALUES('specific','Preserved','preserved')"
        )
    migrate(migration_db)
    assert ledger(migration_db)[: len(before)] == before
    with psycopg.connect(migration_db) as conn:
        assert conn.execute("SELECT name FROM tenants WHERE name_key='preserved'").fetchone() == (
            "Preserved",
        )
    assert_head_and_privileges(migration_db)


@pytest.mark.parametrize("defect", ["checksum", "gap", "unknown"])
def test_invalid_legacy_history_is_not_stamped(migration_db, defect):
    legacy_install(migration_db, "0002")
    with psycopg.connect(migration_db) as conn:
        if defect == "checksum":
            conn.execute("UPDATE schema_migrations SET checksum='tampered'")
        elif defect == "gap":
            conn.execute("DELETE FROM schema_migrations WHERE name='0001_foundation.sql'")
        else:
            conn.execute(
                "INSERT INTO schema_migrations(name,checksum) VALUES('9999_unknown.sql','unknown')"
            )
    with pytest.raises(RuntimeError):
        migrate(migration_db)
    with psycopg.connect(migration_db) as conn:
        assert conn.execute("SELECT to_regclass('alembic_version')").fetchone() == (None,)


@pytest.mark.parametrize("version", ["0046", "9999", None])
def test_alembic_and_checksum_history_must_agree(migration_db, version):
    migrate(migration_db)
    with psycopg.connect(migration_db) as conn:
        if version is None:
            conn.execute("DELETE FROM alembic_version")
        else:
            conn.execute("UPDATE alembic_version SET version_num=%s", (version,))
    with pytest.raises(RuntimeError, match="disagree"):
        migrate(migration_db)


def test_changed_and_missing_sql_rejected(migration_db, tmp_path):
    migrate(migration_db)
    copied = tmp_path / "sql"
    shutil.copytree(migration_directory(), copied)
    target = copied / "0047_api_live_hints.sql"
    target.write_bytes(target.read_bytes() + b"\n-- changed\n")
    with pytest.raises(RuntimeError, match="checksum"):
        migrate(migration_db, copied)
    target.unlink()
    with pytest.raises(RuntimeError, match="absent"):
        migrate(migration_db, copied)


def test_upgrade_failure_rolls_back_adoption_and_pending_sql(migration_db):
    legacy_install(migration_db, "0045")
    before = ledger(migration_db)
    with psycopg.connect(migration_db) as conn:
        conn.execute("ALTER TABLE live_hint_outbox RENAME TO live_hint_outbox_saved")
    with pytest.raises(psycopg.errors.UndefinedTable):
        migrate(migration_db)
    assert ledger(migration_db) == before
    with psycopg.connect(migration_db) as conn:
        assert conn.execute(
            "SELECT to_regclass('alembic_version'),to_regclass('application_scope')"
        ).fetchone() == (None, None)
        conn.execute("ALTER TABLE live_hint_outbox_saved RENAME TO live_hint_outbox")
    migrate(migration_db)
    assert_head_and_privileges(migration_db)


def test_cli_upgrade_current_and_unsupported_mutations(migration_db):
    current = cli(migration_db, "current")
    assert current.returncode == 0, current.stderr
    with psycopg.connect(migration_db) as conn:
        assert conn.execute(
            "SELECT to_regclass('schema_migrations'),to_regclass('alembic_version')"
        ).fetchone() == (None, None)
    upgraded = cli(migration_db, "upgrade", "head")
    assert upgraded.returncode == 0, upgraded.stderr
    assert "0050" in cli(migration_db, "current").stdout
    for args in (("downgrade", "base"), ("stamp", "base"), ("upgrade", "head", "--sql")):
        assert cli(migration_db, *args).returncode != 0
    assert_head_and_privileges(migration_db)


def test_cli_current_does_not_adopt_legacy_history(migration_db):
    legacy_install(migration_db, "0046")
    before = ledger(migration_db)
    result = cli(migration_db, "current")
    assert result.returncode == 0, result.stderr
    assert "Verified legacy revision 0046" in result.stdout
    assert ledger(migration_db) == before
    with psycopg.connect(migration_db) as conn:
        assert conn.execute("SELECT to_regclass('alembic_version')").fetchone() == (None,)
    result = cli(migration_db, "upgrade", "head")
    assert result.returncode == 0, result.stderr
    assert ledger(migration_db)[: len(before)] == before
    assert_head_and_privileges(migration_db)


def test_two_processes_serialize_on_the_existing_lock(migration_db):
    env = {**os.environ, "APPCHI_MIGRATION_URL": migration_db}
    with psycopg.connect(migration_db) as blocker:
        blocker.execute("SELECT pg_advisory_xact_lock(418003210)")
        processes = [
            subprocess.Popen(
                [sys.executable, "-m", "appchi.migrate"],
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            for _ in range(2)
        ]
        try:
            # A bounded server-side wait proves the processes reached the database lock.
            with psycopg.connect(migration_db, autocommit=True) as observer:
                for _ in range(100):
                    waiting = observer.execute(
                        "SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND NOT granted "
                        "AND objid=418003210"
                    ).fetchone()[0]
                    if waiting == 2:
                        break
                    observer.execute("SELECT pg_sleep(0.1)")
                assert waiting == 2
            blocker.commit()
            for process in processes:
                _, stderr = process.communicate(timeout=60)
                assert process.returncode == 0, stderr
        finally:
            for process in processes:
                if process.poll() is None:
                    process.kill()
                    process.communicate(timeout=10)
    assert len(ledger(migration_db)) == 47
    assert_head_and_privileges(migration_db)


def test_scalability_upgrade_preserves_scan_progress_and_adds_safe_nullable_state(migration_db):
    legacy_install(migration_db, "0047")
    tenant = uuid4()
    with psycopg.connect(migration_db) as conn:
        conn.execute("INSERT INTO tenants(id,kind,name,name_key) VALUES(%s,'specific','Scale','scale')", (tenant,))
        conn.execute("INSERT INTO search_reconciliation(index_epoch,tenant_id,boundary_seq) VALUES('scale',%s,99)", (tenant,))
    migrate(migration_db)
    with psycopg.connect(migration_db) as conn:
        assert conn.execute("SELECT boundary_seq,lease_owner,lease_until,retry_after,last_error FROM search_reconciliation WHERE tenant_id=%s", (tenant,)).fetchone() == (99, None, None, None, None)
        assert conn.execute("SELECT floor_seq,full_audit_at,audit_cursor,audit_boundary_seq,audit_started_at,audit_page_at,audit_turns FROM search_reconciliation WHERE tenant_id=%s", (tenant,)).fetchone() == (0, None, None, None, None, None, 0)
        assert conn.execute("SELECT audit_retry_after,audit_last_error FROM search_reconciliation WHERE tenant_id=%s", (tenant,)).fetchone() == (None, None)
        # The actual streaming predicate can use a live-note index even when
        # this small upgrade fixture has no notes. Avoid a full-table fallback.
        conn.execute("SET LOCAL enable_seqscan=off")
        plan = conn.execute("EXPLAIN (FORMAT JSON) SELECT text FROM alert_notes WHERE tenant_id=%s AND alert_id=%s AND NOT deleted ORDER BY id", (tenant, uuid4())).fetchone()[0]
        assert "alert_notes_projection_lookup" in json.dumps(plan)
        assert conn.execute("SELECT is_nullable,data_type FROM information_schema.columns WHERE table_name='maintenance_alert_checkpoints' AND column_name='continuation'").fetchone() == ("YES", "jsonb")
        conn.execute("SET LOCAL ROLE appchi_worker")
        conn.execute("UPDATE search_reconciliation SET lease_owner=%s,lease_until=clock_timestamp()+interval '30 seconds' WHERE tenant_id=%s", (uuid4(), tenant))
    with psycopg.connect(migration_db) as conn:
        with pytest.raises(psycopg.errors.CheckViolation):
            conn.execute("UPDATE search_reconciliation SET lease_owner=NULL WHERE tenant_id=%s", (tenant,))
    with psycopg.connect(migration_db) as conn:
        with pytest.raises(psycopg.errors.CheckViolation):
            conn.execute("UPDATE search_reconciliation SET audit_boundary_seq=99 WHERE tenant_id=%s", (tenant,))
    with psycopg.connect(migration_db) as conn:
        conn.execute("SET LOCAL ROLE appchi_worker")
        conn.execute("UPDATE search_reconciliation SET audit_boundary_seq=99,audit_started_at=clock_timestamp(),audit_turns=4 WHERE tenant_id=%s", (tenant,))
