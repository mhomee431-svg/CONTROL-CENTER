#!/usr/bin/env python3
"""scripts/ci/collect_client_endpoints.py -- endpoints the shipped apps call.

Used by the release-ordering guard. The Dart clients centralise every backend
URL in `ApiEndpoints`, so the client-side contract is read from exactly the
place the code uses it rather than from a hand-maintained list that would
drift. Paths are normalised to the form the OpenAPI document uses
(`/a/{id}`) so the two can be compared directly.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

# A single Dart string literal, e.g. '/api/v1/shopkeeper/shops' or
# 'api/v1/x/$id'. Anchored on the opening quote and stopped at the closing one,
# so surrounding prose (``"values must carry the /api/v1 prefix"``) and
# trailing punctuation can never be mistaken for a path.
_PATH_RE = re.compile(r"['\"](/?api/v1[^'\"\s]*)['\"]")
_PARAM_RE = re.compile(r"\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*")
_TRAILING_JUNK = re.compile(r"[^A-Za-z0-9_/{}.\-]+$")


def normalise(raw: str) -> str:
    """`/api/v1/x/{$id}?a=b` -> `/api/v1/x/{}` (the OpenAPI convention)."""
    path = _PARAM_RE.sub("{}", raw)
    path = path.split("?")[0]
    path = _TRAILING_JUNK.sub("", path)
    # A bare version root is a base URL, not an endpoint.
    if path.rstrip("/") in ("/api/v1", "/api", ""):
        return ""
    return path.rstrip("/") or "/"


def endpoint_files() -> list[Path]:
    """Every client's ApiEndpoints file that git tracks."""
    out = subprocess.run(
        ["git", "ls-files", "apps/*/lib/core/network/api_endpoints.dart"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=True,
    ).stdout.split()
    return [REPO_ROOT / f for f in out]


# A template literal that concatenates a base constant, e.g. '$posJob/$jobId'.
# The collected literals alone would miss every derived path, which in turn
# would make the base constant look like a real endpoint (see the prefix rule
# below).
_LEAD_VAR_RE = re.compile(r"\$([A-Za-z_][A-Za-z0-9_]*)(.*)$", re.DOTALL)
_ANY_VAR_RE = re.compile(r"\$[A-Za-z_][A-Za-z0-9_]*")


def _materialise_templates(text: str, bases: dict[str, str]) -> set[str]:
    """Resolve `'$base/$id/...'` into concrete `/api/v1/...` paths.

    The first `$name` selects the base constant; every later `$var` becomes a
    path parameter, because that is exactly how `ApiEndpoints` builds its
    helpers (`'$posJob/$jobId/retry'`).
    """
    derived: set[str] = set()
    for match in re.finditer(r"['\"]([^'\"]*)['\"]", text):
        literal = match.group(1)
        if "$" not in literal:
            continue
        lead = _LEAD_VAR_RE.match(literal)
        if not lead:
            continue
        base = bases.get(lead.group(1))
        if not base:
            continue
        tail = _ANY_VAR_RE.sub("{}", lead.group(2))
        derived.add(normalise(f"{base}{tail}"))
    return {p for p in derived if p.startswith("/api/v1")}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", help="write the sorted paths here instead of stdout")
    args = ap.parse_args()

    files = endpoint_files()
    if not files:
        print(
            "::warning::No client ApiEndpoints files found -- has the layout changed?",
            file=sys.stderr,
        )

    paths: set[str] = set()
    for path in files:
        text = path.read_text(encoding="utf-8")
        # Map `static const String name = '/api/v1/...'` so templates can be
        # resolved against it. The quote group is non-capturing so the loop
        # below unpacks exactly (name, path).
        bases: dict[str, str] = {}
        for name, raw in re.findall(
            r"static const String (\w+)\s*=\s*['\"](/api/v1[^'\"]*)['\"]", text
        ):
            cleaned = normalise(raw)
            if cleaned:
                bases[name] = cleaned
                paths.add(cleaned)
        for match in _PATH_RE.findall(text):
            cleaned = normalise(match)
            if cleaned.startswith("/api/v1"):
                paths.add(cleaned)
        paths |= _materialise_templates(text, bases)

    # Drop base paths that are only ever used for string concatenation.
    #
    # `ApiEndpoints` declares things like
    #     static const String posJob = '/api/v1/shopkeeper/pos/jobs';
    #     static String posJobDetail(int id) => '$posJob/$id';
    # and the base constant is never requested on its own. Reporting it as an
    # "endpoint the app calls" would make the release-ordering guard fail a
    # perfectly good release, so a path is kept only when no longer, more
    # specific path is built from it.
    concrete = {
        p for p in paths if not any(q != p and q.startswith(f"{p}/") for q in paths)
    }
    dropped = sorted(paths - concrete)
    if dropped:
        print(
            f"Note: {len(dropped)} base path(s) used only for concatenation were "
            f"excluded: {', '.join(dropped)}",
            file=sys.stderr,
        )

    paths = concrete

    payload = "\n".join(sorted(paths)) + ("\n" if paths else "")
    if args.out:
        Path(args.out).write_text(payload, encoding="utf-8")
        print(f"Collected {len(paths)} client endpoint path(s) from {len(files)} file(s).")
    else:
        sys.stdout.write(payload)
    return 0


if __name__ == "__main__":
    sys.exit(main())
