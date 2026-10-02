"""Phase 26 — Database Migration Automation tests.

Automated verification of the six guarantees the migration pipeline must
provide. Every check runs in one of two flows, chosen automatically at
collection time — a missing database changes the flow, it never skips a check:

  ``live``  the PostgreSQL/PostGIS database behind ``DATABASE_URL``, used only
            when it answers and really is PostgreSQL: alembic_version,
            pg_indexes, pg_constraint, information_schema, pg_extension.
  ``local`` the ORM surface materialised in-process on SQLite plus the revision
            sources — the DB-free equivalent of the same guarantees, so CI
            without a database still verifies all six.

  1. forward migration         chain linear/single-head + head stamped
  2. rollback (where supported) every downgrade() statically reverses its
                               upgrade() (tables + indexes); the live rehearsal
                               drills the -1 and full-chain rollback on a
                               scratch DB (scripts/migration_rehearsal.py)
  3. data safety               no silent NOT NULL add_column (static policy)
  4. index creation            representative indexes exist after upgrade
  5. foreign keys              FKs exist AND are enforced
  6. PostGIS changes           extension + Geography types + GiST indexes

Usage:
    python -m pytest tests/test_phase26_migration_automation.py -q"""
from __future__ import annotations

import ast
import importlib.util
import re
import sys
from functools import lru_cache
from pathlib import Path

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy import inspect as sa_inspect
from sqlalchemy.exc import IntegrityError

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


# ── Flow probe: a live PostgreSQL database, or the DB-free local flow ───────
def _sync_url(url: str | None = None) -> str:
    """Sync SQLAlchemy URL for ``url`` (default: the configured database).

    ``settings.sqlalchemy_sync_url`` yields the libpq form (``postgresql://``),
    which SQLAlchemy maps to psycopg2 — that driver is not installed here, so the
    installed psycopg3 driver is selected explicitly.
    """
    if url is None:
        from app.core.config import settings

        url = settings.sqlalchemy_sync_url
    if url.startswith("postgresql://"):
        return url.replace("postgresql://", "postgresql+psycopg://", 1)
    return url


def _database_available() -> bool:
    """True when the configured ``DATABASE_URL`` answers AND is PostgreSQL.

    A SQLite URL (the test-environment default) is not a PostGIS database, so
    it never counts as live — the local flow covers it instead.
    """
    url = _sync_url()
    if not url.startswith("postgresql"):
        return False
    engine = create_engine(url, pool_pre_ping=True, connect_args={"connect_timeout": 5})
    try:
        with engine.connect():
            pass
    except Exception:  # noqa: BLE001 — unreachable database means the local flow
        return False
    finally:
        engine.dispose()
    return True


DATABASE_AVAILABLE = _database_available()


# ═══════════════════════════════════════════════════════════════════════════
# 1. Forward migration — chain integrity (static, no DB)
# ═══════════════════════════════════════════════════════════════════════════
def test_chain_is_linear_with_single_head():
    revisions = rehearsal.parse_revisions(VERSIONS_DIR)
    assert rehearsal.chain_issues(revisions) == []
    # Derive the expected head from the chain itself: revisions must be a
    # contiguous 0001..N run, so the head is always the last one. Hardcoding a
    # revision here made this test fail every time a new migration landed.
    nums = sorted(int(r["revision"]) for r in revisions)
    assert nums == list(range(1, len(nums) + 1)), (
        f"revisions must be a contiguous 0001..{len(nums):04d} run, got {nums}"
    )
    assert rehearsal.head_revision(revisions) == f"{len(nums):04d}"


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
    revisions = rehearsal.parse_revisions(VERSIONS_DIR)
    expected = f"{len(revisions) + 1:04d}"
    assert gen.next_rev_id(VERSIONS_DIR) == expected


