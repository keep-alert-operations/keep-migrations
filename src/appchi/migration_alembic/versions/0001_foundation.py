"""0001 foundation; original SQL bytes preserved."""

from appchi.migrate import apply_sql

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None
sql_file = "0001_foundation.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
