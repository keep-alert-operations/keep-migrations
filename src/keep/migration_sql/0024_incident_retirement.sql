ALTER TABLE incident_identities ADD COLUMN final_revision bigint;
CREATE TABLE incident_retention_holds (
 tenant_id uuid NOT NULL,incident_id uuid NOT NULL,kind text NOT NULL,reference text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),released_at timestamptz,
 PRIMARY KEY(tenant_id,incident_id,kind,reference),
 FOREIGN KEY(tenant_id,incident_id) REFERENCES incident_identities(tenant_id,id)
);
CREATE TABLE command_resources (
 scope text NOT NULL,command_id uuid NOT NULL,tenant_id uuid NOT NULL,
 resource_kind text NOT NULL CHECK(resource_kind='incident'),resource_id uuid NOT NULL,
 PRIMARY KEY(scope,command_id,resource_kind,resource_id),
 FOREIGN KEY(scope,command_id) REFERENCES command_receipts(scope,command_id),
 FOREIGN KEY(tenant_id,resource_id) REFERENCES incident_identities(tenant_id,id)
);
CREATE INDEX command_resources_parent ON command_resources(tenant_id,resource_kind,resource_id);
CREATE FUNCTION guard_incident_retention_hold() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 PERFORM tenant_id FROM tenant_work_state WHERE tenant_id=NEW.tenant_id FOR UPDATE;
 IF NEW.released_at IS NULL THEN
  PERFORM id FROM incident_identities WHERE tenant_id=NEW.tenant_id AND id=NEW.incident_id AND retired_at IS NULL FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'incident_retirement_already_fenced' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER incident_hold_guard BEFORE INSERT OR UPDATE ON incident_retention_holds
 FOR EACH ROW EXECUTE FUNCTION guard_incident_retention_hold();
-- Existing initial-release receipts are immutable; attach their exact parents.
INSERT INTO command_resources
SELECT DISTINCT c.scope,c.command_id,i.tenant_id,'incident',i.id
FROM command_receipts c JOIN incidents i ON split_part(c.scope,':',1)=i.tenant_id::text
WHERE split_part(c.scope,':',3) LIKE 'incident-%'
AND (c.result#>>'{data,id}'=i.id::text OR c.result#>>'{data,source,id}'=i.id::text OR c.result#>>'{data,destination,id}'=i.id::text)
ON CONFLICT DO NOTHING;
INSERT INTO command_resources
SELECT DISTINCT c.scope,c.command_id,n.tenant_id,'incident',n.incident_id
FROM command_receipts c JOIN incident_notes n ON split_part(c.scope,':',1)=n.tenant_id::text
WHERE split_part(c.scope,':',3)='incident-note' AND c.result#>>'{data,id}'=n.id::text
ON CONFLICT DO NOTHING;
DO $$ DECLARE tab text; BEGIN
 FOREACH tab IN ARRAY ARRAY['incident_retention_holds','command_resources'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',tab);
  EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY',tab);
  EXECUTE format('CREATE POLICY tenant_scope ON %I TO appchi_api USING (tenant_id::text=current_setting(''appchi.tenant_id'',true)) WITH CHECK(tenant_id::text=current_setting(''appchi.tenant_id'',true))',tab);
  EXECUTE format('CREATE POLICY worker_scope ON %I TO appchi_worker USING(true) WITH CHECK(true)',tab);
  EXECUTE format('GRANT SELECT,INSERT,UPDATE,DELETE ON %I TO appchi_worker',tab);
 END LOOP;
END $$;
GRANT SELECT,INSERT ON command_resources TO appchi_api;
GRANT SELECT ON incident_retention_holds TO appchi_api;
CREATE TABLE command_content_retirements (
 id uuid PRIMARY KEY,scope text NOT NULL,command_id uuid NOT NULL,tenant_id uuid NOT NULL,
 fingerprint bytea NOT NULL,result_digest text NOT NULL,evidence_digest text NOT NULL,
 intent_id uuid NOT NULL UNIQUE,final_id uuid NOT NULL UNIQUE,
 state text NOT NULL CHECK(state IN ('prepared','final_protected','cleaned')),
 intent_ack jsonb,final_ack jsonb,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),UNIQUE(scope,command_id),
 FOREIGN KEY(scope,command_id) REFERENCES command_receipts(scope,command_id)
);
GRANT SELECT,INSERT,UPDATE ON command_content_retirements TO appchi_worker;
