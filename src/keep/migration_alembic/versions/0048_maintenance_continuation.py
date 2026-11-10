"""0048 maintenance continuation; additive temporal replay optimization."""

from keep.migrate import apply_sql

revision = "0048"
down_revision = "0047"
branch_labels = None
depends_on = None
sql_file = "0048_maintenance_continuation.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
