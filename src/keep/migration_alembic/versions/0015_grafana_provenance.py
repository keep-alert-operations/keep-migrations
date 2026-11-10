"""0015 grafana provenance; original SQL bytes preserved."""

from keep.migrate import apply_sql

revision = "0015"
down_revision = "0014"
branch_labels = None
depends_on = None
sql_file = "0015_grafana_provenance.sql"


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Keep migrations are forward-only; use a reviewed forward migration")
