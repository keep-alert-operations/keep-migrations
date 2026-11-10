"""0053 removed the correlation and maintenance capability gates (REV-39)."""

from keep.migrate import apply_sql

revision = "0053"
down_revision = "0052"
branch_labels = None
depends_on = None
sql_file = "0053_always_on_correlation_maintenance.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
