"""0050 indexed live-note projection lookup."""

from appchi.migrate import apply_sql

revision = "0050"
down_revision = "0049"
branch_labels = None
depends_on = None
sql_file = "0050_alert_notes_projection_lookup.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
