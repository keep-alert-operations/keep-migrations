"""0012 recovery attempt fences; original SQL bytes preserved."""

from keep.migrate import apply_sql

revision = "0012"
down_revision = "0011"
branch_labels = None
depends_on = None
sql_file = "0012_recovery_attempt_fences.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
