"""0046 worker scope; original SQL bytes preserved."""

from appchi.migrate import apply_sql

revision = "0046"
down_revision = "0045"
branch_labels = None
depends_on = None
sql_file = "0046_worker_scope.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
