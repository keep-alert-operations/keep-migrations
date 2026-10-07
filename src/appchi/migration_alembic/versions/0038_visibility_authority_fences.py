"""0038 visibility authority fences; original SQL bytes preserved."""

from appchi.migrate import apply_sql

revision = "0038"
down_revision = "0037"
branch_labels = None
depends_on = None
sql_file = "0038_visibility_authority_fences.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
