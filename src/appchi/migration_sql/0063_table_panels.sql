-- Alert table panels (REV-63). A 'table' panel lists its preset's latest alerts, so it
-- keeps the preset reference in preset_id, like a count panel, and its row count in
-- content ({"rows": 1..50}); thresholds stay empty. Checks are replaced, not rows:
-- every stored count and html panel already satisfies the widened checks.
ALTER TABLE dashboard_panels
 DROP CONSTRAINT dashboard_panels_type_known,
 DROP CONSTRAINT dashboard_panels_count_preset,
 ADD CONSTRAINT dashboard_panels_type_known CHECK (type IN ('count','html','table')),
 ADD CONSTRAINT dashboard_panels_preset_reference CHECK ((type IN ('count','table')) = (preset_id IS NOT NULL)),
 ADD CONSTRAINT dashboard_panels_table_rows CHECK (type <> 'table' OR coalesce(
   jsonb_typeof(content->'rows') = 'number' AND (content->>'rows') ~ '^([1-9]|[1-4][0-9]|50)$', false));
