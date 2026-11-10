-- Monotonic authority continuity prerequisites; no eligibility or render success.
ALTER TABLE authorization_guards ADD COLUMN directory_revision bigint NOT NULL DEFAULT 0 CHECK(directory_revision>=0);
CREATE FUNCTION preserve_directory_authority_fence() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.scope IS DISTINCT FROM OLD.scope OR
    (NEW.directory_revision IS DISTINCT FROM OLD.directory_revision AND NEW.directory_revision<>OLD.directory_revision+1) THEN
  RAISE EXCEPTION 'Directory authority fence must advance monotonically by one';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER directory_authority_fence BEFORE UPDATE ON authorization_guards
 FOR EACH ROW EXECUTE FUNCTION preserve_directory_authority_fence();
REVOKE INSERT,DELETE,TRUNCATE ON authorization_guards FROM appchi_api,appchi_worker;

ALTER TABLE capability_gates ADD COLUMN generation bigint NOT NULL DEFAULT 0 CHECK(generation>=0);
CREATE FUNCTION preserve_human_auth_generation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='INSERT' THEN
  NEW.generation:=0;
 ELSE
  IF NEW.capability IS DISTINCT FROM OLD.capability THEN
   RAISE EXCEPTION 'Capability identity is immutable';
  END IF;
  NEW.generation:=OLD.generation;
  IF OLD.capability='human_auth' AND NEW.ready IS DISTINCT FROM OLD.ready THEN
   NEW.generation:=OLD.generation+1;
  END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER human_auth_generation BEFORE INSERT OR UPDATE ON capability_gates
 FOR EACH ROW EXECUTE FUNCTION preserve_human_auth_generation();
-- The gate trigger modifies only the row already being written. It never takes
-- the identity guard after a gate-row lock, which would invert application locks.
REVOKE DELETE,TRUNCATE ON capability_gates FROM appchi_api,appchi_worker,appchi_recovery;
