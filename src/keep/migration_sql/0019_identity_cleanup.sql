CREATE TABLE audit_retention_holds (
 event_id uuid NOT NULL REFERENCES audit_events(id),kind text NOT NULL CHECK(kind IN ('unfinished_command','reference','recovery')),
 reference text NOT NULL CHECK(length(reference) BETWEEN 1 AND 256),created_at timestamptz NOT NULL DEFAULT clock_timestamp(),released_at timestamptz,
 PRIMARY KEY(event_id,kind,reference)
);
CREATE TABLE audit_retirement_jobs (
 id uuid PRIMARY KEY,event_id uuid NOT NULL,scope_tenant_id uuid NOT NULL REFERENCES tenants(id),event_tenant_id uuid,
 event_recorded_at timestamptz NOT NULL,digest text NOT NULL CHECK(length(digest)=64),
 state text NOT NULL CHECK(state IN ('prepared','retired','final_protected','cancelled')),
 intent_id uuid NOT NULL UNIQUE,final_id uuid NOT NULL UNIQUE,cancel_id uuid NOT NULL UNIQUE,
 intent_ack jsonb,final_ack jsonb,cancel_ack jsonb,created_at timestamptz NOT NULL,updated_at timestamptz NOT NULL,
 CHECK(intent_id<>final_id AND intent_id<>cancel_id AND final_id<>cancel_id)
);
CREATE UNIQUE INDEX audit_one_active_retirement ON audit_retirement_jobs(event_id) WHERE state<>'cancelled';
CREATE TABLE audit_expiry_fences (
 event_id uuid PRIMARY KEY,scope_tenant_id uuid NOT NULL REFERENCES tenants(id),event_recorded_at timestamptz NOT NULL,
 final_evidence_id uuid NOT NULL UNIQUE,digest text NOT NULL CHECK(length(digest)=64),retired_at timestamptz NOT NULL
);
GRANT SELECT,INSERT,UPDATE,DELETE ON audit_retention_holds,audit_retirement_jobs,audit_expiry_fences TO appchi_worker;
GRANT SELECT ON audit_retention_holds,audit_expiry_fences TO appchi_api;
INSERT INTO capability_gates(capability,ready,reason) VALUES('audit_retention',false,'audit_protection_and_restore_contract_required');
