-- User-selected source-driven maintenance and deferred automation.
-- Keep old proof and existing retirements; never restore already retired data.
CREATE TABLE application_scope (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 source_release_since timestamptz NOT NULL DEFAULT clock_timestamp()
);
INSERT INTO application_scope(singleton) VALUES(true);
GRANT SELECT ON application_scope TO appchi_api,appchi_worker;
-- Old jobs are retained as evidence, but have no active scheduler.
UPDATE maintenance_fanout_jobs SET state='obsolete',lease_until=NULL
 WHERE state IN ('pending','blocked');
UPDATE maintenance_windows SET processing_health='healthy'
 WHERE processing_health='updating';
