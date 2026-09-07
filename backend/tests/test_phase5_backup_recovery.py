"""Phase 5 — Database Backup & Recovery (DB-free structural checks).

These tests validate the parts of the Phase 5 deliverable that are statically
verifiable without a live database (the live recovery drill runs in CI against
a real PostGIS service and locally via scripts/recovery_test.py):

- Every migration ships a downgrade() so Alembic rollback is possible.
- The migration chain is linear with a single HEAD (rollback target is unique).
- scripts/recovery_test.py performs all the required recovery checks
  (pg_dump, pg_restore into a scratch DB, revision/table/row/schema-surface
  comparison, cleanup) and compiles.
- The four operator scripts (backup, restore, cron-install, rollback) exist
  and are syntactically valid shell (checked when bash is available).
"""
import re
import shutil
import subprocess
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
ROOT_DIR = BACKEND_DIR.parent
VERSIONS = BACKEND_DIR / "alembic" / "versions"
RECOVERY = BACKEND_DIR / "scripts" / "recovery_test.py"
SCRIPTS = ROOT_DIR / "infra" / "scripts"


def _migration_files():
    return sorted(VERSIONS.glob("[0-9]*_*.py"))


def _source(path):
    return path.read_text(encoding="utf-8")


def _bash():
    return shutil.which("bash")


def test_every_migration_has_downgrade():
    for f in _migration_files():
        assert "def downgrade" in _source(f), f"{f.name} is missing downgrade()"


def test_recovery_chain_linear_single_head():
    revisions = {}
    for f in _migration_files():
        src = _source(f)
        m = re.search(r"^revision:.*?= ['\"]([^'\"]+)['\"]", src, re.M)
        d = re.search(r"^down_revision:.*?=\s*(['\"]([^'\"]+)['\"]|None)", src, re.M)
        assert m, f"No revision id in {f.name}"
        rev = m.group(1)
        down = None if d is None or d.group(1) == "None" else d.group(2)
        revisions[rev] = down
    roots = [r for r, d in revisions.items() if d is None]
    assert len(roots) == 1, f"expected 1 root (0001), got {roots}"
    next_of = {down: rev for rev, down in revisions.items() if down is not None}
    current = roots[0]
    seen = set()
    while current in revisions and current not in seen:
        seen.add(current)
        nxt = next_of.get(current)
        if nxt is None:
            break
        current = nxt
    assert len(seen) == len(revisions), "migration chain is not linear (branch/merge)"


def test_recovery_test_does_dump_restore_verify_and_cleanup():
    src = _source(RECOVERY)
    for needle in ("pg_dump", "-Fc", "pg_restore", "CREATE DATABASE", "DROP DATABASE",
                   "alembic revision match", "table set match", "row counts match",
                   "schema surface match", "no-cleanup", "report-file"):
        assert needle in src, f"recovery_test.py missing: {needle}"


def test_recovery_test_compiles():
    import py_compile
    py_compile.compile(str(RECOVERY), doraise=True)


def test_operator_scripts_present():
    for name in ("backup_db.sh", "restore_db.sh", "install_backup_cron.sh",
                 "rds_migrate_rollback.sh"):
        assert (SCRIPTS / name).is_file(), f"missing infrastructure/scripts/{name}"


def test_operator_scripts_bash_syntax():
    """Run bash -n on each operator script (best-effort; skipped if bash is
    unavailable or the platform can't run it cleanly, e.g. Git bash on Windows
    expecting a console)."""
    b = _bash()
    if not b:
        import pytest
        pytest.skip("bash not available on this host")
    import os
    if os.name == "nt":
        # Windows Git bash can block waiting on a console pager; the scripts are
        # validated here by structure instead (they are bash-syntax-checked in
        # CI on ubuntu-latest).
        import pytest
        pytest.skip("bash -n skipped on Windows (validated in CI on Linux)")
    for name in ("backup_db.sh", "restore_db.sh", "install_backup_cron.sh",
                 "rds_migrate_rollback.sh"):
        script = SCRIPTS / name
        res = subprocess.run([b, "-n", str(script)], capture_output=True, text=True,
                             timeout=30)
        assert res.returncode == 0, f"{name} has a bash syntax error:\n{res.stderr}"
