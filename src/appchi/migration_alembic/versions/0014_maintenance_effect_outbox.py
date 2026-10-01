"""0014 maintenance effect outbox; original SQL bytes preserved."""

from appchi.migrate import apply_sql

revision = "0014"
down_revision = "0013"
branch_labels = None
depends_on = None
sql_file = "0014_maintenance_effect_outbox.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
