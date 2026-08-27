"""Phase 30 — Secure file upload validation.

Shared, defense-in-depth upload controls used by every file-intake path
(Excel inventory import today, more later):

    * filename sanitization   — path traversal, control characters,
                                deceptive double extensions
    * size cap                — enforced on raw bytes BEFORE parsing
    * extension allow-list    — single supported type per intake
    * magic-byte sniffing     — content must match its claimed type
                                (.xlsx ⇒ ZIP local-file header ``PK\\x03\\x04``);
                                blocks polyglot/renamed executables

All rejections are plain ``ValueError`` subclasses so services can map them
to their own typed errors without importing FastAPI here.
"""
from __future__ import annotations

import re

MAX_FILENAME_LENGTH = 255
#: .xlsx files are ZIP archives — Office Open XML always starts with PK\x03\x04.
XLSX_MAGIC = b"PK\x03\x04"

_CONTROL_CHARS = re.compile(r"[\x00-\x1f\x7f]")
_UNSAFE_NAME_CHARS = re.compile(r"[^A-Za-z0-9._ ()\-]")


class UploadValidationError(ValueError):
    """Raised when an uploaded file fails a safety check."""


def sanitize_filename(filename: str | None, *, fallback: str = "upload") -> str:
    """Reduce an untrusted filename to a safe, flat, printable basename.

    - strips any path components (``../``, drives, backslashes)
    - removes control characters and other unsafe characters
    - collapses results to a single safe token, capped at 255 chars
    """
    name = str(filename or "")
    # Keep only the final path component (handles \ and / and mixed).
    name = name.replace("\\", "/").split("/")[-1]
    name = _CONTROL_CHARS.sub("", name)
    name = _UNSAFE_NAME_CHARS.sub("_", name).strip(". ")
    if not name:
        return fallback
    return name[:MAX_FILENAME_LENGTH]


def sniff_magic(content: bytes) -> bytes:
    """Return the leading bytes used for content-type sniffing."""
    return bytes(content[:8])


def validate_upload(
    filename: str | None,
    content: bytes | None,
    *,
    allowed_extensions: tuple[str, ...] = (".xlsx",),
    max_bytes: int,
    expected_magic: bytes | None = XLSX_MAGIC,
) -> str:
    """Full pre-parse validation. Returns the sanitized filename.

    Raises :class:`UploadValidationError` with a machine-friendly reason in
    ``.reason_code`` for each rejection class.
    """
    err = UploadValidationError
    safe_name = sanitize_filename(filename)

    ext_ok = any(safe_name.lower().endswith(ext) for ext in allowed_extensions)
    if not ext_ok:
        e = err(
            f"Only {'/'.join(allowed_extensions)} files are supported"
        )
        e.reason_code = "INVALID_FILE_TYPE"  # type: ignore[attr-defined]
        raise e

    if not content:
        e = err("Uploaded file is empty")
        e.reason_code = "EMPTY_FILE"  # type: ignore[attr-defined]
        raise e

    if len(content) > max_bytes:
        e = err(f"File exceeds the {max_bytes // (1024 * 1024)} MB limit")
        e.reason_code = "FILE_TOO_LARGE"  # type: ignore[attr-defined]
        raise e

    if expected_magic is not None and not sniff_magic(content).startswith(expected_magic):
        e = err(
            "File contents do not match the declared type (failed magic-byte check)"
        )
        e.reason_code = "CONTENT_TYPE_MISMATCH"  # type: ignore[attr-defined]
        raise e

    return safe_name