"""0063 adds alert table dashboard panels (REV-63)."""

from appchi.migrate import apply_sql

revision = "0063"
down_revision = "0062"
branch_labels = None
depends_on = None
sql_file = "0063_table_panels.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
