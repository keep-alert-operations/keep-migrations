"""0017 pipeline leases; original SQL bytes preserved."""

from appchi.migrate import apply_sql

revision = "0017"
down_revision = "0016"
branch_labels = None
depends_on = None
sql_file = "0017_pipeline_leases.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
