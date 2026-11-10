"""0036 visibility inputs; original SQL bytes preserved."""

from keep.migrate import apply_sql

revision = "0036"
down_revision = "0035"
branch_labels = None
depends_on = None
sql_file = "0036_visibility_inputs.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
