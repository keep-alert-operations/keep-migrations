"""0003 refresh uncertainty; original SQL bytes preserved."""

from appchi.migrate import apply_sql

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None
sql_file = "0003_refresh_uncertainty.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
