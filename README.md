# appchi-migrations

One ordered Alembic revision chain over immutable, checksummed PostgreSQL SQL files.

See [system design](https://github.com/appchi-alert-operations/appchi-design), [workspace setup](https://github.com/appchi-alert-operations/appchi-delivery) and [source provenance](SOURCE.md).

## Development

Use Python 3.13, Poetry 2.3.1 and the committed `poetry.lock`. Configure Git authentication for the
private organization repositories before resolving internal dependencies.

```powershell
poetry check --lock
poetry sync --all-extras
poetry run ruff check src tests
poetry run pytest
poetry build --format wheel
```

Shared `appchi` modules use namespace packaging; each module has exactly one owning
distribution. Dependencies resolve immutable Git revisions in Python dependency metadata and `poetry.lock`.
For coordinated local edits use the delivery workspace setup, which installs local
packages without changing release dependency pins.

## Execution

`poetry run appchi-migrate` is the entrypoint. Supply the documented environment
bindings; package installation does not start services or migrate data.

Set `APPCHI_MIGRATION_URL` to the dedicated migration identity's PostgreSQL URL or
libpq connection string. The existing `python -m appchi.migrate` and Python
`migrate(dsn, directory=None)` interfaces call Alembic `upgrade head`. Runtime
services never migrate on startup. The wheel includes the Alembic environment,
revisions, SQL files and `migration_sql/checksums.json` manifest.

From this repository, the standard Alembic commands are also available:

```powershell
poetry run alembic history
poetry run alembic heads
poetry run alembic current
poetry run alembic upgrade head
```

`history` and `heads` do not connect to PostgreSQL. `current` verifies the packaged
SQL and database history without adopting a legacy database or changing its schema.
All database commands use `APPCHI_MIGRATION_URL`; no credentials belong in
`alembic.ini`. The migration schema is `public`.

## Existing databases and rollout

The original 44 SQL files (0001–0047, retaining the numbering gaps) are unchanged.
The current chain adds 0048 for maintenance continuation and 0049 for exclusive
search reconciliation leases, delta progress, separate repair-audit cursors and
independent retry diagnostics. Revision 0050 adds a partial live-note lookup
index for projection probes and ordered streaming reads. Apply all three before
starting the updated writers. Index creation uses the migration transaction and
belongs in the same stopped-writer migration window; allow time for retained notes.
Revision 0051 adds a partial index of unconfirmed source results, so the source
processor's partition-assignment catch-up reads only unconfirmed inputs instead of
the partition's whole retained history. Writers are compatible with or without it,
but its build blocks source-result writes for one scan of the retained table; run
it in the same window.
Revision 0052 adds a partial index of projection rows that still await a
retirement or deletion, matching the API's retention probe, so a search feed or
count page no longer scans the tenant's whole projection history past
`searchable_seq`. The API is correct with or without it. The runner's single
transaction rules out `CREATE INDEX CONCURRENTLY`, so its build blocks
`projection_work` inserts (alert writes and retirement) for one scan of the
table; run it in a stopped-writer window like 0050 and 0051.
Revision 0053 (REV-39) deletes the `correlation` and `maintenance` capability
gates, so both features are always on, and restarts rules that were saved
blocked while correlation was gated with a fresh evaluation epoch and boundary.
Runtime code from before 0053 reads those gate rows; stop every writer before
applying it and start only updated services afterwards.
Revision 0054 (REV-41) adds the nullable `received_topic_id` and
`changed_topic_id` columns to `kafka_pipeline_control`. The cutover records the
Kafka topic IDs there, and the updated source processor refuses a received topic
that is not the recorded incarnation, or any received topic while none is recorded.
Older code ignores the columns. For a cutover recorded before 0054, stop source,
correlation and indexer, apply it, then run `python -m appchi.kafka_cutover
--record-topic-identity` before starting the updated processor.
Revision 0055 (REV-44) adds the nullable `presets.group_by` column for a saved
preset's optional grouping field. It needs no stopped-writer window: older API
code names its columns explicitly and leaves the new one unchanged.
Revision 0057 (REV-50) replaces the `dashboard_panels` width and height checks:
width is 3 through 12 and height 2 or more, inside the unchanged grid bound. Existing
rows already satisfy them and older API code writes only the old sizes, so it needs
no stopped-writer window. Apply it before an API that accepts the new sizes; an older
API reading a panel saved at a new size rejects it, so do not roll the API back past
REV-50 once such panels exist.
Revision 0058 (REV-53) indexes `incident_cycles` by tenant and opening time and by
tenant and resolution time, and assignment history in `incident_activity` by incident
and time, for the incident report's period reads. The API is correct without them,
only slower. Their build blocks incident cycle and activity writes for one scan of
each table, so run it in a stopped-writer window like 0050–0052, before the API that
serves incident reports.
Revision 0059 (REV-54) adds the nullable `alerts.name` column for a sender-supplied
v2 alert name. It rewrites no rows and needs no stopped-writer window: older source
code names its insert columns from the alert record, so its rows keep NULL, which
means unnamed. Apply it before the processor that stores names.
Revision 0060 (REV-55) adds the nullable `alerts.provider` (`api` or `grafana`) and
`alerts.alert_rule_url` columns, with a check that only a Grafana provider has a rule
URL. It rewrites no rows and needs no stopped-writer window; validating the checks
reads `alerts` once under the migration's table lock. Older source code leaves both
NULL, which marks a row for the source processor's one-time provider backfill. Apply
it before the processor that stores providers.
Existing continuation values remain nullable and historical unions default to
full snapshots; no prior replay proof is rewritten by these migrations.
`schema_migrations` remains the checksum/audit ledger. `alembic_version` records
the revision Alembic has reached; both must describe the same ordered prefix.

For a database that has only `schema_migrations`, `upgrade head` first validates
every recorded filename and checksum and rejects gaps or unknown entries. It then
adopts that exact revision and applies only pending SQL. Existing ledger timestamps
and application data are preserved. Never manually stamp a database to bypass this
check. An existing empty or inconsistent Alembic version table is not a legacy
database and is rejected when it disagrees with the ledger.

Adoption, pending migrations, both ledgers and privilege revocation share one
PostgreSQL transaction under the original advisory lock (418003210). Failure rolls
everything back. Concurrent migration processes serialize on that lock. The API
and worker roles receive no privileges on either migration ledger, including after
the foundation migration's broad initial grants.

Keep the dedicated migration job before dependent writers. Existing Kafka cutover
and stopped-scheduler prerequisites still apply to the corresponding pending SQL;
Alembic does not execute those operational steps. Stop use of the old migration
runner after adoption. Deploying an older application image still requires the
documented schema/protocol compatibility; database downgrades, arbitrary stamping,
autogeneration and offline SQL execution are not supported by this environment.
Use a reviewed forward migration for corrections.

## Add a migration

1. Check the current head and highest SQL number; preserve all published files,
   checksums and numbering gaps. Use the next four-digit identifier.
2. Create its revision, for example
   `poetry run alembic revision --rev-id NNNN -m "descriptive change"`.
3. Add the SQL file named by the generated revision's `sql_file` under
   `src/appchi/migration_sql`. Add its exact-byte SHA-256 entry to
   `src/appchi/migration_sql/checksums.json`; do not update old entries.
4. Keep one linear revision chain. Review SQL and run fresh-install, supported
   upgrade, privilege, failure and relevant application compatibility tests.

SQL executes through Psycopg unchanged, including PL/pgSQL bodies, literal percent
signs and multiple statements. Keep schema/data changes in the SQL files and the
revision wrappers limited to calling `apply_sql`; SQLAlchemy models are not required.
The current runner uses a single transaction for the pending batch, so operations
that require execution outside a transaction need a separately designed workflow.

## Database verification

Set `APPCHI_MIGRATION_TEST_ADMIN_URL` to a **disposable isolated PostgreSQL cluster**
whose test identity can create/drop databases and create the synthetic runtime
roles. Each test creates a uniquely named database and removes it afterward.

```powershell
poetry run pytest tests -q
```

Without that binding, database tests skip. CI supplies an isolated PostgreSQL 18
service; this is a test fixture, not a supported company-infrastructure declaration.
