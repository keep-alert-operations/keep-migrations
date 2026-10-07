"""0025 search rebuild; original SQL bytes preserved."""

from appchi.migrate import apply_sql

revision = "0025"
down_revision = "0024"
branch_labels = None
depends_on = None
sql_file = "0025_search_rebuild.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
