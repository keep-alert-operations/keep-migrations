"""0024 incident retirement; original SQL bytes preserved."""

from appchi.migrate import apply_sql

revision = "0024"
down_revision = "0023"
branch_labels = None
depends_on = None
sql_file = "0024_incident_retirement.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
