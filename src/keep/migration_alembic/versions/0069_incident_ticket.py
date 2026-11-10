"""0069 adds a ServiceNow ticket link to incidents (REV-70)."""

from keep.migrate import apply_sql

revision = "0069"
down_revision = "0068"
branch_labels = None
depends_on = None
sql_file = "0069_incident_ticket.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
