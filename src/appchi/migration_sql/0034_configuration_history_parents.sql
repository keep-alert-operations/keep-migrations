-- Exact historical names and holds that cannot revive expired bodies.
ALTER TABLE preset_revisions ADD COLUMN name_key text;
ALTER TABLE dashboard_revisions ADD COLUMN name_key text;
UPDATE preset_revisions r SET name_key=p.name_key FROM presets p
 WHERE p.tenant_id=r.tenant_id AND p.id=r.id AND p.revision=r.revision AND p.name=r.snapshot->>'name';
UPDATE dashboard_revisions r SET name_key=p.name_key FROM dashboards p
 WHERE p.tenant_id=r.tenant_id AND p.id=r.id AND p.revision=r.revision AND p.name=r.snapshot->>'name';
CREATE FUNCTION configuration_revision_name() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 EXECUTE format('SELECT name_key FROM %I WHERE tenant_id=$1 AND id=$2 AND revision=$3 AND name=$4',TG_ARGV[0])
 INTO NEW.name_key USING NEW.tenant_id,NEW.id,NEW.revision,NEW.snapshot->>'name';
 RETURN NEW;
END $$;
CREATE TRIGGER preset_revision_name BEFORE INSERT ON preset_revisions FOR EACH ROW EXECUTE FUNCTION configuration_revision_name('presets');
CREATE TRIGGER dashboard_revision_name BEFORE INSERT ON dashboard_revisions FOR EACH ROW EXECUTE FUNCTION configuration_revision_name('dashboards');
CREATE INDEX preset_revision_tenant_history ON preset_revisions(tenant_id,id,revision DESC);
CREATE INDEX dashboard_revision_tenant_history ON dashboard_revisions(tenant_id,id,revision DESC);
CREATE INDEX configuration_delete_resource_revision ON configuration_delete_jobs(tenant_id,resource_kind,resource_id,expected_revision);

CREATE FUNCTION configuration_pending_revision(target_tenant uuid,target_kind text,target_id uuid,target_revision bigint,event_only boolean DEFAULT false)
 RETURNS boolean LANGUAGE sql STABLE AS $$
 SELECT EXISTS(SELECT 1 FROM configuration_delete_jobs j
  WHERE j.tenant_id=target_tenant AND j.resource_kind=target_kind AND j.resource_id=target_id
  AND (target_revision=j.expected_revision+1 OR (NOT event_only AND target_revision=j.expected_revision))
  AND (j.state IN ('prepared','deleted') OR (j.state='cancelled' AND j.cancel_ack IS NULL)
    OR (j.state='final_protected' AND j.final_ack IS NULL)))
$$;

-- Same record-scoped predicate as configuration.retention.retained_versions.
-- BEFORE INSERT/reactivation observes preexisting holds, never the new hold itself.
CREATE FUNCTION configuration_revision_is_retained(target_tenant uuid,target_kind text,target_id uuid,target_revision bigint,at_time timestamptz)
 RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE current_table text; revision_table text; kept boolean;
BEGIN
 IF target_kind='preset' THEN current_table:='presets';revision_table:='preset_revisions';
 ELSIF target_kind='dashboard' THEN current_table:='dashboards';revision_table:='dashboard_revisions';
 ELSE RAISE EXCEPTION 'Unknown configuration kind'; END IF;
 EXECUTE format($query$
 SELECT EXISTS(SELECT 1 FROM %I r
 JOIN configuration_identities i ON i.tenant_id=r.tenant_id AND i.resource_kind=$4 AND i.resource_id=r.id
 LEFT JOIN %I p ON p.tenant_id=r.tenant_id AND p.id=r.id
 WHERE r.tenant_id=$1 AND r.id=$2 AND r.revision=$3 AND (
  (r.superseded_at IS NOT NULL AND r.superseded_at+interval '2160 hours'>$5)
  OR (r.revision=coalesce(p.revision,i.final_revision) AND (i.deleted_at IS NULL OR i.deleted_at+interval '2160 hours'>$5))
  OR configuration_pending_revision(r.tenant_id,$4,r.id,r.revision)
  OR EXISTS(SELECT 1 FROM configuration_retention_holds h WHERE h.tenant_id=r.tenant_id
    AND h.resource_kind=$4 AND h.resource_id=r.id AND h.released_at IS NULL AND (h.revision IS NULL OR h.revision=r.revision))
  OR EXISTS(SELECT 1 FROM configuration_activity a WHERE a.tenant_id=r.tenant_id AND a.resource_kind=$4 AND a.resource_id=r.id
    AND r.revision IN(a.before_revision,a.after_revision) AND (a.recorded_at+interval '2160 hours'>$5
      OR (a.kind='deleted' AND configuration_pending_revision(a.tenant_id,a.resource_kind,a.resource_id,a.revision,true)) OR EXISTS(
      SELECT 1 FROM configuration_retention_holds h WHERE h.tenant_id=a.tenant_id AND h.resource_kind=a.resource_kind
      AND h.resource_id=a.resource_id AND h.released_at IS NULL AND (h.revision IS NULL OR h.revision=a.revision))))
 ))$query$,revision_table,current_table)
 INTO kept USING target_tenant,target_id,target_revision,target_kind,at_time;
 RETURN kept;
