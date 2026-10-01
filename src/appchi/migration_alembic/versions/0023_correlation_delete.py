"""0023 correlation delete; original SQL bytes preserved."""

from appchi.migrate import apply_sql

revision = "0023"
down_revision = "0022"
branch_labels = None
depends_on = None
sql_file = "0023_correlation_delete.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
