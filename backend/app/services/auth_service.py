"""Authentication service — session management, token lifecycle, and revocation."""
import hashlib
import secrets
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.exceptions import UnauthorizedError
from app.core.logging import get_logger
from app.core.security import create_access_token, create_refresh_token
from app.models.session import AuthSession, TokenBlacklist
from app.models.user import User, UserStatus

logger = get_logger("app.services.auth")


def hash_refresh_token(token: str) -> str:
    """SHA-256 hash of a refresh token (raw token is never stored)."""
    return hashlib.sha256(token.encode()).hexdigest()


def generate_session_id() -> str:
    return str(uuid.uuid4())


def generate_refresh_token() -> str:
    """Generate a cryptographically-secure opaque refresh token."""
    return secrets.token_urlsafe(48)


def _as_utc(dt: datetime) -> datetime:
    """Normalize a datetime to timezone-aware UTC (naive assumed UTC).

    Production (PostgreSQL TIMESTAMPTZ) returns aware datetimes; SQLite returns
    naive ones. Comparing the two raises ``TypeError`` — which surfaced as an
    HTTP 500 on token refresh.
    """
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt


def issue_tokens(
    user: User,
    db: Session,
    *,
    device_id: str | None = None,
    device_name: str | None = None,
    device_type: str | None = None,
    platform: str | None = None,
    app_version: str | None = None,
    ip_address: str | None = None,
    user_agent: str | None = None,
) -> dict:
    """Issue a new access token + refresh token and create a persistent session.

    Enforces max devices per user.
    """
    now = datetime.now(timezone.utc)

    # ── Enforce session limits ─────────────────────────────────────────────
    active_sessions = (
        db.query(AuthSession)
        .filter(
            AuthSession.user_id == user.id,
            AuthSession.is_active == True,  # noqa: E712
            AuthSession.is_revoked == False,  # noqa: E712
        )
        .order_by(AuthSession.created_at.asc())
        .all()
    )

    if len(active_sessions) >= settings.SESSION_MAX_DEVICES:
        # Revoke the oldest session
        oldest = active_sessions[0]
        oldest.is_active = False
        oldest.is_revoked = True
        oldest.revoked_at = now
        oldest.revoked_reason = "session_limit"
        oldest.revoked_by = "system"
        logger.info("Revoked oldest session %s due to device limit", oldest.session_id)

    # ── Create new session ──────────────────────────────────────────────────
    refresh_token_raw = generate_refresh_token()
    refresh_token_hash = hash_refresh_token(refresh_token_raw)
    refresh_expires = now + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    session_expires = now + timedelta(days=settings.SESSION_IDLE_TIMEOUT_DAYS)

    auth_session = AuthSession(
        session_id=generate_session_id(),
        user_id=user.id,
        device_id=device_id,
        device_name=device_name,
        device_type=device_type,
        platform=platform,
        app_version=app_version,
        ip_address=ip_address,
        user_agent=user_agent,
        refresh_token_hash=refresh_token_hash,
        refresh_token_expires_at=refresh_expires,
        is_active=True,
        is_revoked=False,
        last_activity_at=now,
        expires_at=session_expires,
        refresh_rotation_count=0,
    )
    db.add(auth_session)
    db.flush()

    # ── Update user login metadata ─────────────────────────────────────────
    user.last_login_at = now
    user.last_login_ip = ip_address
    db.flush()

    # ── Issue JWT tokens ───────────────────────────────────────────────────
    access_token, access_jti = create_access_token(
        subject=str(user.id),
        extra_claims={
            "session_id": auth_session.session_id,
            "role": user.role.name if user.role else None,
        },
    )
    refresh_token, refresh_jti = create_refresh_token(
        subject=str(user.id),
        extra_claims={
            "session_id": auth_session.session_id,
            "token_version": auth_session.refresh_rotation_count,
        },
    )

    # Store jti mappings on the session for revocation
    auth_session.access_jti = access_jti  # type: ignore[attr-defined]
    auth_session.refresh_jti = refresh_jti  # type: ignore[attr-defined]

    logger.info(
        "Issued tokens for user=%s session=%s device=%s",
        user.id,
        auth_session.session_id,
        device_name or device_type or "unknown",
    )

    return {
        "access_token": access_token,
        "refresh_token": refresh_token_raw,
        "token_type": "bearer",
        "expires_in": settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
        "session_id": auth_session.session_id,
        "user": {
            "id": user.id,
            "phone_number": user.phone_number,
            "name": user.name,
            "role": user.role.name if user.role else None,
        },
    }


