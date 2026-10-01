"""0027 restore fencing; original SQL bytes preserved."""

from appchi.migrate import apply_sql

revision = "0027"
down_revision = "0026"
branch_labels = None
depends_on = None
sql_file = "0027_restore_fencing.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
