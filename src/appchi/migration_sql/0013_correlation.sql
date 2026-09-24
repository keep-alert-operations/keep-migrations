-- Configuration/evidence authority only. The consumer remains readiness-gated.
CREATE TABLE correlation_rule_identities (
 id uuid PRIMARY KEY,tenant_id uuid NOT NULL REFERENCES tenants(id),deleted_at timestamptz,final_revision bigint,
 UNIQUE(tenant_id,id)
);
CREATE TABLE correlation_rules (
 id uuid PRIMARY KEY,tenant_id uuid NOT NULL,revision bigint NOT NULL CHECK(revision>0),
 epoch bigint NOT NULL CHECK(epoch>0),grouping_generation bigint NOT NULL CHECK(grouping_generation>0),
 name text NOT NULL,name_key text NOT NULL,name_profile text NOT NULL,
 description text NOT NULL,severity text NOT NULL CHECK(severity IN ('critical','high','medium','low')),
 window_minutes integer NOT NULL CHECK(window_minutes BETWEEN 1 AND 1440),group_by jsonb NOT NULL,
 enabled boolean NOT NULL,health text NOT NULL CHECK(health IN ('healthy','delayed','blocked','recovery_needed')),
 blocked_reason text,last_reset_reason text,profile text NOT NULL,evaluation_cost bigint NOT NULL CHECK(evaluation_cost>=0),
 epoch_boundary_at timestamptz NOT NULL,epoch_boundary_order bigint NOT NULL CHECK(epoch_boundary_order>0),
 created_at timestamptz NOT NULL,updated_at timestamptz NOT NULL,created_by uuid NOT NULL,updated_by uuid NOT NULL,deleted_at timestamptz,
 UNIQUE(tenant_id,id),FOREIGN KEY(tenant_id,id) REFERENCES correlation_rule_identities(tenant_id,id),
 CHECK(jsonb_typeof(group_by)='array' AND jsonb_array_length(group_by)<=3)
);
CREATE UNIQUE INDEX correlation_rule_names ON correlation_rules(tenant_id,name_key) WHERE deleted_at IS NULL;
CREATE INDEX correlation_rule_order ON correlation_rules(tenant_id,created_at,id) WHERE deleted_at IS NULL;
CREATE TABLE correlation_condition_identities (
 id uuid PRIMARY KEY,tenant_id uuid NOT NULL,rule_id uuid NOT NULL,
 UNIQUE(tenant_id,rule_id,id),FOREIGN KEY(tenant_id,rule_id) REFERENCES correlation_rule_identities(tenant_id,id)
);
CREATE TABLE correlation_conditions (
 tenant_id uuid NOT NULL,rule_id uuid NOT NULL,id uuid NOT NULL,position integer NOT NULL CHECK(position BETWEEN 0 AND 9),
 label text NOT NULL,label_key text NOT NULL,cel text NOT NULL,profile text NOT NULL,checked_program bytea NOT NULL,
 evaluation_cost bigint NOT NULL CHECK(evaluation_cost>=0),
 PRIMARY KEY(tenant_id,rule_id,id),UNIQUE(tenant_id,rule_id,position),UNIQUE(tenant_id,rule_id,label_key),
 FOREIGN KEY(tenant_id,rule_id,id) REFERENCES correlation_condition_identities(tenant_id,rule_id,id)
);
CREATE TABLE correlation_rule_revisions (
 tenant_id uuid NOT NULL,rule_id uuid NOT NULL,revision bigint NOT NULL,snapshot jsonb NOT NULL,
 action text NOT NULL,reset_reason text,changed_fields jsonb NOT NULL,command_id uuid NOT NULL,
 recorded_at timestamptz NOT NULL,actor_id uuid NOT NULL,actor_label text NOT NULL,
 PRIMARY KEY(tenant_id,rule_id,revision),FOREIGN KEY(tenant_id,rule_id) REFERENCES correlation_rule_identities(tenant_id,id)
);
CREATE TABLE correlation_rule_controls (
 id uuid PRIMARY KEY,tenant_id uuid NOT NULL,rule_id uuid NOT NULL,revision bigint NOT NULL,
 epoch bigint NOT NULL,grouping_generation bigint NOT NULL,effective_at timestamptz NOT NULL,
 tenant_order bigint NOT NULL,observed_change_order bigint NOT NULL,kind text NOT NULL,
 UNIQUE(tenant_id,tenant_order),FOREIGN KEY(tenant_id,rule_id) REFERENCES correlation_rule_identities(tenant_id,id)
);
CREATE TABLE correlation_contexts (
 id uuid PRIMARY KEY,tenant_id uuid NOT NULL,rule_id uuid NOT NULL,grouping_generation bigint NOT NULL,
 group_digest bytea NOT NULL CHECK(octet_length(group_digest)=32),group_key bytea NOT NULL,
 active_incident_id uuid,created_at timestamptz NOT NULL,reset_at timestamptz,reset_order bigint,
 UNIQUE(tenant_id,id),UNIQUE(tenant_id,rule_id,id),
 FOREIGN KEY(tenant_id,rule_id) REFERENCES correlation_rule_identities(tenant_id,id),
 FOREIGN KEY(tenant_id,active_incident_id) REFERENCES incident_identities(tenant_id,id),
 CHECK((reset_at IS NULL)=(reset_order IS NULL))
);
-- Digest is a bounded lookup key, never a unique full-group identity.
CREATE INDEX correlation_context_bucket ON correlation_contexts(tenant_id,rule_id,grouping_generation,group_digest);
CREATE UNIQUE INDEX correlation_context_active_incident ON correlation_contexts(tenant_id,active_incident_id) WHERE active_incident_id IS NOT NULL;
CREATE TABLE correlation_evidence (
 tenant_id uuid NOT NULL,rule_id uuid NOT NULL,epoch bigint NOT NULL,context_id uuid NOT NULL,condition_id uuid NOT NULL,alert_id uuid NOT NULL,
 qualifier_ref uuid NOT NULL,start_at timestamptz NOT NULL,expires_at timestamptz NOT NULL,observed_revision bigint NOT NULL,
 PRIMARY KEY(tenant_id,rule_id,epoch,context_id,condition_id,alert_id),
 FOREIGN KEY(tenant_id,rule_id,context_id) REFERENCES correlation_contexts(tenant_id,rule_id,id),
 FOREIGN KEY(tenant_id,rule_id,condition_id) REFERENCES correlation_condition_identities(tenant_id,rule_id,id),
 FOREIGN KEY(tenant_id,alert_id) REFERENCES alert_identities(tenant_id,id),CHECK(expires_at>start_at)
);
CREATE INDEX correlation_evidence_expiry ON correlation_evidence(tenant_id,rule_id,context_id,condition_id,expires_at);
CREATE INDEX correlation_evidence_alert ON correlation_evidence(tenant_id,alert_id);
CREATE TABLE correlation_consumer_state (
 tenant_id uuid PRIMARY KEY REFERENCES tenants(id),change_order bigint NOT NULL DEFAULT 0,
 pending boolean NOT NULL DEFAULT false,health text NOT NULL DEFAULT 'blocked',blocked_reason text NOT NULL DEFAULT 'consumer_not_integrated',
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE correlation_revision_holds (
 tenant_id uuid NOT NULL,rule_id uuid NOT NULL,revision bigint NOT NULL,
 consumer_kind text NOT NULL CHECK(consumer_kind IN ('incident','input','recovery')),reference text NOT NULL,released_at timestamptz,
 PRIMARY KEY(tenant_id,rule_id,revision,consumer_kind,reference),
 FOREIGN KEY(tenant_id,rule_id,revision) REFERENCES correlation_rule_revisions(tenant_id,rule_id,revision)
);
DO $$ DECLARE tab text; BEGIN
 FOREACH tab IN ARRAY ARRAY['correlation_rule_identities','correlation_rules','correlation_condition_identities','correlation_conditions','correlation_rule_revisions','correlation_rule_controls','correlation_contexts','correlation_evidence','correlation_consumer_state','correlation_revision_holds'] LOOP
  EXECUTE format('GRANT SELECT,INSERT,UPDATE,DELETE ON %I TO appchi_api,appchi_worker',tab);
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',tab);
  EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY',tab);
  EXECUTE format('CREATE POLICY tenant_scope ON %I TO appchi_api USING (tenant_id::text=current_setting(''appchi.tenant_id'',true)) WITH CHECK (tenant_id::text=current_setting(''appchi.tenant_id'',true))',tab);
  EXECUTE format('CREATE POLICY worker_scope ON %I TO appchi_worker USING (true) WITH CHECK (true)',tab);
 END LOOP;
END $$;
UPDATE capability_gates SET ready=false,reason='correlation_consumer_and_capacity_qualification_required' WHERE capability='correlation';
