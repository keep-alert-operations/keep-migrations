"""0031 visibility registry; original SQL bytes preserved."""

from keep.migrate import apply_sql

revision = "0031"
down_revision = "0030"
branch_labels = None
depends_on = None
sql_file = "0031_visibility_registry.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