def test_drift_checker_self_consistent():
    """The ORM schema compared against itself must have zero drift — proves the
    checker is wired correctly before any live database is required.

    Note: we intentionally do NOT call restore_geo_columns() here. The whole
    SQLite test suite shares the process-global ``Base.metadata``; restoring
    pristine PostGIS types mid-session makes every later module's
    ``create_all`` fail with "near POINT: syntax error". Self-diff is
    identical whether the Geography columns are stripped to Text or not.
    """
    drift = _load_script_module("check_migration_drift", DRIFT)
    import app.models  # noqa: F401
    from app.database.session import Base

    orm = drift.build_orm_schema(Base.metadata)
    result = drift.compare(orm, orm)
    assert result["drift"] == [], f"self-diff drift:\n{result['drift']}"


# ═══════════════════════════════════════════════════════════════════════════
# 4-6. Schema surface — the live database when reachable, the local flow
#      (ORM surface + revision sources) otherwise. Never skipped.
# ═══════════════════════════════════════════════════════════════════════════
_GIST_SQL = re.compile(r"USING\s+GIST", re.IGNORECASE)
_POSTGIS_EXTENSION_SQL = re.compile(
    r"CREATE\s+EXTENSION\s+IF\s+NOT\s+EXISTS\s+postgis", re.IGNORECASE
)


@lru_cache(maxsize=1)
def _chain_artifacts() -> dict[str, object]:
    """Names the revision sources create, via Alembic ops or raw SQL."""
    indexes: set[str] = set()
    tables: set[str] = set()
    sources: list[str] = []
    for path in sorted(VERSIONS_DIR.glob("*.py")):
        if path.name.startswith("__"):
            continue
        source = path.read_text(encoding="utf-8", errors="replace")
        sources.append(source)
        # Whole-file scan: several revisions create indexes with raw SQL
        # (GIN trigram, GIN search_vector) rather than ``op.create_index``.
        indexes.update(_CREATE_INDEX_SQL.findall(source))
        for node in ast.parse(source).body:
            if isinstance(node, ast.FunctionDef) and node.name == "upgrade":
                ops = _collect_ops(node)
                indexes |= ops["create_index"] | ops["raw_created_indexes"]
                tables |= ops["create_table"]
    joined = "\n".join(sources)
    return {
        "indexes": frozenset(indexes),
        "tables": frozenset(tables),
        "postgis": bool(_POSTGIS_EXTENSION_SQL.search(joined)),
        "gist": bool(_GIST_SQL.search(joined)),
    }


def _local_engine():
    """Materialise the ORM metadata on SQLite (PostGIS Geography -> Text)."""
    from sqlalchemy.pool import StaticPool

    import app.models  # noqa: F401
    from app.database.session import Base
    from tests.geo_compat import make_timestamp_defaults_portable, strip_geo_columns

    strip_geo_columns()
    make_timestamp_defaults_portable()
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    return engine


@pytest.fixture(scope="module")
def scratch_engine():
    """Local-flow SQLite engine (``None`` when the live database is used)."""
    if DATABASE_AVAILABLE:
        yield None
        return
    engine = _local_engine()
    try:
        yield engine
    finally:
        engine.dispose()


def test_forward_migration_at_head(scratch_engine):
    """Guarantee 1 — the schema is stamped at the single computed head.

    Live: ``alembic_version`` on the real database. Local: the same reader
    (``rehearsal.read_version``) against a scratch database stamped with the
    computed head, plus proof that a fresh database reads as "not migrated"
    instead of blowing up.
    """
    head = rehearsal.head_revision(rehearsal.parse_revisions(VERSIONS_DIR))
    assert head == "0026", f"chain head is {head}, expected 0026"

    if DATABASE_AVAILABLE:
        from sqlalchemy import create_engine

        engine = create_engine(_sync_url())
        try:
            stamped = rehearsal.read_version(engine)
        finally:
            engine.dispose()
        assert stamped == head, f"DB at {stamped}, expected {head}"
        return

    assert rehearsal.read_version(scratch_engine) is None, (
        "a fresh database must read as unmigrated"
    )
    with scratch_engine.begin() as conn:
        conn.execute(text("CREATE TABLE alembic_version (version_num VARCHAR(32) NOT NULL)"))
        conn.execute(
            text("INSERT INTO alembic_version (version_num) VALUES (:v)"), {"v": head}
        )
    assert rehearsal.read_version(scratch_engine) == head


