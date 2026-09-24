-- Draft: terminal identities remain durable after diagnostic content expires.
ALTER TABLE operator_operations ADD COLUMN diagnostics_retired_at timestamptz;
ALTER TABLE operator_operations ALTER COLUMN actor_label DROP NOT NULL;
CREATE INDEX operator_diagnostics_age ON operator_operations(completed_at,tenant_id,operator_id,id)
 WHERE diagnostics_retired_at IS NULL AND completed_at IS NOT NULL
 AND state IN ('completed','cancelled','superseded');
CREATE INDEX operator_step_cleanup ON operator_steps(tenant_id,operator_id,operation_id,id);
CREATE INDEX command_operator_dependency ON command_retention(operator_operation_id)
 WHERE operator_operation_id IS NOT NULL;
CREATE INDEX legacy_command_operator_dependency ON command_receipts((result->'data'->'operation'->>'id'))
 WHERE result IS NOT NULL;
CREATE INDEX operator_predecessor_journal ON operator_operations(tenant_id,operator_id,kind,created_at DESC)
 WHERE completed_at IS NOT NULL;

-- Minimal operation identity is also the stale-worker fence.
REVOKE DELETE ON operator_operations FROM appchi_api,appchi_worker;
CREATE FUNCTION protect_retired_operator_operation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF OLD.diagnostics_retired_at IS NOT NULL AND NEW IS DISTINCT FROM OLD THEN
  RAISE EXCEPTION 'operator_diagnostics_already_retired' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER operator_retired_operation_immutable BEFORE UPDATE ON operator_operations
 FOR EACH ROW EXECUTE FUNCTION protect_retired_operator_operation();
CREATE FUNCTION protect_retired_operator_steps() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 PERFORM id FROM operator_operations
  WHERE tenant_id=NEW.tenant_id AND operator_id=NEW.operator_id AND id=NEW.operation_id
  AND diagnostics_retired_at IS NULL FOR UPDATE;
 IF NOT FOUND THEN
  RAISE EXCEPTION 'operator_diagnostics_already_retired' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER operator_retired_steps_guard BEFORE INSERT OR UPDATE ON operator_steps
 FOR EACH ROW EXECUTE FUNCTION protect_retired_operator_steps();
