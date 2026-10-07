# appchi-migrations

One ordered Alembic revision chain over immutable, checksummed PostgreSQL SQL files.

See [system design](https://github.com/appchi-alert-operations/appchi-design), [workspace setup](https://github.com/appchi-alert-operations/appchi-delivery) and [source provenance](SOURCE.md).

## Development

Use Python 3.13 and the committed `uv.lock`. Configure Git authentication for the
private organization repositories before resolving internal dependencies.

```powershell
uv sync --locked --all-extras
uv run --locked ruff check src tests
uv run --locked pytest
uv build --wheel
```

Shared `appchi` modules use namespace packaging; each module has exactly one owning
distribution. Dependencies resolve immutable Git revisions in Python dependency metadata and `uv.lock`.
For coordinated local edits use the delivery workspace setup, which installs local
packages without changing release dependency pins.

## Execution

`uv run --locked appchi-migrate` is the entrypoint. Supply the documented environment
bindings; package installation does not start services or migrate data.

Set `APPCHI_MIGRATION_URL` to the dedicated migration identity's PostgreSQL URL or
libpq connection string. The existing `python -m appchi.migrate` and Python
`migrate(dsn, directory=None)` interfaces call Alembic `upgrade head`. Runtime
services never migrate on startup. The wheel includes the Alembic environment,
revisions, SQL files and `migration_sql/checksums.json` manifest.

From this repository, the standard Alembic commands are also available:

```powershell
uv run --locked alembic history
uv run --locked alembic heads
uv run --locked alembic current
uv run --locked alembic upgrade head
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
   `uv run --locked alembic revision --rev-id 0051 -m "descriptive change"`.
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
uv run --locked pytest tests -q
```

Without that binding, database tests skip. CI supplies an isolated PostgreSQL 18
service; this is a test fixture, not a supported company-infrastructure declaration.
