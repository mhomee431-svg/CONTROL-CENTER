"""Dedicated admin username/password login - single Super Admin access.
POST /api/v1/admin/auth/login   { username, password } -> access+refresh tokens
POST /api/v1/admin/auth/refresh { refresh_token }        -> new access token
POST /api/v1/admin/auth/logout  (Bearer access token)    -> revoke access token
Credentials live ONLY in backend env (.env): ADMIN_USERNAME / ADMIN_PASSWORD
Security: rotating refresh tokens, token blacklist on logout, short-lived
access tokens (60 min), rate-limited login, constant-time credential compare.
"""
from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session
import hashlib as _hashlib
import uuid as _uuid
from app.core.config import settings
from app.core.responses import success_response, error_response
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    get_token_jti,
    validate_token_type,
    TokenPurpose,
)
from app.core.rate_limit import auth_rate_limit
router = APIRouter(prefix="/admin/auth", tags=["admin-auth"])
_bearer = HTTPBearer(auto_error=False)
class AdminLoginRequest(BaseModel):
    username: str = Field(..., min_length=1, max_length=128)
    password: str = Field(..., min_length=1, max_length=256)
class RefreshRequest(BaseModel):
    refresh_token: str = Field(..., min_length=10, max_length=1024)
def _get_db():
    """Yield a sync session using the project SessionLocal."""
    from app.database.session import SessionLocal
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
def _hash_refresh(token: str) -> str:
    return _hashlib.sha256(token.encode()).hexdigest()
def _blacklist_token(db: Session, jti: str, token_type: str, user_id, reason: str) -> None:
    from app.models.session import TokenBlacklist
    # expires_at from decoded exp handled by caller; use now+24h fallback
    db.add(TokenBlacklist(
        jti=jti,
        token_type=token_type,
        user_id=user_id,
        expires_at=datetime.now(timezone.utc) + timedelta(hours=24),
        revoked_at=datetime.now(timezone.utc),
        reason=reason,
    ))
def _find_admin_user(db: Session):
    from app.database.session import SessionLocal as _SL  # noqa: F401
    from app.models.user import User
    from app.core.admin_permissions import user_is_admin_family
    users = db.query(User).filter(User.is_active == True).all()  # noqa: E712
    return next((u for u in users if u.role is not None and user_is_admin_family(u)), None)
@router.post("/login")
@auth_rate_limit()
async def admin_login(payload: AdminLoginRequest, request: Request, db: Session = Depends(_get_db)):
    """Single Super Admin login -> issues short-lived access + rotating refresh token."""
    from app.models.session import AuthSession
    expected_user = getattr(settings, "ADMIN_USERNAME", None)
    expected_pass = getattr(settings, "ADMIN_PASSWORD", None)
    if not expected_user or not expected_pass:
        return error_response(
            message="Admin credentials not configured on server",
            error_code="ADMIN_CREDENTIALS_MISSING",
            status_code=500,
        )
    import hmac as _hmac
    user_ok = _hmac.compare_digest(payload.username.encode(), expected_user.encode())
    pass_ok = _hmac.compare_digest(payload.password.encode(), expected_pass.encode())
    if not (user_ok and pass_ok):
        return error_response(
            message="Invalid username or password",
            error_code="INVALID_CREDENTIALS",
            status_code=401,
        )
    admin_user = _find_admin_user(db)
    if admin_user is None:
        return error_response(
            message="No admin-family user found in database",
            error_code="NO_ADMIN_USER",
            status_code=500,
        )
    now = datetime.now(timezone.utc)
    access_token, access_jti = create_access_token(
        subject=str(admin_user.id),
        extra_claims={"role": "admin", "scope": "super"},
    )
    refresh_token, refresh_jti = create_refresh_token(
        subject=str(admin_user.id),
        extra_claims={"role": "admin", "scope": "super"},
    )
    session_row = AuthSession(
        session_id=str(_uuid.uuid4()),
        user_id=admin_user.id,
        device_name="Control Center (Web)",
        device_type="web",
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent", "")[:500],
        refresh_token_hash=_hash_refresh(refresh_token),
        refresh_token_expires_at=now + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
        access_jti=access_jti,
        refresh_jti=refresh_jti,
        is_active=True,
        last_activity_at=now,
        expires_at=now + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
    )
    db.add(session_row)
    db.commit()
    return success_response(
        data={
            "access_token": access_token,
            "refresh_token": refresh_token,
            "token_type": "bearer",
            "expires_in": settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
            "admin": {"username": expected_user, "level": "SUPER"},
        },
        message="Login successful",
    )
