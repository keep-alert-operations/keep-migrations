"""0044 kafka diagnostics; original SQL bytes preserved."""

from appchi.migrate import apply_sql

revision = "0044"
down_revision = "0041"
branch_labels = None
depends_on = None
sql_file = "0044_kafka_diagnostics.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
