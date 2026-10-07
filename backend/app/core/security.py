"""Password hashing, JWT issuance and the current-admin dependency."""

from datetime import datetime, timedelta, timezone
from typing import Any, Optional
from uuid import uuid4

import bcrypt
from fastapi import Depends, HTTPException, Request, status
from jose import JWTError, jwt
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db
from app.models import AdminUser

# bcrypt only hashes the first 72 bytes; reject longer passwords rather than
# silently treating two different inputs as the same credential.
_BCRYPT_MAX_BYTES = 72

def hash_password(plain: str) -> str:
    encoded = plain.encode("utf-8")
    if not encoded or len(encoded) > _BCRYPT_MAX_BYTES:
        raise ValueError("Password must be between 1 and 72 bytes")
    return bcrypt.hashpw(encoded, bcrypt.gensalt()).decode("utf-8")


def verify_password(plain: str, hashed: str) -> bool:
    encoded = plain.encode("utf-8")
    if not encoded or len(encoded) > _BCRYPT_MAX_BYTES:
        return False
    try:
        return bcrypt.checkpw(encoded, hashed.encode("utf-8"))
    except (ValueError, TypeError):
        return False


def create_access_token(subject: str | int, extra: Optional[dict[str, Any]] = None) -> str:
    now = datetime.now(timezone.utc)
    payload: dict[str, Any] = {
        "sub": str(subject),
        "exp": now + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES),
        "iat": now,
        "jti": uuid4().hex,
        "purpose": "admin_access",
    }
    if extra:
        payload.update(extra)
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def decode_access_token(token: str) -> dict[str, Any]:
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        if (payload.get("purpose") != "admin_access" or not isinstance(payload.get("jti"), str)
                or not isinstance(payload.get("sub"), str) or not payload["sub"].isdigit()
                or not isinstance(payload.get("iat"), int)):
            raise JWTError("Invalid admin token claims")
        return payload
    except (JWTError, KeyError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
        )


def _token_from_request(request: Request) -> Optional[str]:
    """Bearer header first, then the HttpOnly session cookie."""
    header = request.headers.get("Authorization")
    if header and header.lower().startswith("bearer "):
        return header[7:]
    return request.cookies.get("admin_session")


def get_current_admin(request: Request, db: Session = Depends(get_db)) -> AdminUser:
    """Resolve the acting admin.

    The token can arrive either as a bearer header or as the session cookie.
    No token at all is a 401 so the frontend redirects to the login screen
    rather than rendering an empty console.
    """
    token = _token_from_request(request)
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated",
        )
    payload = decode_access_token(token)
    user_id = payload["sub"]
    admin = db.get(AdminUser, int(user_id))
    if admin is None or not admin.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Admin account unavailable",
        )
    from app.models import RevokedAdminToken
    if db.get(RevokedAdminToken, payload["jti"]) is not None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Session revoked")
    return admin


def require_capability(capability: str):
    """Route guard for a named capability.

    The platform owner bypasses the check; every other admin must hold the
    grant explicitly. Capabilities are compared case-insensitively so the
    frontend's lowercase dotted names line up with stored grants.

    Verification triage accepts aliases: the console guards Approve / Reject /
    Correction / Hold with `shops.approve`, `shops.reject` and `shops.suspend`
    while the API historically required `shops.verify`. Either grant opens the
    decision and assignment routes so a reviewer is never locked out by a
    naming mismatch — the audit log still records exactly what was decided.
    """

    # Frontend guard -> backend grant(s) that satisfy it.
    _ALIASES: dict[str, set[str]] = {
        "shops.verify": {"shops.verify", "shops.approve", "shops.reject", "shops.suspend"},
        "shops.approve": {"shops.approve", "shops.verify"},
        "shops.reject": {"shops.reject", "shops.verify"},
        "shops.suspend": {"shops.suspend", "shops.verify"},
    }

    def _guard(admin: AdminUser = Depends(get_current_admin)) -> AdminUser:
        if admin.is_owner:
            return admin
        grants = {g.lower() for g in (admin.permissions or [])}
        wanted = capability.lower()
        accepted = {wanted} | _ALIASES.get(wanted, set())
        if not (grants & accepted):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Missing capability: {capability}",
            )
        return admin

    return _guard
