-- REV-67: the system is renamed from Appchi to Keep.
-- Earlier migrations stay byte-for-byte unchanged, so a fresh chain still creates
-- appchi_* roles and appchi.tenant_id policies first; this migration moves them.
--
-- Roles are cluster-wide. When keep_* does not exist yet, the role is renamed and
-- every grant, policy and membership follows it by OID. When another database in
-- the same cluster already renamed it, this database's chain re-created appchi_*;
-- its policies, privileges, memberships and ownership move to keep_* here and the
-- re-created role is dropped when nothing else in the cluster still uses it.
DO $migration$
DECLARE
  pair text[];
  old_role text;
  new_role text;
  item record;
  privilege record;
  target text;
  new_roles text;
BEGIN
  FOREACH pair SLICE 1 IN ARRAY ARRAY[
    ['appchi_api', 'keep_api'],
    ['appchi_worker', 'keep_worker'],
    ['appchi_recovery', 'keep_recovery']
  ] LOOP
    old_role := pair[1];
    new_role := pair[2];
    CONTINUE WHEN NOT EXISTS (SELECT FROM pg_roles WHERE rolname = old_role);
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = new_role) THEN
      EXECUTE format('ALTER ROLE %I RENAME TO %I', old_role, new_role);
      CONTINUE;
    END IF;

    FOR item IN
      SELECT schemaname, tablename, policyname, roles FROM pg_policies WHERE old_role = ANY (roles)
    LOOP
      SELECT string_agg(quote_ident(CASE WHEN r = old_role THEN new_role ELSE r END), ', ')
        INTO new_roles FROM unnest(item.roles) AS r;
      EXECUTE format('ALTER POLICY %I ON %I.%I TO %s',
        item.policyname, item.schemaname, item.tablename, new_roles);
    END LOOP;

    FOR item IN
      SELECT c.oid, c.relkind, c.relacl FROM pg_class c
      WHERE c.relacl IS NOT NULL
        AND EXISTS (SELECT FROM aclexplode(c.relacl) a WHERE a.grantee = old_role::regrole)
    LOOP
      target := CASE WHEN item.relkind = 'S' THEN 'SEQUENCE ' ELSE 'TABLE ' END
        || item.oid::regclass::text;
      FOR privilege IN
        SELECT a.privilege_type, a.is_grantable FROM aclexplode(item.relacl) a
        WHERE a.grantee = old_role::regrole
      LOOP
        EXECUTE format('GRANT %s ON %s TO %I%s', privilege.privilege_type, target, new_role,
          CASE WHEN privilege.is_grantable THEN ' WITH GRANT OPTION' ELSE '' END);
      END LOOP;
      EXECUTE format('REVOKE ALL ON %s FROM %I', target, old_role);
    END LOOP;

    FOR item IN
      SELECT p.oid FROM pg_proc p
      WHERE p.proacl IS NOT NULL
        AND EXISTS (SELECT FROM aclexplode(p.proacl) a WHERE a.grantee = old_role::regrole)
    LOOP
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO %I', item.oid::regprocedure, new_role);
      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %I', item.oid::regprocedure, old_role);
    END LOOP;

    FOR item IN
      SELECT n.nspname, a.privilege_type FROM pg_namespace n, aclexplode(n.nspacl) a
      WHERE n.nspacl IS NOT NULL AND a.grantee = old_role::regrole
    LOOP
      EXECUTE format('GRANT %s ON SCHEMA %I TO %I', item.privilege_type, item.nspname, new_role);
      EXECUTE format('REVOKE %s ON SCHEMA %I FROM %I', item.privilege_type, item.nspname, old_role);
    END LOOP;

    FOR item IN
      SELECT m.rolname FROM pg_auth_members am JOIN pg_roles m ON m.oid = am.member
      WHERE am.roleid = old_role::regrole
    LOOP
      EXECUTE format('GRANT %I TO %I', new_role, item.rolname);
    END LOOP;

    EXECUTE format('REASSIGN OWNED BY %I TO %I', old_role, new_role);
    BEGIN
      EXECUTE format('DROP ROLE %I', old_role);
    EXCEPTION WHEN dependent_objects_still_exist THEN
      RAISE NOTICE 'Role % is still used by another database in this cluster', old_role;
    END;
  END LOOP;

  FOR item IN
    SELECT schemaname, tablename, policyname, qual, with_check FROM pg_policies
    WHERE qual LIKE '%appchi.tenant_id%' OR with_check LIKE '%appchi.tenant_id%'
  LOOP
    EXECUTE format('ALTER POLICY %I ON %I.%I', item.policyname, item.schemaname, item.tablename)
      || CASE WHEN item.qual IS NULL THEN ''
         ELSE format(' USING (%s)', replace(item.qual, 'appchi.tenant_id', 'keep.tenant_id')) END
      || CASE WHEN item.with_check IS NULL THEN ''
         ELSE format(' WITH CHECK (%s)',
           replace(item.with_check, 'appchi.tenant_id', 'keep.tenant_id')) END;
  END LOOP;
END
$migration$;

ALTER TABLE visibility_inputs DROP CONSTRAINT visibility_inputs_sampling_algorithm_check;
UPDATE visibility_inputs SET sampling_algorithm = 'keep-visibility-sample-v1'
WHERE sampling_algorithm = 'appchi-visibility-sample-v1';
ALTER TABLE visibility_inputs ADD CONSTRAINT visibility_inputs_sampling_algorithm_check
  CHECK (sampling_algorithm = 'keep-visibility-sample-v1');
