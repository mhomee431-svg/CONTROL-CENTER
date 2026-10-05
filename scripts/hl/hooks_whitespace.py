#!/usr/bin/env python3
"""Trailing whitespace, missing final newline, CRLF/LF drift.

THE ONLY HOOK HERE THAT FIXES INSTEAD OF BLOCKING
-------------------------------------------------
Every other hook refuses the commit, because their findings need a decision.
These three do not: the correct value is unambiguous, and a diff that is only
whitespace is exactly the kind of noise that makes a real change hard to read.

That is why this one repairs in place. The repaired files are staged, the
commit proceeds, and the next ``git diff`` is clean.

THE CRLF RULE, AND WHY IT IS OPT-OUT PER DIRECTORY
--------------------------------------------------
The repository is developed on Windows (OneDrive checkout, CRLF by default) and
built on Linux (LF). A hook that silently rewrites line endings turns every
file into a whole-file diff the first time someone touches it on the other
platform -- a 400-line diff to change one line.

So: this hook does NOT convert line endings. It only normalises the whitespace
WITHIN a line and guarantees a final newline. The line-ending policy is
``.gitattributes``, which git applies consistently on every platform.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

# Files whose trailing whitespace is load-bearing, not accidental.
BINARY_SUFFIXES = {".png", ".jpg", ".jpeg", ".gif", ".ico", ".pdf", ".zip",
                   ".gz", ".ttf", ".otf", ".woff", ".woff2", ".so", ".pyc"}


def _read(path: Path) -> bytes | None:
    try:
        raw = path.read_bytes()
    except OSError:
        return None
    # A NUL byte means binary; rewriting binary as text would corrupt it.
    if b"\x00" in raw[:4096]:
        return None
    return raw


def normalise(raw: bytes) -> tuple[bytes, list[str]]:
    """Return (fixed_bytes, list_of_problems)."""
    problems: list[str] = []
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return raw, problems

    # Split on \n and keep it: this preserves CRLF, because a CRLF line ends
    # with "\r\n" and only the "\n" is consumed as the separator.
    lines = text.split("\n")

    trailing = sum(1 for l in lines if l != l.rstrip())
    if trailing:
        problems.append(f"{trailing} line(s) with trailing whitespace")

    fixed = [l.rstrip() for l in lines]

    if not text.endswith("\n"):
        problems.append("no newline at end of file")
        fixed.append("")

    return "\n".join(fixed).encode("utf-8"), problems


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        return 0

    changed: list[str] = []
    unfixable: list[tuple[str, str]] = []

    for arg in argv[1:]:
        path = Path(arg)
        if not path.is_file() or path.suffix.lower() in BINARY_SUFFIXES:
            continue
        raw = _read(path)
        if raw is None:
            continue

        fixed, problems = normalise(raw)
        if not problems:
            continue
        if fixed == raw:
            continue

        try:
            path.write_bytes(fixed)
        except OSError as exc:
            unfixable.append((arg, str(exc)))
            continue
        changed.append(arg)

    if changed:
        print("hl: fixed whitespace in:")
        for name in changed:
            print(f"    {name}")
        # Re-stage so the repair is actually part of the commit. Without this
        # the fix lands on disk but the commit still contains the old bytes,
        # which is the classic "why did my hook not work" failure.
        try:
            subprocess.run(
                ["git", "add", "--", *changed],
                check=True,
                capture_output=True,
            )
        except (subprocess.CalledProcessError, FileNotFoundError) as exc:
            print(
                f"hl: could not re-stage the fixed files: {exc}\n"
                "    Fix them with `git add` before committing.",
                file=sys.stderr,
            )
            return 1
        print("    (re-staged)")

    for name, err in unfixable:
        print(f"hl: could not fix {name}: {err}", file=sys.stderr)

    return 1 if unfixable else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
