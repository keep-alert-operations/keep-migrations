"""0055 adds the optional preset grouping field (REV-44)."""

from keep.migrate import apply_sql

revision = "0055"
down_revision = "0054"
branch_labels = None
depends_on = None
sql_file = "0055_preset_group_by.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
