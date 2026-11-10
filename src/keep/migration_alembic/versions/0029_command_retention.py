"""0029 command retention; original SQL bytes preserved."""

from keep.migrate import apply_sql

revision = "0029"
down_revision = "0028"
branch_labels = None
depends_on = None
sql_file = "0029_command_retention.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
