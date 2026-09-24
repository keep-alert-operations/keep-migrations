CREATE TABLE maintenance_alert_inputs (
 tenant_id uuid NOT NULL,alert_id uuid NOT NULL,id uuid NOT NULL,effective_at timestamptz NOT NULL,original_order bigint NOT NULL,
 kind text NOT NULL,new_logical_alert boolean NOT NULL,before_snapshot jsonb,after_snapshot jsonb NOT NULL,
 source_suppressed boolean,request_digest bytea NOT NULL,recorded_at timestamptz NOT NULL,
 PRIMARY KEY(tenant_id,alert_id,id),UNIQUE(tenant_id,alert_id,effective_at,original_order),
 FOREIGN KEY(tenant_id,alert_id) REFERENCES alert_identities(tenant_id,id),CHECK(original_order>0)
);
CREATE INDEX maintenance_input_replay ON maintenance_alert_inputs(tenant_id,alert_id,effective_at,original_order);
CREATE TABLE maintenance_alert_checkpoints (
 tenant_id uuid NOT NULL,alert_id uuid NOT NULL,proof_digest bytea NOT NULL,catalog_generation bigint NOT NULL,
 current_suppressed boolean NOT NULL,current_cause_ids jsonb NOT NULL,union_intervals jsonb NOT NULL,
 complete boolean NOT NULL DEFAULT false,checked_at timestamptz NOT NULL,
 PRIMARY KEY(tenant_id,alert_id),FOREIGN KEY(tenant_id,alert_id) REFERENCES alert_identities(tenant_id,id)
);
CREATE TABLE maintenance_cause_history (
 tenant_id uuid NOT NULL,alert_id uuid NOT NULL,id uuid NOT NULL,cause_id text NOT NULL,
 boundary_kind text NOT NULL CHECK(boundary_kind IN ('open','close','correction')),boundary_id text NOT NULL,
 effective_at timestamptz NOT NULL,recorded_at timestamptz NOT NULL,evidence jsonb NOT NULL,corrects_id uuid,
 PRIMARY KEY(tenant_id,alert_id,id),UNIQUE(tenant_id,alert_id,cause_id,boundary_kind,boundary_id),
 FOREIGN KEY(tenant_id,alert_id) REFERENCES alert_identities(tenant_id,id)
) PARTITION BY HASH(alert_id);
CREATE TABLE maintenance_union_history (
 tenant_id uuid NOT NULL,alert_id uuid NOT NULL,id uuid NOT NULL,proof_digest bytea NOT NULL,effective_intervals jsonb NOT NULL,
 recorded_at timestamptz NOT NULL,corrects_id uuid,
 PRIMARY KEY(tenant_id,alert_id,id),UNIQUE(tenant_id,alert_id,proof_digest),
 FOREIGN KEY(tenant_id,alert_id) REFERENCES alert_identities(tenant_id,id)
) PARTITION BY HASH(alert_id);
DO $$ BEGIN
 FOR i IN 0..31 LOOP
  EXECUTE format('CREATE TABLE maintenance_cause_history_%s PARTITION OF maintenance_cause_history FOR VALUES WITH (MODULUS 32,REMAINDER %s)',i,i);
  EXECUTE format('CREATE TABLE maintenance_union_history_%s PARTITION OF maintenance_union_history FOR VALUES WITH (MODULUS 32,REMAINDER %s)',i,i);
 END LOOP;
END $$;
CREATE TABLE maintenance_qualifier_effects (
 tenant_id uuid NOT NULL,alert_id uuid NOT NULL,id uuid NOT NULL,effective_at timestamptz NOT NULL,
 active boolean NOT NULL,recorded_at timestamptz NOT NULL,
 PRIMARY KEY(tenant_id,alert_id,id),FOREIGN KEY(tenant_id,alert_id) REFERENCES alert_identities(tenant_id,id)
);
DO $$ DECLARE tab text; BEGIN
 FOREACH tab IN ARRAY ARRAY['maintenance_alert_inputs','maintenance_alert_checkpoints','maintenance_cause_history','maintenance_union_history','maintenance_qualifier_effects'] LOOP
  EXECUTE format('GRANT SELECT,INSERT,UPDATE,DELETE ON %I TO appchi_api,appchi_worker',tab);
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',tab);
  EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY',tab);
  EXECUTE format('CREATE POLICY tenant_scope ON %I TO appchi_api USING (tenant_id::text=current_setting(''appchi.tenant_id'',true)) WITH CHECK (tenant_id::text=current_setting(''appchi.tenant_id'',true))',tab);
  EXECUTE format('CREATE POLICY worker_scope ON %I TO appchi_worker USING (true) WITH CHECK (true)',tab);
 END LOOP;
END $$;
-- Existing retained alerts have no proven maintenance-input baseline. Do not
-- synthesize creation proof or enable suppression from their current snapshots.
UPDATE capability_gates SET ready=false,reason='maintenance_full_history_baseline_and_pipeline_required' WHERE capability='maintenance';
