ALTER TABLE command_resources DROP CONSTRAINT command_resources_resource_kind_check;
ALTER TABLE command_resources DROP CONSTRAINT command_resources_tenant_id_resource_id_fkey;
ALTER TABLE command_resources ADD CONSTRAINT command_resources_resource_kind_check CHECK(resource_kind IN ('incident','alert'));
ALTER TABLE command_resources ADD COLUMN incident_parent_id uuid GENERATED ALWAYS AS (CASE WHEN resource_kind='incident' THEN resource_id END) STORED;
ALTER TABLE command_resources ADD COLUMN alert_parent_id uuid GENERATED ALWAYS AS (CASE WHEN resource_kind='alert' THEN resource_id END) STORED;
ALTER TABLE command_resources ADD FOREIGN KEY(tenant_id,incident_parent_id) REFERENCES incident_identities(tenant_id,id);
ALTER TABLE command_resources ADD FOREIGN KEY(tenant_id,alert_parent_id) REFERENCES alert_identities(tenant_id,id);
-- Existing command results remain immutable; map their recorded result parents.
INSERT INTO command_resources(scope,command_id,tenant_id,resource_kind,resource_id)
SELECT c.scope,c.command_id,i.tenant_id,'alert',i.id FROM command_receipts c JOIN alert_identities i
 ON split_part(c.scope,':',1)=i.tenant_id::text
WHERE split_part(c.scope,':',3)='alert-command' AND c.result#>>'{data,id}'=i.id::text
ON CONFLICT DO NOTHING;
INSERT INTO command_resources(scope,command_id,tenant_id,resource_kind,resource_id)
SELECT DISTINCT c.scope,c.command_id,i.tenant_id,'alert',i.id FROM command_receipts c
 CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(c.result->'data')='array' THEN c.result->'data' ELSE '[]'::jsonb END) r
 JOIN alert_identities i ON split_part(c.scope,':',1)=i.tenant_id::text AND r->>'id'=i.id::text
WHERE split_part(c.scope,':',3)='alert-bulk' ON CONFLICT DO NOTHING;
INSERT INTO command_resources(scope,command_id,tenant_id,resource_kind,resource_id)
SELECT c.scope,c.command_id,n.tenant_id,'alert',n.alert_id FROM command_receipts c JOIN alert_notes n
 ON split_part(c.scope,':',1)=n.tenant_id::text AND c.result#>>'{data,id}'=n.id::text
WHERE split_part(c.scope,':',3) IN ('note-create','note-edit','note-delete') ON CONFLICT DO NOTHING;
CREATE TABLE alert_retention_holds (
 tenant_id uuid NOT NULL,alert_id uuid NOT NULL,kind text NOT NULL,reference text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),released_at timestamptz,
 PRIMARY KEY(tenant_id,alert_id,kind,reference),
 FOREIGN KEY(tenant_id,alert_id) REFERENCES alert_identities(tenant_id,id)
);
CREATE FUNCTION guard_alert_retention_hold() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 PERFORM tenant_id FROM tenant_work_state WHERE tenant_id=NEW.tenant_id FOR UPDATE;
 IF NEW.released_at IS NULL THEN
  PERFORM id FROM alert_identities WHERE tenant_id=NEW.tenant_id AND id=NEW.alert_id AND retired_at IS NULL FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'alert_retirement_already_fenced' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER alert_hold_guard BEFORE INSERT OR UPDATE ON alert_retention_holds
 FOR EACH ROW EXECUTE FUNCTION guard_alert_retention_hold();
ALTER TABLE alert_retention_holds ENABLE ROW LEVEL SECURITY;
ALTER TABLE alert_retention_holds FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON alert_retention_holds TO appchi_api USING(tenant_id::text=current_setting('appchi.tenant_id',true));
CREATE POLICY worker_scope ON alert_retention_holds TO appchi_worker USING(true) WITH CHECK(true);
GRANT SELECT ON alert_retention_holds TO appchi_api;
GRANT SELECT,INSERT,UPDATE,DELETE ON alert_retention_holds TO appchi_worker;
