"""Phase 4 — RDS PostgreSQL + PostGIS verification (DB-free unit checks).

These tests require no live database. They validate the parts of the Phase 4
deliverable that are statically verifiable:

- The Alembic migration chain is linear and has exactly one head.
- PostGIS is enabled by a migration (CREATE EXTENSION postgis).
- PostGIS Geography columns exist in the migration chain.
- The Phase 4 verifier (scripts/verify_rds.py) encodes the same approved
  table set that the migration chain actually creates.

Live PostGIS/database checks live in scripts/verify_rds.py (run against the
real RDS instance) and in tests/test_database_schema.py (requires DB).
"""
import re
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
VERSIONS = BACKEND_DIR / "alembic" / "versions"
VERIFIER = BACKEND_DIR / "scripts" / "verify_rds.py"


def _migration_files():
    return sorted(VERSIONS.glob("[0-9]*_*.py"))


def _source(path):
    return path.read_text(encoding="utf-8")


def _migration_tables():
    tables = set()
    for f in _migration_files():
        tables |= set(re.findall(r'op\.create_table\([^("]*"([\w_]+)"', _source(f)))
    return tables


def _verifier_tables():
    src = _source(VERIFIER)
    # Extract the string literals inside EXPECTED_TABLES = { ... } block.
    block = re.search(r"EXPECTED_TABLES.*?=\s*\{(.*?)\n\}", src, re.DOTALL)
    assert block, "EXPECTED_TABLES set not found in verify_rds.py"
    return set(re.findall(r'"([\w_]+)"', block.group(1)))


def test_migration_chain_is_linear_with_single_head():
    revisions = {}
    for f in _migration_files():
        src = _source(f)
        m = re.search(r"^revision:.*?= [\"']([^\"']+)[\"']", src, re.MULTILINE)
        d = re.search(r"^down_revision:.*?=\s*([\"']([^\"']+)[\"']|None)", src, re.MULTILINE)
        assert m, f"No revision id in {f.name}"
        rev = m.group(1)
        down = None if d is None or d.group(1) == "None" else d.group(2)
        revisions[rev] = down
    # single root == single head === linear chain
    roots = [r for r, d in revisions.items() if d is None]
    assert len(roots) == 1, f"expected 1 root (0001), got {roots}"
    # next_of[down] = rev — follow the forward direction from the root.
    next_of = {down: rev for rev, down in revisions.items() if down is not None}
    current = roots[0]
    seen = set()
    while current in revisions and current not in seen:
        seen.add(current)
        nxt = next_of.get(current)
        if nxt is None:
            break
        current = nxt
    # The HEAD is whatever the newest migration is — derive it instead of
    # hardcoding a revision, so adding 0027/0028/... never fails this check
    # (it previously pinned "0025" and broke the moment 0026 landed).
    assert sorted(revisions) == sorted(seen), "chain is not linear (branch/merge)"
    assert current == max(revisions), (
        f"HEAD {current} is not the highest revision {max(revisions)} — "
        "a later migration may be orphaned from the chain"
    )
    # Revision ids must stay contiguous 0001..N so ordering is unambiguous.
    assert sorted(revisions) == [f"{i:04d}" for i in range(1, len(revisions) + 1)]


def test_postgis_extension_enabled_by_migration():
    combined = "\n".join(_source(f) for f in _migration_files())
    assert re.search(r"CREATE EXTENSION IF NOT EXISTS postgis", combined)
    assert re.search(r"CREATE EXTENSION IF NOT EXISTS pg_trgm", combined)


def test_geography_columns_present_in_migrations():
    combined = "\n".join(_source(f) for f in _migration_files())
    assert "Geography" in combined or "geography" in combined
    assert "POINT" in combined
    assert "srid=4326" in combined.lower()
    assert "spatial_index=True" in combined or "spatial_index" in combined


def test_verifier_expected_tables_cover_migrations():
    migrated = _migration_tables()
    verifier = _verifier_tables()
    uncovered = migrated - verifier
    # 'products' is the superseded legacy table dropped in 0002 — exclude it.
    uncovered.discard("products")
    assert not uncovered, f"verifier EXPECTED_TABLES missing: {sorted(uncovered)}"


def test_verifier_has_required_checks():
    src = _source(VERIFIER)
    for needle in (
        "PostGIS_Version",
        "alembic_version",
        "information_schema.tables",
        "pg_constraint",
        "ST_DWithin",
        "ST_Distance",
        "ST_Within",
        "rollback",
    ):
        assert needle in src, f"verify_rds.py missing check for {needle}"


def test_verifier_compiles():
    import py_compile
    py_compile.compile(str(VERIFIER), doraise=True)