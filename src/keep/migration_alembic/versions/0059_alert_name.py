"""0059 adds the optional sender-supplied alert name (REV-54)."""

from keep.migrate import apply_sql

revision = "0059"
down_revision = "0058"
branch_labels = None
depends_on = None
sql_file = "0059_alert_name.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
