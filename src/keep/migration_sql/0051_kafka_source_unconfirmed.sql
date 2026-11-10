-- Bound source assignment catch-up to the unconfirmed inputs. Source results
-- are retained, so a partition offset range grows with its whole history.
CREATE INDEX kafka_source_results_unconfirmed
 ON kafka_source_results(topic,partition,input_offset) WHERE NOT kafka_confirmed;
