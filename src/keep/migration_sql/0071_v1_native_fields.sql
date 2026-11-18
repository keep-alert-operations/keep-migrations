-- v1 alerts are stored as sent (REV-77), after password login and ADAPI (0070,
-- REV-73). A v1 alert keeps its field `object` in a new nullable column instead of
-- `component`, and its severities error, major and warning instead of critical,
-- high and warning. v1 rows hold `object` with `component` NULL; v2 rows hold
-- `component` with `object` NULL, so `component` becomes nullable. The severity
-- CHECK allows the union of both vocabularies: critical, high, error, major,
-- warning and clear (`clear` stays the first-seen v1 sentinel). Tightening it per
-- schema version is out of scope. Adding a nullable column without a default and
-- dropping NOT NULL rewrite no rows; stored v1 rows keep the old vocabulary until
-- the REV-77 conversion command or their next source update converts them. The
-- alerts table has only table-level grants, no column grants, views or partitions.
ALTER TABLE alerts ADD COLUMN object text;
ALTER TABLE alerts ALTER COLUMN component DROP NOT NULL;
ALTER TABLE alerts DROP CONSTRAINT alerts_severity_check;
ALTER TABLE alerts ADD CONSTRAINT alerts_severity_check
  CHECK(severity IN ('critical','high','error','major','warning','clear'));
