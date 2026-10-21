"""0052 indexed pending retirement projection rows for search probes."""

from appchi.migrate import apply_sql

revision = "0052"
down_revision = "0051"
branch_labels = None
depends_on = None
sql_file = "0052_projection_retirement_pending.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
