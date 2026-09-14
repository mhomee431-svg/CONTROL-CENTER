"""Google profile data minimalization (Phase 19).

Purpose
-------
Google exposes a lot of account data. Per the product security decision the
platform stores ONLY the fields needed by a Shopkeeper profile — display name,
email, and photo URL — and never pulls or persists anything else (tokens,
scopes data, contacts, drive, etc.).

This service is the single trusted boundary between Firebase-verified token
claims and the application user model. It:
  * whitelists exactly which Google claims may be read,
  * maps them onto the app's minimal fields,
  * and discards everything else.

No Google OAuth scope beyond the default ``email profile`` (which the native
Credential Manager flow requests) is ever needed or used by the backend.
"""

from __future__ import annotations

from typing import Any

# Allowlist of Firebase ID token claims that carry Google profile data. These
# are the ONLY claims we will ever read from a verified token.
ALLOWED_GOOGLE_CLAIM_KEYS = frozenset(
    {
        "sub",  # Firebase UID (identity link, stored, never exposed via API)
        "name",  # display name
        "email",  # profile email
        "picture",  # avatar URL
        "email_verified",  # used ONLY for the lightweight email-verified hint
    }
)

# Secrets/other scopes must NEVER leak out of the token boundary.
DENIED_SCOPE_MARKERS = (
    "token",
    "access_token",
    "oauth",
    "refresh",
    "credentials",
    "hd",
    "locale",
    "profile_grant",
)


class MinimalGoogleProfile:
    """Strict minimal profile derived from a verified Firebase ID token."""

    __slots__ = ("uid", "name", "email", "picture", "email_verified")

    def __init__(
        self,
        *,
        uid: str | None,
        name: str | None,
        email: str | None,
        picture: str | None,
        email_verified: bool | None = None,
    ) -> None:
        self.uid = uid
        self.name = name
        self.email = email
        self.picture = picture
        self.email_verified = email_verified

    def to_dict(self) -> dict[str, Any]:
        """Only the app-facing minimal fields (firebase_uid not exposed)."""
        return {
            "name": self.name,
            "email": self.email,
            "picture": self.picture,
            "email_verified": self.email_verified,
        }

    def __repr__(self) -> str:  # pragma: no cover
        return (
            f"MinimalGoogleProfile(name={self.name!r}, email={self.email!r}, "
            f"picture_set={bool(self.picture)}, email_verified={self.email_verified})"
        )


def extract_minimal_profile(claims: dict[str, Any]) -> MinimalGoogleProfile:
    """Extract ONLY the whitelisted Google fields from verified token claims.

    Args:
        claims: The decoded, cryptographically verified Firebase ID token
            claims (returned by ``verify_firebase_id_token_claims``).

    Returns:
        A :class:`MinimalGoogleProfile` populated with the minimal fields.

    Raises:
        ValueError: if a denied claim key is present.
    """
    # Guard: reject any token whose claims leak non-whitelisted data keys.
    for key in claims:
        if key in ALLOWED_GOOGLE_CLAIM_KEYS:
            continue
        if any(marker in key.lower() for marker in DENIED_SCOPE_MARKERS):
            raise ValueError(f"Forbidden Google claim key in token: {key}")

    return MinimalGoogleProfile(
        uid=claims.get("sub"),
        name=claims.get("name"),
        email=claims.get("email"),
        picture=claims.get("picture"),
        email_verified=claims.get("email_verified"),
    )


# ── OAuth scope policy (documentation + runtime constant) ──────────────────
# The Shopkeeper App requests the DEFAULT Google OAuth scopes only:
#   * openid
#   * email
#   * profile
# These yield exactly the claims above — nothing more. No contacts, no drive,
# no calendar, no billing. This constant is enforced by the native client
# (Credential Manager) and documented here for the backend.
MINIMAL_OAUTH_SCOPES = (
    "openid",
    "email",
    "profile",
)