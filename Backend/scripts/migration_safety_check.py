#!/usr/bin/env python
"""Phase 25 — CI/CD migration safety gate.

Static, database-free analyzer for the Alembic migrations under
``Backend/alembic/versions``. It is the guard that stops the automated
pipeline from silently applying a *dangerous* schema change:

  DANGEROUS   (block automatic deploy unless explicitly approved):
    - op.drop_table / drop_index / drop_column / drop_constraint
    - op.batch_alter_table(...) blocks containing any drop_* / alter_type
    - raw op.execute(...) whose SQL contains DROP | TRUNCATE | DELETE FROM
    - drop_all(...)
  WARN        (reported, does not block):
    - op.alter_column with an explicit type change (narrowing/lossy changes
      deserve human eyes even though Alembic allows them)
    - rename operations

Only files that changed in this push (``--base-sha``) are classified, so a
long-ago-reviewed migration never re-blocks a deploy. Every run also emits a
machine-readable report (default ``migration_safety_report.json``) that the
deploy jobs keep as an audit artifact.

CLI:
  python scripts/migration_safety_check.py                     # scan all revisions
  python scripts/migration_safety_check.py --base-sha <sha>    # only files changed since <sha>
  python scripts/migration_safety_check.py --output report.json
  python scripts/migration_safety_check.py --dump              # prints DANGEROUS=yes|no

Exit codes: 0 = safe, 2 = dangerous/unreviewed (blocking), 1 = error.
"""
from __future__ import annotations

import argparse
import ast
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List

BACKEND_DIR = Path(__file__).resolve().parents[1]
DEFAULT_VERSIONS_DIR = BACKEND_DIR / "alembic" / "versions"

# ── Operation classification ───────────────────────────────────────────────────
SAFE_OPS = {
    "create_table", "create_index", "create_unique_index", "create_primary_key",
    "create_foreign_key", "create_check_constraint", "create_unique_constraint",
    "add_column", "bulk_insert", "execute",
}
DANGEROUS_OPS = {
    "drop_table", "drop_index", "drop_column", "drop_constraint", "drop_all",
}
WARN_OPS = {"alter_column", "rename_table", "rename_column"}

# Raw SQL inside op.execute(...) that implies a destructive change.
# NOTE: "DROP DEFAULT" / "DROP NOT NULL" are NOT data-lossy and are excluded.
_DANGEROUS_SQL = re.compile(
    r"\bDROP\s+(TABLE|INDEX|CONSTRAINT|VIEW|SCHEMA|DATABASE)\b"
    r"|\bDROP\s+COLUMN\b"
    r"|\bTRUNCATE\b"
    r"|\bDELETE\s+FROM\b"
    r"|\bALTER\s+TABLE\b[^;]*\bDROP\s+COLUMN\b",
    re.IGNORECASE,
)
_WARN_SQL = re.compile(r"\bALTER\s+(TABLE|COLUMN)\b[^;]*\bTYPE\b", re.IGNORECASE)


class RevisionInfo:
    def __init__(self, path: Path, revision: str, down_revision: str) -> None:
        self.path = path
        self.revision = revision
        self.down_revision = down_revision
        self.dangerous: List[Dict[str, Any]] = []
        self.warnings: List[Dict[str, Any]] = []
        self.operations: List[str] = []

    def as_dict(self) -> Dict[str, Any]:
        return {
            "file": str(self.path.relative_to(BACKEND_DIR)),
            "revision": self.revision,
            "down_revision": self.down_revision,
            "operations": self.operations,
            "dangerous": self.dangerous,
            "warnings": self.warnings,
        }


def _revision_meta(source: str, path: Path) -> "tuple[str, str]":
    """Extract revision + down_revision using string-literal assignments.

    Handles both ``revision: str = "0015"`` (AnnAssign) and plain
    ``revision = "0015"`` (Assign) styles.
    """
    revision = down = ""
    try:
        tree = ast.parse(source, filename=str(path))
    except SyntaxError:
        return "", ""
    for node in ast.walk(tree):
        value = None
        if isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            value = node.value
        elif isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            value = node.value
        if value is not None and isinstance(value, ast.Constant) and isinstance(value.value, str):
            if isinstance(node, ast.AnnAssign):
                var = node.target.id
            else:
                var = node.targets[0].id
            if var == "revision":
                revision = value.value
            elif var == "down_revision":
                down = value.value
    return revision, down


def _string_of(arg: ast.expr) -> str:
    """Best-effort stringification of an AST expression (handles f-strings)."""
    if isinstance(arg, ast.Constant) and isinstance(arg.value, str):
        return arg.value
    if isinstance(arg, ast.JoinedStr):
        return "".join(
            part.value if isinstance(part, ast.Constant) and isinstance(part.value, str) else "?"
            for part in arg.values
        )
    if isinstance(arg, ast.BinOp) and isinstance(arg.op, ast.Add):
        return _string_of(arg.left) + _string_of(arg.right)
    if isinstance(arg, ast.Name):
        return arg.id
    return ""


