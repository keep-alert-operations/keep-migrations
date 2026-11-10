-- REV-39: correlation and maintenance are always on. Their capability gates no
-- longer exist, so neither activation nor a restore fence can switch them off.
DELETE FROM capability_gates WHERE capability IN ('correlation','maintenance');
-- Rules saved while the correlation gate was closed were stored blocked. Restart
-- each like a re-enable: a fresh evaluation epoch whose arrival boundary is this
-- migration, so changed events queued while the gate was closed never count.
WITH tenants AS (
 SELECT DISTINCT tenant_id FROM correlation_rules
 WHERE deleted_at IS NULL AND health='blocked' AND blocked_reason='consumer_not_integrated'
), boundary AS (
 UPDATE tenant_work_state w SET admission_order=w.admission_order+1
 FROM tenants t WHERE w.tenant_id=t.tenant_id
 RETURNING w.tenant_id,w.admission_order
)
UPDATE correlation_rules r SET epoch=r.epoch+1,health='healthy',blocked_reason=NULL,
 last_reset_reason='always_on',epoch_boundary_at=clock_timestamp(),
 epoch_boundary_order=b.admission_order
FROM boundary b
WHERE r.tenant_id=b.tenant_id AND r.deleted_at IS NULL
 AND r.health='blocked' AND r.blocked_reason='consumer_not_integrated';
