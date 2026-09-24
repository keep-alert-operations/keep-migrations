CREATE TABLE pipeline_leases (
 tenant_id uuid NOT NULL REFERENCES tenants(id),stream text NOT NULL CHECK(stream IN ('received','changed')),
 generation bigint NOT NULL DEFAULT 0,token uuid,epoch text,lease_until timestamptz,
 failures integer NOT NULL DEFAULT 0,next_attempt_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 blocked boolean NOT NULL DEFAULT false,reason text,
 PRIMARY KEY(tenant_id,stream)
);
CREATE TABLE pipeline_receipts (
 consumer_name text NOT NULL,topic text NOT NULL,partition integer NOT NULL,broker_offset bigint NOT NULL,
 tenant_id uuid NOT NULL REFERENCES tenants(id),outbox_id uuid NOT NULL REFERENCES application_outbox(id),
 received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(consumer_name,topic,partition,broker_offset)
);
CREATE TABLE pipeline_quarantine (
 consumer_name text NOT NULL,topic text NOT NULL,partition integer NOT NULL,broker_offset bigint NOT NULL,
 digest bytea NOT NULL,reason text NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(consumer_name,topic,partition,broker_offset)
);
GRANT SELECT,INSERT,UPDATE,DELETE ON pipeline_leases,pipeline_receipts,pipeline_quarantine TO appchi_worker;
