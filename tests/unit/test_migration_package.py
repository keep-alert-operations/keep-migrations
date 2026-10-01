from hashlib import sha256
import json
from pathlib import Path
from appchi.migrate import migration_directory


def test_extracted_migration_bytes_and_complete_chain():
    baseline = json.loads((Path(__file__).resolve().parents[2] / "migration-checksums.json").read_text())
    actual = {p.name: sha256(p.read_bytes()).hexdigest() for p in migration_directory().glob("*.sql")}
    assert actual == baseline
