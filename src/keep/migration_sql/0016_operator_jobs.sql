ALTER TABLE operators DROP CONSTRAINT operators_name_key_key;
ALTER TABLE operators ADD COLUMN pending_name text, ADD COLUMN pending_name_key text,
 ADD COLUMN updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 ADD COLUMN last_reconciled_at timestamptz, ADD COLUMN deleted_at timestamptz;
ALTER TABLE operator_credentials ADD COLUMN created_at timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE UNIQUE INDEX one_prepared ON operator_credentials(operator_id) WHERE state='prepared';
CREATE TABLE operator_name_claims (
 name_key text PRIMARY KEY, operator_id uuid NOT NULL, tenant_id uuid NOT NULL, name text NOT NULL,
 FOREIGN KEY(tenant_id,operator_id) REFERENCES operators(tenant_id,id)
);
INSERT INTO operator_name_claims SELECT name_key,id,tenant_id,name FROM operators WHERE lifecycle<>'deleted';
CREATE TABLE operator_operations (
 id uuid PRIMARY KEY,tenant_id uuid NOT NULL,operator_id uuid NOT NULL,
 kind text NOT NULL CHECK(kind IN ('setup','create_key','rotate','rename','delete','cancel','cleanup','repair')),
 generation bigint NOT NULL,candidate_id uuid REFERENCES operator_credentials(id),
 state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','running','needs_attention','completed','cancelled','superseded')),
 step text NOT NULL DEFAULT 'reconcile',progress jsonb NOT NULL DEFAULT '{}',
 attempts integer NOT NULL DEFAULT 0,next_attempt_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 lease_token uuid,lease_until timestamptz,error_code text,
 actor_id uuid,actor_label text NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 completed_at timestamptz,
 FOREIGN KEY(tenant_id,operator_id) REFERENCES operators(tenant_id,id),UNIQUE(tenant_id,operator_id,id)
);
CREATE UNIQUE INDEX one_operator_operation ON operator_operations(operator_id) WHERE completed_at IS NULL;
CREATE INDEX operator_jobs_due ON operator_operations(next_attempt_at,id) WHERE completed_at IS NULL;
CREATE TABLE operator_steps (
 id uuid PRIMARY KEY,tenant_id uuid NOT NULL,operator_id uuid NOT NULL,operation_id uuid NOT NULL,
 generation bigint NOT NULL,step text NOT NULL,outcome text NOT NULL,recorded_at timestamptz NOT NULL,
 FOREIGN KEY(tenant_id,operator_id,operation_id) REFERENCES operator_operations(tenant_id,operator_id,id)
);
CREATE TABLE operator_activity (
 id uuid PRIMARY KEY,tenant_id uuid NOT NULL,operator_id uuid NOT NULL,actor_id uuid,actor_label text NOT NULL,
 kind text NOT NULL,evidence jsonb NOT NULL,recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(tenant_id,operator_id) REFERENCES operators(tenant_id,id)
);
CREATE INDEX operator_activity_page ON operator_activity(tenant_id,operator_id,recorded_at,id);
CREATE TABLE operator_remote_bindings (
 tenant_id uuid NOT NULL,operator_id uuid NOT NULL,kind text NOT NULL,remote_id text NOT NULL,
 generation bigint NOT NULL,verified_at timestamptz NOT NULL,
 PRIMARY KEY(operator_id,kind),FOREIGN KEY(tenant_id,operator_id) REFERENCES operators(tenant_id,id)
);
CREATE TABLE operator_routing_guard(scope text PRIMARY KEY,lease_token uuid,lease_until timestamptz);
INSERT INTO operator_routing_guard(scope) VALUES('grafana');
DO $$ DECLARE tab text; BEGIN
 FOREACH tab IN ARRAY ARRAY['operator_name_claims','operator_operations','operator_steps','operator_activity','operator_remote_bindings'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',tab);
  EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY',tab);
  EXECUTE format('CREATE POLICY tenant_scope ON %I TO appchi_api USING (tenant_id::text=current_setting(''appchi.tenant_id'',true)) WITH CHECK (tenant_id::text=current_setting(''appchi.tenant_id'',true))',tab);
  EXECUTE format('CREATE POLICY worker_scope ON %I TO appchi_worker USING (true) WITH CHECK (true)',tab);
  EXECUTE format('GRANT SELECT,INSERT,UPDATE,DELETE ON %I TO appchi_api,appchi_worker',tab);
 END LOOP;
END $$;
GRANT SELECT,UPDATE ON operator_routing_guard TO appchi_worker;
