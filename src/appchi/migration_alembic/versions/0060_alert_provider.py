"""0060 adds the alert provider and Grafana alert rule URL (REV-55)."""

from appchi.migrate import apply_sql

revision = "0060"
down_revision = "0059"
branch_labels = None
depends_on = None
sql_file = "0060_alert_provider.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
