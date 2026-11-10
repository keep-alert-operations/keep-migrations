ALTER TABLE configuration_activity DROP CONSTRAINT configuration_activity_kind_check;
ALTER TABLE configuration_activity ADD CHECK(kind IN ('created','updated','deleted'));
ALTER TABLE configuration_activity ALTER COLUMN before_revision DROP NOT NULL;
ALTER TABLE configuration_activity ADD COLUMN changed_fields text[];
CREATE INDEX configuration_before_reference ON configuration_activity(tenant_id,resource_kind,resource_id,before_revision,recorded_at);
CREATE INDEX configuration_after_reference ON configuration_activity(tenant_id,resource_kind,resource_id,after_revision,recorded_at);
ALTER TABLE configuration_delete_jobs ALTER COLUMN actor_label DROP NOT NULL;

CREATE TABLE configuration_identities (
 tenant_id uuid NOT NULL REFERENCES tenants(id),resource_kind text NOT NULL CHECK(resource_kind IN ('preset','dashboard')),
 resource_id uuid NOT NULL,final_revision bigint,deleted_at timestamptz,
 PRIMARY KEY(tenant_id,resource_kind,resource_id),
 CHECK((final_revision IS NULL)=(deleted_at IS NULL))
);
INSERT INTO configuration_identities
 SELECT tenant_id,'preset',id,CASE WHEN deleted_at IS NOT NULL THEN revision END,deleted_at FROM presets
 UNION ALL SELECT tenant_id,'dashboard',id,CASE WHEN deleted_at IS NOT NULL THEN revision END,deleted_at FROM dashboards;

CREATE TABLE configuration_retention_holds (
 id uuid PRIMARY KEY,tenant_id uuid NOT NULL,resource_kind text NOT NULL,resource_id uuid NOT NULL,
 revision bigint CHECK(revision>0),reason text NOT NULL CHECK(length(reason) BETWEEN 1 AND 128),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),released_at timestamptz,
 FOREIGN KEY(tenant_id,resource_kind,resource_id) REFERENCES configuration_identities
);
CREATE INDEX configuration_holds_active ON configuration_retention_holds(tenant_id,resource_kind,resource_id,revision) WHERE released_at IS NULL;

CREATE FUNCTION configuration_identity_sync() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO configuration_identities(tenant_id,resource_kind,resource_id,final_revision,deleted_at)
 VALUES(NEW.tenant_id,TG_ARGV[0],NEW.id,CASE WHEN NEW.deleted_at IS NOT NULL THEN NEW.revision END,NEW.deleted_at)
 ON CONFLICT(tenant_id,resource_kind,resource_id) DO UPDATE
 SET final_revision=EXCLUDED.final_revision,deleted_at=EXCLUDED.deleted_at
 WHERE configuration_identities.deleted_at IS NULL;
 IF NOT FOUND AND (TG_OP='INSERT' OR NEW.deleted_at IS NULL) THEN
  RAISE EXCEPTION 'Retired configuration identity cannot be reused';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER preset_identity BEFORE INSERT OR UPDATE ON presets FOR EACH ROW EXECUTE FUNCTION configuration_identity_sync('preset');
CREATE TRIGGER dashboard_identity BEFORE INSERT OR UPDATE ON dashboards FOR EACH ROW EXECUTE FUNCTION configuration_identity_sync('dashboard');
CREATE FUNCTION immutable_retired_configuration() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF OLD.deleted_at IS NOT NULL AND NEW IS DISTINCT FROM OLD THEN
  RAISE EXCEPTION 'Retired configuration fence is immutable';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER configuration_fence_immutable BEFORE UPDATE ON configuration_identities FOR EACH ROW EXECUTE FUNCTION immutable_retired_configuration();

-- Physical removal of an intermediate revision must not change an older
-- revision's supersession clock. Capture that clock independently of row presence.
ALTER TABLE preset_revisions ADD COLUMN superseded_at timestamptz;
ALTER TABLE dashboard_revisions ADD COLUMN superseded_at timestamptz;
WITH v AS (SELECT id,revision,lead(recorded_at) OVER(PARTITION BY id ORDER BY revision) AS next_at FROM preset_revisions)
 UPDATE preset_revisions r SET superseded_at=v.next_at FROM v WHERE r.id=v.id AND r.revision=v.revision;
WITH v AS (SELECT id,revision,lead(recorded_at) OVER(PARTITION BY id ORDER BY revision) AS next_at FROM dashboard_revisions)
 UPDATE dashboard_revisions r SET superseded_at=v.next_at FROM v WHERE r.id=v.id AND r.revision=v.revision;
CREATE FUNCTION configuration_supersession() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 EXECUTE format('UPDATE %I SET superseded_at=$1 WHERE tenant_id=$2 AND id=$3 AND revision=$4 AND superseded_at IS NULL',TG_TABLE_NAME)
 USING NEW.recorded_at,NEW.tenant_id,NEW.id,NEW.revision-1;
 RETURN NEW;
END $$;
CREATE TRIGGER preset_supersession AFTER INSERT ON preset_revisions FOR EACH ROW EXECUTE FUNCTION configuration_supersession();
CREATE TRIGGER dashboard_supersession AFTER INSERT ON dashboard_revisions FOR EACH ROW EXECUTE FUNCTION configuration_supersession();

CREATE FUNCTION configuration_hold_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 PERFORM 1 FROM tenant_configuration_guard WHERE tenant_id=NEW.tenant_id FOR UPDATE;
 IF NEW.released_at IS NULL THEN
  IF NEW.resource_kind='preset' THEN
   PERFORM 1 FROM presets WHERE tenant_id=NEW.tenant_id AND id=NEW.resource_id;
  ELSE
   PERFORM 1 FROM dashboards WHERE tenant_id=NEW.tenant_id AND id=NEW.resource_id;
  END IF;
  IF NOT FOUND THEN RAISE EXCEPTION 'Configuration content already erased'; END IF;
  IF NEW.revision IS NOT NULL THEN
   IF NEW.resource_kind='preset' THEN
    PERFORM 1 FROM preset_revisions WHERE tenant_id=NEW.tenant_id AND id=NEW.resource_id AND revision=NEW.revision;
   ELSE
    PERFORM 1 FROM dashboard_revisions WHERE tenant_id=NEW.tenant_id AND id=NEW.resource_id AND revision=NEW.revision;
   END IF;
   IF NOT FOUND THEN RAISE EXCEPTION 'Configuration revision already erased'; END IF;
  END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER configuration_hold_serialization BEFORE INSERT OR UPDATE ON configuration_retention_holds FOR EACH ROW EXECUTE FUNCTION configuration_hold_guard();

DO $$ DECLARE tab text; BEGIN
 FOREACH tab IN ARRAY ARRAY['configuration_identities','configuration_retention_holds'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',tab);
  EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY',tab);
  EXECUTE format('CREATE POLICY tenant_scope ON %I TO appchi_api USING (tenant_id::text=current_setting(''appchi.tenant_id'',true)) WITH CHECK (tenant_id::text=current_setting(''appchi.tenant_id'',true))',tab);
  EXECUTE format('CREATE POLICY worker_scope ON %I TO appchi_worker USING (true) WITH CHECK(true)',tab);
 END LOOP;
END $$;
GRANT SELECT,INSERT,UPDATE ON configuration_identities TO appchi_api,appchi_worker;
GRANT SELECT ON configuration_retention_holds TO appchi_api;
GRANT SELECT,INSERT,UPDATE,DELETE ON configuration_retention_holds TO appchi_worker;