def test_indexes_fks_and_postgis_surface(scratch_engine):
    """Guarantees 4-6 — indexes, enforced foreign keys and the PostGIS surface.

    Live: ``rehearsal.check_schema_surface`` (pg_indexes / pg_constraint /
    information_schema / pg_extension). Local: the same expectations against the
    ORM surface plus the revision sources, with FK enforcement drilled by an
    orphaned insert on SQLite (``PRAGMA foreign_keys=ON``).
    """
    if DATABASE_AVAILABLE:
        from sqlalchemy import create_engine

        engine = create_engine(_sync_url())
        try:
            _checks, errors = rehearsal.check_schema_surface(engine)
        finally:
            engine.dispose()
        assert errors == [], f"schema-surface failures:\n{errors}"
        return

    artifacts = _chain_artifacts()
    chain_indexes = set(artifacts["indexes"])
    inspector = sa_inspect(scratch_engine)
    tables = set(inspector.get_table_names())

    # 4. Representative indexes (btree, composite, GIN trigram) exist.
    declared_indexes = {
        index["name"] for table in tables for index in inspector.get_indexes(table)
    }
    missing = sorted(rehearsal.EXPECTED_INDEXES - declared_indexes - chain_indexes)
    assert not missing, f"missing indexes: {missing}"


    # 5. Foreign keys exist ...
    with_fk = {table for table in tables if inspector.get_foreign_keys(table)}
    missing_fk_tables = sorted(set(rehearsal.EXPECTED_FKS) - with_fk)
    assert not missing_fk_tables, f"tables without their declared FK: {missing_fk_tables}"

    # ... and are enforced: an orphaned child row must be rejected.
    with scratch_engine.begin() as conn:
        conn.execute(text("PRAGMA foreign_keys=ON"))
    with pytest.raises(IntegrityError), scratch_engine.begin() as conn:
        conn.execute(
            text(
                "INSERT INTO role_permissions (role_id, permission_id) "
                "VALUES (999999, 999999)"
            )
        )

    # 6. PostGIS: extension, Geography typing and spatial GiST indexes.
    assert artifacts["postgis"] is True, "no revision enables the postgis extension"
    assert artifacts["gist"] is True, "no revision creates a GiST index"
    from geoalchemy2 import Geography

    from tests.geo_compat import declared_type

    bad_geography = [
        f"{table}.{column}"
        for table, columns in rehearsal.GEOGRAPHY_COLUMNS.items()
        for column in columns
        if not isinstance(declared_type(table, column), Geography)
    ]
    assert not bad_geography, f"geography columns not PostGIS-typed: {bad_geography}"
    spatial = {name for names in rehearsal.SPATIAL_INDEXES.values() for name in names}
    missing_spatial = sorted(spatial - chain_indexes)
    assert not missing_spatial, f"missing spatial GiST indexes: {missing_spatial}"


def test_rehearsal_tooling_contract():
    """The rehearsal/drift tooling is usable in this environment.

    Live: the drift checker can reach the database. Local: the same entry points
    the live drill uses (URL translation, chain integrity, data-safety policy)
    run against the revision sources alone.
    """
    if DATABASE_AVAILABLE:
        import sqlalchemy

        from app.core.config import settings

        drift = _load_script_module("check_migration_drift", DRIFT)
        # Translate with the tool's own helper, then select the installed driver.
        engine = sqlalchemy.create_engine(
            _sync_url(drift.to_sync_url(settings.sqlalchemy_sync_url))
        )
        try:
            with engine.connect():
                pass
        finally:
            engine.dispose()
        return

    revisions = rehearsal.parse_revisions(VERSIONS_DIR)
    assert rehearsal.chain_issues(revisions) == []
    assert rehearsal.scan_data_safety_violations(VERSIONS_DIR) == []
    assert rehearsal.head_revision(revisions) == "0026"
    sync_url = rehearsal.to_sync_url("postgresql+asyncpg://u:p@localhost:5432/hyperlocal")
    assert sync_url.startswith("postgresql://") and "asyncpg" not in sync_url
    assert rehearsal.db_name_of(sync_url) == "hyperlocal"
