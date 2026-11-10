-- Historical names cannot be reconstructed from the current directory. Existing
-- rows remain NULL; new human actions capture the name in their transaction.
ALTER TABLE alert_notes ADD COLUMN actor_display_name text;
ALTER TABLE alert_note_revisions ADD COLUMN actor_display_name text;
ALTER TABLE alert_activity ADD COLUMN actor_display_name text;
