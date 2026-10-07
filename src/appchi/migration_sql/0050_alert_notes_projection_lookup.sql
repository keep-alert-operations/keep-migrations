-- Bound projection note probes and streaming reads to the selected alert.
-- Deleted notes are absent from the rebuildable current-alert projection.
CREATE INDEX alert_notes_projection_lookup
 ON alert_notes(tenant_id,alert_id,id) WHERE NOT deleted;
