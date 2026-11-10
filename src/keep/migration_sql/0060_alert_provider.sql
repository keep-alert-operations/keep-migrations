-- Alert provider and Grafana alert rule URL (REV-55). provider is the source of the
-- latest applied delivery: 'grafana' for the Grafana webhook, 'api' for the native
-- v1 and v2 routes. alert_rule_url is the Grafana rule link, so only a Grafana
-- delivery has one. NULL provider marks a row stored before REV-55, or by an older
-- processor during rollout; the one-time provider backfill fills it from the alert's
-- latest applied source event. Nullable columns without a default rewrite no rows,
-- and older code that names its columns from the alert record leaves both NULL,
-- which satisfies both checks.
ALTER TABLE alerts
 ADD COLUMN provider text,
 ADD COLUMN alert_rule_url text,
 ADD CONSTRAINT alerts_provider_known CHECK (provider IN ('api','grafana')),
 ADD CONSTRAINT alerts_rule_url_grafana CHECK (alert_rule_url IS NULL OR provider = 'grafana');
