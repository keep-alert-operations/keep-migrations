DO $$ DECLARE constraint_name text; BEGIN
 FOR constraint_name IN SELECT conname FROM pg_constraint WHERE conrelid='retirement_jobs'::regclass AND contype='u' LOOP
  EXECUTE format('ALTER TABLE retirement_jobs DROP CONSTRAINT %I',constraint_name);
 END LOOP;
END $$;
CREATE UNIQUE INDEX retirement_active_attempt ON retirement_jobs(resource_kind,resource_id) WHERE state<>'cancelled';
