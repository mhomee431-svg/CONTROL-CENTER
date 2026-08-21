"""JWT token creation, validation, and claim helpers."""
import uuid
from datetime import datetime, timedelta, timezone
from enum import Enum
from typing import Any, Optional

from jose import jwt, JWTError

from app.core.config import settings


class TokenPurpose(str, Enum):
    ACCESS = "access"
    REFRESH = "refresh"


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _create_token(
    subject: str,
    purpose: TokenPurpose,
    expires_delta: timedelta,
    extra_claims: Optional[dict] = None,
) -> tuple[str, str]:
    """Create a JWT with the given purpose and return (token, jti)."""
    jti = str(uuid.uuid4())
    now = _now()
    expire = now + expires_delta

    payload: dict[str, Any] = {
        "sub": subject,
        "exp": expire,
        "iat": now,
        "jti": jti,
        "iss": settings.TOKEN_ISSUER,
        "aud": settings.TOKEN_AUDIENCE,
        "type": purpose.value,
    }
    if extra_claims:
        payload.update(extra_claims)

    token = jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)
    return token, jti


def create_access_token(
    subject: str,
    expires_minutes: Optional[int] = None,
    extra_claims: Optional[dict] = None,
) -> tuple[str, str]:
    """Create a JWT access token. Returns (token, jti)."""
    delta = timedelta(minutes=expires_minutes or settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    return _create_token(subject, TokenPurpose.ACCESS, delta, extra_claims)


def create_refresh_token(
    subject: str,
    expires_days: Optional[int] = None,
    extra_claims: Optional[dict] = None,
) -> tuple[str, str]:
    """Create a JWT refresh token. Returns (token, jti)."""
    delta = timedelta(days=expires_days or settings.REFRESH_TOKEN_EXPIRE_DAYS)
    return _create_token(subject, TokenPurpose.REFRESH, delta, extra_claims)


def decode_token(token: str) -> dict:
    """Decode and validate a JWT token. Raises JWTError if invalid."""
    return jwt.decode(
        token,
        settings.JWT_SECRET_KEY,
        algorithms=[settings.JWT_ALGORITHM],
        audience=settings.TOKEN_AUDIENCE,
        issuer=settings.TOKEN_ISSUER,
    )


def get_token_subject(token: str) -> Optional[int]:
    """Extract the user id (subject) from a valid token."""
    try:
        payload = decode_token(token)
        sub = payload.get("sub")
        return int(sub) if sub is not None else None
    except JWTError:
        return None


def get_token_jti(token: str) -> Optional[str]:
    """Extract the JWT ID (jti) from a valid token."""
    try:
        payload = decode_token(token)
        return payload.get("jti")
    except JWTError:
        return None


def get_token_claims(token: str) -> dict:
    """Return the full decoded claims of a valid token."""
    return decode_token(token)


def validate_token_type(token: str, expected: TokenPurpose) -> bool:
    """Check that the token is of the expected type (access/refresh)."""
    try:
        payload = decode_token(token)
        return payload.get("type") == expected.value
    except JWTError:
        return False