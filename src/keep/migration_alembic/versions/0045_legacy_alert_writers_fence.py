"""0045 legacy alert writers fence; original SQL bytes preserved."""

from keep.migrate import apply_sql

revision = "0045"
down_revision = "0044"
branch_labels = None
depends_on = None
sql_file = "0045_legacy_alert_writers_fence.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
