-- Keep password sign-in and the ADAPI directory replace Keycloak (REV-73), after
-- ServiceNow tickets on incidents (0069, REV-70). People sign in with a Keep form and an
-- LDAP bind, so the OpenID Connect state goes: provider bindings, login transactions,
-- back-channel logout fences and the session's provider, token, refresh and activity
-- columns. A session keeps its handle, principal, CSRF secret, sign-in time, absolute
-- expiry, revocation, deployment epoch and last tenant. Nothing else references the
-- dropped tables or columns: no view, function, trigger, policy or foreign key; their
-- grants (including keep_recovery's on login_transactions) go with them.
DROP INDEX auth_session_sid;
ALTER TABLE auth_sessions
 DROP COLUMN issuer,
 DROP COLUMN subject,
 DROP COLUMN provider_sid,
 DROP COLUMN tokens,
 DROP COLUMN refresh_generation,
 DROP COLUMN refresh_started_at,
 DROP COLUMN refresh_at,
 DROP COLUMN refresh_uncertain,
 DROP COLUMN activity_at;
DROP TABLE oidc_bindings;
DROP TABLE login_transactions;
DROP TABLE logout_fences;

-- A principal an admin picks is saved from the directory when it is picked. A save that
-- doesn't fit the request waits in directory_verification_requests, one row per
-- (source, object_id) by its primary key, with its kind, the lease of the API process
-- saving it and the reason the last save failed. Existing rows came from the old
-- search path and have no kind, so they are removed.
DELETE FROM directory_verification_requests;
ALTER TABLE directory_verification_requests
 ADD COLUMN kind text NOT NULL,
 ADD COLUMN lease_owner uuid,
 ADD COLUMN lease_until timestamptz,
 ADD COLUMN last_failure text,
 ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now(),
 ADD CONSTRAINT directory_verification_requests_kind CHECK (kind IN ('user','team')),
 ADD CONSTRAINT directory_verification_requests_last_failure CHECK (last_failure IS NULL OR last_failure IN (
  'directory_unavailable','directory_group_too_large','directory_verification_deadline','directory_busy'));

-- The Product API now claims, updates and deletes pending saves and publishes the saved
-- principal itself. It already writes principals, memberships, verifications, audit
-- events, capability gates and sessions and updates the identity guard; publication also
-- writes directory edges and root checkpoints and allocates a directory generation.
GRANT SELECT,UPDATE,DELETE ON directory_verification_requests TO keep_api;
GRANT INSERT,UPDATE,DELETE ON directory_edges,directory_root_checkpoints TO keep_api;
GRANT USAGE ON SEQUENCE directory_generation_seq TO keep_api;
