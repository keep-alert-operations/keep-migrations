-- Disjoint bounded scan ownership and per-tenant retry isolation. Existing
-- serving watermarks are unchanged; failing work cannot claim search visibility.
ALTER TABLE search_reconciliation
 ADD COLUMN lease_owner uuid,
 ADD COLUMN lease_until timestamptz,
 ADD COLUMN retry_after timestamptz,
 ADD COLUMN last_error text;
-- Persist each pass's verified lower bound; epoch bootstrap and periodic full
-- audits retain complete-authority repair for missing unchanged documents.
ALTER TABLE search_reconciliation ADD COLUMN floor_seq bigint NOT NULL DEFAULT 0 CHECK (floor_seq>=0);
ALTER TABLE search_reconciliation ADD COLUMN full_audit_at timestamptz;
-- Repair unchanged missing documents without holding back ordinary delta
-- watermarks for the duration of a large tenant's full identity scan.
ALTER TABLE search_reconciliation
 ADD COLUMN audit_cursor uuid,
 ADD COLUMN audit_boundary_seq bigint CHECK (audit_boundary_seq>=0),
 ADD COLUMN audit_started_at timestamptz,
 ADD COLUMN audit_page_at timestamptz,
 ADD COLUMN audit_retry_after timestamptz,
 ADD COLUMN audit_last_error text,
 ADD COLUMN audit_turns integer NOT NULL DEFAULT 0 CHECK (audit_turns>=0);
ALTER TABLE search_reconciliation ADD CONSTRAINT search_reconciliation_audit_pair
 CHECK ((audit_boundary_seq IS NULL)=(audit_started_at IS NULL)
        AND (audit_cursor IS NULL OR audit_boundary_seq IS NOT NULL));
CREATE INDEX alert_identity_projection_changes
 ON alert_identities(tenant_id,current_projection_seq,id);
ALTER TABLE search_reconciliation ADD CONSTRAINT search_reconciliation_lease_pair
 CHECK ((lease_owner IS NULL)=(lease_until IS NULL));
CREATE INDEX search_reconciliation_due
 ON search_reconciliation(index_epoch,retry_after,last_page_at);
