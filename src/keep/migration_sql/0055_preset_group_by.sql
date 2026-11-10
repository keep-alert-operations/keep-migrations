-- A saved preset may group its results by one field (REV-44); null means no
-- grouping. The API validates the field, and revisions keep their own snapshots.
ALTER TABLE presets ADD COLUMN group_by text;
