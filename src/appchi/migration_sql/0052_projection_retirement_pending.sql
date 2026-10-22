-- Bound the search feed's and counts' retention probe to retirement snapshots.
-- In the Kafka-first flow no projection row becomes visible, so NOT visible alone
-- matches the tenant's whole projection history past searchable_seq.
CREATE INDEX projection_work_retirement_pending
 ON projection_work(tenant_id,seq)
 WHERE NOT visible AND (snapshot->>'live'='false' OR snapshot->>'deleted'='true');
