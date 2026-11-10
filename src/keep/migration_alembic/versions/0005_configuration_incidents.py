"""0005 configuration incidents; original SQL bytes preserved."""

from keep.migrate import apply_sql

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None
sql_file = "0005_configuration_incidents.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
