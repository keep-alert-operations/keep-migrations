"""0011 maintenance processing; original SQL bytes preserved."""

from appchi.migrate import apply_sql

revision = "0011"
down_revision = "0009"
branch_labels = None
depends_on = None
sql_file = "0011_maintenance_processing.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
