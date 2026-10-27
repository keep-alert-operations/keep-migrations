"""0054 records the Kafka topic incarnations at cutover (REV-41)."""

from appchi.migrate import apply_sql

revision = "0054"
down_revision = "0053"
branch_labels = None
depends_on = None
sql_file = "0054_kafka_topic_identity.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
