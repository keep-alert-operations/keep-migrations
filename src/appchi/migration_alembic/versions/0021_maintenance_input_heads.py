"""0021 maintenance input heads; original SQL bytes preserved."""

from appchi.migrate import apply_sql

revision = "0021"
down_revision = "0020"
branch_labels = None
depends_on = None
sql_file = "0021_maintenance_input_heads.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
