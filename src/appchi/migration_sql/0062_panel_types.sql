-- Dashboard panel types (REV-57). type names what a panel shows: 'count' is the
-- preset count panel, 'html' shows sanitized HTML and references no preset.
-- content holds type-specific settings ({"html": ...} for HTML panels); count panels
-- keep their preset_id and thresholds columns so preset references stay
-- foreign-key enforced. The defaults make every existing row, and any row an older
-- API writes without naming the new columns, a count panel; no row is rewritten.
ALTER TABLE dashboard_panels
 ADD COLUMN type text NOT NULL DEFAULT 'count',
 ADD COLUMN content jsonb NOT NULL DEFAULT '{}'::jsonb,
 ALTER COLUMN preset_id DROP NOT NULL,
 ADD CONSTRAINT dashboard_panels_type_known CHECK (type IN ('count','html')),
 ADD CONSTRAINT dashboard_panels_count_preset CHECK ((type = 'count') = (preset_id IS NOT NULL)),
 ADD CONSTRAINT dashboard_panels_html_plain CHECK (type = 'count' OR thresholds = '[]'::jsonb),
 ADD CONSTRAINT dashboard_panels_content_object CHECK (jsonb_typeof(content) = 'object'),
 ADD CONSTRAINT dashboard_panels_html_content CHECK (type <> 'html' OR coalesce(jsonb_typeof(content->'html') = 'string', false));
