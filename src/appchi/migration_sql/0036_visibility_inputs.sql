-- Coordination prerequisites only: no eligibility classification or rendered success.
CREATE TABLE visibility_input_capacity (
 tenant_id uuid PRIMARY KEY REFERENCES tenants(id),
 inputs bigint NOT NULL DEFAULT 0 CHECK(inputs>=0),
 candidates bigint NOT NULL DEFAULT 0 CHECK(candidates>=0),
 applications bigint NOT NULL DEFAULT 0 CHECK(applications>=0),
 application_bytes bigint NOT NULL DEFAULT 0 CHECK(application_bytes>=0),
 seed_gap_attempts bigint NOT NULL DEFAULT 0 CHECK(seed_gap_attempts>=0),
 first_gap_started_at timestamptz,last_gap_started_at timestamptz
);
CREATE TABLE visibility_inputs (
 tenant_id uuid NOT NULL REFERENCES tenants(id),id uuid NOT NULL,
 kind text NOT NULL CHECK(kind IN ('incoming','maintenance_expiry')),
 started_at timestamptz NOT NULL,original_order bigint NOT NULL CHECK(original_order>=0),
 deadline_at timestamptz NOT NULL,seed_checkpoint bigint NOT NULL CHECK(seed_checkpoint>=0),
 cohort_checkpoint bigint CHECK(cohort_checkpoint>=0),
 policy_epoch text NOT NULL CHECK(octet_length(policy_epoch) BETWEEN 1 AND 256),qualification boolean NOT NULL,
 deployment_epoch text NOT NULL CHECK(octet_length(deployment_epoch) BETWEEN 1 AND 256),allocations jsonb NOT NULL,
 sampling_algorithm text NOT NULL CHECK(sampling_algorithm='appchi-visibility-sample-v1'),
 schedule jsonb,fingerprint bytea NOT NULL CHECK(octet_length(fingerprint)=32),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 disposition text NOT NULL DEFAULT 'pending' CHECK(disposition IN ('pending','cancelled','superseded')),
 disposition_proof jsonb,
 expansion_state text NOT NULL DEFAULT 'pending' CHECK(expansion_state IN ('pending','expanded')),
 last_view_id uuid,enumerated bigint NOT NULL DEFAULT 0 CHECK(enumerated>=0),
 selected bigint NOT NULL DEFAULT 0 CHECK(selected>=0 AND selected<=enumerated),
 expansion_gap text,application_gap text,deadline_exceeded boolean NOT NULL DEFAULT false,expanded_at timestamptz,
 expansion_attempted_at timestamptz,
 PRIMARY KEY(tenant_id,id),
 CHECK(deadline_at=started_at+interval '5 seconds'),
 CHECK((kind='incoming' AND original_order>0 AND schedule IS NULL AND cohort_checkpoint IS NOT NULL)
    OR (kind='maintenance_expiry' AND original_order=0 AND schedule IS NOT NULL))
);
CREATE INDEX visibility_inputs_pending ON visibility_inputs(expansion_attempted_at NULLS FIRST,started_at,tenant_id,id) WHERE expansion_state='pending' AND disposition='pending';
CREATE TABLE visibility_applications (
 tenant_id uuid NOT NULL,input_id uuid NOT NULL,id uuid NOT NULL,alert_id uuid,
 before_digest bytea CHECK(octet_length(before_digest)=32),after_digest bytea CHECK(octet_length(after_digest)=32),
 journal_order bigint CHECK(journal_order>0),source_event_id uuid,projection_seq bigint CHECK(projection_seq>=0),
 projection_version bigint CHECK(projection_version>0),error_code text,
 disposition text NOT NULL CHECK(disposition IN ('applied','unchanged','rejected')),
 fingerprint bytea NOT NULL CHECK(octet_length(fingerprint)=32),byte_charge bigint NOT NULL CHECK(byte_charge>0),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,input_id,id),FOREIGN KEY(tenant_id,input_id) REFERENCES visibility_inputs(tenant_id,id),
 FOREIGN KEY(tenant_id,alert_id) REFERENCES alert_identities(tenant_id,id),
 CHECK((disposition='rejected' AND alert_id IS NULL AND before_digest IS NULL AND after_digest IS NULL
   AND journal_order IS NULL AND source_event_id IS NULL
   AND projection_seq IS NULL AND projection_version IS NULL AND error_code IS NOT NULL
   AND error_code ~ '^[a-z][a-z0-9_]{0,127}$')
   OR (disposition IN ('applied','unchanged') AND alert_id IS NOT NULL AND after_digest IS NOT NULL
   AND projection_seq IS NOT NULL AND projection_version IS NOT NULL AND error_code IS NULL))
);
CREATE TABLE visibility_candidates (
 tenant_id uuid NOT NULL,input_id uuid NOT NULL,view_id uuid NOT NULL,view_epoch bigint NOT NULL CHECK(view_epoch>0),
 control_checkpoint bigint NOT NULL,query_digest text NOT NULL CHECK(query_digest ~ '^[0-9a-f]{64}$'),
 eligibility text NOT NULL DEFAULT 'unclassified' CHECK(eligibility='unclassified'),
 coverage_reason text NOT NULL CHECK(coverage_reason IN ('proof_pending','contact_unknown','reported_not_foreground','deployment_epoch_mismatch')),
 deadline_at timestamptz NOT NULL,recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,input_id,view_id,view_epoch),
 FOREIGN KEY(tenant_id,input_id) REFERENCES visibility_inputs(tenant_id,id),
 FOREIGN KEY(tenant_id,control_checkpoint) REFERENCES visibility_view_controls(tenant_id,checkpoint)
);
CREATE FUNCTION visibility_seed_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF (NEW.tenant_id,NEW.id,NEW.kind,NEW.started_at,NEW.original_order,NEW.deadline_at,NEW.seed_checkpoint,
     NEW.policy_epoch,NEW.qualification,NEW.deployment_epoch,NEW.allocations,NEW.sampling_algorithm,NEW.schedule,NEW.fingerprint,NEW.recorded_at)
 IS DISTINCT FROM
    (OLD.tenant_id,OLD.id,OLD.kind,OLD.started_at,OLD.original_order,OLD.deadline_at,OLD.seed_checkpoint,
     OLD.policy_epoch,OLD.qualification,OLD.deployment_epoch,OLD.allocations,OLD.sampling_algorithm,OLD.schedule,OLD.fingerprint,OLD.recorded_at)
 OR (OLD.cohort_checkpoint IS NOT NULL AND NEW.cohort_checkpoint IS DISTINCT FROM OLD.cohort_checkpoint)
 OR (OLD.disposition<>'pending' AND (NEW.disposition,NEW.disposition_proof) IS DISTINCT FROM (OLD.disposition,OLD.disposition_proof)) THEN
  RAISE EXCEPTION 'Visibility input boundary and policy are immutable';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER visibility_seed_immutable BEFORE UPDATE ON visibility_inputs FOR EACH ROW EXECUTE FUNCTION visibility_seed_immutable();
DO $$ DECLARE tab text; BEGIN
 FOREACH tab IN ARRAY ARRAY['visibility_input_capacity','visibility_inputs','visibility_applications','visibility_candidates'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',tab);
  EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY',tab);
  EXECUTE format('CREATE POLICY tenant_scope ON %I TO appchi_api USING(tenant_id::text=current_setting(''appchi.tenant_id'',true)) WITH CHECK(tenant_id::text=current_setting(''appchi.tenant_id'',true))',tab);
  EXECUTE format('CREATE POLICY worker_scope ON %I TO appchi_worker USING(true) WITH CHECK(true)',tab);
 END LOOP;
END $$;
GRANT SELECT,INSERT,UPDATE ON visibility_input_capacity,visibility_inputs TO appchi_api,appchi_worker;
GRANT SELECT,INSERT ON visibility_applications TO appchi_api,appchi_worker;
GRANT SELECT ON visibility_candidates TO appchi_api;
GRANT SELECT,INSERT ON visibility_candidates TO appchi_worker;
-- No DELETE grants, telemetry lifetime, ACK endpoint or success transition.