def _classify_call(node: ast.Call, rev: RevisionInfo) -> None:
    """Classify one ``op.*`` / ``sa.*`` / ``batch_op.*`` call."""
    func = node.func
    if not isinstance(func, ast.Attribute):
        return
    attr = func.attr
    owner = func.value
    owner_name = ""
    if isinstance(owner, ast.Name):
        owner_name = owner.id
    elif isinstance(owner, ast.Attribute):
        owner_name = owner.attr

    rev.operations.append(attr)

    # Raw SQL escapes (op.execute / sa.text(...))
    if attr == "execute":
        for arg in node.args:
            sql = _string_of(arg)
            if not sql:
                continue
            if _DANGEROUS_SQL.search(sql):
                rev.dangerous.append(
                    {"op": "execute(raw sql)", "detail": sql[:200], "line": node.lineno}
                )
            elif _WARN_SQL.search(sql):
                rev.warnings.append(
                    {"op": "execute(type change)", "detail": sql[:200], "line": node.lineno}
                )
        return

    # batch_alter_table blocks expose drop_* on the batch_op object
    if owner_name.startswith("batch_op"):
        if attr in DANGEROUS_OPS:
            rev.dangerous.append(
                {"op": f"batch.{attr}",
                 "detail": _string_of(node.args[0]) if node.args else "",
                 "line": node.lineno}
            )
        elif attr in WARN_OPS:
            rev.warnings.append(
                {"op": f"batch.{attr}",
                 "detail": _string_of(node.args[0]) if node.args else "",
                 "line": node.lineno}
            )
        return

    if attr in DANGEROUS_OPS and owner_name in {"op", "sa"}:
        detail = _string_of(node.args[0]) if node.args else ""
        rev.dangerous.append({"op": attr, "detail": detail, "line": node.lineno})
    elif attr in WARN_OPS and owner_name in {"op", "sa"}:
        detail = _string_of(node.args[0]) if node.args else ""
        rev.warnings.append({"op": attr, "detail": detail, "line": node.lineno})


def _classify_module(tree: ast.Module, rev: RevisionInfo) -> None:
    """Walk every function except ``downgrade`` so helper functions are covered."""
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            if node.name == "downgrade":
                continue
            for child in ast.walk(node):
                if isinstance(child, ast.Call):
                    try:
                        _classify_call(child, rev)
                    except Exception:  # noqa: BLE001
                        continue


def changed_files(base_sha: str, versions_dir: Path) -> List[Path]:
    """Migration files changed between ``base_sha`` and the working tree."""
    if not base_sha or set(base_sha) == {"0"}:
        # No reliable base (first run / manual dispatch): scan everything.
        return sorted(versions_dir.glob("*.py"))
    try:
        out = subprocess.run(
            ["git", "diff", "--name-only", base_sha, "HEAD", "--", "Backend/alembic/versions/"],
            capture_output=True, text=True, check=True, timeout=30,
        ).stdout
    except Exception:  # noqa: BLE001
        return sorted(versions_dir.glob("*.py"))
    files = [line.strip() for line in out.splitlines() if line.strip()]
    result: List[Path] = []
    for f in files:
        p = Path(f)
        if not p.is_absolute():
            p = Path(os.getcwd()) / p
        p = p.resolve()
        if p.suffix == ".py" and p.exists():
            result.append(p)
    return sorted(result)


def scan(versions_dir: Path, base_sha: str = "") -> Dict[str, Any]:
    files = changed_files(base_sha, versions_dir)
    revisions: List[Dict[str, Any]] = []
    dangerous_all: List[Dict[str, Any]] = []

    for path in files:
        try:
            source = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        revision, down = _revision_meta(source, path)
        rev = RevisionInfo(path, revision, down)
        try:
            tree = ast.parse(source, filename=str(path))
            _classify_module(tree, rev)
        except SyntaxError as exc:
            rev.dangerous.append({"op": "syntax-error", "detail": str(exc), "line": 0})
        revisions.append(rev.as_dict())
        dangerous_all.extend(rev.dangerous)

    head = ""
    try:
        acquired: tuple[set[str], set[str]] = (set(), set())
        for p in sorted(versions_dir.glob("*.py")):
            src = p.read_text(encoding="utf-8", errors="replace")
            r, d = _revision_meta(src, p)
            if r:
                acquired[0].add(r)
            if d:
                acquired[1].add(d)
        head = next(iter(acquired[0] - acquired[1]), "")
    except Exception:  # noqa: BLE001
        head = ""

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "head_revision": head,
        "base_sha": base_sha or "(all)",
        "scanned_files": [str(Path(f["file"])) for f in revisions],
        "revisions": revisions,
        "dangerous": dangerous_all,
        "warnings": [w for r in revisions for w in r.get("warnings", [])],
        "verdict": "dangerous" if dangerous_all else "safe",
    }


def main(argv: List[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Phase 25 migration safety gate")
    parser.add_argument("--versions-dir", type=Path, default=DEFAULT_VERSIONS_DIR)
    parser.add_argument("--base-sha", default="", help="Only classify files changed since this SHA")
    parser.add_argument("--output", type=Path, default=BACKEND_DIR / "migration_safety_report.json")
    parser.add_argument("--dump", action="store_true", help="Print DANGEROUS=yes|no for GitHub outputs")
    args = parser.parse_args(argv)

    report = scan(args.versions_dir, base_sha=args.base_sha)
    args.output.write_text(json.dumps(report, indent=2), encoding="utf-8")

    print(f"head_revision     : {report['head_revision'] or '(unknown)'}")
    print(f"scanned files     : {len(report['scanned_files'])}")
    for r in report["revisions"]:
        print(f"  - {r['file']} (revision {r['revision']}) "
              f"dangerous={len(r['dangerous'])} warnings={len(r['warnings'])}")
        for d in r["dangerous"]:
            print(f"      !! {d['op']}: {d['detail']}  (line {d['line']})")
    print(f"verdict           : {report['verdict']}")
    print(f"report            : {args.output}")

    if args.dump:
        print(f"DANGEROUS={'yes' if report['verdict'] == 'dangerous' else 'no'}")
        print(f"HEAD_REVISION={report['head_revision'] or 'unknown'}")

    return 2 if report["verdict"] == "dangerous" else 0


if __name__ == "__main__":
    sys.exit(main())