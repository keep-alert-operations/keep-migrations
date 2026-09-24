CREATE TABLE correlation_delete_jobs (
 id uuid PRIMARY KEY,tenant_id uuid NOT NULL,rule_id uuid NOT NULL,scope text NOT NULL,command_id uuid NOT NULL,
 fingerprint bytea NOT NULL,expected_revision bigint NOT NULL,actor_id uuid NOT NULL,actor_label text NOT NULL,
 intent_id uuid NOT NULL UNIQUE,final_id uuid NOT NULL UNIQUE,cancel_id uuid NOT NULL UNIQUE,digest text NOT NULL,
 state text NOT NULL CHECK(state IN ('prepared','deleted','final_protected','cancelled')),
 intent_ack jsonb,final_ack jsonb,cancel_ack jsonb,receipt jsonb,error_code text,
 created_at timestamptz NOT NULL,updated_at timestamptz NOT NULL,
 UNIQUE(scope,command_id),FOREIGN KEY(tenant_id,rule_id) REFERENCES correlation_rule_identities(tenant_id,id)
);
CREATE UNIQUE INDEX correlation_delete_active ON correlation_delete_jobs(tenant_id,rule_id) WHERE state<>'cancelled' OR cancel_ack IS NULL;
ALTER TABLE correlation_delete_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE correlation_delete_jobs FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON correlation_delete_jobs TO appchi_api USING (tenant_id::text=current_setting('appchi.tenant_id',true)) WITH CHECK(tenant_id::text=current_setting('appchi.tenant_id',true));
CREATE POLICY worker_scope ON correlation_delete_jobs TO appchi_worker USING (true) WITH CHECK(true);
GRANT SELECT,INSERT,UPDATE,DELETE ON correlation_delete_jobs TO appchi_api,appchi_worker;
