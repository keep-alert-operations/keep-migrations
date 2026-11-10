CREATE TABLE restore_runs (
 id uuid PRIMARY KEY, previous_epoch text NOT NULL, deployment_epoch uuid NOT NULL UNIQUE,
 operation_reference text NOT NULL CHECK(length(operation_reference) BETWEEN 1 AND 256),
 state text NOT NULL CHECK(state IN ('fenced','collecting','collected')),
 evidence_namespace text, snapshot_checkpoint text, collected_count bigint NOT NULL DEFAULT 0,
 collection_id uuid, binding_digest text,collection_digest text,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE restore_control (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 deployment_epoch text, run_id uuid REFERENCES restore_runs(id), fenced boolean NOT NULL DEFAULT false
);
INSERT INTO restore_control(singleton) VALUES(true);
CREATE TABLE restore_evidence_stage (
 run_id uuid NOT NULL REFERENCES restore_runs(id),collection_id uuid NOT NULL,evidence_id uuid NOT NULL,
 ordinal bigint NOT NULL CHECK(ordinal>0),tenant_id uuid NOT NULL,resource_kind text NOT NULL,
 resource_id uuid NOT NULL,revision bigint NOT NULL CHECK(revision>=0),
 state text NOT NULL CHECK(state IN ('intent','final','cancel')),digest text NOT NULL CHECK(digest ~ '^[0-9a-f]{64}$'),
 PRIMARY KEY(run_id,collection_id,evidence_id),UNIQUE(run_id,collection_id,ordinal)
);
DO $$ BEGIN
 IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='appchi_recovery') THEN CREATE ROLE appchi_recovery NOLOGIN; END IF;
END $$;
GRANT USAGE ON SCHEMA public TO appchi_recovery;
GRANT SELECT ON restore_control TO appchi_api,appchi_worker;
GRANT SELECT,INSERT,UPDATE,DELETE ON restore_runs,restore_control,restore_evidence_stage TO appchi_recovery;
GRANT SELECT,UPDATE ON capability_gates,auth_sessions TO appchi_recovery;
GRANT SELECT,DELETE ON login_transactions TO appchi_recovery;
-- Recovery authority is a separate deployment identity, never an API capability.
CREATE FUNCTION block_restore_gate_open() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
 IF NEW.ready AND EXISTS(SELECT 1 FROM restore_control WHERE singleton AND fenced) THEN
  RAISE EXCEPTION 'restore_reconciliation_required' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER restore_gate_guard BEFORE INSERT OR UPDATE ON capability_gates
 FOR EACH ROW EXECUTE FUNCTION block_restore_gate_open();
