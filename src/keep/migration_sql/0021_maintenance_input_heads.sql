CREATE TABLE maintenance_alert_input_heads (
 tenant_id uuid NOT NULL,alert_id uuid NOT NULL,input_revision bigint NOT NULL CHECK(input_revision>0),last_input_id uuid NOT NULL,
 PRIMARY KEY(tenant_id,alert_id),FOREIGN KEY(tenant_id,alert_id) REFERENCES alert_identities(tenant_id,id),
 FOREIGN KEY(tenant_id,alert_id,last_input_id) REFERENCES maintenance_alert_inputs(tenant_id,alert_id,id)
);
INSERT INTO maintenance_alert_input_heads(tenant_id,alert_id,input_revision,last_input_id)
 SELECT tenant_id,alert_id,count(*),(array_agg(id ORDER BY recorded_at DESC,effective_at DESC,original_order DESC))[1]
 FROM maintenance_alert_inputs GROUP BY tenant_id,alert_id;
ALTER TABLE maintenance_alert_checkpoints ADD COLUMN input_revision bigint NOT NULL DEFAULT 0;
UPDATE maintenance_alert_checkpoints SET complete=false;
GRANT SELECT,INSERT,UPDATE,DELETE ON maintenance_alert_input_heads TO appchi_api,appchi_worker;
ALTER TABLE maintenance_alert_input_heads ENABLE ROW LEVEL SECURITY;
ALTER TABLE maintenance_alert_input_heads FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON maintenance_alert_input_heads TO appchi_api USING (tenant_id::text=current_setting('appchi.tenant_id',true)) WITH CHECK (tenant_id::text=current_setting('appchi.tenant_id',true));
CREATE POLICY worker_scope ON maintenance_alert_input_heads TO appchi_worker USING (true) WITH CHECK (true);
UPDATE capability_gates SET ready=false,reason='maintenance_input_checkpoint_warmup_required' WHERE capability='maintenance';
