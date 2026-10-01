-- Forward-only expansion. Legacy queues remain solely for a fenced cutover drain.
CREATE TABLE kafka_source_results (
 delivery_id uuid PRIMARY KEY,
 tenant_id uuid NOT NULL REFERENCES tenants(id),
 topic text NOT NULL,
 partition integer NOT NULL CHECK(partition>=0),
 input_offset bigint NOT NULL CHECK(input_offset>=0),
 input_digest bytea NOT NULL,
 received_at timestamptz NOT NULL,
 alert_id uuid,
 outcome text NOT NULL CHECK(outcome IN ('applied','rejected')),
 error_code text,
 changed_envelope bytea,
 changed_event_id uuid UNIQUE,
 kafka_confirmed boolean NOT NULL DEFAULT false,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(topic,partition,input_offset),
 FOREIGN KEY(tenant_id,alert_id) REFERENCES alert_identities(tenant_id,id)
);
CREATE INDEX kafka_source_results_alert ON kafka_source_results(tenant_id,alert_id);
CREATE TABLE kafka_consumer_positions (
 consumer text NOT NULL, topic text NOT NULL, partition integer NOT NULL,
 next_offset bigint NOT NULL CHECK(next_offset>=0),
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(consumer,topic,partition)
);
CREATE TABLE kafka_pipeline_faults (
 consumer text NOT NULL, topic text NOT NULL, partition integer NOT NULL,
 input_offset bigint NOT NULL, reason text NOT NULL, digest bytea,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(consumer,topic,partition,input_offset)
);
CREATE TABLE kafka_correlation_events (
 event_id uuid PRIMARY KEY, tenant_id uuid NOT NULL REFERENCES tenants(id),
 topic text NOT NULL, partition integer NOT NULL, input_offset bigint NOT NULL,
 processed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE search_reconciliation (
 index_epoch text NOT NULL, tenant_id uuid NOT NULL REFERENCES tenants(id),
 boundary_seq bigint NOT NULL CHECK(boundary_seq>=0), cursor uuid,
 completed_at timestamptz, started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(index_epoch,tenant_id)
);
ALTER TABLE alert_identities ADD COLUMN current_projection_seq bigint NOT NULL DEFAULT 0;
UPDATE alert_identities i SET current_projection_seq=coalesce((SELECT max(seq) FROM projection_work p WHERE p.tenant_id=i.tenant_id AND p.alert_id=i.id),0);
CREATE TABLE alert_retired_keys (
 tenant_id uuid NOT NULL REFERENCES tenants(id), schema_version text NOT NULL,
 key_digest bytea NOT NULL, retired_at timestamptz NOT NULL,
 PRIMARY KEY(tenant_id,schema_version,key_digest)
);
-- Correlation input ordering now belongs to Kafka; this is consumption count,
-- never a comparison with PG change_order.
ALTER TABLE correlation_consumer_state ADD COLUMN kafka_sequence bigint NOT NULL DEFAULT 0;
CREATE INDEX maintenance_inputs_application ON maintenance_alert_inputs(tenant_id,alert_id,original_order);
-- A protected pipeline cutover must establish Kafka progress before timeline
-- content can be reclaimed. No Kafka delivery is represented by ingest_items.
CREATE TABLE kafka_pipeline_control (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 enabled boolean NOT NULL DEFAULT false,
 cutover_at timestamptz,
 maintenance_retention_proven boolean NOT NULL DEFAULT false
);
INSERT INTO kafka_pipeline_control(singleton) VALUES(true);

-- Worker-only transport/proof bookkeeping; human-facing authority remains RLS.
GRANT SELECT,INSERT,UPDATE,DELETE ON kafka_source_results,kafka_consumer_positions,
 kafka_pipeline_faults,kafka_correlation_events,search_reconciliation,
 alert_retired_keys,kafka_pipeline_control TO appchi_worker;
GRANT SELECT ON kafka_pipeline_control,kafka_source_results TO appchi_api;

ALTER FUNCTION maintenance_dependency_held(uuid,uuid) RENAME TO maintenance_legacy_dependency_held;
CREATE FUNCTION maintenance_dependency_held(p_tenant uuid,p_window uuid) RETURNS boolean
LANGUAGE sql STABLE AS $$ SELECT maintenance_legacy_dependency_held(p_tenant,p_window)
 OR EXISTS(SELECT 1 FROM kafka_pipeline_control WHERE enabled AND NOT maintenance_retention_proven) $$;
REVOKE EXECUTE ON FUNCTION maintenance_dependency_held(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION maintenance_dependency_held(uuid,uuid) TO appchi_api,appchi_worker;
CREATE TABLE operator_gateway_policies (
    operator_id uuid PRIMARY KEY REFERENCES operators(id),
    generation bigint NOT NULL CHECK (generation BETWEEN 1 AND 9007199254740991),
    document text NOT NULL,
    verified_generation bigint,
    verified_at timestamptz
);
GRANT SELECT,INSERT,UPDATE ON operator_gateway_policies TO appchi_api,appchi_worker;
ALTER TABLE maintenance_qualifier_effects ADD COLUMN source_input_id uuid;
ALTER TABLE maintenance_qualifier_effects ADD COLUMN correlation_allowed boolean NOT NULL DEFAULT false;
ALTER TABLE maintenance_qualifier_effects ADD COLUMN origin_input_id uuid;
ALTER TABLE kafka_source_results ADD COLUMN application_order bigint;
