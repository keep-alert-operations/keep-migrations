"""0066 renames Appchi database roles and the tenant setting to Keep (REV-67)."""

from keep.migrate import apply_sql

revision = "0066"
down_revision = "0065"
branch_labels = None
depends_on = None
sql_file = "0066_keep_rename.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
