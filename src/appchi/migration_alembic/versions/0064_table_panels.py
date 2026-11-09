"""0064 adds alert table dashboard panels (REV-63)."""

from appchi.migrate import apply_sql

revision = "0064"
down_revision = "0063"
branch_labels = None
depends_on = None
sql_file = "0064_table_panels.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
