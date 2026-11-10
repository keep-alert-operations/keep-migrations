"""0004 directory proof; original SQL bytes preserved."""

from keep.migrate import apply_sql

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None
sql_file = "0004_directory_proof.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
