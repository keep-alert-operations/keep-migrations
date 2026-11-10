"""0068 adds incident count dashboard panels (REV-69)."""

from keep.migrate import apply_sql

revision = "0068"
down_revision = "0067"
branch_labels = None
depends_on = None
sql_file = "0068_incident_count_panels.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
