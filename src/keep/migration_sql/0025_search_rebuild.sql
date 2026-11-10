CREATE TABLE search_index_control (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 alias_name text NOT NULL,physical_index text NOT NULL,index_epoch text NOT NULL,
 writers_paused boolean NOT NULL DEFAULT false,active_rebuild_id uuid,
 binding_digest text NOT NULL,updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE search_rebuild_jobs (
 id uuid PRIMARY KEY,source_index text NOT NULL,target_index text NOT NULL UNIQUE,
 source_epoch text NOT NULL,target_epoch text NOT NULL UNIQUE,binding_digest text NOT NULL,
 state text NOT NULL CHECK(state IN ('registered','copying','catching_up','draining','validating','switching','complete','cancelled')),
 hold_active boolean NOT NULL DEFAULT true,lease_token uuid,lease_until timestamptz,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 error_code text,validation_count bigint NOT NULL DEFAULT 0,validation_cursor text
);
CREATE UNIQUE INDEX search_one_rebuild ON search_rebuild_jobs((true)) WHERE hold_active;
CREATE TABLE search_rebuild_positions (
 job_id uuid NOT NULL REFERENCES search_rebuild_jobs(id),tenant_id uuid NOT NULL REFERENCES tenants(id),
 snapshot_seq bigint NOT NULL,copied_seq bigint NOT NULL DEFAULT 0,copy_cursor uuid,
 copy_done boolean NOT NULL DEFAULT false,cutover_seq bigint,PRIMARY KEY(job_id,tenant_id)
);
CREATE TABLE search_writer_leases (
 id uuid PRIMARY KEY,index_epoch text NOT NULL,expires_at timestamptz NOT NULL
);
CREATE INDEX projection_snapshot_copy ON projection_work(tenant_id,alert_id,seq DESC);
-- Registration and physical outbox cleanup share this lock. An active global
-- hold also covers tenants created after snapshot capture.
CREATE FUNCTION protect_search_rebuild_work() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 PERFORM pg_advisory_xact_lock(713411725);
 IF EXISTS(SELECT 1 FROM search_rebuild_jobs WHERE hold_active) THEN
  RAISE EXCEPTION 'search_rebuild_hold_active' USING ERRCODE='23514';
 END IF;
 RETURN NULL;
END $$;
CREATE TRIGGER projection_rebuild_hold BEFORE DELETE ON projection_work
 FOR EACH STATEMENT EXECUTE FUNCTION protect_search_rebuild_work();
CREATE FUNCTION inherit_search_epoch() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE epoch text;
BEGIN
 SELECT index_epoch INTO epoch FROM search_index_control WHERE singleton FOR SHARE;
 IF FOUND THEN NEW.index_epoch=epoch; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER tenant_search_epoch BEFORE INSERT ON tenant_view_state
 FOR EACH ROW EXECUTE FUNCTION inherit_search_epoch();
GRANT SELECT ON search_index_control,search_rebuild_jobs TO appchi_api;
GRANT SELECT,INSERT,UPDATE,DELETE ON search_index_control,search_rebuild_jobs,search_rebuild_positions,search_writer_leases TO appchi_worker;
ALTER TABLE projection_work ADD COLUMN visibility_epoch text;
