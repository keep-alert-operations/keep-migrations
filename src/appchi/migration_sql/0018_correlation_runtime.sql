-- Durable per-action proof; incident activity references this immutable decision.
CREATE TABLE correlation_decisions (
 id uuid PRIMARY KEY,tenant_id uuid NOT NULL,rule_id uuid NOT NULL,rule_revision bigint NOT NULL,
 epoch bigint NOT NULL,context_id uuid NOT NULL,incident_id uuid NOT NULL,decision_at timestamptz NOT NULL,
 observed_change_order bigint NOT NULL,evidence jsonb NOT NULL,
 FOREIGN KEY(tenant_id,rule_id,rule_revision) REFERENCES correlation_rule_revisions(tenant_id,rule_id,revision),
 FOREIGN KEY(tenant_id,rule_id,context_id) REFERENCES correlation_contexts(tenant_id,rule_id,id),
 FOREIGN KEY(tenant_id,incident_id) REFERENCES incident_identities(tenant_id,id)
);
CREATE INDEX correlation_decisions_incident ON correlation_decisions(tenant_id,incident_id,decision_at,id);
ALTER TABLE correlation_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE correlation_decisions FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON correlation_decisions TO appchi_api USING (tenant_id::text=current_setting('appchi.tenant_id',true)) WITH CHECK (tenant_id::text=current_setting('appchi.tenant_id',true));
CREATE POLICY worker_scope ON correlation_decisions TO appchi_worker USING (true) WITH CHECK (true);
GRANT SELECT,INSERT,UPDATE,DELETE ON correlation_decisions TO appchi_api,appchi_worker;
