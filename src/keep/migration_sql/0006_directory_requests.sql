CREATE TABLE directory_verification_requests(source text NOT NULL,object_id text NOT NULL,requested_at timestamptz NOT NULL DEFAULT clock_timestamp(),PRIMARY KEY(source,object_id));
GRANT SELECT,INSERT,UPDATE,DELETE ON directory_verification_requests TO appchi_worker;
GRANT INSERT ON directory_verification_requests TO appchi_api;
