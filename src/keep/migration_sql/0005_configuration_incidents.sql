CREATE TABLE presets (
 id uuid PRIMARY KEY, tenant_id uuid NOT NULL REFERENCES tenants(id),name text NOT NULL,name_key text NOT NULL,
 revision bigint NOT NULL DEFAULT 1,cel text NOT NULL,profile text NOT NULL,sort jsonb NOT NULL,columns jsonb NOT NULL,
 created_at timestamptz NOT NULL,updated_at timestamptz NOT NULL,created_by uuid NOT NULL,updated_by uuid NOT NULL,deleted_at timestamptz,
 UNIQUE(tenant_id,id)
);
CREATE UNIQUE INDEX preset_names ON presets(tenant_id,name_key) WHERE deleted_at IS NULL;
CREATE TABLE preset_revisions (tenant_id uuid NOT NULL,id uuid NOT NULL,revision bigint NOT NULL,snapshot jsonb NOT NULL,recorded_at timestamptz NOT NULL,actor_id uuid NOT NULL,PRIMARY KEY(id,revision));
CREATE TABLE dashboards (
 id uuid PRIMARY KEY,tenant_id uuid NOT NULL REFERENCES tenants(id),name text NOT NULL,name_key text NOT NULL,
 revision bigint NOT NULL DEFAULT 1,created_at timestamptz NOT NULL,updated_at timestamptz NOT NULL,
 created_by uuid NOT NULL,updated_by uuid NOT NULL,deleted_at timestamptz,UNIQUE(tenant_id,id)
);
CREATE UNIQUE INDEX dashboard_names ON dashboards(tenant_id,name_key) WHERE deleted_at IS NULL;
CREATE TABLE dashboard_panels (
 id uuid PRIMARY KEY,tenant_id uuid NOT NULL,dashboard_id uuid NOT NULL,preset_id uuid NOT NULL,title text,
 x integer NOT NULL CHECK(x>=0), y integer NOT NULL CHECK(y>=0),w integer NOT NULL CHECK(w IN (3,4,6,12)),h integer NOT NULL CHECK(h IN (2,3,4)),
 thresholds jsonb NOT NULL,CHECK(x+w<=12 AND y+h<=100),
 FOREIGN KEY(tenant_id,dashboard_id) REFERENCES dashboards(tenant_id,id),FOREIGN KEY(tenant_id,preset_id) REFERENCES presets(tenant_id,id)
);
CREATE INDEX dashboard_references ON dashboard_panels(tenant_id,preset_id,dashboard_id);
CREATE TABLE dashboard_revisions (tenant_id uuid NOT NULL,id uuid NOT NULL,revision bigint NOT NULL,snapshot jsonb NOT NULL,recorded_at timestamptz NOT NULL,actor_id uuid NOT NULL,PRIMARY KEY(id,revision));
CREATE TABLE incident_identities (id uuid PRIMARY KEY,tenant_id uuid NOT NULL REFERENCES tenants(id),retired_at timestamptz,UNIQUE(tenant_id,id));
CREATE TABLE incidents (
 id uuid PRIMARY KEY,tenant_id uuid NOT NULL,title text NOT NULL,description text NOT NULL,severity text NOT NULL CHECK(severity IN ('critical','high','medium','low')),
 status text NOT NULL CHECK(status IN ('open','investigating','resolved')),assignee_id uuid REFERENCES principals(id),revision bigint NOT NULL DEFAULT 1,
 origin text NOT NULL CHECK(origin IN ('manual','correlation')),context_id uuid,cycle_id uuid NOT NULL,created_at timestamptz NOT NULL,
 updated_at timestamptz NOT NULL,last_activity timestamptz NOT NULL,resolved_at timestamptz,retention_at timestamptz,
 FOREIGN KEY(tenant_id,id) REFERENCES incident_identities(tenant_id,id),UNIQUE(tenant_id,id)
);
CREATE INDEX incident_activity_due ON incidents(last_activity,id) WHERE status<>'resolved';
CREATE INDEX incident_retention_due ON incidents(retention_at,id) WHERE status='resolved';
CREATE TABLE incident_alert_links (
 tenant_id uuid NOT NULL,incident_id uuid NOT NULL,alert_id uuid NOT NULL,linked_at timestamptz NOT NULL,unlinked_at timestamptz,
 PRIMARY KEY(tenant_id,incident_id,alert_id),FOREIGN KEY(tenant_id,incident_id) REFERENCES incident_identities(tenant_id,id),
 FOREIGN KEY(tenant_id,alert_id) REFERENCES alert_identities(tenant_id,id)
);
CREATE TABLE alert_active_ownership (
 tenant_id uuid NOT NULL,alert_id uuid NOT NULL,incident_id uuid NOT NULL,
 PRIMARY KEY(tenant_id,alert_id),FOREIGN KEY(tenant_id,alert_id) REFERENCES alert_identities(tenant_id,id),FOREIGN KEY(tenant_id,incident_id) REFERENCES incident_identities(tenant_id,id)
);
CREATE TABLE incident_cycles (
 tenant_id uuid NOT NULL,incident_id uuid NOT NULL,id uuid NOT NULL,opened_at timestamptz NOT NULL,
 investigating_at timestamptz,resolved_at timestamptz,cause text,PRIMARY KEY(incident_id,id)
) PARTITION BY HASH(incident_id);
CREATE TABLE incident_activity (
 tenant_id uuid NOT NULL,incident_id uuid NOT NULL,id uuid NOT NULL,kind text NOT NULL,
 recorded_at timestamptz NOT NULL,actor_id uuid,evidence jsonb NOT NULL,PRIMARY KEY(incident_id,id)
) PARTITION BY HASH(incident_id);
CREATE TABLE incident_notes (
 id uuid PRIMARY KEY,tenant_id uuid NOT NULL,incident_id uuid NOT NULL,text text NOT NULL,deleted boolean NOT NULL DEFAULT false,
 revision bigint NOT NULL DEFAULT 1,actor_id uuid NOT NULL,created_at timestamptz NOT NULL,
 FOREIGN KEY(tenant_id,incident_id) REFERENCES incident_identities(tenant_id,id)
);
CREATE TABLE incident_note_revisions (
 tenant_id uuid NOT NULL,incident_id uuid NOT NULL,note_id uuid NOT NULL,revision bigint NOT NULL,
 text text NOT NULL,deleted boolean NOT NULL,actor_id uuid NOT NULL,recorded_at timestamptz NOT NULL,
 PRIMARY KEY(incident_id,note_id,revision)
) PARTITION BY HASH(incident_id);
CREATE TABLE incident_search_tokens(tenant_id uuid NOT NULL,incident_id uuid NOT NULL,id uuid PRIMARY KEY,token_digest bytea NOT NULL,token_text text NOT NULL);
CREATE INDEX incident_tokens ON incident_search_tokens(tenant_id,token_digest);
CREATE TABLE correlation_boundaries(tenant_id uuid NOT NULL,alert_id uuid NOT NULL,order_token bigint NOT NULL,effective_at timestamptz NOT NULL,PRIMARY KEY(tenant_id,alert_id));
DO $$ BEGIN FOR i IN 0..31 LOOP
 EXECUTE format('CREATE TABLE incident_cycles_%s PARTITION OF incident_cycles FOR VALUES WITH (MODULUS 32, REMAINDER %s)',i,i);
 EXECUTE format('CREATE TABLE incident_activity_%s PARTITION OF incident_activity FOR VALUES WITH (MODULUS 32, REMAINDER %s)',i,i);
 EXECUTE format('CREATE TABLE incident_note_revisions_%s PARTITION OF incident_note_revisions FOR VALUES WITH (MODULUS 32, REMAINDER %s)',i,i);
END LOOP; END $$;
DO $$ DECLARE tab text; BEGIN
 FOREACH tab IN ARRAY ARRAY['presets','preset_revisions','dashboards','dashboard_panels','dashboard_revisions','incidents','incident_identities','incident_alert_links','alert_active_ownership','incident_cycles','incident_activity','incident_notes','incident_note_revisions','incident_search_tokens','correlation_boundaries'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',tab);
  EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY',tab);
  EXECUTE format('CREATE POLICY tenant_scope ON %I TO appchi_api USING (tenant_id::text=current_setting(''appchi.tenant_id'',true)) WITH CHECK (tenant_id::text=current_setting(''appchi.tenant_id'',true))',tab);
  EXECUTE format('CREATE POLICY worker_scope ON %I TO appchi_worker USING (true) WITH CHECK (true)',tab);
  EXECUTE format('GRANT SELECT,INSERT,UPDATE,DELETE ON %I TO appchi_api,appchi_worker',tab);
 END LOOP;
END $$;
