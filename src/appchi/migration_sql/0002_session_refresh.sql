ALTER TABLE auth_sessions ADD COLUMN refresh_started_at timestamptz;
ALTER TABLE auth_sessions ADD COLUMN refresh_at timestamptz NOT NULL DEFAULT clock_timestamp();