END $$;

CREATE OR REPLACE FUNCTION configuration_hold_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE current_table text; revision_table text; current_revision bigint; has_expired boolean; at_time timestamptz;
BEGIN
 IF TG_OP='UPDATE' AND (NEW.id,NEW.tenant_id,NEW.resource_kind,NEW.resource_id,NEW.revision)
    IS DISTINCT FROM (OLD.id,OLD.tenant_id,OLD.resource_kind,OLD.resource_id,OLD.revision) THEN
  RAISE EXCEPTION 'Configuration hold scope is immutable';
 END IF;
 PERFORM 1 FROM tenant_configuration_guard WHERE tenant_id=NEW.tenant_id FOR UPDATE;
 IF NEW.released_at IS NOT NULL THEN RETURN NEW; END IF;
 at_time:=clock_timestamp();
 IF NEW.revision IS NOT NULL THEN
  IF NOT configuration_revision_is_retained(NEW.tenant_id,NEW.resource_kind,NEW.resource_id,NEW.revision,at_time) THEN
   RAISE EXCEPTION 'Configuration revision already expired or erased';
  END IF;
  IF EXISTS(SELECT 1 FROM configuration_activity a WHERE a.tenant_id=NEW.tenant_id AND a.resource_kind=NEW.resource_kind
    AND a.resource_id=NEW.resource_id AND a.revision=NEW.revision AND a.recorded_at+interval '2160 hours'<=at_time
    AND NOT (a.kind='deleted' AND configuration_pending_revision(a.tenant_id,a.resource_kind,a.resource_id,a.revision,true))
    AND NOT EXISTS(SELECT 1 FROM configuration_retention_holds h WHERE h.tenant_id=a.tenant_id AND h.resource_kind=a.resource_kind
      AND h.resource_id=a.resource_id AND h.released_at IS NULL AND (h.revision IS NULL OR h.revision=a.revision))) THEN
   RAISE EXCEPTION 'Configuration hold would revive expired activity';
  END IF;
  RETURN NEW;
 END IF;
 IF NEW.resource_kind='preset' THEN current_table:='presets';revision_table:='preset_revisions';
 ELSIF NEW.resource_kind='dashboard' THEN current_table:='dashboards';revision_table:='dashboard_revisions';
 ELSE RAISE EXCEPTION 'Unknown configuration kind'; END IF;
 EXECUTE format('SELECT revision FROM %I WHERE tenant_id=$1 AND id=$2',current_table)
 INTO current_revision USING NEW.tenant_id,NEW.resource_id;
 IF current_revision IS NULL OR NOT configuration_revision_is_retained(NEW.tenant_id,NEW.resource_kind,NEW.resource_id,current_revision,at_time) THEN
  RAISE EXCEPTION 'Configuration current body already expired or erased';
 END IF;
 -- Whole-resource holds must not widen retention to expired physical leftovers.
 EXECUTE format('SELECT EXISTS(SELECT 1 FROM %I WHERE tenant_id=$1 AND id=$2 AND NOT configuration_revision_is_retained(tenant_id,$3,id,revision,$4))',revision_table)
 INTO has_expired USING NEW.tenant_id,NEW.resource_id,NEW.resource_kind,at_time;
 IF has_expired THEN RAISE EXCEPTION 'Whole configuration hold would revive expired history'; END IF;
 IF EXISTS(SELECT 1 FROM configuration_activity a WHERE a.tenant_id=NEW.tenant_id AND a.resource_kind=NEW.resource_kind
   AND a.resource_id=NEW.resource_id AND a.recorded_at+interval '2160 hours'<=at_time
   AND NOT (a.kind='deleted' AND configuration_pending_revision(a.tenant_id,a.resource_kind,a.resource_id,a.revision,true))
   AND NOT EXISTS(SELECT 1 FROM configuration_retention_holds h WHERE h.tenant_id=a.tenant_id AND h.resource_kind=a.resource_kind
     AND h.resource_id=a.resource_id AND h.released_at IS NULL AND (h.revision IS NULL OR h.revision=a.revision))) THEN
  RAISE EXCEPTION 'Whole configuration hold would revive expired activity';
 END IF;
 RETURN NEW;
END $$;
