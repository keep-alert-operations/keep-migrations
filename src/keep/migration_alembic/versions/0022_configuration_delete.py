"""0022 configuration delete; original SQL bytes preserved."""

from keep.migrate import apply_sql

revision = "0022"
down_revision = "0021"
branch_labels = None
depends_on = None
sql_file = "0022_configuration_delete.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
