"""Google OAuth 2.0 (Authorization Code flow) integration.

Implements a secure, dependency-light Google sign-in:

  * ``POST /api/auth/google``  → returns the Google consent URL (the client
    opens it in a browser). A short-lived signed ``state`` JWT (CSRF token)
    is embedded so the callback can never be confused with another login.
  * ``GET /api/auth/google/callback`` → exchanges ``?code`` for tokens,
    verifies the Google ID token (signature + ``aud`` + ``iss`` + ``exp``
    against Google's published JWKS), then upserts the user and issues the
    platform's JWT session tokens.

Only the ID token's verified claims are trusted; the raw ``access_token`` is
never persisted and the profile is never fetched with an unverified token.
"""
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any
from urllib.parse import urlencode

import httpx
from jose import JWTError, jwk, jwt

from app.core.config import settings
from app.core.logging import get_logger

logger = get_logger("app.services.google_oauth")

# Scope needed to read the user's profile (email + name + picture).
_GOOGLE_SCOPE = "openid email profile"
_TOKEN_TIMEOUT = 10.0


class GoogleOAuthError(RuntimeError):
    """Raised for any Google OAuth failure (network, verification, config)."""


def build_authorization_url(state: str) -> str:
    """Build the Google consent screen URL for this app."""
    if not settings.GOOGLE_CLIENT_ID:
        raise GoogleOAuthError("GOOGLE_CLIENT_ID is not configured")
    params = {
        "client_id": settings.GOOGLE_CLIENT_ID,
        "redirect_uri": settings.GOOGLE_CALLBACK_URL,
        "response_type": "code",
        "scope": settings.GOOGLE_OAUTH_SCOPES or _GOOGLE_SCOPE,
        "access_type": "online",
        "prompt": "select_account",
        "state": state,
    }
    return f"{settings.GOOGLE_OAUTH_AUTHORIZE_URL}?{urlencode(params)}"


def create_state_token() -> str:
    """Create a short-lived, signed CSRF state token for the OAuth round-trip."""
    now = datetime.now(timezone.utc)
    payload = {
        "csrf": secrets.token_urlsafe(32),
        "exp": now + timedelta(minutes=10),
        "iat": now,
    }
    return jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def validate_state_token(state: str) -> bool:
    """Validate the signed state token (expiry + signature). Never trusts a
    caller-supplied state string."""
    if not state:
        return False
    try:
        jwt.decode(
            state,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM],
            options={"verify_sub": False, "verify_aud": False},
        )
        return True
    except JWTError:
        return False


def exchange_code_for_tokens(code: str) -> dict[str, Any]:
    """Exchange the authorization code for Google tokens."""
    if not (settings.GOOGLE_CLIENT_ID and settings.GOOGLE_CLIENT_SECRET):
        raise GoogleOAuthError("Google OAuth credentials are not configured")
    data = {
        "code": code,
        "client_id": settings.GOOGLE_CLIENT_ID,
        "client_secret": settings.GOOGLE_CLIENT_SECRET,
        "redirect_uri": settings.GOOGLE_CALLBACK_URL,
        "grant_type": "authorization_code",
    }
    try:
        resp = httpx.post(
            settings.GOOGLE_OAUTH_TOKEN_URL,
            data=data,  # form-encoded, as required by the token endpoint
            timeout=_TOKEN_TIMEOUT,
        )
    except httpx.HTTPError as exc:
        raise GoogleOAuthError(f"Google token exchange failed: {exc}") from exc

    if resp.status_code >= 400:
        raise GoogleOAuthError(
            f"Google rejected the authorization code (HTTP {resp.status_code})"
        )
    try:
        return resp.json()
    except ValueError as exc:
        raise GoogleOAuthError("Google returned a non-JSON token response") from exc


def _fetch_jwks() -> dict[str, Any]:
    """Fetch Google's current public signing keys (JWKS)."""
    try:
        resp = httpx.get(settings.GOOGLE_OAUTH_CERTS_URL, timeout=_TOKEN_TIMEOUT)
        resp.raise_for_status()
        return resp.json()
    except (httpx.HTTPError, ValueError) as exc:
        raise GoogleOAuthError(f"Failed to fetch Google signing keys: {exc}") from exc


def verify_id_token(id_token: str) -> dict[str, Any]:
    """Verify a Google ID token (signature, audience, issuer, expiry) and
    return its verified claims."""
    try:
        header = jwt.get_unverified_header(id_token)
        kid = header.get("kid")
        alg = header.get("alg", "RS256")
    except JWTError as exc:
        raise GoogleOAuthError("Invalid Google ID token") from exc

    keys = _fetch_jwks().get("keys", [])
    candidates = [k for k in keys if k.get("kid") == kid] or keys

    for key in candidates:
        try:
            public_key = jwk.construct(key, alg)
            claims = jwt.decode(
                id_token,
                public_key,
                algorithms=[alg],
                audience=settings.GOOGLE_CLIENT_ID,
                issuer=["accounts.google.com", "https://accounts.google.com"],
            )
            return claims
        except JWTError:
            continue

    raise GoogleOAuthError("Google ID token could not be verified")


def google_user_profile(tokens: dict[str, Any]) -> dict[str, Any]:
    """Return the verified Google profile: google_id, email, name, picture.

    The ID token is verified cryptographically; its claims are authoritative.
    If no ID token is present we refuse (never trust an unverified profile).
    """
    id_token = tokens.get("id_token")
    if not id_token:
        raise GoogleOAuthError("Google did not return an ID token")
    claims = verify_id_token(id_token)

    if not claims.get("email_verified", False):
        raise GoogleOAuthError("Google account email is not verified")
    if not claims.get("email"):
        raise GoogleOAuthError("Google account has no email address")

    return {
        "google_id": str(claims.get("sub", "")),
        "email": claims.get("email"),
        "name": claims.get("name"),
        "picture": claims.get("picture"),
    }