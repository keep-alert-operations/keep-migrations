CREATE TABLE tenants (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), kind text NOT NULL CHECK(kind IN ('global','specific')),
 name text NOT NULL, name_key text NOT NULL UNIQUE, revision bigint NOT NULL DEFAULT 1 CHECK(revision>0),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK(kind <> 'global' OR (name='Global' AND name_key='global'))
);
CREATE UNIQUE INDEX one_global ON tenants(kind) WHERE kind='global';
INSERT INTO tenants(kind,name,name_key) VALUES('global','Global','global') ON CONFLICT DO NOTHING;
CREATE TABLE authorization_guards (scope text PRIMARY KEY);
INSERT INTO authorization_guards VALUES ('identity');
CREATE TABLE principals (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), directory_source text NOT NULL, object_id text NOT NULL,
 kind text NOT NULL CHECK(kind IN ('user','team')), display_name text NOT NULL, eligible boolean NOT NULL,
 deleted boolean NOT NULL DEFAULT false, super_admin boolean NOT NULL DEFAULT false,
 evidence_generation bigint NOT NULL DEFAULT 0, verified_at timestamptz,
 UNIQUE(directory_source,object_id)
);
CREATE TABLE directory_memberships (
 team_id uuid NOT NULL REFERENCES principals(id), user_id uuid NOT NULL REFERENCES principals(id),
 PRIMARY KEY(team_id,user_id)
);
CREATE TABLE directory_verifications (
 generation bigint PRIMARY KEY, started_at timestamptz NOT NULL, completed_at timestamptz,
 complete boolean NOT NULL, semantic_revision bigint NOT NULL, coverage jsonb NOT NULL
);
CREATE TABLE tenant_grants (
 tenant_id uuid NOT NULL REFERENCES tenants(id), principal_id uuid NOT NULL REFERENCES principals(id),
 role text NOT NULL CHECK(role IN ('view','edit','admin')), PRIMARY KEY(tenant_id,principal_id)
);
CREATE TABLE oidc_bindings (
 issuer text NOT NULL, subject text NOT NULL, principal_id uuid NOT NULL REFERENCES principals(id),
 PRIMARY KEY(issuer,subject), UNIQUE(issuer,principal_id)
);
CREATE TABLE auth_sessions (
 handle_hash bytea PRIMARY KEY, principal_id uuid NOT NULL REFERENCES principals(id), issuer text NOT NULL,
 subject text NOT NULL, provider_sid text NOT NULL, tokens bytea, csrf_hash bytea NOT NULL,
 csrf_cipher bytea NOT NULL, auth_time timestamptz NOT NULL, activity_at timestamptz NOT NULL,
 absolute_at timestamptz NOT NULL, revoked_at timestamptz, deployment_epoch text NOT NULL,
 refresh_generation bigint NOT NULL DEFAULT 0, last_tenant_id uuid REFERENCES tenants(id)
);
CREATE INDEX auth_session_principal ON auth_sessions(principal_id);
CREATE INDEX auth_session_sid ON auth_sessions(issuer,provider_sid);
CREATE TABLE login_transactions (
 state_hash bytea PRIMARY KEY, browser_hash bytea NOT NULL, encrypted_state bytea NOT NULL,
 expires_at timestamptz NOT NULL, consumed boolean NOT NULL DEFAULT false
);
CREATE TABLE logout_fences (
 issuer text NOT NULL, sid text NOT NULL, event_id text NOT NULL, expires_at timestamptz NOT NULL,
 PRIMARY KEY(issuer,sid,event_id)
);
CREATE TABLE tenant_work_state (
 tenant_id uuid PRIMARY KEY REFERENCES tenants(id), admission_order bigint NOT NULL DEFAULT 0,
 change_order bigint NOT NULL DEFAULT 0, projection_seq bigint NOT NULL DEFAULT 0,
 last_clock timestamptz, blocked boolean NOT NULL DEFAULT false, failures integer NOT NULL DEFAULT 0,
 block_generation bigint NOT NULL DEFAULT 0, next_attempt_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 lease_generation bigint NOT NULL DEFAULT 0, lease_epoch text, lease_until timestamptz
);
INSERT INTO tenant_work_state(tenant_id) SELECT id FROM tenants;
CREATE TABLE tenant_view_state (
 tenant_id uuid PRIMARY KEY REFERENCES tenants(id), view_generation bigint NOT NULL DEFAULT 0,
 searchable_seq bigint NOT NULL DEFAULT 0, resource_generation bigint NOT NULL DEFAULT 0,
 purge_generation bigint NOT NULL DEFAULT 0, maintenance_generation bigint NOT NULL DEFAULT 0,
 index_epoch text NOT NULL DEFAULT 'uninitialized', verified_at timestamptz
);
INSERT INTO tenant_view_state(tenant_id) SELECT id FROM tenants;
CREATE TABLE tenant_configuration_guard (tenant_id uuid PRIMARY KEY REFERENCES tenants(id));
INSERT INTO tenant_configuration_guard SELECT id FROM tenants;
CREATE TABLE command_receipts (
 scope text NOT NULL, command_id uuid NOT NULL, fingerprint bytea NOT NULL,
 result jsonb, status integer NOT NULL, completed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(scope,command_id)
);
CREATE TABLE audit_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid REFERENCES tenants(id), actor_id uuid,
 actor_label text NOT NULL, kind text NOT NULL, recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 evidence jsonb NOT NULL
);
CREATE INDEX audit_scope_time ON audit_events(tenant_id,recorded_at,id);
CREATE TABLE operators (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL REFERENCES tenants(id),
 name text NOT NULL, name_key text NOT NULL UNIQUE, lifecycle text NOT NULL CHECK(lifecycle IN ('setup_pending','ready','deleted')),
 revision bigint NOT NULL DEFAULT 1, generation bigint NOT NULL DEFAULT 1, deletion_pending boolean NOT NULL DEFAULT false,
 integration_health text NOT NULL DEFAULT 'pending', created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(tenant_id,id)
);
CREATE TABLE operator_credentials (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL, operator_id uuid NOT NULL,
 state text NOT NULL CHECK(state IN ('prepared','current','retiring','revoked','expired')),
 verifier bytea NOT NULL UNIQUE, ciphertext bytea, kong_consumer_id text, kong_credential_id text UNIQUE,
 activated_at timestamptz, expires_at timestamptz, revoked_at timestamptz,
 FOREIGN KEY(tenant_id,operator_id) REFERENCES operators(tenant_id,id),
 CHECK(state<>'retiring' OR expires_at IS NOT NULL), CHECK(state NOT IN ('revoked','expired') OR ciphertext IS NULL)
);
CREATE UNIQUE INDEX one_current ON operator_credentials(operator_id) WHERE state='current';
CREATE UNIQUE INDEX one_retiring ON operator_credentials(operator_id) WHERE state='retiring';
CREATE TABLE ingest_requests (
 id uuid PRIMARY KEY, tenant_id uuid NOT NULL REFERENCES tenants(id), operator_id uuid,
 version text NOT NULL CHECK(version IN ('v1','v2')), retry_scope text NOT NULL, retry_key text,
 fingerprint bytea NOT NULL, receipt_hash bytea NOT NULL, response_cipher bytea NOT NULL,
 response_status integer NOT NULL, admitted_at timestamptz NOT NULL, expires_at timestamptz NOT NULL,
 UNIQUE(retry_scope,retry_key)
);
CREATE TABLE ingest_items (
 id uuid PRIMARY KEY, request_id uuid NOT NULL REFERENCES ingest_requests(id) DEFERRABLE INITIALLY DEFERRED,
 tenant_id uuid NOT NULL REFERENCES tenants(id), operator_id uuid, version text NOT NULL,
 admission_order bigint NOT NULL, received_at timestamptz NOT NULL, key_field text NOT NULL,
 key_digest bytea NOT NULL, identity_material bytea NOT NULL, payload jsonb, raw_json bytea,
 time_defaulted boolean NOT NULL, disposition text NOT NULL DEFAULT 'pending' CHECK(disposition IN ('pending','applied','rejected')),
 error_code text, alert_id uuid, occurrence_id uuid, UNIQUE(tenant_id,admission_order)
);
CREATE INDEX pending_source ON ingest_items(tenant_id,admission_order) WHERE disposition='pending';
CREATE INDEX pending_key ON ingest_items(tenant_id,version,key_digest) WHERE disposition='pending';
CREATE TABLE ingest_retry_keys (
 scope text NOT NULL, event_id text NOT NULL, fingerprint bytea NOT NULL,
 item_id uuid NOT NULL REFERENCES ingest_items(id), expires_at timestamptz,
 PRIMARY KEY(scope,event_id)
);
CREATE TABLE admission_capacity (
 scope text PRIMARY KEY, pending_items bigint NOT NULL DEFAULT 0 CHECK(pending_items>=0),
 pending_bytes bigint NOT NULL DEFAULT 0 CHECK(pending_bytes>=0), blocked boolean NOT NULL DEFAULT false
);
INSERT INTO admission_capacity(scope) VALUES('global');
INSERT INTO admission_capacity(scope) SELECT id::text FROM tenants;
CREATE TABLE admission_reservations (
 item_id uuid PRIMARY KEY REFERENCES ingest_items(id), tenant_id uuid NOT NULL REFERENCES tenants(id),
 bytes bigint NOT NULL CHECK(bytes>0), profile text NOT NULL, released boolean NOT NULL DEFAULT false
);
CREATE TABLE alert_identities (
 id uuid PRIMARY KEY, tenant_id uuid NOT NULL REFERENCES tenants(id), retired_at timestamptz,
 final_version bigint, UNIQUE(tenant_id,id)
);
CREATE TABLE alerts (
 id uuid PRIMARY KEY, tenant_id uuid NOT NULL, schema_version text NOT NULL, key_field text NOT NULL,
 operator text NOT NULL, application text NOT NULL, component text NOT NULL, node_name text, site text,
 impact text, runbook_url text, message text NOT NULL,
 severity text NOT NULL CHECK(severity IN ('critical','high','warning','clear')),
 status text NOT NULL CHECK(status IN ('firing','resolved')), source_suppressed boolean NOT NULL DEFAULT false,
 suppressed boolean NOT NULL DEFAULT false, time_created timestamptz NOT NULL, first_received_at timestamptz NOT NULL,
 timestamp timestamptz NOT NULL, occurrence_id uuid, occurrence_number bigint NOT NULL DEFAULT 0,
 opened_at timestamptz, resolved_at timestamptz, acknowledged boolean NOT NULL DEFAULT false,
 acknowledged_by uuid REFERENCES principals(id), acknowledged_at timestamptz, assignee_id uuid REFERENCES principals(id),
 revision bigint NOT NULL DEFAULT 1, projection_version bigint NOT NULL DEFAULT 1, history_id uuid NOT NULL,
 last_source_activity timestamptz NOT NULL, retention_at timestamptz,
 FOREIGN KEY(tenant_id,id) REFERENCES alert_identities(tenant_id,id), UNIQUE(tenant_id,id),
 CHECK(occurrence_number>=0), CHECK(revision>0 AND projection_version>0)
);
CREATE INDEX alerts_retention ON alerts(retention_at,id) WHERE status='resolved';
CREATE INDEX alerts_inactivity ON alerts(last_source_activity,id) WHERE status='firing';
CREATE INDEX alerts_operator ON alerts(tenant_id,operator);
CREATE TABLE alert_key_claims (
 tenant_id uuid NOT NULL, schema_version text NOT NULL, key_digest bytea NOT NULL,
 key_field text NOT NULL, identity_material bytea NOT NULL, alert_id uuid NOT NULL UNIQUE,
 PRIMARY KEY(tenant_id,schema_version,key_digest), FOREIGN KEY(tenant_id,alert_id) REFERENCES alert_identities(tenant_id,id)
);
CREATE TABLE alert_source_events (
 tenant_id uuid NOT NULL, alert_id uuid NOT NULL, id uuid NOT NULL, admission_order bigint NOT NULL,
 received_at timestamptz NOT NULL, payload jsonb NOT NULL, raw_json bytea NOT NULL,
 time_defaulted boolean NOT NULL, occurrence_id uuid,
 PRIMARY KEY(alert_id,id), FOREIGN KEY(tenant_id,alert_id) REFERENCES alert_identities(tenant_id,id)
) PARTITION BY HASH(alert_id);
CREATE TABLE alert_activity (
 tenant_id uuid NOT NULL, alert_id uuid NOT NULL, id uuid NOT NULL, change_order bigint NOT NULL,
 recorded_at timestamptz NOT NULL, effective_at timestamptz NOT NULL, actor_id uuid,
 kind text NOT NULL, evidence jsonb NOT NULL, PRIMARY KEY(alert_id,id),
 FOREIGN KEY(tenant_id,alert_id) REFERENCES alert_identities(tenant_id,id)
) PARTITION BY HASH(alert_id);
CREATE TABLE alert_occurrences (
 tenant_id uuid NOT NULL, alert_id uuid NOT NULL, id uuid NOT NULL, number bigint NOT NULL,
 opened_at timestamptz NOT NULL, resolved_at timestamptz, time_created timestamptz NOT NULL,
 PRIMARY KEY(alert_id,id), UNIQUE(alert_id,number), FOREIGN KEY(tenant_id,alert_id) REFERENCES alert_identities(tenant_id,id)
) PARTITION BY HASH(alert_id);
CREATE TABLE alert_notes (
 id uuid PRIMARY KEY, tenant_id uuid NOT NULL, alert_id uuid NOT NULL, text text NOT NULL,
 deleted boolean NOT NULL DEFAULT false, revision bigint NOT NULL DEFAULT 1, actor_id uuid NOT NULL,
 created_at timestamptz NOT NULL, occurrence_id uuid,
 FOREIGN KEY(tenant_id,alert_id) REFERENCES alert_identities(tenant_id,id)
);
CREATE TABLE alert_note_revisions (
 tenant_id uuid NOT NULL, alert_id uuid NOT NULL, note_id uuid NOT NULL, revision bigint NOT NULL,
 text text NOT NULL, deleted boolean NOT NULL, actor_id uuid NOT NULL, recorded_at timestamptz NOT NULL,
 PRIMARY KEY(alert_id,note_id,revision), FOREIGN KEY(tenant_id,alert_id) REFERENCES alert_identities(tenant_id,id)
) PARTITION BY HASH(alert_id);
DO $$ BEGIN
 FOR i IN 0..31 LOOP
  EXECUTE format('CREATE TABLE alert_source_events_%s PARTITION OF alert_source_events FOR VALUES WITH (MODULUS 32, REMAINDER %s)',i,i);
  EXECUTE format('CREATE TABLE alert_activity_%s PARTITION OF alert_activity FOR VALUES WITH (MODULUS 32, REMAINDER %s)',i,i);
  EXECUTE format('CREATE TABLE alert_occurrences_%s PARTITION OF alert_occurrences FOR VALUES WITH (MODULUS 32, REMAINDER %s)',i,i);
  EXECUTE format('CREATE TABLE alert_note_revisions_%s PARTITION OF alert_note_revisions FOR VALUES WITH (MODULUS 32, REMAINDER %s)',i,i);
 END LOOP;
