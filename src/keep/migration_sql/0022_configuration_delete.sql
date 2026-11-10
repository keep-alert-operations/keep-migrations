CREATE TABLE configuration_delete_jobs (
 id uuid PRIMARY KEY, tenant_id uuid NOT NULL REFERENCES tenants(id),
 resource_kind text NOT NULL CHECK(resource_kind IN ('preset','dashboard')),resource_id uuid NOT NULL,
 scope text NOT NULL,command_id uuid NOT NULL,fingerprint bytea NOT NULL,
 expected_revision bigint NOT NULL CHECK(expected_revision>0),actor_id uuid NOT NULL,actor_label text NOT NULL,
 intent_id uuid NOT NULL UNIQUE,final_id uuid NOT NULL UNIQUE,cancel_id uuid NOT NULL UNIQUE,
 digest text NOT NULL CHECK(digest ~ '^[0-9a-f]{64}$'),
 state text NOT NULL CHECK(state IN ('prepared','deleted','final_protected','cancelled')),
 intent_ack jsonb,final_ack jsonb,cancel_ack jsonb,receipt jsonb,error_code text,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(scope,command_id),UNIQUE(tenant_id,id)
);
CREATE UNIQUE INDEX configuration_delete_active ON configuration_delete_jobs(tenant_id,resource_kind,resource_id)
 WHERE state IN ('prepared','deleted') OR (state='cancelled' AND cancel_ack IS NULL);
CREATE INDEX configuration_delete_pending ON configuration_delete_jobs(updated_at,id)
 WHERE state IN ('prepared','deleted') OR (state='cancelled' AND cancel_ack IS NULL);
CREATE TABLE configuration_activity (
 id uuid PRIMARY KEY,tenant_id uuid NOT NULL REFERENCES tenants(id),resource_kind text NOT NULL CHECK(resource_kind IN ('preset','dashboard')),
 resource_id uuid NOT NULL,revision bigint NOT NULL,kind text NOT NULL CHECK(kind='deleted'),
 command_id uuid NOT NULL,actor_id uuid NOT NULL,actor_label text NOT NULL,
 before_revision bigint NOT NULL,after_revision bigint NOT NULL,recorded_at timestamptz NOT NULL,
 UNIQUE(tenant_id,resource_kind,resource_id,revision)
);
CREATE INDEX configuration_activity_page ON configuration_activity(tenant_id,resource_kind,resource_id,recorded_at,id);
DO $$ DECLARE tab text; BEGIN
 FOREACH tab IN ARRAY ARRAY['configuration_delete_jobs','configuration_activity'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',tab);
  EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY',tab);
  EXECUTE format('CREATE POLICY tenant_scope ON %I TO appchi_api USING (tenant_id::text=current_setting(''appchi.tenant_id'',true)) WITH CHECK (tenant_id::text=current_setting(''appchi.tenant_id'',true))',tab);
  EXECUTE format('CREATE POLICY worker_scope ON %I TO appchi_worker USING (true) WITH CHECK (true)',tab);
  EXECUTE format('GRANT SELECT,INSERT,UPDATE,DELETE ON %I TO appchi_api,appchi_worker',tab);
 END LOOP;
END $$;
