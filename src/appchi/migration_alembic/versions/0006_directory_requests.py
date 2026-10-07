"""0006 directory requests; original SQL bytes preserved."""

from appchi.migrate import apply_sql

revision = "0006"
down_revision = "0005"
branch_labels = None
depends_on = None
sql_file = "0006_directory_requests.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
