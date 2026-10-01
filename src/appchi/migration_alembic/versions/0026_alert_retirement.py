"""0026 alert retirement; original SQL bytes preserved."""

from appchi.migrate import apply_sql

revision = "0026"
down_revision = "0025"
branch_labels = None
depends_on = None
sql_file = "0026_alert_retirement.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
