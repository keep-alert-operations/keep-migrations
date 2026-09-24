-- Actor labels are historical evidence captured at the note mutation.
-- Existing rows deliberately remain NULL: today's directory label cannot prove yesterday's label.
ALTER TABLE incident_note_revisions ADD COLUMN actor_display_name text;
CREATE INDEX incident_note_revision_page ON incident_note_revisions(tenant_id,incident_id,note_id,revision DESC);
CREATE INDEX incident_notes_page ON incident_notes(tenant_id,incident_id,created_at DESC,id DESC);
