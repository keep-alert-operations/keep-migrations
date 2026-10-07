"""0032 correlation retention; original SQL bytes preserved."""

from appchi.migrate import apply_sql

revision = "0032"
down_revision = "0031"
branch_labels = None
depends_on = None
sql_file = "0032_correlation_retention.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
