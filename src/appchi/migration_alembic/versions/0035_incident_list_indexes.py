"""0035 incident list indexes; original SQL bytes preserved."""

from appchi.migrate import apply_sql

revision = "0035"
down_revision = "0034"
branch_labels = None
depends_on = None
sql_file = "0035_incident_list_indexes.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
