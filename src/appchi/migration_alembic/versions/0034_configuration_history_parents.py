"""0034 configuration history parents; original SQL bytes preserved."""

from appchi.migrate import apply_sql

revision = "0034"
down_revision = "0033"
branch_labels = None
depends_on = None
sql_file = "0034_configuration_history_parents.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
