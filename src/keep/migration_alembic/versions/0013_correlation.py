"""0013 correlation; original SQL bytes preserved."""

from keep.migrate import apply_sql

revision = "0013"
down_revision = "0012"
branch_labels = None
depends_on = None
sql_file = "0013_correlation.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
