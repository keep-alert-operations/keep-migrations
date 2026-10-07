"""0041 kafka first cutover; original SQL bytes preserved."""

from appchi.migrate import apply_sql

revision = "0041"
down_revision = "0040"
branch_labels = None
depends_on = None
sql_file = "0041_kafka_first_cutover.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
