"""0061 adds the preset alarm flag (REV-58)."""

from keep.migrate import apply_sql

revision = "0061"
down_revision = "0060"
branch_labels = None
depends_on = None
sql_file = "0061_preset_noisy.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
