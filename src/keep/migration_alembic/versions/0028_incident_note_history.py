"""0028 incident note history; original SQL bytes preserved."""

from keep.migrate import apply_sql

revision = "0028"
down_revision = "0027"
branch_labels = None
depends_on = None
sql_file = "0028_incident_note_history.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
