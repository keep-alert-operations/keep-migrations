CREATE TABLE maintenance_content_retirements (
 tenant_id uuid NOT NULL,window_id uuid NOT NULL,final_revision bigint NOT NULL,
 state text NOT NULL CHECK(state IN ('erasing','cleaned')),
 started_at timestamptz NOT NULL DEFAULT clock_timestamp(),completed_at timestamptz,
 PRIMARY KEY(tenant_id,window_id),FOREIGN KEY(tenant_id,window_id) REFERENCES maintenance_identities(tenant_id,id)
);
ALTER TABLE maintenance_content_retirements ENABLE ROW LEVEL SECURITY;
ALTER TABLE maintenance_content_retirements FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON maintenance_content_retirements TO appchi_api USING(tenant_id::text=current_setting('appchi.tenant_id',true));
CREATE POLICY worker_scope ON maintenance_content_retirements TO appchi_worker USING(true) WITH CHECK(true);
GRANT SELECT ON maintenance_content_retirements TO appchi_api;
GRANT SELECT,INSERT,UPDATE ON maintenance_content_retirements TO appchi_worker;
CREATE INDEX maintenance_input_time ON maintenance_alert_inputs(tenant_id,effective_at,original_order);
CREATE INDEX maintenance_pending_input_time ON ingest_items(tenant_id,received_at,admission_order) WHERE disposition='pending';
CREATE INDEX maintenance_history_window ON maintenance_cause_history(tenant_id,(evidence->>'window_id'));
CREATE TABLE maintenance_configuration_holds (
 id uuid PRIMARY KEY,tenant_id uuid NOT NULL,window_id uuid NOT NULL,
 reason text NOT NULL CHECK(length(reason) BETWEEN 1 AND 128),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),released_at timestamptz,
 FOREIGN KEY(tenant_id,window_id) REFERENCES maintenance_identities(tenant_id,id)
);
CREATE INDEX maintenance_configuration_holds_active ON maintenance_configuration_holds(tenant_id,window_id) WHERE released_at IS NULL;
ALTER TABLE maintenance_configuration_holds ENABLE ROW LEVEL SECURITY;
ALTER TABLE maintenance_configuration_holds FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON maintenance_configuration_holds TO appchi_api USING(tenant_id::text=current_setting('appchi.tenant_id',true));
CREATE POLICY worker_scope ON maintenance_configuration_holds TO appchi_worker USING(true) WITH CHECK(true);
GRANT SELECT ON maintenance_configuration_holds TO appchi_api;
GRANT SELECT,INSERT,UPDATE,DELETE ON maintenance_configuration_holds TO appchi_worker;
-- Shared by the hold guard and application readers/cleanup; invoker RLS applies.
CREATE FUNCTION maintenance_dependency_held(p_tenant uuid,p_window uuid) RETURNS boolean
LANGUAGE sql STABLE AS $$ SELECT COALESCE((SELECT (
 EXISTS(SELECT 1 FROM maintenance_configuration_holds h WHERE h.tenant_id=w.tenant_id AND h.window_id=w.id AND h.released_at IS NULL) OR
 EXISTS(SELECT 1 FROM alert_maintenance_causes c WHERE c.tenant_id=w.tenant_id AND c.window_id=w.id) OR
 EXISTS(SELECT 1 FROM maintenance_cause_history h WHERE h.tenant_id=w.tenant_id AND h.evidence->>'window_id'=w.id::text) OR
 EXISTS(SELECT 1 FROM maintenance_fanout_jobs j WHERE j.tenant_id=w.tenant_id AND j.window_id=w.id AND j.state IN ('pending','blocked')) OR
 EXISTS(SELECT 1 FROM maintenance_delete_jobs j WHERE j.tenant_id=w.tenant_id AND j.window_id=w.id AND (j.state IN ('prepared','deleted') OR (j.state='final_protected' AND j.final_ack IS NULL) OR (j.state='cancelled' AND j.cancel_ack IS NULL))) OR
 EXISTS(SELECT 1 FROM maintenance_segments s WHERE s.tenant_id=w.tenant_id AND s.window_id=w.id AND (
   EXISTS(SELECT 1 FROM maintenance_alert_inputs i WHERE i.tenant_id=s.tenant_id
     AND i.effective_at>=s.start_at AND (i.effective_at,i.original_order)>=(s.activation_at,s.activation_order)
     AND i.effective_at<s.end_at AND (s.deactivation_at IS NULL OR (i.effective_at,i.original_order)<(s.deactivation_at,s.deactivation_order))) OR
   EXISTS(SELECT 1 FROM ingest_items i WHERE i.tenant_id=s.tenant_id AND i.disposition='pending'
     AND i.received_at>=s.start_at AND (i.received_at,i.admission_order)>=(s.activation_at,s.activation_order)
     AND i.received_at<s.end_at AND (s.deactivation_at IS NULL OR (i.received_at,i.admission_order)<(s.deactivation_at,s.deactivation_order)))))
) FROM maintenance_identities w WHERE w.tenant_id=p_tenant AND w.id=p_window),false) $$;
REVOKE EXECUTE ON FUNCTION maintenance_dependency_held(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION maintenance_dependency_held(uuid,uuid) TO appchi_api,appchi_worker;
CREATE FUNCTION maintenance_configuration_hold_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 PERFORM 1 FROM tenant_work_state WHERE tenant_id=NEW.tenant_id FOR UPDATE;
 PERFORM 1 FROM maintenance_windows WHERE tenant_id=NEW.tenant_id AND id=NEW.window_id FOR UPDATE;
 IF NOT FOUND AND NEW.released_at IS NULL THEN RAISE EXCEPTION 'Maintenance content already erased'; END IF;
 IF NEW.released_at IS NULL AND EXISTS(SELECT 1 FROM maintenance_content_retirements WHERE tenant_id=NEW.tenant_id AND window_id=NEW.window_id) THEN
  RAISE EXCEPTION 'Maintenance content retirement already started';
 END IF;
 IF NEW.released_at IS NULL AND EXISTS(SELECT 1 FROM maintenance_windows WHERE tenant_id=NEW.tenant_id AND id=NEW.window_id AND deleted_at+interval '2160 hours'<=clock_timestamp()) AND NOT maintenance_dependency_held(NEW.tenant_id,NEW.window_id) THEN
  RAISE EXCEPTION 'Expired maintenance content cannot be revived';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER maintenance_configuration_hold_serialization BEFORE INSERT OR UPDATE ON maintenance_configuration_holds FOR EACH ROW EXECUTE FUNCTION maintenance_configuration_hold_guard();
ALTER TABLE maintenance_delete_jobs ALTER COLUMN actor_label DROP NOT NULL;
CREATE FUNCTION immutable_retired_maintenance() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF OLD.deleted_at IS NOT NULL AND NEW IS DISTINCT FROM OLD THEN
  RAISE EXCEPTION 'Retired maintenance fence is immutable';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER maintenance_fence_immutable BEFORE UPDATE ON maintenance_identities FOR EACH ROW EXECUTE FUNCTION immutable_retired_maintenance();
REVOKE DELETE ON maintenance_identities FROM appchi_api,appchi_worker;
