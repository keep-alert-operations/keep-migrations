"""0020 live hints; original SQL bytes preserved."""

from appchi.migrate import apply_sql

revision = "0020"
down_revision = "0019"
branch_labels = None
depends_on = None
sql_file = "0020_live_hints.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
