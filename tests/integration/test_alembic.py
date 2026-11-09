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
        assert conn.execute("SELECT version_num FROM alembic_version").fetchall() == [("0065",)]
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
    assert len(before) == 62
    migrate(migration_db)
    assert ledger(migration_db) == before
    assert_head_and_privileges(migration_db)


@pytest.mark.parametrize("through", ["0001", "0039", "0046", "0047", "0048", "0049", "0050", "0051", "0052", "0053", "0054", "0055", "0056", "0057", "0058", "0059", "0060", "0061", "0062", "0063", "0064"])
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
    assert "0065" in cli(migration_db, "current").stdout
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
    assert len(ledger(migration_db)) == 62
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


def test_source_assignment_catch_up_reads_only_unconfirmed_results(migration_db):
    legacy_install(migration_db, "0050")
    tenant, topic = uuid4(), "appchi.test.alerts.received"
    with psycopg.connect(migration_db) as conn:
        conn.execute("INSERT INTO tenants(id,kind,name,name_key) VALUES(%s,'specific','Source','source')", (tenant,))
        conn.execute("SET LOCAL ROLE appchi_worker")
        # Retained history from before the upgrade; the last ten inputs lost confirmation.
        conn.execute(
            "INSERT INTO kafka_source_results(delivery_id,tenant_id,topic,partition,input_offset,input_digest,received_at,outcome,kafka_confirmed) "
            "SELECT gen_random_uuid(),%s,%s,0,n,decode('00','hex'),clock_timestamp(),'applied',n<20000 FROM generate_series(0,20009) n",
            (tenant, topic),
        )
    migrate(migration_db)
    # The processor's assignment statement, below a committed offset of 20005.
    catch_up = "UPDATE kafka_source_results SET kafka_confirmed=true WHERE topic=%s AND partition=%s AND input_offset<%s AND NOT kafka_confirmed"
    with psycopg.connect(migration_db) as conn:
        conn.execute("ANALYZE kafka_source_results")
        conn.execute("SET LOCAL ROLE appchi_worker")
        plan = conn.execute("EXPLAIN (FORMAT JSON) " + catch_up, (topic, 0, 20005)).fetchone()[0]
        assert "kafka_source_results_unconfirmed" in json.dumps(plan)
        assert conn.execute(catch_up, (topic, 0, 20005)).rowcount == 5
        assert conn.execute("SELECT array_agg(input_offset ORDER BY input_offset) FROM kafka_source_results WHERE NOT kafka_confirmed").fetchone() == ([20005, 20006, 20007, 20008, 20009],)


def plan_nodes(node):
    yield node
    for child in node.get("Plans", ()):
        yield from plan_nodes(child)


def test_search_retention_probe_reads_only_pending_retirements(migration_db):
    legacy_install(migration_db, "0051")
    tenant, other = uuid4(), uuid4()
    with psycopg.connect(migration_db) as conn:
        for name, key in ((tenant, "probe"), (other, "other")):
            conn.execute("INSERT INTO tenants(id,kind,name,name_key) VALUES(%s,'specific',%s,%s)", (name, key, key))
            conn.execute("INSERT INTO tenant_view_state(tenant_id) VALUES(%s) ON CONFLICT DO NOTHING", (name,))
            conn.execute("UPDATE tenant_view_state SET searchable_seq=20000 WHERE tenant_id=%s", (name,))
        conn.execute("SET LOCAL ROLE appchi_worker")
        # Kafka-first projection history: no row ever becomes visible. Every 40th
        # row is an already-searchable retirement; the rest are live.
        conn.execute(
            "INSERT INTO projection_work(tenant_id,seq,alert_id,version,snapshot) "
            "SELECT t,n,gen_random_uuid(),1,jsonb_build_object('live',n%%40<>0,'deleted',false) "
            "FROM unnest(%s::uuid[]) t, generate_series(1,20000) n",
            ([tenant, other],),
        )
    migrate(migration_db)
    # The feed's probe from appchi-api search_routes.py.
    probe = (
        "SELECT clock_timestamp() AS now,EXISTS(SELECT 1 FROM projection_work WHERE tenant_id=%(tenant)s"
        " AND seq>(SELECT searchable_seq FROM tenant_view_state WHERE tenant_id=%(tenant)s)"
        " AND NOT visible AND (snapshot->>'live'='false' OR snapshot->>'deleted'='true')) AS pending"
    )
    with psycopg.connect(migration_db) as conn:
        conn.execute("ANALYZE projection_work")
        conn.execute("ANALYZE tenant_view_state")
        conn.execute("SET LOCAL ROLE appchi_api")
        conn.execute("SELECT set_config('appchi.tenant_id',%s,true)", (str(tenant),))
        # Planner choice between index paths is what is asserted, not scan costs.
        conn.execute("SET LOCAL enable_seqscan = off")
        conn.execute("SET LOCAL enable_bitmapscan = off")
        plan = conn.execute("EXPLAIN (FORMAT JSON) " + probe, {"tenant": tenant}).fetchone()[0]
        scans = [
            node
            for node in plan_nodes(plan[0]["Plan"])
            if node.get("Index Name") == "projection_work_retirement_pending"
            and "seq >" in node.get("Index Cond", "")  # starts past searchable_seq
        ]
        assert scans, json.dumps(plan)
        assert conn.execute(probe, {"tenant": tenant}).fetchone()[1] is False
        conn.execute(
            "INSERT INTO projection_work(tenant_id,seq,alert_id,version,snapshot) "
            "VALUES(%s,20001,gen_random_uuid(),2,'{\"live\":false,\"deleted\":false}')",
            (tenant,),
        )
        assert conn.execute(probe, {"tenant": tenant}).fetchone()[1] is True


