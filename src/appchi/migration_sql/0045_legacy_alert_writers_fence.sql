-- Old application binaries must not repopulate the retired alert queues.
CREATE FUNCTION fence_legacy_alert_insert() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM kafka_pipeline_control WHERE singleton AND enabled) THEN
  IF TG_TABLE_NAME='ingest_items' THEN
   RAISE EXCEPTION 'legacy_pipeline_fenced' USING ERRCODE='55000';
  ELSIF NEW.stream IN ('received','changed') THEN
   RAISE EXCEPTION 'legacy_pipeline_fenced' USING ERRCODE='55000';
  END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER legacy_ingest_fence BEFORE INSERT ON ingest_items
 FOR EACH ROW EXECUTE FUNCTION fence_legacy_alert_insert();
CREATE TRIGGER legacy_alert_outbox_fence BEFORE INSERT ON application_outbox
 FOR EACH ROW EXECUTE FUNCTION fence_legacy_alert_insert();
