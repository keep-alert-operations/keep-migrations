DO $$ DECLARE tab record; BEGIN
 FOR tab IN SELECT c.relname FROM pg_class c JOIN pg_inherits i ON i.inhrelid=c.oid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r' LOOP
  EXECUTE format('REVOKE ALL ON %I FROM appchi_api,appchi_worker',tab.relname);
 END LOOP;
END $$;

