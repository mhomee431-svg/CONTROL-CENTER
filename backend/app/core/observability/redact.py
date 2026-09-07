"""Sensitive-data redaction for structured logs.

Every log line produced by the application passes through
:func:`redact_message` before it reaches a sink. The following families are
scrubbed (the exact secret value is never known to the output path):

* passwords / passphrases assigned inline            ``password=...``
* OTP / verification codes                           ``otp: 482913``
* JWT / opaque tokens & bearer credentials           ``Bearer eyJ...``
* API keys / client secrets                          ``api_key=...``
* private key blocks (RSA / EC / OPENSSH / PGP)      ``-----BEGIN ... KEY-----``
* payment card numbers                               ``4242 4242 4242 4242``
* refresh/access tokens in any key=value context     ``access_token=...``

This is a defence-in-depth last line: callers should still avoid *placing*
secrets in log messages in the first place (see ``app/core/logging.py``).
"""

from __future__ import annotations

import re

_REDACTED = "[REDACTED]"

# ── Patterns ──────────────────────────────────────────────────────────────
# key=value / key:value / key-value assignments for common secret names.
# The value is consumed greedily up to whitespace or a comma/quote, so
# ``password=abc123&user=x`` redacts to ``password=[REDACTED]&user=x``.
_SECRET_KEYS = (
    r"password|passwd|pwd|passphrase|secret|api[_-]?key|api[_-]?secret|"
    r"client[_-]?secret|client[_-]?id|private[_-]?key|auth[_-]?token|"
    r"access[_-]?token|refresh[_-]?token|id[_-]?token|"
    r"jwt|signing[_-]?secret|webhook[_-]?secret|payment[_-]?secret|"
    r"authorization|bearer|cookie|set-cookie|"
    r"otp|otp[_-]?code|verification[_-]?code|verification[_-]?token|"
    r"firebase[_-]?credentials|fcm[_-]?key|smtp[_-]?password"
)
_SECRET_ASSIGNMENT_RE = re.compile(
    r"(?i)\b(" + _SECRET_KEYS + r")\b\s*(?:=|:|\s+)\s*"
    r"('([^']*)'|\"([^\"]*)\"|[^\s,&;'\"]+)"
)
# JWT: three base64url dot-separated segments.
_TOKEN_RE = re.compile(r"\b[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}")
# Private key blocks (may span multiple lines).
_PRIVATE_KEY_RE = re.compile(
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----[^-]*-----END [A-Z ]*PRIVATE KEY-----",
    re.DOTALL,
)
# Payment card numbers (13-19 digits in 4-4-4-4 groups, optional separators).
_CARD_RE = re.compile(r"\b(?:\d{4}[ -]?){3}\d{4}\b")


def redact_message(message: str) -> str:
    """Return ``message`` with every recognised secret value replaced."""
    if not message:
        return message

    def _replace_key_value(match: "re.Match[str]") -> str:
        raw = match.group(0)
        if match.group(3) is not None:
            consumed = match.group(3)
        elif match.group(4) is not None:
            consumed = match.group(4)
        else:
            consumed = match.group(2)
        if not consumed:
            return raw
        pos = raw.find(consumed)
        if pos < 0:
            return raw
        return f"{raw[:pos]}{_REDACTED}"

    out = _SECRET_ASSIGNMENT_RE.sub(_replace_key_value, message)
    out = _TOKEN_RE.sub(_REDACTED, out)
    out = _PRIVATE_KEY_RE.sub(_REDACTED, out)
    out = _CARD_RE.sub(_REDACTED, out)
    return out


#: Keys whose log-record ``extra`` payload must never be emitted.
FORBIDDEN_EXTRA_KEYS = frozenset(
    {
        "password", "passwd", "pwd", "secret", "otp", "otp_code", "token",
        "access_token", "refresh_token", "id_token", "authorization",
        "api_key", "client_secret", "payment_secret", "private_key", "jwt",
    }
)

#: Sub-strings that mark a dict key as carrying a secret value.
_SECRET_KEY_HINTS = (
    "password", "passwd", "pwd", "secret", "token", "otp", "api_key",
    "api-key", "authorization", "bearer", "credential", "private_key",
    "card_number", "cvv", "upi", "jwt",
)


def is_secret_key(key: str) -> bool:
    """True when ``key`` itself signals that its value is a secret."""
    normalized = str(key).strip().lower()
    return any(hint in normalized for hint in _SECRET_KEY_HINTS)


def redact_value(value, key: str = None):
    """Redact one value, key-aware.

    * When ``key`` looks like a secret (``otp``, ``token``, ``password``…)
      the entire value is replaced — even numbers/objects that inline
      patterns cannot see.
    * Otherwise plain string redaction still applies (JWT/card/password=…).
    """
    if key is not None and is_secret_key(key):
        return _REDACTED
    if isinstance(value, str):
        return redact_message(value)
    return value


def sanitize_extra(extra: dict) -> dict:
    """Return an ``extra`` dict with forbidden keys removed (defence in depth)."""
    if not extra:
        return {}
    return {k: v for k, v in extra.items() if str(k).lower() not in FORBIDDEN_EXTRA_KEYS}