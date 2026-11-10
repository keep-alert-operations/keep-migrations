-- Incident count panels (REV-69), after REV-68's Grafana panels (0067). An
-- 'incident_count' panel counts the incidents its preset's alerts are in, so it keeps the
-- preset reference in preset_id like count and table panels, its count thresholds in
-- thresholds like count and servicenow panels, and which incident statuses it counts in
-- content ({"incident_status": "open" | "investigating" | "both"}). Checks are replaced,
-- not rows: every stored panel already satisfies the widened checks.
ALTER TABLE dashboard_panels
 DROP CONSTRAINT dashboard_panels_type_known,
 DROP CONSTRAINT dashboard_panels_preset_reference,
 DROP CONSTRAINT dashboard_panels_thresholds_counted,
 ADD CONSTRAINT dashboard_panels_type_known CHECK (type IN ('count','html','image','table','servicenow','grafana','incident_count')),
 ADD CONSTRAINT dashboard_panels_preset_reference CHECK ((type IN ('count','table','incident_count')) = (preset_id IS NOT NULL)),
 ADD CONSTRAINT dashboard_panels_thresholds_counted CHECK (type IN ('count','servicenow','incident_count') OR thresholds = '[]'::jsonb),
 ADD CONSTRAINT dashboard_panels_incident_count_content CHECK (type <> 'incident_count' OR coalesce(
   jsonb_typeof(content->'incident_status') = 'string'
   AND content->>'incident_status' IN ('open','investigating','both'), false));
