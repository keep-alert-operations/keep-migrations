-- REV-41: the Kafka topic incarnations recorded at cutover, in Kafka's 22-character
-- topic ID text. A recreated topic restarts its offsets under existing replay
-- proof; the source refuses a received topic that is not the recorded one.
-- A cutover recorded earlier stays NULL until kafka_cutover --record-topic-identity.
ALTER TABLE kafka_pipeline_control
 ADD COLUMN received_topic_id text CHECK(received_topic_id ~ '^[A-Za-z0-9_-]{22}$'),
 ADD COLUMN changed_topic_id text CHECK(changed_topic_id ~ '^[A-Za-z0-9_-]{22}$');
