CREATE TABLE maintenance_identities (
 id uuid PRIMARY KEY,tenant_id uuid NOT NULL REFERENCES tenants(id),deleted_at timestamptz,final_revision bigint,
 UNIQUE(tenant_id,id)
);
CREATE TABLE maintenance_windows (
 id uuid PRIMARY KEY,tenant_id uuid NOT NULL,revision bigint NOT NULL CHECK(revision>0),name text NOT NULL,name_key text NOT NULL,
 reason text NOT NULL,cel text NOT NULL,profile text NOT NULL,cel_digest text NOT NULL,
 start_at timestamptz NOT NULL,end_at timestamptz NOT NULL,timezone text NOT NULL,schedule_evidence jsonb NOT NULL,
 enabled boolean NOT NULL DEFAULT true,started_lock boolean NOT NULL DEFAULT false,deleted_at timestamptz,
 processing_health text NOT NULL DEFAULT 'healthy' CHECK(processing_health IN ('healthy','updating','blocked')),
 created_at timestamptz NOT NULL,updated_at timestamptz NOT NULL,created_by uuid NOT NULL,updated_by uuid NOT NULL,
 FOREIGN KEY(tenant_id,id) REFERENCES maintenance_identities(tenant_id,id),UNIQUE(tenant_id,id),CHECK(end_at>start_at)
);
CREATE INDEX maintenance_list ON maintenance_windows(tenant_id,deleted_at,start_at,id);
CREATE INDEX maintenance_name ON maintenance_windows(tenant_id,name_key,id);
CREATE TABLE maintenance_revisions (
 tenant_id uuid NOT NULL,window_id uuid NOT NULL,revision bigint NOT NULL,snapshot jsonb NOT NULL,
 action text NOT NULL,recorded_at timestamptz NOT NULL,actor_id uuid NOT NULL,actor_label text NOT NULL,
 PRIMARY KEY(tenant_id,window_id,revision),FOREIGN KEY(tenant_id,window_id) REFERENCES maintenance_identities(tenant_id,id)
);
CREATE TABLE maintenance_controls (
 id uuid PRIMARY KEY,tenant_id uuid NOT NULL,window_id uuid NOT NULL,revision bigint NOT NULL,
 effective_at timestamptz NOT NULL,tenant_order bigint NOT NULL,kind text NOT NULL,generation bigint NOT NULL,
 UNIQUE(tenant_id,tenant_order),FOREIGN KEY(tenant_id,window_id) REFERENCES maintenance_identities(tenant_id,id),UNIQUE(tenant_id,id)
);
CREATE TABLE maintenance_segments (
 id uuid PRIMARY KEY,tenant_id uuid NOT NULL,window_id uuid NOT NULL,expression_revision bigint NOT NULL,
 cel text NOT NULL,profile text NOT NULL,cel_digest text NOT NULL,start_at timestamptz NOT NULL,end_at timestamptz NOT NULL,
 activation_id uuid NOT NULL,activation_at timestamptz NOT NULL,activation_order bigint NOT NULL,
 deactivation_id uuid,deactivation_at timestamptz,deactivation_order bigint,end_revisions jsonb NOT NULL,
 generation bigint NOT NULL,FOREIGN KEY(tenant_id,window_id) REFERENCES maintenance_identities(tenant_id,id),
 FOREIGN KEY(tenant_id,activation_id) REFERENCES maintenance_controls(tenant_id,id),UNIQUE(tenant_id,id),CHECK(end_at>start_at),
 CHECK((deactivation_id IS NULL)=(deactivation_at IS NULL) AND (deactivation_at IS NULL)=(deactivation_order IS NULL))
);
CREATE INDEX maintenance_segment_due ON maintenance_segments(end_at,tenant_id,id) WHERE deactivation_at IS NULL;
CREATE TABLE maintenance_fanout_jobs (
 id uuid PRIMARY KEY,tenant_id uuid NOT NULL,window_id uuid NOT NULL,segment_id uuid,control_id uuid NOT NULL,
 generation bigint NOT NULL,kind text NOT NULL CHECK(kind IN ('control','scheduled_end')),
 due_at timestamptz NOT NULL,expected_end timestamptz,state text NOT NULL CHECK(state IN ('pending','complete','obsolete','blocked')),
 cursor_alert_id uuid,lease_generation bigint NOT NULL DEFAULT 0,lease_until timestamptz,required_projection_seq bigint,
 FOREIGN KEY(tenant_id,window_id) REFERENCES maintenance_identities(tenant_id,id),
 FOREIGN KEY(tenant_id,segment_id) REFERENCES maintenance_segments(tenant_id,id),UNIQUE(tenant_id,control_id,kind)
);
CREATE INDEX maintenance_job_due ON maintenance_fanout_jobs(due_at,id) WHERE state='pending';
CREATE TABLE alert_maintenance_causes (
 tenant_id uuid NOT NULL,alert_id uuid NOT NULL,id uuid NOT NULL,window_id uuid NOT NULL,segment_id uuid NOT NULL,
 opening_proof text NOT NULL,opened_at timestamptz NOT NULL,opened_order bigint NOT NULL,closed_at timestamptz,closed_order bigint,
 closing_proof text,recorded_at timestamptz NOT NULL,PRIMARY KEY(tenant_id,alert_id,id),
 FOREIGN KEY(tenant_id,alert_id) REFERENCES alert_identities(tenant_id,id),
 FOREIGN KEY(tenant_id,segment_id) REFERENCES maintenance_segments(tenant_id,id),
 UNIQUE(tenant_id,alert_id,segment_id,opening_proof),CHECK(closed_at IS NULL OR closed_at>=opened_at)
);
CREATE INDEX maintenance_cause_scan ON alert_maintenance_causes(tenant_id,window_id,segment_id,alert_id);
CREATE TABLE maintenance_delete_jobs (
 id uuid PRIMARY KEY,tenant_id uuid NOT NULL,window_id uuid NOT NULL,scope text NOT NULL,command_id uuid NOT NULL,
 fingerprint bytea NOT NULL,expected_revision bigint NOT NULL,actor_id uuid NOT NULL,actor_label text NOT NULL,
 intent_id uuid NOT NULL UNIQUE,final_id uuid NOT NULL UNIQUE,cancel_id uuid NOT NULL UNIQUE,digest text NOT NULL,
 state text NOT NULL CHECK(state IN ('prepared','deleted','final_protected','cancelled')),intent_ack jsonb,final_ack jsonb,cancel_ack jsonb,
 receipt jsonb,created_at timestamptz NOT NULL,updated_at timestamptz NOT NULL,
 UNIQUE(scope,command_id),FOREIGN KEY(tenant_id,window_id) REFERENCES maintenance_identities(tenant_id,id),
 CHECK(intent_id<>final_id AND final_id<>cancel_id AND intent_id<>cancel_id)
);
DO $$ DECLARE tab text; BEGIN
 FOREACH tab IN ARRAY ARRAY['maintenance_identities','maintenance_windows','maintenance_revisions','maintenance_controls','maintenance_segments','maintenance_fanout_jobs','alert_maintenance_causes','maintenance_delete_jobs'] LOOP
  EXECUTE format('GRANT SELECT,INSERT,UPDATE,DELETE ON %I TO appchi_api,appchi_worker',tab);
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',tab);
  EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY',tab);
  EXECUTE format('CREATE POLICY tenant_scope ON %I TO appchi_api USING (tenant_id::text=current_setting(''appchi.tenant_id'',true)) WITH CHECK (tenant_id::text=current_setting(''appchi.tenant_id'',true))',tab);
  EXECUTE format('CREATE POLICY worker_scope ON %I TO appchi_worker USING (true) WITH CHECK (true)',tab);
 END LOOP;
END $$;
