CREATE TABLE live_hint_outbox (
 tenant_id uuid PRIMARY KEY REFERENCES tenants(id),generation bigint NOT NULL,
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE FUNCTION enqueue_live_hint() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO live_hint_outbox(tenant_id,generation) VALUES(NEW.tenant_id,NEW.view_generation)
 ON CONFLICT(tenant_id) DO UPDATE SET generation=EXCLUDED.generation,updated_at=clock_timestamp();
 RETURN NEW;
END $$;
CREATE TRIGGER tenant_live_hint AFTER INSERT OR UPDATE ON tenant_view_state
 FOR EACH ROW EXECUTE FUNCTION enqueue_live_hint();
INSERT INTO live_hint_outbox(tenant_id,generation) SELECT tenant_id,view_generation FROM tenant_view_state;
GRANT SELECT,INSERT,UPDATE,DELETE ON live_hint_outbox TO appchi_worker;
GRANT INSERT,UPDATE ON live_hint_outbox TO appchi_api;
ALTER TABLE live_hint_outbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE live_hint_outbox FORCE ROW LEVEL SECURITY;
CREATE POLICY live_hint_tenant ON live_hint_outbox TO appchi_api
 USING(tenant_id::text=current_setting('appchi.tenant_id',true))
 WITH CHECK(tenant_id::text=current_setting('appchi.tenant_id',true));
CREATE POLICY live_hint_worker ON live_hint_outbox TO appchi_worker USING(true) WITH CHECK(true);
GRANT SELECT ON live_hint_outbox TO appchi_api;
