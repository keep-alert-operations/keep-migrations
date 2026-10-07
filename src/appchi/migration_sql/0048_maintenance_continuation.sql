-- Optional continuation accelerates proven temporal replay. NULL preserves the
-- exact legacy replay/bootstrap path; no old history or proof is rewritten.
ALTER TABLE maintenance_alert_checkpoints ADD COLUMN continuation jsonb;
ALTER TABLE maintenance_alert_checkpoints ADD CONSTRAINT maintenance_continuation_object
 CHECK (continuation IS NULL OR jsonb_typeof(continuation)='object');
-- Historical full snapshots remain interpretable. A versioned continuation can
-- append only its affected final interval without duplicating lifetime unions.
ALTER TABLE maintenance_union_history ADD COLUMN representation text NOT NULL DEFAULT 'full'
 CHECK (representation IN ('full','tail'));
-- Delayed replay must also find ended/deactivated segments; the due-work
-- partial index deliberately cannot serve this historical catalog lookup.
CREATE INDEX maintenance_segment_tenant_effective_end
 ON maintenance_segments(tenant_id,LEAST(end_at,COALESCE(deactivation_at,end_at)),id);