def test_always_on_upgrade_removes_gates_and_restarts_blocked_rules(migration_db):
    """Requirements: REV-39; correlation rules 6."""
    legacy_install(migration_db, "0052")
    tenant, actor = uuid4(), uuid4()
    blocked, healthy, deleted = uuid4(), uuid4(), uuid4()
    with psycopg.connect(migration_db) as conn:
        conn.execute("INSERT INTO tenants(id,kind,name,name_key) VALUES(%s,'specific','Rules','rules')", (tenant,))
        conn.execute("INSERT INTO tenant_work_state(tenant_id,admission_order) VALUES(%s,7)", (tenant,))
        for rule, health, reason, gone in (
            (blocked, "blocked", "consumer_not_integrated", None),
            (healthy, "healthy", None, None),
            (deleted, "blocked", "consumer_not_integrated", "2026-10-01T00:00:00Z"),
        ):
            conn.execute("INSERT INTO correlation_rule_identities(id,tenant_id) VALUES(%s,%s)", (rule, tenant))
            conn.execute(
                """INSERT INTO correlation_rules(id,tenant_id,revision,epoch,grouping_generation,name,name_key,name_profile,
                description,severity,window_minutes,group_by,enabled,health,blocked_reason,last_reset_reason,profile,
                evaluation_cost,epoch_boundary_at,epoch_boundary_order,created_at,updated_at,created_by,updated_by,deleted_at)
                VALUES(%s,%s,1,1,1,%s,%s,'nfc','','medium',10,'[]',true,%s,%s,'created','cel',1,
                '2026-10-01T00:00:00Z',3,'2026-10-01T00:00:00Z','2026-10-01T00:00:00Z',%s,%s,%s)""",
                (rule, tenant, str(rule), str(rule), health, reason, actor, actor, gone),
            )
    migrate(migration_db)
    with psycopg.connect(migration_db) as conn:
        assert conn.execute(
            "SELECT capability FROM capability_gates WHERE capability IN ('correlation','maintenance')"
        ).fetchall() == []
        assert conn.execute("SELECT admission_order FROM tenant_work_state WHERE tenant_id=%s", (tenant,)).fetchone() == (8,)
        rows = {
            row[0]: row[1:]
            for row in conn.execute(
                "SELECT id,epoch,health,blocked_reason,last_reset_reason,epoch_boundary_order,epoch_boundary_at>created_at FROM correlation_rules"
            )
        }
        assert rows[blocked] == (2, "healthy", None, "always_on", 8, True)
        assert rows[healthy] == (1, "healthy", None, "created", 3, False)
        assert rows[deleted] == (1, "blocked", "consumer_not_integrated", "created", 3, False)


