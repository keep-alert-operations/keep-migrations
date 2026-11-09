from hashlib import sha256
import json
import shutil

import pytest
from appchi.migrate import alembic_config, migration_chain, migration_directory


def test_extracted_migration_bytes_and_complete_chain():
    baseline = json.loads((migration_directory() / "checksums.json").read_text())
    actual = {
        p.name: sha256(p.read_bytes()).hexdigest() for p in migration_directory().glob("*.sql")
    }
    assert actual == baseline


def test_every_sql_file_has_one_ordered_alembic_revision():
    chain = migration_chain(alembic_config())
    assert len(chain) == 60
    assert chain[0].revision == "0001"
    assert chain[-1].revision == "0063"
    assert {"0010", "0042", "0043"}.isdisjoint(step.revision for step in chain)


def test_pending_sql_is_verified_before_connecting(tmp_path):
    directory = tmp_path / "sql"
    shutil.copytree(migration_directory(), directory)
    path = directory / "0047_api_live_hints.sql"
    path.write_bytes(path.read_bytes() + b"\n-- modified pending SQL\n")
    with pytest.raises(RuntimeError, match="checksum"):
        migration_chain(alembic_config(directory))


def test_sql_without_a_revision_is_rejected(tmp_path):
    directory = tmp_path / "sql"
    shutil.copytree(migration_directory(), directory)
    (directory / "0054_unregistered.sql").write_text("SELECT 1;")
    with pytest.raises(RuntimeError, match="disagree"):
        migration_chain(alembic_config(directory))


def test_multiple_revision_heads_are_rejected(tmp_path):
    config = alembic_config()
    scripts = tmp_path / "alembic"
    shutil.copytree(config.get_main_option("script_location"), scripts)
    (scripts / "versions" / "0054_branch.py").write_text(
        "revision='0054'\ndown_revision='0045'\nbranch_labels=None\ndepends_on=None\n"
    )
    config.set_main_option("script_location", str(scripts).replace("%", "%%"))
    with pytest.raises(RuntimeError, match="one Alembic head"):
        migration_chain(config)