@router.post("/refresh")
async def admin_refresh(payload: RefreshRequest, db: Session = Depends(_get_db)):
    """Rotate refresh token: old one revoked, new pair issued. Detects reuse."""
    from app.models.session import AuthSession
    try:
        claims = decode_token(payload.refresh_token)
    except Exception:
        return error_response(message="Invalid refresh token", error_code="INVALID_TOKEN", status_code=401)
    if claims.get("type") != TokenPurpose.REFRESH.value:
        return error_response(message="Invalid token type", error_code="INVALID_TOKEN", status_code=401)
    jti = claims.get("jti")
    token_hash = _hash_refresh(payload.refresh_token)
    session_row = db.query(AuthSession).filter(AuthSession.refresh_token_hash == token_hash).first()
    if session_row is None:
        return error_response(message="Refresh token not recognized", error_code="INVALID_TOKEN", status_code=401)
    if session_row.is_revoked or not session_row.is_active:
        return error_response(message="Session revoked", error_code="SESSION_REVOKED", status_code=401)
    now = datetime.now(timezone.utc)
    exp = session_row.refresh_token_expires_at
    if exp:
        if exp.tzinfo is None:
            exp = exp.replace(tzinfo=timezone.utc)
        if exp < now:
            return error_response(message="Refresh token expired", error_code="TOKEN_EXPIRED", status_code=401)
    # Reuse detection: if token was already used (rotated), revoke whole session
    if session_row.refresh_token_used_at is not None:
        session_row.is_revoked = True
        session_row.is_active = False
        session_row.revoked_at = now
        session_row.revoked_reason = "refresh_reuse_detected"
        db.commit()
        return error_response(message="Token reuse detected - session revoked", error_code="REUSE_DETECTED", status_code=401)
    # Reuse detection #2: if the previous hash matches this token, revoke
    if session_row.previous_refresh_token_hash == token_hash:
        session_row.is_revoked = True
        session_row.is_active = False
        db.commit()
        return error_response(message="Token reuse detected - session revoked", error_code="REUSE_DETECTED", status_code=401)
    # Rotate: keep old hash as previous, set new
    admin_user = _find_admin_user(db)
    if admin_user is None or str(admin_user.id) != str(claims.get("sub")):
        return error_response(message="User mismatch", error_code="INVALID_TOKEN", status_code=401)
    new_access, new_access_jti = create_access_token(
        subject=str(admin_user.id),
        extra_claims={"role": "admin", "scope": "super"},
    )
    new_refresh, new_refresh_jti = create_refresh_token(
        subject=str(admin_user.id),
        extra_claims={"role": "admin", "scope": "super"},
    )
    session_row.previous_refresh_token_hash = session_row.refresh_token_hash
    session_row.refresh_token_hash = _hash_refresh(new_refresh)
    session_row.refresh_token_expires_at = now + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    session_row.access_jti = new_access_jti
    session_row.refresh_jti = new_refresh_jti
    session_row.refresh_token_used_at = now
    session_row.last_activity_at = now
    db.commit()
    return success_response(
        data={
            "access_token": new_access,
            "refresh_token": new_refresh,
            "token_type": "bearer",
            "expires_in": settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
        },
        message="Token refreshed",
    )
@router.post("/logout")
async def admin_logout(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer),
    db: Session = Depends(_get_db),
):
    """Revoke the presented access token (blacklist) and deactivate the session."""
    from app.models.session import AuthSession
    if credentials is None:
        return error_response(message="Not authenticated", error_code="UNAUTHORIZED", status_code=401)
    token = credentials.credentials
    try:
        claims = decode_token(token)
    except Exception:
        return error_response(message="Invalid token", error_code="INVALID_TOKEN", status_code=401)
    jti = claims.get("jti")
    sub = claims.get("sub")
    if jti:
        _blacklist_token(db, jti, claims.get("type", "access"), int(sub) if sub and sub.isdigit() else None, "logout")
    session_row = db.query(AuthSession).filter(AuthSession.access_jti == jti).first()
    if session_row:
        session_row.is_active = False
        session_row.is_revoked = True
        session_row.revoked_at = datetime.now(timezone.utc)
        session_row.revoked_reason = "logout"
        session_row.revoked_by = "user"
    db.commit()
    return success_response(message="Logged out successfully")



