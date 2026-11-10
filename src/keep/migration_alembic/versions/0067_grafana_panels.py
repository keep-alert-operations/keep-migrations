"""0067 adds Grafana dashboard panels (REV-68)."""

from keep.migrate import apply_sql

revision = "0067"
down_revision = "0066"
branch_labels = None
depends_on = None
sql_file = "0067_grafana_panels.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
