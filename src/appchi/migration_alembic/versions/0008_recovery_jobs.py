"""0008 recovery jobs; original SQL bytes preserved."""

from appchi.migrate import apply_sql

revision = "0008"
down_revision = "0007"
branch_labels = None
depends_on = None
sql_file = "0008_recovery_jobs.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
