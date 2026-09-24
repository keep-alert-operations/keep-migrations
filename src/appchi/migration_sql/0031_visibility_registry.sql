-- Per-view coordination only. No measurement inputs, offers or success ledger.
CREATE TABLE visibility_registry_heads (
 tenant_id uuid PRIMARY KEY REFERENCES tenants(id),
 checkpoint bigint NOT NULL DEFAULT 0 CHECK(checkpoint>=0)
);
CREATE TABLE visibility_views (
 tenant_id uuid NOT NULL REFERENCES tenants(id), id uuid NOT NULL,
 session_hash bytea NOT NULL CHECK(octet_length(session_hash)=32),
 principal_id uuid NOT NULL REFERENCES principals(id), deployment_epoch text NOT NULL,
 tab_id uuid NOT NULL, revision bigint NOT NULL CHECK(revision>0),
 view_epoch bigint NOT NULL CHECK(view_epoch>0), query_digest text NOT NULL CHECK(query_digest ~ '^[0-9a-f]{64}$'),
 descriptor jsonb NOT NULL, state text NOT NULL CHECK(state IN ('foreground','background','closed')),
 recorded_at timestamptz NOT NULL, lease_until timestamptz NOT NULL,
 checkpoint bigint NOT NULL CHECK(checkpoint>0), authority jsonb NOT NULL,
 PRIMARY KEY(tenant_id,id), CHECK(lease_until>=recorded_at)
);
CREATE INDEX visibility_session_views ON visibility_views(tenant_id,session_hash,deployment_epoch,lease_until) WHERE state<>'closed';
CREATE INDEX visibility_tenant_views ON visibility_views(tenant_id,lease_until) WHERE state<>'closed';
CREATE TABLE visibility_view_controls (
 tenant_id uuid NOT NULL, checkpoint bigint NOT NULL CHECK(checkpoint>0),
 view_id uuid NOT NULL, session_hash bytea NOT NULL CHECK(octet_length(session_hash)=32),
 command_id uuid NOT NULL, fingerprint bytea NOT NULL CHECK(octet_length(fingerprint)=32),
 recorded_at timestamptz NOT NULL, snapshot jsonb NOT NULL, response jsonb NOT NULL,
 PRIMARY KEY(tenant_id,checkpoint),
 UNIQUE(tenant_id,session_hash,command_id),
 FOREIGN KEY(tenant_id,view_id) REFERENCES visibility_views(tenant_id,id)
);
CREATE INDEX visibility_control_timeline ON visibility_view_controls(tenant_id,view_id,recorded_at,checkpoint);
DO $$ DECLARE tab text; BEGIN
 FOREACH tab IN ARRAY ARRAY['visibility_registry_heads','visibility_views','visibility_view_controls'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',tab);
  EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY',tab);
  EXECUTE format('CREATE POLICY tenant_scope ON %I TO appchi_api USING (tenant_id::text=current_setting(''appchi.tenant_id'',true)) WITH CHECK(tenant_id::text=current_setting(''appchi.tenant_id'',true))',tab);
  EXECUTE format('CREATE POLICY worker_scope ON %I TO appchi_worker USING(true) WITH CHECK(true)',tab);
 END LOOP;
END $$;
GRANT SELECT,INSERT,UPDATE ON visibility_registry_heads,visibility_views TO appchi_api;
GRANT SELECT,INSERT ON visibility_view_controls TO appchi_api;
GRANT SELECT ON visibility_registry_heads,visibility_views,visibility_view_controls TO appchi_worker;
-- No API UPDATE/DELETE of immutable controls and no cleanup grants until the
-- supplied telemetry handoff/evidence retention contract is implemented.
