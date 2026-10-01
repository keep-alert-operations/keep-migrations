"""0018 correlation runtime; original SQL bytes preserved."""

from appchi.migrate import apply_sql

revision = "0018"
down_revision = "0017"
branch_labels = None
depends_on = None
sql_file = "0018_correlation_runtime.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
