"""0065 adds ServiceNow ticket dashboard panels (REV-65)."""

from keep.migrate import apply_sql

revision = "0065"
down_revision = "0064"
branch_labels = None
depends_on = None
sql_file = "0065_servicenow_panels.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