def refresh_session(
    db: Session,
    refresh_token_raw: str,
    *,
    device_id: str | None = None,
) -> dict:
    """Rotate a refresh token and issue new tokens.

    Implements:
      - Token reuse detection (if a rotated token is reused, revoke the session)
      - Session revocation check
      - Session expiry check
    """
    now = datetime.now(timezone.utc)
    refresh_hash = hash_refresh_token(refresh_token_raw)

    session_record = (
        db.query(AuthSession)
        .filter(AuthSession.refresh_token_hash == refresh_hash)
        .first()
    )

    if session_record is None:
        # Possibly a replayed (already-rotated) token → search previous hash
        replayed = (
            db.query(AuthSession)
            .filter(AuthSession.previous_refresh_token_hash == refresh_hash)
            .first()
        )
        if replayed and settings.REFRESH_TOKEN_REUSE_DETECTION:
            # Refresh token replay detected — revoke the entire session
            replayed.is_active = False
            replayed.is_revoked = True
            replayed.reuse_detected = True
            replayed.revoked_at = now
            replayed.revoked_reason = "token_reuse"
            replayed.revoked_by = "system"
            db.flush()
            logger.warning(
                "Refresh token reuse detected — revoked session %s",
                replayed.session_id,
            )
            raise UnauthorizedError("Refresh token reuse detected. Session revoked.")
        raise UnauthorizedError("Invalid refresh token")

    # ── Session checks ─────────────────────────────────────────────────────
    if not session_record.is_active or session_record.is_revoked:
        raise UnauthorizedError("Session has been revoked")

    if session_record.refresh_token_expires_at and now > _as_utc(session_record.refresh_token_expires_at):
        session_record.is_active = False
        session_record.is_revoked = True
        session_record.revoked_at = now
        session_record.revoked_reason = "token_expired"
        session_record.revoked_by = "system"
        db.flush()
        raise UnauthorizedError("Refresh token expired")

    if session_record.expires_at and now > _as_utc(session_record.expires_at):
        session_record.is_active = False
        session_record.is_revoked = True
        session_record.revoked_at = now
        session_record.revoked_reason = "session_expired"
        session_record.revoked_by = "system"
        db.flush()
        raise UnauthorizedError("Session expired")

    # ── User checks ────────────────────────────────────────────────────────
    user = db.query(User).filter(User.id == session_record.user_id).first()
    if user is None or not user.is_active or user.status in (UserStatus.SUSPENDED, UserStatus.BANNED):
        session_record.is_active = False
        session_record.is_revoked = True
        session_record.revoked_at = now
        session_record.revoked_reason = "user_inactive"
        session_record.revoked_by = "system"
        db.flush()
        raise UnauthorizedError("User account is not active")

    # ── Rotate tokens ──────────────────────────────────────────────────────
    old_refresh_hash = session_record.refresh_token_hash
    new_refresh_raw = generate_refresh_token()
    new_refresh_hash = hash_refresh_token(new_refresh_raw)
    new_refresh_expires = now + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)

    session_record.previous_refresh_token_hash = old_refresh_hash
    session_record.refresh_token_hash = new_refresh_hash
    session_record.refresh_token_expires_at = new_refresh_expires
    session_record.refresh_token_used_at = now
    session_record.refresh_rotation_count += 1
    session_record.last_activity_at = now
    session_record.device_id = device_id or session_record.device_id

    db.flush()
    db.refresh(session_record)

    # ── Issue new JWT tokens ───────────────────────────────────────────────
    access_token, access_jti = create_access_token(
        subject=str(user.id),
        extra_claims={
            "session_id": session_record.session_id,
            "role": user.role.name if user.role else None,
        },
    )
    refresh_token, refresh_jti = create_refresh_token(
        subject=str(user.id),
        extra_claims={
            "session_id": session_record.session_id,
            "token_version": session_record.refresh_rotation_count,
        },
    )

    session_record.access_jti = access_jti  # type: ignore[attr-defined]
    session_record.refresh_jti = refresh_jti  # type: ignore[attr-defined]

    logger.info(
        "Refreshed tokens for user=%s session=%s rotation=%d",
        user.id,
        session_record.session_id,
        session_record.refresh_rotation_count,
    )

    return {
        "access_token": access_token,
        "refresh_token": new_refresh_raw,
        "token_type": "bearer",
        "expires_in": settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
        "session_id": session_record.session_id,
        "user": {
            "id": user.id,
            "phone_number": user.phone_number,
            "name": user.name,
            "role": user.role.name if user.role else None,
        },
    }


