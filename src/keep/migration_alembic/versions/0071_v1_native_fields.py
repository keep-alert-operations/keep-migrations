"""0071 stores v1 alerts as sent: an `object` column and v1 severities (REV-77)."""

from keep.migrate import apply_sql

revision = "0071"
down_revision = "0070"
branch_labels = None
depends_on = None
sql_file = "0071_v1_native_fields.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
