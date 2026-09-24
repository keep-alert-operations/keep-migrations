CREATE TABLE command_retention (
 scope text NOT NULL,command_id uuid NOT NULL,tenant_id uuid NOT NULL REFERENCES tenants(id),
 family text NOT NULL CHECK(family IN ('tenant','preset','dashboard','maintenance','correlation','operator','source-processing-retry')),
 operator_operation_id uuid REFERENCES operator_operations(id),
 configuration_delete_id uuid REFERENCES configuration_delete_jobs(id),
 maintenance_delete_id uuid REFERENCES maintenance_delete_jobs(id),
 correlation_delete_id uuid REFERENCES correlation_delete_jobs(id),
 registered_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(scope,command_id),FOREIGN KEY(scope,command_id) REFERENCES command_receipts(scope,command_id)
);
CREATE TABLE command_retention_holds (
 scope text NOT NULL,command_id uuid NOT NULL,kind text NOT NULL CHECK(kind IN ('pending_work','reference','recovery')),
 reference text NOT NULL CHECK(length(reference) BETWEEN 1 AND 1024),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),released_at timestamptz,
 PRIMARY KEY(scope,command_id,kind,reference),
 FOREIGN KEY(scope,command_id) REFERENCES command_receipts(scope,command_id)
);
CREATE FUNCTION guard_command_retention_hold() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 PERFORM scope FROM command_receipts WHERE scope=NEW.scope AND command_id=NEW.command_id AND result IS NOT NULL FOR UPDATE;
 IF NOT FOUND AND NEW.released_at IS NULL THEN
  RAISE EXCEPTION 'command_result_already_erased' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER command_retention_hold_guard BEFORE INSERT OR UPDATE ON command_retention_holds
 FOR EACH ROW EXECUTE FUNCTION guard_command_retention_hold();
CREATE INDEX command_result_age_scan ON command_receipts(completed_at,scope,command_id) WHERE result IS NOT NULL;
-- Internal replay indexes follow command_receipts scope, not a product collection.
GRANT SELECT,INSERT ON command_retention TO appchi_api;
GRANT SELECT ON command_retention_holds TO appchi_api;
GRANT SELECT,INSERT,UPDATE,DELETE ON command_retention,command_retention_holds TO appchi_worker;
