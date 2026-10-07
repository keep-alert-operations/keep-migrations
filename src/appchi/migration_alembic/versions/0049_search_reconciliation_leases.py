"""0049 search reconciliation leases and retry isolation."""

from appchi.migrate import apply_sql

revision = "0049"
down_revision = "0048"
branch_labels = None
depends_on = None
sql_file = "0049_search_reconciliation_leases.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
