"""0039 alert actor snapshots; original SQL bytes preserved."""

from appchi.migrate import apply_sql

revision = "0039"
down_revision = "0038"
branch_labels = None
depends_on = None
sql_file = "0039_alert_actor_snapshots.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
