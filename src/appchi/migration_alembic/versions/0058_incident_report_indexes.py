"""0058 indexes incident cycles and assignment history for incident reports (REV-53)."""

from appchi.migrate import apply_sql

revision = "0058"
down_revision = "0057"
branch_labels = None
depends_on = None
sql_file = "0058_incident_report_indexes.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
