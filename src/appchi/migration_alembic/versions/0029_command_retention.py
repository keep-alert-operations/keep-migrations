"""0029 command retention; original SQL bytes preserved."""

from appchi.migrate import apply_sql

revision = "0029"
down_revision = "0028"
branch_labels = None
depends_on = None
sql_file = "0029_command_retention.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
