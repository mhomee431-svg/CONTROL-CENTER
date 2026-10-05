#!/usr/bin/env python3
"""Block a commit containing an unresolved merge-conflict marker.

WHY THIS IS WORTH A HOOK
------------------------
A stray ``<<<<<<<`` is the most confusing thing you can ship. Python often
still *parses* around conflict markers -- the marker sits inside a comment or
between two valid statements -- so the file imports cleanly and the failure
surfaces much later, somewhere unrelated, as a syntax error in a file you have
not touched in a month.

It is also the failure mode of the normal workflow: resolve most of a conflict,
commit, and discover the last hunk was missed. This hook makes that impossible
to do silently.

Exits non-zero to block the commit.
"""

from __future__ import annotations

import sys
from pathlib import Path

# `<<<<<<<` / `>>>>>>>` must be at the start of a line to be a real marker. A
# mention of the word inside prose (this very file, documentation about
# resolving conflicts) is not a conflict, and matching it would make this hook
# block commits that merely discuss the problem.
CONFLICT_STARTS = ("<<<<<<< ", ">>>>>>> ")

# A bare `=======` line is far too common to treat as a conflict on its own: it
# is a valid Markdown setext heading underline and a valid separator in text
# files. It is only reported when the SAME file also has a `<<<<<<<`, which is
# what the two-pass check below does.
SEPARATOR = "======="


def scan(path: Path) -> list[int]:
    """Return 1-based line numbers of conflict markers in `path`."""
    try:
        raw = path.read_bytes()
    except OSError:
        return []
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        # Binary: cannot contain a text conflict marker.
        return []

    hits: list[int] = []
    for number, line in enumerate(text.splitlines(), start=1):
        stripped = line.lstrip()
        if stripped.startswith(CONFLICT_STARTS):
            hits.append(number)
        elif stripped == SEPARATOR and any(
            l.lstrip().startswith("<<<<<<< ") for l in text.splitlines()
        ):
            hits.append(number)
    return hits


def main(argv: list[str]) -> int:
    blocked: list[tuple[str, list[int]]] = []

    for arg in argv[1:]:
        path = Path(arg)
        if not path.is_file():
            continue
        # .git/MERGE_MSG and friends live under .git and are never passed here,
        # but guard anyway: this hook must never read its own metadata.
        if ".git" in path.parts:
            continue
        lines = scan(path)
        if lines:
            blocked.append((arg, lines))

    if not blocked:
        return 0

    print("BLOCKED: unresolved merge-conflict markers.\n", file=sys.stderr)
    for name, lines in blocked:
        preview = ", ".join(str(n) for n in lines[:8])
        more = "" if len(lines) <= 8 else f" (+{len(lines) - 8} more)"
        print(f"  {name}: lines {preview}{more}", file=sys.stderr)
    print(
        "\nResolve the conflict and `git add` the file, or run:\n"
        "    git status        # UU entries are the unresolved ones\n"
        "    git diff --check  # also reports leftover whitespace errors",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
