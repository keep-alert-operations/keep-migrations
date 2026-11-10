"""0016 operator jobs; original SQL bytes preserved."""

from keep.migrate import apply_sql

revision = "0016"
down_revision = "0015"
branch_labels = None
depends_on = None
sql_file = "0016_operator_jobs.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
