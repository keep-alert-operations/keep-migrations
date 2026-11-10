"""Dedicated migration-role environment shared by the CLI and packaged runner."""

from alembic import context

from keep.migrate import run_environment

run_environment(context)
