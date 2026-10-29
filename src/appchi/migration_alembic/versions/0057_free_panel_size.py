"""0057 lets panel width step by one column and drops the height cap (REV-50)."""

from appchi.migrate import apply_sql

revision = "0057"
down_revision = "0056"
branch_labels = None
depends_on = None
sql_file = "0057_free_panel_size.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
