"""0070 replaces Keycloak sign-in state with password login and ADAPI saves (REV-73)."""

from keep.migrate import apply_sql

revision = "0070"
down_revision = "0069"
branch_labels = None
depends_on = None
sql_file = "0070_password_login_adapi.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
