-- A saved preset may sound an alarm while its results page has alerts (REV-58).
-- The constant default fills existing rows without rewriting the table.
ALTER TABLE presets ADD COLUMN noisy boolean NOT NULL DEFAULT false;
