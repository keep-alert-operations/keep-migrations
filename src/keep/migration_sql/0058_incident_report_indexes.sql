-- Incident reports (REV-53) read a tenant's lifecycle cycles by opening and by
-- resolution time, and each cycle's assignment history, at request time.
-- These indexes keep those reads to the requested period; the API is correct
-- without them, only slower. The runner's single transaction rules out
-- CREATE INDEX CONCURRENTLY, so the build blocks incident cycle and activity
-- writes for one scan of each table: run it in the stopped-writer window.
CREATE INDEX incident_cycles_tenant_opened ON incident_cycles(tenant_id,opened_at);
CREATE INDEX incident_cycles_tenant_resolved ON incident_cycles(tenant_id,resolved_at) WHERE resolved_at IS NOT NULL;
CREATE INDEX incident_activity_assignee ON incident_activity(incident_id,recorded_at)
  WHERE kind IN ('assignment','eligibility_lost');
