"""0037 operator diagnostics retention; original SQL bytes preserved."""

from appchi.migrate import apply_sql

revision = "0037"
down_revision = "0036"
branch_labels = None
depends_on = None
sql_file = "0037_operator_diagnostics_retention.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