def logout_session(
    db: Session,
    user: User,
    *,
    session_id: str | None = None,
    revoke_all: bool = False,
) -> dict:
    """Revoke one session or all sessions for a user."""
    now = datetime.now(timezone.utc)

    if revoke_all:
        sessions = (
            db.query(AuthSession)
            .filter(
                AuthSession.user_id == user.id,
                AuthSession.is_active == True,  # noqa: E712
            )
            .all()
        )
        count = 0
        for s in sessions:
            s.is_active = False
            s.is_revoked = True
            s.revoked_at = now
            s.revoked_reason = "logout_all"
            s.revoked_by = "user"
            count += 1
        logger.info("Revoked %d sessions for user=%s", count, user.id)
        return {"revoked": count}

    if session_id:
        session = (
            db.query(AuthSession)
            .filter(
                AuthSession.session_id == session_id,
                AuthSession.user_id == user.id,
            )
            .first()
        )
        if session is None:
            raise UnauthorizedError("Session not found")
        session.is_active = False
        session.is_revoked = True
        session.revoked_at = now
        session.revoked_reason = "logout"
        session.revoked_by = "user"
        logger.info("Revoked session %s for user=%s", session_id, user.id)
        return {"revoked": 1}

    # Default: revoke current session (identified via token's session claim)
    return {"revoked": 0}


def revoke_token(db: Session, jti: str, token_type: str, user_id: int, expires_at: datetime) -> None:
    """Add a JWT to the blacklist."""
    blacklist = TokenBlacklist(
        jti=jti,
        token_type=token_type,
        user_id=user_id,
        expires_at=expires_at,
        revoked_at=datetime.now(timezone.utc),
        reason="logout",
    )
    db.add(blacklist)
    db.flush()


def is_token_blacklisted(db: Session, jti: str) -> bool:
    """Check if a JWT is blacklisted."""
    return db.query(TokenBlacklist).filter(TokenBlacklist.jti == jti).first() is not None


def get_active_sessions(db: Session, user_id: int) -> list[dict]:
    """List currently active sessions for a user."""
    sessions = (
        db.query(AuthSession)
        .filter(
            AuthSession.user_id == user_id,
            AuthSession.is_active == True,  # noqa: E712
            AuthSession.is_revoked == False,  # noqa: E712
        )
        .order_by(AuthSession.last_activity_at.desc())
        .all()
    )
    return [
        {
            "session_id": s.session_id,
            "device_name": s.device_name,
            "device_type": s.device_type,
            "platform": s.platform,
            "app_version": s.app_version,
            "ip_address": s.ip_address,
            "last_activity_at": s.last_activity_at.isoformat() if s.last_activity_at else None,
            "created_at": s.created_at.isoformat() if s.created_at else None,
            "expires_at": s.expires_at.isoformat() if s.expires_at else None,
        }
        for s in sessions
    ]


def revoke_session_by_id(db: Session, user_id: int, session_id: str) -> bool:
    """Revoke a specific session belonging to the user."""
    session = (
        db.query(AuthSession)
        .filter(
            AuthSession.session_id == session_id,
            AuthSession.user_id == user_id,
        )
        .first()
    )
    if session is None:
        return False
    session.is_active = False
    session.is_revoked = True
    session.revoked_at = datetime.now(timezone.utc)
    session.revoked_reason = "user_revoked"
    session.revoked_by = "user"
    return True


# ── Account status helpers ────────────────────────────────────────────────
def get_account_status(user: User) -> dict:
    """Return the user's account status."""
    return {
        "is_active": user.is_active,
        "status": user.status.value,
        "last_login_at": user.last_login_at.isoformat() if user.last_login_at else None,
    }


def is_account_allowed(user: User) -> bool:
    """Check if the user account can authenticate."""
    if not user.is_active:
        return False
    if user.status in (UserStatus.SUSPENDED, UserStatus.BANNED, UserStatus.INACTIVE):
        return False
    return True