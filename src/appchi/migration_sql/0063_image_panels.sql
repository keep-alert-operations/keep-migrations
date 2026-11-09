-- Image dashboard panels (REV-62). dashboard_images holds uploaded files once per
-- tenant and SHA-256; rows are immutable apart from first_used_at, which a dashboard
-- save sets when a panel first references the image. Never-used uploads are the only
-- rows the API deletes (bounded, during later uploads). Image panels reference an
-- upload through image_id, foreign-key enforced like preset_id, or carry an https
-- address in content->'url'; exactly one. No existing row is rewritten.
CREATE TABLE dashboard_images (
 id uuid PRIMARY KEY,
 tenant_id uuid NOT NULL REFERENCES tenants(id),
 sha256 bytea NOT NULL CHECK (octet_length(sha256) = 32),
 media_type text NOT NULL CHECK (media_type IN ('image/png','image/jpeg','image/gif','image/webp')),
 width integer NOT NULL CHECK (width BETWEEN 1 AND 8000),
 height integer NOT NULL CHECK (height BETWEEN 1 AND 8000),
 byte_size integer NOT NULL CHECK (byte_size BETWEEN 1 AND 5242880),
 bytes bytea NOT NULL CHECK (octet_length(bytes) = byte_size),
 created_at timestamptz NOT NULL,
 created_by uuid NOT NULL,
 first_used_at timestamptz,
 UNIQUE (tenant_id, id),
 UNIQUE (tenant_id, sha256)
);
ALTER TABLE dashboard_images ALTER COLUMN bytes SET STORAGE EXTERNAL;
CREATE INDEX dashboard_images_unused ON dashboard_images(tenant_id, created_at) WHERE first_used_at IS NULL;
ALTER TABLE dashboard_images ENABLE ROW LEVEL SECURITY;
ALTER TABLE dashboard_images FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON dashboard_images TO appchi_api
 USING (tenant_id::text=current_setting('appchi.tenant_id',true))
 WITH CHECK (tenant_id::text=current_setting('appchi.tenant_id',true));
CREATE POLICY worker_scope ON dashboard_images TO appchi_worker USING (true) WITH CHECK (true);
GRANT SELECT,INSERT,UPDATE,DELETE ON dashboard_images TO appchi_api,appchi_worker;

ALTER TABLE dashboard_panels
 ADD COLUMN image_id uuid,
 ADD CONSTRAINT dashboard_panels_image FOREIGN KEY (tenant_id, image_id) REFERENCES dashboard_images(tenant_id, id),
 DROP CONSTRAINT dashboard_panels_type_known,
 ADD CONSTRAINT dashboard_panels_type_known CHECK (type IN ('count','html','image')),
 ADD CONSTRAINT dashboard_panels_image_only CHECK (type = 'image' OR image_id IS NULL),
 ADD CONSTRAINT dashboard_panels_image_source CHECK (
  type <> 'image' OR ((image_id IS NOT NULL) <> coalesce(jsonb_typeof(content->'url') = 'string', false))
 );
CREATE INDEX dashboard_panels_images ON dashboard_panels(tenant_id, image_id) WHERE image_id IS NOT NULL;
