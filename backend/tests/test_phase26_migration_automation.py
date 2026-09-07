"""Phase 26 — Database Migration Automation tests.

Automated verification of the six guarantees the migration pipeline must
provide — most run with NO database (static analysis of the migration chain and
files); a few are live-database-gated by the standard ``requires_db`` pattern:

  1. forward migration         chain linear/single-head + (live) alembic head
  2. rollback (where supported) every downgrade() statically reverses its
                                upgrade() (tables + indexes); the live rehearsal
                                drills the -1 and full-chain rollback on a
                                scratch DB (scripts/migration_rehearsal.py)
  3. data safety               no silent NOT NULL add_column (static policy)
  4. index creation            representative indexes exist after upgrade (live)
  5. foreign keys              FKs exist AND are enforced (live)
  6. PostGIS changes           extension + Geography types + GiST indexes (live)

Usage:
    python -m pytest tests/test_phase26_migration_automation.py -q
"""
from __future__ import annotations

import ast
import importlib.util
import re
import sys
from pathlib import Path

import pytest

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

REHEARSAL = BACKEND_DIR / "scripts" / "migration_rehearsal.py"
DRIFT = BACKEND_DIR / "scripts" / "check_migration_drift.py"
VERSIONS_DIR = BACKEND_DIR / "alembic" / "versions"


