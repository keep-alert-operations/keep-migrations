"""0062 adds dashboard panel types (REV-57)."""

from keep.migrate import apply_sql

revision = "0062"
down_revision = "0061"
branch_labels = None
depends_on = None
sql_file = "0062_panel_types.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
