"""0002 session refresh; original SQL bytes preserved."""

from keep.migrate import apply_sql

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None
sql_file = "0002_session_refresh.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
