#!/usr/bin/env python3
"""Block a commit that would add a private key to the repository.

WHY A DEDICATED HOOK INSTEAD OF .gitignore
------------------------------------------
``.gitignore`` stops a file being staged by accident. It does NOT stop
``git add -f``, and it does not stop a key that was renamed to something the
ignore rules do not cover -- which is exactly how a key ends up in history.
This hook is the last line before the commit object is created, so it fires
regardless of how the file was added.

A committed key is not a "delete it later" situation: it stays in history, it
is on the remote, and every clone has it. The recovery is to rotate the key.
See docs/security/SECRET_ROTATION.md.

Exits non-zero to block the commit.
"""

from __future__ import annotations

import sys
from pathlib import Path

# Files that are obviously fixtures or documentation, not credentials.
# Anything matching this must be added here deliberately with a reason -- this
# list is an allowlist of exceptions, and it should stay as short as possible.
ALLOWLIST = {
    # Trust-store and certificate-authority bundles are public by definition.
    "trust-policy.json",
}


def _looks_like_a_key(path: Path) -> str | None:
    """Return the PEM marker if this file contains private key material.

    Content is the signal, not the file extension. A key called `.txt`, or a
    `.json` with the key pasted into it, is still a key; checking the suffix
    would miss both.
    """
    try:
        # Bytes, not text: key material is not necessarily valid UTF-8, and
        # decoding it as text is how this check silently passes on a binary key.
        raw = path.read_bytes()
    except OSError:
        return None

    # Only PRIVATE key headers. The public counterparts ("BEGIN PUBLIC KEY",
    # "BEGIN CERTIFICATE") are deliberately absent: a public key or a
    # certificate is not a secret, and the repo legitimately ships some.
    markers = (
        b"BEGIN RSA PRIVATE KEY",
        b"BEGIN EC PRIVATE KEY",
        b"BEGIN DSA PRIVATE KEY",
        b"BEGIN OPENSSH PRIVATE KEY",
        b"BEGIN ENCRYPTED PRIVATE KEY",
        b"BEGIN PRIVATE KEY",
    )
    for marker in markers:
        if marker in raw:
            return marker.decode("ascii")
    return None


def main(argv: list[str]) -> int:
    offenders: list[tuple[str, str]] = []

    for arg in argv[1:]:
        path = Path(arg)
        if path.name in ALLOWLIST or not path.is_file():
            continue
        marker = _looks_like_a_key(path)
        if marker:
            offenders.append((arg, marker))

    if not offenders:
        return 0

    print("BLOCKED: private key material in a staged file.\n", file=sys.stderr)
    for name, marker in offenders:
        print(f"  {name}  contains '{marker}'", file=sys.stderr)
    print(
        "\nA committed key cannot be un-committed. Rotate it, then commit the\n"
        "replacement through your secret store -- never through this repo.\n"
        "See docs/security/SECRET_ROTATION.md for the full procedure.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
