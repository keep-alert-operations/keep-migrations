-- ServiceNow ticket panels (REV-65), after REV-63's table panels (0064). A 'servicenow'
-- panel shows a team's ticket count from the deployment's counting service. It references
-- no preset (dashboard_panels_preset_reference already requires preset_id IS NULL), keeps
-- its settings in content ({"team": trimmed NFC text of 1-200 characters without control
-- characters, "ticket_state": open|in_progress|both, "detection": hamal|direct|all}) and
-- its count thresholds in thresholds, like a count panel. Checks are replaced, not rows:
-- every stored panel already satisfies them.
ALTER TABLE dashboard_panels
 DROP CONSTRAINT dashboard_panels_type_known,
 DROP CONSTRAINT dashboard_panels_html_plain,
 ADD CONSTRAINT dashboard_panels_type_known CHECK (type IN ('count','html','image','table','servicenow')),
 ADD CONSTRAINT dashboard_panels_thresholds_counted CHECK (type IN ('count','servicenow') OR thresholds = '[]'::jsonb),
 ADD CONSTRAINT dashboard_panels_servicenow_content CHECK (type <> 'servicenow' OR coalesce(
   jsonb_typeof(content->'team') = 'string'
   AND length(content->>'team') BETWEEN 1 AND 200
   AND content->>'team' = btrim(content->>'team')
   AND content->>'team' !~ '[[:cntrl:]]'
   AND content->>'team' IS NFC NORMALIZED
   AND jsonb_typeof(content->'ticket_state') = 'string' AND content->>'ticket_state' IN ('open','in_progress','both')
   AND jsonb_typeof(content->'detection') = 'string' AND content->>'detection' IN ('hamal','direct','all'), false));
