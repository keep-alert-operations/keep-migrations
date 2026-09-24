CREATE TABLE maintenance_effect_outbox (
 tenant_id uuid NOT NULL,alert_id uuid NOT NULL,id uuid NOT NULL,qualifier_id uuid NOT NULL,
 change_order bigint NOT NULL,action text NOT NULL CHECK(action IN ('activate','withdraw')),
 effective_at timestamptz NOT NULL,original_order bigint NOT NULL,scheduled boolean NOT NULL,
 boundary_id text NOT NULL,before_snapshot jsonb NOT NULL,after_snapshot jsonb NOT NULL,
 observed_revision bigint NOT NULL,proof_digest bytea NOT NULL,corrects_id uuid,
 recorded_at timestamptz NOT NULL,processed_at timestamptz,
 PRIMARY KEY(tenant_id,id),UNIQUE(tenant_id,change_order),
 FOREIGN KEY(tenant_id,alert_id) REFERENCES alert_identities(tenant_id,id),
 FOREIGN KEY(tenant_id,corrects_id) REFERENCES maintenance_effect_outbox(tenant_id,id)
);
CREATE INDEX maintenance_effect_pending ON maintenance_effect_outbox(tenant_id,change_order) WHERE processed_at IS NULL;
GRANT SELECT,INSERT,UPDATE,DELETE ON maintenance_effect_outbox TO appchi_api,appchi_worker;
ALTER TABLE maintenance_effect_outbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE maintenance_effect_outbox FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON maintenance_effect_outbox TO appchi_api USING (tenant_id::text=current_setting('appchi.tenant_id',true)) WITH CHECK (tenant_id::text=current_setting('appchi.tenant_id',true));
CREATE POLICY worker_scope ON maintenance_effect_outbox TO appchi_worker USING (true) WITH CHECK (true);
