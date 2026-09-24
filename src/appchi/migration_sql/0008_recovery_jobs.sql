CREATE TABLE retirement_jobs (
 id uuid PRIMARY KEY,tenant_id uuid NOT NULL,resource_kind text NOT NULL CHECK(resource_kind IN ('alert','incident','preset','dashboard','maintenance','correlation')),
 resource_id uuid NOT NULL,expected_revision bigint NOT NULL,final_version bigint NOT NULL,
 state text NOT NULL CHECK(state IN ('intent','intent_protected','retired','final_protected','cancelled','cleaned')),
 intent_evidence_id uuid NOT NULL DEFAULT gen_random_uuid(), final_evidence_id uuid NOT NULL DEFAULT gen_random_uuid(), cancel_evidence_id uuid NOT NULL DEFAULT gen_random_uuid(),
 intent_ack jsonb,final_ack jsonb,cancel_ack jsonb,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(resource_kind,resource_id,expected_revision)
);
CREATE TABLE recovery_evidence (
 id uuid PRIMARY KEY,tenant_id uuid NOT NULL,resource_kind text NOT NULL,resource_id uuid NOT NULL,
 revision bigint NOT NULL,state text NOT NULL CHECK(state IN ('intent','final','cancel')),
 digest text NOT NULL,acknowledgement jsonb,recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
GRANT SELECT,INSERT,UPDATE ON retirement_jobs,recovery_evidence TO appchi_worker;
