-- Forward extension for bounded reconciliation fairness and cutover proof.
ALTER TABLE search_reconciliation ADD COLUMN last_page_at timestamptz NOT NULL DEFAULT clock_timestamp();
ALTER TABLE kafka_pipeline_control ADD COLUMN received_partitions integer;
ALTER TABLE kafka_pipeline_control ADD COLUMN changed_partitions integer;
ALTER TABLE kafka_pipeline_control ADD COLUMN cutover_offsets jsonb;
ALTER TABLE correlation_rules ADD COLUMN kafka_schema_blocked boolean NOT NULL DEFAULT false;
CREATE TABLE operator_kafka_drains (
 operator_id uuid PRIMARY KEY REFERENCES operators(id),
 policy_generation bigint NOT NULL,
 denied_at timestamptz NOT NULL,
 offsets jsonb
);
GRANT SELECT,INSERT,UPDATE ON operator_kafka_drains TO appchi_worker;
