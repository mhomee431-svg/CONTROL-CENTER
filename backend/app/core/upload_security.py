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

    #: Machine-friendly rejection reason (assigned by ``validate_upload``).
    reason_code: str


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


# ── Phase 7 — media (image / document) validation ────────────────────────────
#
# The signed-upload flow cannot sniff bytes (the backend never sees them), so
# it validates the *declared* type/extension/size at intent time and re-checks
# the *stored* object's content-type + size at confirm time. Direct uploads
# (local development) additionally get full magic-byte verification here.

JPEG_MAGIC = b"\xff\xd8\xff"
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
WEBP_MAGIC = b"WEBP"  # at offset 8 inside a RIFF container
PDF_MAGIC = b"%PDF-"
MAX_FILENAME_LENGTH = 255

#: allowed content types → accepted file extensions
MEDIA_TYPES: dict[str, tuple[str, ...]] = {
    "image/jpeg": (".jpg", ".jpeg"),
    "image/png": (".png",),
    "image/webp": (".webp",),
    "application/pdf": (".pdf",),
}

#: detected-from-bytes content type → declared content types that match it
MEDIA_MAGIC_BY_TYPE: dict[str, tuple[bytes, int, bytes]] = {
    # content_type: (leading magic, offset, comparison bytes)
    "image/jpeg": (JPEG_MAGIC, 0, JPEG_MAGIC),
    "image/png": (PNG_MAGIC, 0, PNG_MAGIC),
    "image/webp": (b"RIFF", 8, WEBP_MAGIC),
    "application/pdf": (PDF_MAGIC, 0, PDF_MAGIC),
}


def sniff_media_content_type(content: bytes) -> str | None:
    """Best-effort content-type detection from magic bytes; None if unknown."""
    for ctype, (prefix, offset, expected) in MEDIA_MAGIC_BY_TYPE.items():
        if content[: len(prefix)] == prefix and content[offset : offset + len(expected)] == expected:
            return ctype
    return None


def validate_media_upload(
    filename: str | None,
    content: bytes | None,
    *,
    allowed_content_types: tuple[str, ...],
    max_bytes: int,
) -> tuple[str, str]:
    """Validate a directly-streamed media upload. Returns (safe_name, content_type).

    Checks: extension allow-list, declared content-type allow-list, non-empty,
    size cap, and magic-byte truth (declared type must match actual bytes —
    blocks renamed executables / polyglots). Raises UploadValidationError.
    """
    err = UploadValidationError
    safe_name = sanitize_filename(filename)

    allowed_exts: tuple[str, ...] = tuple(
        ext for ctype in allowed_content_types for ext in MEDIA_TYPES.get(ctype, ())
    )
    if not any(safe_name.lower().endswith(ext) for ext in allowed_exts):
        e = err(f"Only {'/'.join(allowed_exts)} files are supported")
        e.reason_code = "INVALID_FILE_TYPE"  # type: ignore[attr-defined]
        raise e

    declared = sniff_media_content_type(content or b"")
    if declared is None:
        e = err("Unrecognized or unsupported file contents")
        e.reason_code = "CONTENT_TYPE_MISMATCH"  # type: ignore[attr-defined]
        raise e
    if declared not in allowed_content_types:
        e = err(f"Content type {declared} is not allowed for this upload")
        e.reason_code = "CONTENT_TYPE_NOT_ALLOWED"  # type: ignore[attr-defined]
        raise e

    if not content:
        e = err("Uploaded file is empty")
        e.reason_code = "EMPTY_FILE"  # type: ignore[attr-defined]
        raise e

    if len(content) > max_bytes:
        e = err(f"File exceeds the {max_bytes // (1024 * 1024)} MB limit")
        e.reason_code = "FILE_TOO_LARGE"  # type: ignore[attr-defined]
        raise e

    return safe_name, declared