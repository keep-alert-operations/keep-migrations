-- Read-only operational evidence; no client receipt or dispatch queue.
ALTER TABLE kafka_source_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE kafka_source_results FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON kafka_source_results TO appchi_api
 USING (tenant_id::text=current_setting('appchi.tenant_id',true));
CREATE POLICY worker_scope ON kafka_source_results TO appchi_worker USING (true) WITH CHECK (true);
GRANT SELECT ON kafka_consumer_positions,kafka_pipeline_faults,search_reconciliation TO appchi_api;
CREATE INDEX kafka_rejection_diagnostics ON kafka_source_results(tenant_id,recorded_at DESC,delivery_id)
 WHERE outcome='rejected';