def test_topic_identity_upgrade_leaves_an_existing_cutover_unrecorded(migration_db):
    """Requirements: REV-41; Kafka alert pipeline 8."""
    legacy_install(migration_db, "0053")
    with psycopg.connect(migration_db) as conn:
        conn.execute("UPDATE kafka_pipeline_control SET enabled=true,received_partitions=1,changed_partitions=1")
    migrate(migration_db)
    with psycopg.connect(migration_db) as conn:
        assert conn.execute(
            "SELECT enabled,received_topic_id,changed_topic_id FROM kafka_pipeline_control"
        ).fetchone() == (True, None, None)
        # Kafka's topic ID text: 22 characters of unpadded URL-safe base64.
        conn.execute(
            "UPDATE kafka_pipeline_control SET received_topic_id='YnmTZeuHT_iG2FXpjd3lUQ',changed_topic_id='XvLjZHK5QdW5sr9DukPJTg'"
        )
        for invalid in ("/////+uHT/j/////jd3lUQ", "YnmTZeuHT_iG2FXpjd3lUQ==", ""):
            with pytest.raises(psycopg.errors.CheckViolation), conn.transaction():
                conn.execute("UPDATE kafka_pipeline_control SET received_topic_id=%s", (invalid,))


def test_incident_report_reads_use_period_and_assignment_indexes(migration_db):
    """Requirements: REV-53; incident operations 20; N3; reliability operations 5."""
    legacy_install(migration_db, "0057")
    tenant = uuid4()
    seed = (
        "SELECT n,timestamptz '2026-01-01 00:00:00+00' + n * interval '3 hours' AS t FROM generate_series(1,2000) n"
    )
    with psycopg.connect(migration_db) as conn:
        conn.execute("INSERT INTO tenants(id,kind,name,name_key) VALUES(%s,'specific','Reports','reports')", (tenant,))
        conn.execute(
            "INSERT INTO incident_identities(id,tenant_id) SELECT md5('i'||n)::uuid,%s FROM generate_series(1,2000) n",
            (tenant,),
        )
        conn.execute(
            "INSERT INTO incidents(id,tenant_id,title,description,severity,status,origin,cycle_id,created_at,updated_at,last_activity,resolved_at) "
            "SELECT md5('i'||n)::uuid,%s,'Incident '||n,'',(ARRAY['critical','high','medium','low'])[1+n%%4],'resolved','manual',"
            f"md5('c'||n)::uuid,t,t,t+interval '1 hour',t+interval '1 hour' FROM ({seed}) s",
            (tenant,),
        )
        conn.execute(
            "INSERT INTO incident_cycles(tenant_id,incident_id,id,opened_at,resolved_at,cause) "
            f"SELECT %s,md5('i'||n)::uuid,md5('c'||n)::uuid,t,t+interval '1 hour','manual' FROM ({seed}) s",
            (tenant,),
        )
        # Each incident has twenty link entries and one assignment in its activity.
        conn.execute(
            "INSERT INTO incident_activity(tenant_id,incident_id,id,kind,recorded_at,evidence) "
            "SELECT %s,md5('i'||n)::uuid,gen_random_uuid(),CASE WHEN k=1 THEN 'assignment' ELSE 'link' END,"
            f"t+k*interval '1 minute','{{}}'::jsonb FROM ({seed}) s,generate_series(1,20) k",
            (tenant,),
        )
    migrate(migration_db)
    reads = {
        "incident_cycles_tenant_opened": "SELECT count(*) FROM incident_cycles WHERE tenant_id=%(tenant)s AND opened_at>=%(start)s AND opened_at<%(end)s",
        "incident_cycles_tenant_resolved": "SELECT count(*) FROM incident_cycles WHERE tenant_id=%(tenant)s AND resolved_at>=%(start)s AND resolved_at<%(end)s",
        "incident_activity_assignee": (
            "SELECT recorded_at FROM incident_activity WHERE incident_id=%(incident)s AND kind IN ('assignment','eligibility_lost') "
            "AND recorded_at<=%(end)s ORDER BY recorded_at DESC LIMIT 1"
        ),
    }
    params = {"tenant": tenant, "start": "2026-03-01T00:00:00Z", "end": "2026-04-01T00:00:00Z", "incident": None}
    with psycopg.connect(migration_db) as conn:
        params["incident"] = conn.execute("SELECT md5('i'||500)::uuid").fetchone()[0]
        leaves = {
            name: {row[0] for row in conn.execute("SELECT relid::regclass::text FROM pg_partition_tree(%s) WHERE isleaf", (name,))}
            for name in reads
        }
        assert all(len(found) == 32 for found in leaves.values()), leaves
        conn.execute("ANALYZE incident_cycles")
        conn.execute("ANALYZE incident_activity")
        conn.execute("SET LOCAL ROLE appchi_api")
        conn.execute("SELECT set_config('appchi.tenant_id',%s,true)", (str(tenant),))
        # The planner's choice of index path is asserted, not scan costs.
        conn.execute("SET LOCAL enable_seqscan = off")
        conn.execute("SET LOCAL enable_bitmapscan = off")
        for name, read in reads.items():
            plan = conn.execute("EXPLAIN (FORMAT JSON) " + read, params).fetchone()[0]
            used = {node.get("Index Name") for node in plan_nodes(plan[0]["Plan"])} - {None}
            assert used and used <= leaves[name], json.dumps(plan)
            assert not any("Seq Scan" == node.get("Node Type") for node in plan_nodes(plan[0]["Plan"])), json.dumps(plan)
        assert conn.execute(reads["incident_cycles_tenant_opened"], params).fetchone() == (248,)
        assert conn.execute(reads["incident_activity_assignee"], params).fetchone() is not None