def _load_script_module(name: str, path: Path):
    """Import a backend/scripts module without requiring a package init."""
    spec = importlib.util.spec_from_file_location(f"phase26_{name}", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


rehearsal = _load_script_module("migration_rehearsal", REHEARSAL)


# ── Database-availability probe (mirror test_database_schema) ───────────────
def _database_available() -> bool:
    try:
        from sqlalchemy import create_engine
        from app.core.config import settings

        engine = create_engine(rehearsal.to_sync_url(settings.sqlalchemy_sync_url),
                               pool_pre_ping=True)
        with engine.connect():
            pass
        engine.dispose()
        return True
    except Exception:  # noqa: BLE001
        return False


requires_db = pytest.mark.skipif(not _database_available(),
                                 reason="requires a reachable PostgreSQL/PostGIS database")


# ═══════════════════════════════════════════════════════════════════════════
# 1. Forward migration — chain integrity (static, no DB)
# ═══════════════════════════════════════════════════════════════════════════
def test_chain_is_linear_with_single_head():
    revisions = rehearsal.parse_revisions(VERSIONS_DIR)
    assert rehearsal.chain_issues(revisions) == []
    assert rehearsal.head_revision(revisions) == "0017"


def test_revision_ids_are_sequential_and_unique():
    revisions = rehearsal.parse_revisions(VERSIONS_DIR)
    nums = [int(r["revision"]) for r in revisions]
    assert len(nums) == len(set(nums)), "duplicate revision ids"
    assert nums == list(range(1, len(nums) + 1)), "revisions must be 0001..N contiguous"


def test_every_revision_defines_upgrade_and_downgrade():
    """A version-controlled schema chain is only rollback-able if every file ships both."""
    for path in sorted(VERSIONS_DIR.glob("*.py")):
        if path.name.startswith("__"):
            continue
        tree = ast.parse(path.read_text(encoding="utf-8", errors="replace"))
        fns = {n.name for n in tree.body if isinstance(n, ast.FunctionDef)}
        assert "upgrade" in fns, f"{path.name} missing upgrade()"
        assert "downgrade" in fns, f"{path.name} missing downgrade()"


# ═══════════════════════════════════════════════════════════════════════════
# 2. Rollback (where supported) — downgrade() must reverse upgrade()
# ═══════════════════════════════════════════════════════════════════════════
_CREATE_INDEX_SQL = re.compile(
    r"CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?([A-Za-z0-9_]+)",
    re.IGNORECASE,
)


def _collect_ops(fn: ast.FunctionDef) -> dict[str, set[str]]:
    """Collect create/drop table + create/drop index names, plus raw-SQL
    ``CREATE INDEX`` names (0014 creates token_blacklist indexes via execute)."""
    created_tables: set[str] = set()
    dropped_tables: set[str] = set()
    created_indexes: set[str] = set()
    dropped_indexes: set[str] = set()
    raw_indexes: set[str] = set()
    for node in ast.walk(fn):
        if isinstance(node, ast.Call):
            func = node.func
            attr = func.attr if isinstance(func, ast.Attribute) else None
            arg0 = node.args[0].value if node.args and isinstance(node.args[0], ast.Constant) else None
            if attr == "create_table" and isinstance(arg0, str):
                created_tables.add(arg0)
            elif attr == "drop_table" and isinstance(arg0, str):
                dropped_tables.add(arg0)
            elif attr == "create_index" and isinstance(arg0, str):
                created_indexes.add(arg0)
            elif attr == "drop_index" and isinstance(arg0, str):
                dropped_indexes.add(arg0)
            elif isinstance(func, ast.Name) and func.id == "execute" or (
                    isinstance(func, ast.Attribute) and func.attr == "execute"):
                src = (node.args[0].value
                       if node.args and isinstance(node.args[0], ast.Constant) else "")
                raw_indexes.update(_CREATE_INDEX_SQL.findall(src))
    return {
        "create_table": created_tables,
        "drop_table": dropped_tables,
        "create_index": created_indexes,
        "drop_index": dropped_indexes,
        "raw_created_indexes": raw_indexes,
    }


def test_downgrade_reverses_upgrade_surface():
    """For every migration: tables dropped by the downgrade must be exactly the
    tables created by the upgrade (swap patterns included), and every index the
    downgrade drops must have been created by the upgrade (directly or via raw
    SQL, e.g. 0014's token_blacklist indexes)."""
    problems: list[str] = []
    for path in sorted(VERSIONS_DIR.glob("*.py")):
        if path.name.startswith("__"):
            continue
        tree = ast.parse(path.read_text(encoding="utf-8", errors="replace"))
        bodies: dict[str, dict[str, set[str]]] = {}
        for node in tree.body:
            if isinstance(node, ast.FunctionDef) and node.name in ("upgrade", "downgrade"):
                bodies[node.name] = _collect_ops(node)
        if "upgrade" not in bodies or "downgrade" not in bodies:
            problems.append(f"{path.name}: missing upgrade/downgrade")
            continue
        up, down = bodies["upgrade"], bodies["downgrade"]
        # Tables created in upgrade must be dropped in downgrade.
        for t in sorted(up["create_table"] - down["drop_table"]):
            problems.append(f"{path.name}: create_table {t} not dropped in downgrade")
        # Tables dropped in upgrade must be recreated in downgrade OR recreated
        # later in the upgrade itself (a swap, e.g. 0002 saved_products).
        for t in sorted(up["drop_table"] - down["create_table"] - up["create_table"]):
            problems.append(f"{path.name}: drop_table {t} not restored in downgrade")
        # Every index the downgrade drops must have been created by the upgrade.
        for idx in sorted(down["drop_index"] - up["create_index"] - up["raw_created_indexes"]):
            problems.append(f"{path.name}: drop_index {idx} in downgrade but never created in upgrade")
    assert not problems, "\n".join(problems)


# ═══════════════════════════════════════════════════════════════════════════
# 3. Data safety — no silent NOT NULL column adds (static, no DB)
# ═══════════════════════════════════════════════════════════════════════════
def test_no_silent_not_null_column_adds():
    violations = rehearsal.scan_data_safety_violations(VERSIONS_DIR)
    assert violations == [], f"data-safety violations:\n{violations}"


# ═══════════════════════════════════════════════════════════════════════════
# Tooling smoke tests (no DB)
# ═══════════════════════════════════════════════════════════════════════════
def test_migration_generator_computes_next_revision():
    gen = _load_script_module("generate_migration", BACKEND_DIR / "scripts" / "generate_migration.py")
    assert gen.next_rev_id(VERSIONS_DIR) == "0018"


def test_drift_checker_self_consistent():
    """The ORM schema compared against itself must have zero drift — proves the
    checker is wired correctly before any live database is required."""
    drift = _load_script_module("check_migration_drift", DRIFT)
    # Reverse any Geography->Text stripping another test module may have applied.
    try:
        from tests.geo_compat import restore_geo_columns
        restore_geo_columns()
    except Exception:  # noqa: BLE001
        pass
    from app.database.session import Base
    import app.models  # noqa: F401

    orm = drift.build_orm_schema(Base.metadata)
    result = drift.compare(orm, orm)
    assert result["drift"] == [], f"self-diff drift:\n{result['drift']}"


# ═══════════════════════════════════════════════════════════════════════════
# 4-6. Live verification (requires a real PostGIS database)
# ═══════════════════════════════════════════════════════════════════════════
@requires_db
def test_live_forward_migration_at_head():
    """The live DB must be stamped at the same head the chain computes."""
    from sqlalchemy import create_engine, text
    from app.core.config import settings

    engine = create_engine(rehearsal.to_sync_url(settings.sqlalchemy_sync_url))
    try:
        with engine.connect() as conn:
            row = conn.execute(text("SELECT version_num FROM alembic_version")).fetchone()
        head = rehearsal.head_revision(rehearsal.parse_revisions(VERSIONS_DIR))
        assert row is not None and row[0] == head, f"DB at {row[0] if row else None}, expected {head}"
    finally:
        engine.dispose()


@requires_db
def test_live_indexes_fks_and_postgis_surface():
    from sqlalchemy import create_engine
    from app.core.config import settings

    engine = create_engine(rehearsal.to_sync_url(settings.sqlalchemy_sync_url))
    try:
        _checks, errors = rehearsal.check_schema_surface(engine)
    finally:
        engine.dispose()
    assert errors == [], f"schema-surface failures:\n{errors}"


@requires_db
def test_live_database_reachable_for_rehearsal():
    """The drift/rehearsal tooling can connect (read-only) — the full rehearsal
    report is produced by scripts/migration_rehearsal.py in CI."""
    import sqlalchemy
    from app.core.config import settings

    drift = _load_script_module("check_migration_drift", DRIFT)
    engine = sqlalchemy.create_engine(drift.to_sync_url(settings.sqlalchemy_sync_url))
    try:
        with engine.connect():
            pass
        ok = True
    except Exception:  # noqa: BLE001
        ok = False
    finally:
        engine.dispose()
    assert ok is True, "database unreachable for drift/rehearsal tooling"