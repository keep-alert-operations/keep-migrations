"""0009 maintenance; original SQL bytes preserved."""

from keep.migrate import apply_sql

revision = "0009"
down_revision = "0008"
branch_labels = None
depends_on = None
sql_file = "0009_maintenance.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
