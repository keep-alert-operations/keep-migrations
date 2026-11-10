"""0047 api live hints; original SQL bytes preserved."""

from keep.migrate import apply_sql

revision = "0047"
down_revision = "0046"
branch_labels = None
depends_on = None
sql_file = "0047_api_live_hints.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
