-- Application indexes for the supported tenant incident filters and live ordering.
CREATE INDEX incidents_tenant_activity ON incidents(tenant_id,last_activity DESC,id);
CREATE INDEX incidents_tenant_status_activity ON incidents(tenant_id,status,last_activity DESC,id);
CREATE INDEX incidents_tenant_created ON incidents(tenant_id,created_at DESC,id);
CREATE INDEX incidents_tenant_resolved ON incidents(tenant_id,resolved_at DESC NULLS LAST,id);
CREATE INDEX incidents_tenant_severity ON incidents(tenant_id,(CASE severity WHEN 'low' THEN 1 WHEN 'medium' THEN 2 WHEN 'high' THEN 3 WHEN 'critical' THEN 4 END) DESC,id);
CREATE INDEX incidents_tenant_assignee ON incidents(tenant_id,assignee_id,last_activity DESC,id);
CREATE INDEX incidents_tenant_origin ON incidents(tenant_id,origin,last_activity DESC,id);
CREATE INDEX incidents_tenant_context ON incidents(tenant_id,context_id);
CREATE INDEX incident_link_alert_lookup ON incident_alert_links(tenant_id,alert_id,incident_id) WHERE unlinked_at IS NULL;
