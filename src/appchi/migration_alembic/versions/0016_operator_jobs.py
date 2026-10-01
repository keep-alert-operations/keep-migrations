"""0016 operator jobs; original SQL bytes preserved."""

from appchi.migrate import apply_sql

revision = "0016"
down_revision = "0015"
branch_labels = None
depends_on = None
sql_file = "0016_operator_jobs.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
