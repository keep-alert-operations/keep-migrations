"""0063 adds image dashboard panels (REV-62)."""

from keep.migrate import apply_sql

revision = "0063"
down_revision = "0062"
branch_labels = None
depends_on = None
sql_file = "0063_image_panels.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
