"""0019 identity cleanup; original SQL bytes preserved."""

from appchi.migrate import apply_sql

revision = "0019"
down_revision = "0018"
branch_labels = None
depends_on = None
sql_file = "0019_identity_cleanup.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
