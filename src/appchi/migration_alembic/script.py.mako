"""${message}"""

from appchi.migrate import apply_sql

revision = ${repr(up_revision)}
down_revision = ${repr(down_revision)}
branch_labels = None
depends_on = None
sql_file = ${repr(up_revision + "_" + "_".join(message.lower().split()) + ".sql")}


def upgrade():
    apply_sql(sql_file)


def downgrade():
    raise RuntimeError("Appchi migrations are forward-only; use a reviewed forward migration")