def test_panel_types_keep_existing_panels_as_counts(migration_db):
    """Requirements: REV-57; dashboard operations 2, 5 and 13."""
    legacy_install(migration_db, "0061")
    tenant, actor, preset, board, old = uuid4(), uuid4(), uuid4(), uuid4(), uuid4()
    with psycopg.connect(migration_db) as conn:
        conn.execute("INSERT INTO tenants(id,kind,name,name_key) VALUES(%s,'specific','Panels','panels')", (tenant,))
        conn.execute(
            "INSERT INTO presets(id,tenant_id,name,name_key,cel,profile,sort,columns,created_at,updated_at,created_by,updated_by) "
            "VALUES(%s,%s,'All','all','true','v1','[]','[]',now(),now(),%s,%s)",
            (preset, tenant, actor, actor),
        )
        conn.execute(
            "INSERT INTO dashboards(id,tenant_id,name,name_key,created_at,updated_at,created_by,updated_by) "
            "VALUES(%s,%s,'Board','board',now(),now(),%s,%s)",
            (board, tenant, actor, actor),
        )
        conn.execute(
            "INSERT INTO dashboard_panels(id,tenant_id,dashboard_id,preset_id,x,y,w,h,thresholds) "
            "VALUES(%s,%s,%s,%s,0,0,3,2,'[]')",
            (old, tenant, board, preset),
        )
    migrate(migration_db)
    insert = (
        "INSERT INTO dashboard_panels(id,tenant_id,dashboard_id,preset_id,x,y,w,h,thresholds,type,content) "
        "VALUES(%s,%s,%s,%s,3,0,3,2,%s,%s,%s)"
    )
    with psycopg.connect(migration_db) as conn:
        assert conn.execute(
            "SELECT type,content FROM dashboard_panels WHERE id=%s", (old,)
        ).fetchone() == ("count", {})
        # An older API names neither new column and still writes a count panel.
        conn.execute(
            "INSERT INTO dashboard_panels(id,tenant_id,dashboard_id,preset_id,x,y,w,h,thresholds) "
            "VALUES(%s,%s,%s,%s,6,0,3,2,'[]')",
            (uuid4(), tenant, board, preset),
        )
        conn.execute(insert, (uuid4(), tenant, board, None, "[]", "html", json.dumps({"html": "<p>Hi</p>"})))
        for preset_id, thresholds, kind, content in (
            (None, "[]", "count", "{}"),
            (preset, "[]", "html", json.dumps({"html": "<p>Hi</p>"})),
            (None, '[{"lower_bound":"1","color":"red"}]', "html", json.dumps({"html": ""})),
            (None, "[]", "html", "{}"),
            (None, "[]", "html", json.dumps({"html": 3})),
            (None, "[]", "chart", "{}"),
            (preset, "[]", "count", "[]"),
        ):
            with pytest.raises(psycopg.errors.CheckViolation), conn.transaction():
                conn.execute(insert, (uuid4(), tenant, board, preset_id, thresholds, kind, content))


