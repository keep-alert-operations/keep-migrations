-- A timed dismissal is a separate suppression cause on the alert row (REV-49).
-- The stored suppressed flag keeps the source and maintenance causes; readers treat
-- the alert as suppressed while dismissed_until is later than their clock.
ALTER TABLE alerts
 ADD COLUMN dismissed_until timestamptz,
 ADD COLUMN dismissed_at timestamptz,
 ADD COLUMN dismissed_by uuid REFERENCES principals(id),
 ADD CONSTRAINT alerts_dismissal_complete CHECK (
  (dismissed_until IS NULL AND dismissed_at IS NULL AND dismissed_by IS NULL)
  OR (dismissed_until IS NOT NULL AND dismissed_at IS NOT NULL AND dismissed_until > dismissed_at)
 );
CREATE INDEX alerts_dismissed_until ON alerts(tenant_id,dismissed_until) WHERE dismissed_until IS NOT NULL;
