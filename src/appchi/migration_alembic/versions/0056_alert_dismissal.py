"""0056 adds the timed alert dismissal cause (REV-49)."""

from appchi.migrate import apply_sql

revision = "0056"
down_revision = "0055"
branch_labels = None
depends_on = None
sql_file = "0056_alert_dismissal.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
