#!/usr/bin/env python3
"""Stop scratch tool output from re-entering the repository.

THE PROBLEM THIS SOLVES, SPECIFICALLY
-------------------------------------
This repository had 27 committed files that were pure tool output:
``pytest_*.txt``, ``*_out.txt``, ``*_err.txt``, ``backend_log.txt`` and a
handful of token files. Every one was added by accident, and every one then
lived in the repository forever -- showing up in diffs, in review, and in
``git log`` of the file they were next to.

``.gitignore`` prevents the *next* accidental add. It does not stop
``git add -f``, and it does not know about a file renamed to something the
rules miss. This hook closes that gap, and it is the structural answer to
"why does this keep happening".

Exits non-zero to block the commit. Nothing is deleted: the file stays on disk.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# Matched against the file NAME, anchored, so `foo.pytest_log_helper.txt` does
# not trip it.
PATTERNS = (
    r"^pytest_.*\.(txt|log)$",
    r"^scoped_pytest\.log$",
    r"^backend_log\.txt$",
    r"^alembic_bg\.txt$",
    r"^analyze.*\.txt$",
    r"^ruff_fmt.*\.txt$",
    r".*_(out|err)\.(txt|log)$",
    # Credentials: named the way a shell one-liner writes them.
    r"^admin_token\.txt$",
    r"^_new_secret\.txt$",
    r"^_access\.txt$",
    r"^_refresh\.txt$",
)

COMPILED = [re.compile(p) for p in PATTERNS]


def is_scratch(name: str) -> str | None:
    for pattern in COMPILED:
        if pattern.match(name):
            return pattern.pattern
    return None


def main(argv: list[str]) -> int:
    offenders: list[tuple[str, str]] = []

    for arg in argv[1:]:
        path = Path(arg)
        pattern = is_scratch(path.name)
        if pattern:
            offenders.append((arg, pattern))

    if not offenders:
        return 0

    print("BLOCKED: tool output does not belong in the repository.\n", file=sys.stderr)
    for name, pattern in offenders:
        print(f"  {name}  matches /{pattern}/", file=sys.stderr)
    print(
        "\nThese are pytest / analyzer / build logs. They are regenerated in\n"
        "seconds and they change on every local run, so committing one adds\n"
        "noise to every future diff for that area.\n\n"
        "Write the output outside the repo instead:\n"
        "    python -m pytest -q > \"$TEMP/pytest_run.txt\"   # or any path outside\n\n"
        "Your file has NOT been deleted or unstaged -- it is still on disk and\n"
        "still staged. Unstage it if you did not mean to commit it:\n"
        "    git restore --staged <file>",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
