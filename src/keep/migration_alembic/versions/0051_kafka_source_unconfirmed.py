"""0051 indexed unconfirmed source results for assignment catch-up."""

from keep.migrate import apply_sql

revision = "0051"
down_revision = "0050"
branch_labels = None
depends_on = None
sql_file = "0051_kafka_source_unconfirmed.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
