"""0017 pipeline leases; original SQL bytes preserved."""

from keep.migrate import apply_sql

revision = "0017"
down_revision = "0016"
branch_labels = None
depends_on = None
sql_file = "0017_pipeline_leases.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