def test_image_panels_reference_tenant_images(migration_db):
    """Requirements: REV-62; dashboard operations 2 and 13."""
    legacy_install(migration_db, "0062")
    tenant, other, actor, board = uuid4(), uuid4(), uuid4(), uuid4()
    with psycopg.connect(migration_db) as conn:
        for key, name in ((tenant, "images"), (other, "other")):
            conn.execute("INSERT INTO tenants(id,kind,name,name_key) VALUES(%s,'specific',%s,%s)", (key, name, name))
        conn.execute(
            "INSERT INTO dashboards(id,tenant_id,name,name_key,created_at,updated_at,created_by,updated_by) "
            "VALUES(%s,%s,'Board','board',now(),now(),%s,%s)",
            (board, tenant, actor, actor),
        )
    migrate(migration_db)
    image, foreign = uuid4(), uuid4()
    upload = (
        "INSERT INTO dashboard_images(id,tenant_id,sha256,media_type,width,height,byte_size,bytes,created_at,created_by) "
        "VALUES(%s,%s,%s,%s,%s,%s,%s,%s,now(),%s)"
    )
    insert = (
        "INSERT INTO dashboard_panels(id,tenant_id,dashboard_id,preset_id,x,y,w,h,thresholds,type,content,image_id) "
        "VALUES(%s,%s,%s,NULL,%s,0,3,2,'[]',%s,%s,%s)"
    )
    with psycopg.connect(migration_db) as conn:
        conn.execute(upload, (image, tenant, bytes(32), "image/png", 10, 10, 4, b"PNG!", actor))
        conn.execute(upload, (foreign, other, bytes(32), "image/png", 10, 10, 4, b"PNG!", actor))
        conn.execute(insert, (uuid4(), tenant, board, 0, "image", json.dumps({"fit": "contain"}), image))
        conn.execute(
            insert, (uuid4(), tenant, board, 3, "image", json.dumps({"url": "https://example.com/a.png"}), None)
        )
        for media, width, size, data in (
            ("image/svg+xml", 10, 4, b"<svg"),
            ("image/png", 8001, 4, b"PNG!"),
            ("image/png", 10, 5, b"PNG!"),
            ("image/png", 10, 5242881, b"x" * 5242881),
        ):
            with pytest.raises(psycopg.errors.CheckViolation), conn.transaction():
                conn.execute(upload, (uuid4(), tenant, bytes(31) + b"x", media, width, 10, size, data, actor))
        with pytest.raises(psycopg.errors.UniqueViolation), conn.transaction():
            conn.execute(upload, (uuid4(), tenant, bytes(32), "image/png", 10, 10, 4, b"PNG!", actor))
        for kind, content, image_id in (
            ("image", "{}", None),
            ("image", json.dumps({"url": "https://example.com/a.png"}), image),
            ("image", json.dumps({"url": 3}), None),
            ("html", json.dumps({"html": ""}), image),
            ("chart", "{}", None),
        ):
            with pytest.raises(psycopg.errors.CheckViolation), conn.transaction():
                conn.execute(insert, (uuid4(), tenant, board, 6, kind, content, image_id))
        with pytest.raises(psycopg.errors.ForeignKeyViolation), conn.transaction():
            conn.execute(insert, (uuid4(), tenant, board, 6, "image", "{}", foreign))
        assert conn.execute(
            "SELECT count(*) FROM pg_policies WHERE tablename='dashboard_images'"
        ).fetchone() == (2,)


