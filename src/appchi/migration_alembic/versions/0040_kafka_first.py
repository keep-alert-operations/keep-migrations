"""0040 kafka first; original SQL bytes preserved."""

from appchi.migrate import apply_sql

revision = "0040"
down_revision = "0039"
branch_labels = None
depends_on = None
sql_file = "0040_kafka_first.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
