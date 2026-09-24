-- Preserve expiry boundaries after intermediate content revisions are compacted.
ALTER TABLE correlation_rule_revisions ADD COLUMN superseded_at timestamptz;
-- Historical keys are filled by bounded Python Unicode-profile warmup. Never
-- approximate NFC/casefold using database locale-dependent lower().
ALTER TABLE correlation_rule_revisions ADD COLUMN name_key text;
UPDATE correlation_rule_revisions v SET name_key=r.name_key FROM correlation_rules r
WHERE (v.tenant_id,v.rule_id,v.revision)=(r.tenant_id,r.id,r.revision);
WITH versions AS (
 SELECT tenant_id,rule_id,revision,lead(recorded_at) OVER(PARTITION BY tenant_id,rule_id ORDER BY revision) AS next_at
 FROM correlation_rule_revisions
)
UPDATE correlation_rule_revisions r SET superseded_at=v.next_at FROM versions v
WHERE (r.tenant_id,r.rule_id,r.revision)=(v.tenant_id,v.rule_id,v.revision);
CREATE FUNCTION correlation_revision_supersession() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 UPDATE correlation_rule_revisions SET name_key=r.name_key FROM correlation_rules r
 WHERE correlation_rule_revisions.tenant_id=NEW.tenant_id AND correlation_rule_revisions.rule_id=NEW.rule_id
 AND correlation_rule_revisions.revision=NEW.revision AND r.tenant_id=NEW.tenant_id AND r.id=NEW.rule_id;
 UPDATE correlation_rule_revisions SET superseded_at=NEW.recorded_at
 WHERE tenant_id=NEW.tenant_id AND rule_id=NEW.rule_id AND revision=NEW.revision-1;
 RETURN NEW;
END $$;
CREATE TRIGGER correlation_revision_supersession AFTER INSERT ON correlation_rule_revisions
FOR EACH ROW EXECUTE FUNCTION correlation_revision_supersession();
-- Event metadata has a separate recording-time lifetime from configuration content.
ALTER TABLE correlation_rule_revisions ALTER COLUMN action DROP NOT NULL,
 ALTER COLUMN changed_fields DROP NOT NULL, ALTER COLUMN command_id DROP NOT NULL,
 ALTER COLUMN actor_id DROP NOT NULL, ALTER COLUMN actor_label DROP NOT NULL;
ALTER TABLE correlation_delete_jobs ALTER COLUMN actor_label DROP NOT NULL;
CREATE INDEX correlation_incident_context_retention ON incidents(tenant_id,context_id) WHERE context_id IS NOT NULL;

CREATE FUNCTION correlation_rule_proof_pending(tenant_p uuid,rule_p uuid) RETURNS boolean
LANGUAGE sql STABLE AS $$
 SELECT NOT EXISTS(SELECT 1 FROM correlation_consumer_state c JOIN tenant_work_state w USING(tenant_id)
  WHERE c.tenant_id=tenant_p AND c.health='healthy' AND NOT c.pending AND c.change_order=w.change_order
  AND NOT EXISTS(SELECT 1 FROM correlation_journal j WHERE j.tenant_id=c.tenant_id AND j.change_order>c.change_order)
  AND NOT EXISTS(SELECT 1 FROM maintenance_effect_outbox e WHERE e.tenant_id=c.tenant_id
    AND (e.change_order>c.change_order OR e.processed_at IS NULL)))
 OR EXISTS(SELECT 1 FROM correlation_delete_jobs j WHERE j.tenant_id=tenant_p AND j.rule_id=rule_p
    AND (j.state IN ('prepared','deleted') OR (j.state='cancelled' AND j.cancel_ack IS NULL)))
$$;
CREATE FUNCTION correlation_revision_retained(tenant_p uuid,rule_p uuid,revision_p bigint,at_p timestamptz)
RETURNS boolean LANGUAGE sql STABLE AS $$
 SELECT EXISTS(SELECT 1 FROM correlation_rule_revisions v
 JOIN correlation_rule_identities p ON p.tenant_id=v.tenant_id AND p.id=v.rule_id
 LEFT JOIN correlation_rules r ON r.tenant_id=p.tenant_id AND r.id=p.id
 WHERE v.tenant_id=tenant_p AND v.rule_id=rule_p AND v.revision=revision_p AND (
  v.superseded_at+interval '2160 hours'>at_p OR v.recorded_at+interval '2160 hours'>at_p
  OR (v.revision=coalesce(r.revision,p.final_revision) AND (p.deleted_at IS NULL OR p.deleted_at+interval '2160 hours'>at_p))
  OR EXISTS(SELECT 1 FROM correlation_revision_holds h WHERE h.tenant_id=v.tenant_id AND h.rule_id=v.rule_id
    AND h.revision=v.revision AND h.released_at IS NULL)
  OR EXISTS(SELECT 1 FROM correlation_decisions d WHERE d.tenant_id=v.tenant_id AND d.rule_id=v.rule_id AND d.rule_revision=v.revision)
  OR (v.revision=coalesce(r.revision,p.final_revision) AND (EXISTS(SELECT 1 FROM correlation_contexts x
    WHERE x.tenant_id=v.tenant_id AND x.rule_id=v.rule_id AND (x.active_incident_id IS NOT NULL
      OR EXISTS(SELECT 1 FROM incidents i WHERE i.tenant_id=x.tenant_id AND i.context_id=x.id)))
    OR EXISTS(SELECT 1 FROM correlation_evidence e WHERE e.tenant_id=v.tenant_id AND e.rule_id=v.rule_id)))
  OR correlation_rule_proof_pending(v.tenant_id,v.rule_id)))
$$;
CREATE FUNCTION correlation_hold_retention_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.released_at IS NOT NULL THEN RETURN NEW; END IF;
 -- Shared with configuration edits, incident proof release and cleanup. Normal
 -- domain callers already own this lock before acquiring narrower resources.
 PERFORM 1 FROM tenant_work_state WHERE tenant_id=NEW.tenant_id FOR UPDATE;
 PERFORM 1 FROM correlation_rule_revisions WHERE tenant_id=NEW.tenant_id AND rule_id=NEW.rule_id
  AND revision=NEW.revision FOR UPDATE;
 IF NOT correlation_revision_retained(NEW.tenant_id,NEW.rule_id,NEW.revision,clock_timestamp()) THEN
  RAISE EXCEPTION 'Correlation revision is no longer retained' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER correlation_hold_retention_guard BEFORE INSERT OR UPDATE ON correlation_revision_holds
 FOR EACH ROW EXECUTE FUNCTION correlation_hold_retention_guard();
REVOKE ALL ON FUNCTION correlation_rule_proof_pending(uuid,uuid),correlation_revision_retained(uuid,uuid,bigint,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION correlation_rule_proof_pending(uuid,uuid),correlation_revision_retained(uuid,uuid,bigint,timestamptz) TO appchi_api,appchi_worker;