def test_table_panels_reference_presets_and_bound_rows(migration_db):
    """Requirements: REV-63; dashboard operations 2, 13 and 14."""
    legacy_install(migration_db, "0063")
    tenant, actor, preset, board, old, html = uuid4(), uuid4(), uuid4(), uuid4(), uuid4(), uuid4()
    with psycopg.connect(migration_db) as conn:
        conn.execute("INSERT INTO tenants(id,kind,name,name_key) VALUES(%s,'specific','Tables','tables')", (tenant,))
        conn.execute(
            "INSERT INTO presets(id,tenant_id,name,name_key,cel,profile,sort,columns,created_at,updated_at,created_by,updated_by) "
            "VALUES(%s,%s,'All','all','true','v1','[]','[]',now(),now(),%s,%s)",
            (preset, tenant, actor, actor),
        )
        conn.execute(
            "INSERT INTO dashboards(id,tenant_id,name,name_key,created_at,updated_at,created_by,updated_by) "
            "VALUES(%s,%s,'Board','board',now(),now(),%s,%s)",
            (board, tenant, actor, actor),
        )
        conn.execute(
            "INSERT INTO dashboard_panels(id,tenant_id,dashboard_id,preset_id,x,y,w,h,thresholds) "
            "VALUES(%s,%s,%s,%s,0,0,3,2,'[]')",
            (old, tenant, board, preset),
        )
        conn.execute(
            "INSERT INTO dashboard_panels(id,tenant_id,dashboard_id,preset_id,x,y,w,h,thresholds,type,content) "
            "VALUES(%s,%s,%s,NULL,3,0,3,2,'[]','html',%s)",
            (html, tenant, board, json.dumps({"html": "<p>Hi</p>"})),
        )
    migrate(migration_db)
    insert = (
        "INSERT INTO dashboard_panels(id,tenant_id,dashboard_id,preset_id,x,y,w,h,thresholds,type,content) "
        "VALUES(%s,%s,%s,%s,%s,2,3,2,%s,%s,%s)"
    )
    with psycopg.connect(migration_db) as conn:
        # Existing count and HTML panels are unchanged and still valid.
        assert conn.execute(
            "SELECT id,type FROM dashboard_panels WHERE dashboard_id=%s ORDER BY x", (board,)
        ).fetchall() == [(old, "count"), (html, "html")]
        for x, rows in ((0, 1), (3, 10), (6, 50)):
            conn.execute(insert, (uuid4(), tenant, board, preset, x, "[]", "table", json.dumps({"rows": rows})))
        for preset_id, thresholds, content in (
            (None, "[]", json.dumps({"rows": 10})),
            (preset, '[{"lower_bound":"1","color":"red"}]', json.dumps({"rows": 10})),
            (preset, "[]", "{}"),
            (preset, "[]", json.dumps({"rows": 0})),
            (preset, "[]", json.dumps({"rows": 51})),
            (preset, "[]", json.dumps({"rows": 2.5})),
            (preset, "[]", json.dumps({"rows": "10"})),
        ):
            with pytest.raises(psycopg.errors.CheckViolation), conn.transaction():
                conn.execute(insert, (uuid4(), tenant, board, preset_id, 9, thresholds, "table", content))
        # A table panel's preset reference is enforced like a count panel's.
        with pytest.raises(psycopg.errors.ForeignKeyViolation), conn.transaction():
            conn.execute(insert, (uuid4(), tenant, board, uuid4(), 9, "[]", "table", json.dumps({"rows": 5})))
        # Image panels (REV-62) still reference no preset.
        with pytest.raises(psycopg.errors.CheckViolation), conn.transaction():
            conn.execute(
                insert,
                (uuid4(), tenant, board, preset, 9, "[]", "image", json.dumps({"url": "https://example.com/a.png"})),
            )


