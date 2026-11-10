"""0007 partition privileges; original SQL bytes preserved."""

from keep.migrate import apply_sql

revision = "0007"
down_revision = "0006"
branch_labels = None
depends_on = None
sql_file = "0007_partition_privileges.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
