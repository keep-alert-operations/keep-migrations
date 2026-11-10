-- The Product API publishes cross-tenant generation hints, never alert bodies.
-- Keep all domain RLS policies and tenant-scoped INSERT/UPDATE unchanged.
GRANT DELETE ON live_hint_outbox TO appchi_api;
CREATE POLICY live_hint_api_publish_read ON live_hint_outbox
 FOR SELECT TO appchi_api USING (true);
CREATE POLICY live_hint_api_publish_delete ON live_hint_outbox
 FOR DELETE TO appchi_api USING (true);
