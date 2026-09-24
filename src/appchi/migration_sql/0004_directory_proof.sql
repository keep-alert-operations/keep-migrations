CREATE TABLE directory_edges(parent_id uuid NOT NULL REFERENCES principals(id),child_id uuid NOT NULL REFERENCES principals(id),PRIMARY KEY(parent_id,child_id));
CREATE TABLE directory_root_checkpoints(root_id uuid PRIMARY KEY REFERENCES principals(id),generation bigint NOT NULL,verified_at timestamptz NOT NULL,semantic_digest text NOT NULL);
CREATE SEQUENCE directory_generation_seq;
ALTER TABLE directory_verifications ADD COLUMN source text NOT NULL DEFAULT 'unconfigured';
ALTER TABLE directory_verifications ADD COLUMN failures jsonb NOT NULL DEFAULT '[]';
ALTER TABLE directory_verifications ADD COLUMN target_missed boolean NOT NULL DEFAULT false;
GRANT SELECT,INSERT,UPDATE,DELETE ON directory_edges,directory_root_checkpoints TO appchi_worker;
GRANT SELECT ON directory_edges,directory_root_checkpoints TO appchi_api;
GRANT USAGE,SELECT ON directory_generation_seq TO appchi_worker;
