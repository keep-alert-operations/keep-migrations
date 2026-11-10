-- Grafana panels (REV-68), after REV-67's rename (0066). A 'grafana' panel frames one
-- live Grafana panel in the browser. It references no preset and no image (the existing
-- preset, image and threshold checks already require preset_id IS NULL, image_id IS NULL
-- and thresholds = '[]' for it) and keeps its address in content ({"url": an absolute
-- http(s) address of 1-2048 characters}); the Product API checks the address against the
-- deployment's allowed Grafana. Checks are replaced, not rows: every stored panel already
-- satisfies them.
ALTER TABLE dashboard_panels
 DROP CONSTRAINT dashboard_panels_type_known,
 ADD CONSTRAINT dashboard_panels_type_known CHECK (type IN ('count','html','image','table','servicenow','grafana')),
 ADD CONSTRAINT dashboard_panels_grafana_content CHECK (type <> 'grafana' OR coalesce(
   jsonb_typeof(content->'url') = 'string'
   AND length(content->>'url') BETWEEN 1 AND 2048
   AND content->>'url' ~ '^[hH][tT][tT][pP][sS]?://', false));