def test_servicenow_panels_keep_thresholds_and_valid_settings(migration_db):
    """Requirements: REV-65; dashboard operations 2, 3 and 14."""
    legacy_install(migration_db, "0064")
    tenant, actor, preset, board = uuid4(), uuid4(), uuid4(), uuid4()
    count, html, table = uuid4(), uuid4(), uuid4()
    with psycopg.connect(migration_db) as conn:
        conn.execute("INSERT INTO tenants(id,kind,name,name_key) VALUES(%s,'specific','Tickets','tickets')", (tenant,))
        conn.execute(
            "INSERT INTO presets(id,tenant_id,name,name_key,cel,profile,sort,columns,created_at,updated_at,created_by,updated_by) "
            "VALUES(%s,%s,'All','all','true','v1','[]','[]',now(),now(),%s,%s)",
            (preset, tenant, actor, actor),
        )
        conn.execute(
            "INSERT INTO dashboards(id,tenant_id,name,name_key,created_at,updated_at,created_by,updated_by) "
            "VALUES(%s,%s,'Board','board',now(),now(),%s,%s)",
            (board, tenant, actor, actor),
        )
        existing = (
            "INSERT INTO dashboard_panels(id,tenant_id,dashboard_id,preset_id,x,y,w,h,thresholds,type,content) "
            "VALUES(%s,%s,%s,%s,%s,0,3,2,%s,%s,%s)"
        )
        conn.execute(existing, (count, tenant, board, preset, 0, '[{"lower_bound":"1","color":"red"}]', "count", "{}"))
        conn.execute(existing, (html, tenant, board, None, 3, "[]", "html", json.dumps({"html": "<p>Hi</p>"})))
        conn.execute(existing, (table, tenant, board, preset, 6, "[]", "table", json.dumps({"rows": 10})))
    migrate(migration_db)
    insert = (
        "INSERT INTO dashboard_panels(id,tenant_id,dashboard_id,preset_id,x,y,w,h,thresholds,type,content) "
        "VALUES(%s,%s,%s,%s,%s,2,3,2,%s,%s,%s)"
    )
    valid = {"team": "Network Ops", "ticket_state": "open", "detection": "hamal"}
    with psycopg.connect(migration_db) as conn:
        # Existing count, HTML and table panels are unchanged and satisfy the widened checks.
        assert conn.execute(
            "SELECT id,type,thresholds FROM dashboard_panels WHERE dashboard_id=%s ORDER BY x", (board,)
        ).fetchall() == [
            (count, "count", [{"lower_bound": "1", "color": "red"}]),
            (html, "html", []),
            (table, "table", []),
        ]
        assert conn.execute(
            "SELECT count(*) FROM pg_constraint WHERE conname='dashboard_panels_html_plain'"
        ).fetchone() == (0,)
        x = 0
        for state in ("open", "in_progress", "both"):
            for detection in ("hamal", "direct", "all"):
                content = {"team": "Network Ops", "ticket_state": state, "detection": detection}
                conn.execute(insert, (uuid4(), tenant, board, None, x, "[]", "servicenow", json.dumps(content)))
                x += 1
        conn.execute(
            insert,
            (uuid4(), tenant, board, None, x, '[{"lower_bound":"5","color":"orange"}]', "servicenow", json.dumps(valid)),
        )
        # Team names match the domain rule: trimmed NFC text of 1-200 characters.
        for team in ("x" * 200, "Café Ops", "Ops Team"):
            with conn.transaction(force_rollback=True):
                conn.execute(
                    insert,
                    (uuid4(), tenant, board, None, 9, "[]", "servicenow", json.dumps({**valid, "team": team})),
                )
        for preset_id, content in (
            (preset, valid),
            (None, {}),
            (None, {**valid, "team": ""}),
            (None, {**valid, "team": "   "}),
            (None, {**valid, "team": 7}),
            (None, {**valid, "team": "x" * 201}),
            (None, {**valid, "team": " Ops"}),
            (None, {**valid, "team": "Ops "}),
            (None, {**valid, "team": "Net\nOps"}),
            (None, {**valid, "team": "Net\tOps"}),
            (None, {**valid, "team": "Net\u007fOps"}),
            (None, {**valid, "team": "Café Ops"}),
            (None, {"ticket_state": "open", "detection": "hamal"}),
            (None, {**valid, "ticket_state": "closed"}),
            (None, {**valid, "ticket_state": None}),
            (None, {"team": "Ops", "detection": "hamal"}),
            (None, {**valid, "detection": "grafana"}),
            (None, {**valid, "detection": True}),
            (None, {"team": "Ops", "ticket_state": "open"}),
        ):
            with pytest.raises(psycopg.errors.CheckViolation), conn.transaction():
                conn.execute(insert, (uuid4(), tenant, board, preset_id, 20, "[]", "servicenow", json.dumps(content)))
        # Thresholds stay limited to count and servicenow panels.
        for kind, preset_id, content in (
            ("html", None, {"html": "<p>Hi</p>"}),
            ("table", preset, {"rows": 5}),
            ("image", None, {"url": "https://example.com/a.png"}),
        ):
            with pytest.raises(psycopg.errors.CheckViolation), conn.transaction():
                conn.execute(
                    insert,
                    (uuid4(), tenant, board, preset_id, 20, '[{"lower_bound":"1","color":"red"}]', kind, json.dumps(content)),
                )
        with pytest.raises(psycopg.errors.CheckViolation), conn.transaction():
            conn.execute(insert, (uuid4(), tenant, board, None, 20, "[]", "pager", "{}"))
