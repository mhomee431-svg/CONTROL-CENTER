#!/usr/bin/env python
"""Phase 26 — generate a versioned Alembic migration.

The first step of the migration workflow:
    developer changes model/schema
      -> THIS SCRIPT generates the revision file
      -> review (safety scan + rehearsal in CI)
      -> staging
      -> production

It wraps ``alembic revision --autogenerate`` with the project conventions:

  - next sequential revision id (0015 -> 0016), keeping the chain canonical
    (0001, 0002, 0003, ...) — never forks or hash ids;
  - a data-safety lint on the generated file: a new NOT NULL column on an
    existing table without ``server_default`` is flagged for a two-step
    migration (add-nullable/backfill/set-NOT-NULL);
  - a printed review checklist (safety scan, rehearsal, deploy path) so no
    manual production step is ever required.

Usage:
    python scripts/generate_migration.py -m "add shop loyalty_badge column"
    python scripts/generate_migration.py -m "create coupons table" --rev-id 0016
    python scripts/generate_migration.py -m "no-autogen change" --no-autogenerate

Notes:
    - ``--autogenerate`` (default) compares the ORM models against the LIVE
      database, so it must point at a database already migrated to head
      (``DATABASE_URL``).
    - Never edit tables directly in production: the generated file IS the
      change; it travels through CI (migration rehearsal + safety scan),
      staging, then production via the deploy pipeline.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))


def next_rev_id(versions_dir: Path) -> str:
    """Next sequential numeric revision id (0001..0015 -> 0016)."""
    nums: list[int] = []
    for path in versions_dir.glob("*.py"):
        if path.name.startswith("__"):
            continue
        m = re.match(r"^(\d{4})_", path.name)
        if m:
            nums.append(int(m.group(1)))
    return f"{max(nums) + 1 if nums else 1:04d}"


def run(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        cmd, cwd=str(cwd), capture_output=True, text=True, check=False,
        env={**os.environ},
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Phase 26 migration generator")
    parser.add_argument("-m", "--message", required=True,
                        help="short human-readable migration message")
    parser.add_argument("--rev-id", default="")
    parser.add_argument("--versions-dir", type=Path,
                        default=BACKEND_DIR / "alembic" / "versions")
    parser.add_argument("--no-autogenerate", action="store_true",
                        help="create an empty revision (no ORM/DB diff)")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    if not args.versions_dir.is_dir():
        print(f"!! versions dir not found: {args.versions_dir}", file=sys.stderr)
        return 1

    rev_id = args.rev_id or next_rev_id(args.versions_dir)
    print(f"==> next revision id: {rev_id}")

    # ── Preflight: alembic present + single head ──────────────────────────────
    alembic_ok = run([sys.executable, "-m", "alembic", "-h"], BACKEND_DIR)
    if alembic_ok.returncode != 0:
        print("!! alembic is not available in this environment", file=sys.stderr)
        return 1

    heads = run([sys.executable, "-m", "alembic", "heads"], BACKEND_DIR)
    head_lines = [ln.strip() for ln in heads.stdout.splitlines() if ln.strip()]
    head_candidates = [ln for ln in head_lines if "->" in ln or "(head)" in ln]
    if len(head_candidates) != 1:
        print("!! alembic heads is not a single head — resolve branches first:", file=sys.stderr)
        print(heads.stdout)
        return 1
    print(f"==> current head: {head_candidates[0]}")

    # ── Generate (dry-run preview requires nothing but the CLI) ───────────────
    cmd = [sys.executable, "-m", "alembic", "revision",
           "--rev-id", rev_id, "-m", args.message]
    if not args.no_autogenerate:
        cmd.append("--autogenerate")
    print(f"==> running: {' '.join(cmd)}")

    if args.dry_run:
        print("--dry-run: skipping actual generation (command above).")
        return 0

    if not args.no_autogenerate:
        url = os.environ.get("DATABASE_URL", "")
        if not url:
            print("!! DATABASE_URL must be set for --autogenerate (the ORM/DB diff "
                  "needs a database that is already at head).", file=sys.stderr)
            return 1

    proc = run(cmd, BACKEND_DIR)
    print(proc.stdout)
    if proc.returncode != 0:
        print(proc.stderr, file=sys.stderr)
        print("!! alembic revision failed — see output above.", file=sys.stderr)
        return proc.returncode

    # ── Post-generate: locate the new file + data-safety lint ─────────────────
    new_file = next((p for p in sorted(args.versions_dir.glob(f"{rev_id}_*.py"))), None)
    if new_file is None:
        print("!! generated file not found — inspect alembic/versions/", file=sys.stderr)
        return 1
    print(f"==> generated: {new_file.name}")

    from scripts.migration_rehearsal import scan_data_safety_violations  # local import

    violations = [v for v in scan_data_safety_violations(args.versions_dir)
                  if v["file"] == new_file.name]
    if violations:
        print("!! DATA-SAFETY: this migration adds NOT NULL column(s) to existing "
              "tables without server_default — every existing row would break:", file=sys.stderr)
        for v in violations:
            print(f"    line {v['line']}: {v['table']} — {v['detail']}")
        print("    Fix: add server_default=sa.text('...') or split into "
              "add-nullable -> backfill -> set-NOT-NULL.", file=sys.stderr)
        return 2
    print("OK data-safety lint: no silent NOT NULL column adds in the new file.")

    # ── Review checklist ──────────────────────────────────────────────────────
    print("""
NEXT STEPS (review -> test -> staging -> production):
  1. Review  alembic/versions/<new>.py and the autogenerate diff above.
  2. Scan    python scripts/migration_safety_check.py   (must not flag DANGEROUS)
  3. Rehearse DATABASE_URL=... python scripts/migration_rehearsal.py --full-chain-rollback
  4. Commit  the migration with the model change — CI runs the rehearsal again.
  5. Ship    it through the normal pipeline (staging -> production).
  NEVER     edit a production table by hand; the migration file is the change.
""")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())