END $$;
CREATE INDEX source_pages ON alert_source_events(tenant_id,alert_id,admission_order,id);
CREATE INDEX activity_pages ON alert_activity(tenant_id,alert_id,change_order,id);
CREATE TABLE correlation_journal (
 tenant_id uuid NOT NULL, change_order bigint NOT NULL, alert_id uuid NOT NULL,
 before_snapshot jsonb, after_snapshot jsonb NOT NULL, original_order bigint,
 effective_at timestamptz NOT NULL, cause text NOT NULL, PRIMARY KEY(tenant_id,change_order)
);
CREATE TABLE application_outbox (
 id uuid PRIMARY KEY, tenant_id uuid NOT NULL REFERENCES tenants(id), stream text NOT NULL,
 stream_order bigint NOT NULL, envelope bytea NOT NULL, published_at timestamptz,
 processed_at timestamptz, next_attempt_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(tenant_id,stream,stream_order)
);
CREATE INDEX pending_outbox ON application_outbox(next_attempt_at,id) WHERE published_at IS NULL;
CREATE TABLE projection_work (
 tenant_id uuid NOT NULL, seq bigint NOT NULL, alert_id uuid NOT NULL, version bigint NOT NULL,
 snapshot jsonb NOT NULL, visible boolean NOT NULL DEFAULT false, PRIMARY KEY(tenant_id,seq)
);
CREATE TABLE capability_gates (
 capability text PRIMARY KEY, ready boolean NOT NULL DEFAULT false, reason text NOT NULL
);
INSERT INTO capability_gates VALUES
 ('human_auth',false,'directory_bootstrap_required'),('v2_ingress',false,'trusted_gateway_required'),
 ('recovery',false,'independent_evidence_required'),('search',false,'index_qualification_required'),
 ('correlation',false,'capacity_and_implementation_required'),('maintenance',false,'capacity_and_implementation_required');
DO $$ BEGIN
 IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='appchi_api') THEN CREATE ROLE appchi_api NOLOGIN; END IF;
 IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='appchi_worker') THEN CREATE ROLE appchi_worker NOLOGIN; END IF;
END $$;
GRANT USAGE ON SCHEMA public TO appchi_api,appchi_worker;
GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO appchi_worker;
GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO appchi_api;
REVOKE ALL ON schema_migrations FROM appchi_api,appchi_worker;
DO $$ DECLARE tab text; BEGIN
 FOREACH tab IN ARRAY ARRAY['alerts','alert_identities','alert_key_claims','alert_source_events','alert_activity','alert_occurrences','alert_notes','alert_note_revisions','operators','operator_credentials','correlation_journal','projection_work'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',tab);
  EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY',tab);
  EXECUTE format('CREATE POLICY tenant_scope ON %I TO appchi_api USING (tenant_id::text=current_setting(''appchi.tenant_id'',true)) WITH CHECK (tenant_id::text=current_setting(''appchi.tenant_id'',true))',tab);
  EXECUTE format('CREATE POLICY worker_scope ON %I TO appchi_worker USING (true) WITH CHECK (true)',tab);
 END LOOP;
END $$;
