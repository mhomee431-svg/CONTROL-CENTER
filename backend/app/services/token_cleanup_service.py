"""Token and session cleanup service.

Handles periodic cleanup of:
- Expired JWT blacklisted tokens
- Expired auth sessions
- Expired password reset tokens

This service is designed to be called by a Celery beat schedule or manually.
"""
import logging
from datetime import datetime, timezone

from sqlalchemy.orm import Session

from app.models.session import AuthSession, TokenBlacklist
from app.models.password_reset import PasswordReset

logger = logging.getLogger("app.services.token_cleanup")


def cleanup_expired_tokens(db: Session) -> dict:
    """Remove expired entries from all token/session tables.
    
    Returns counts of deleted items per category.
    """
    now = datetime.now(timezone.utc)
    results = {
        "blacklisted_tokens": 0,
        "expired_sessions": 0,
        "expired_password_resets": 0,
    }

    # 1. Clean expired blacklisted tokens
    try:
        expired_blacklist = (
            db.query(TokenBlacklist)
            .filter(TokenBlacklist.expires_at < now)
            .delete(synchronize_session=False)
        )
        results["blacklisted_tokens"] = expired_blacklist
        if expired_blacklist > 0:
            logger.info("Cleaned %d expired blacklisted tokens", expired_blacklist)
    except Exception as exc:
        logger.error("Error cleaning blacklisted tokens: %s", exc)

    # 2. Clean expired sessions (inactive for too long)
    try:
        expired_sessions = (
            db.query(AuthSession)
            .filter(
                AuthSession.expires_at < now,
                AuthSession.is_active == True,  # noqa: E712
            )
            .update(
                {
                    "is_active": False,
                    "is_revoked": True,
                    "revoked_reason": "expired",
                    "revoked_by": "system",
                    "revoked_at": now,
                },
                synchronize_session=False,
            )
        )
        results["expired_sessions"] = expired_sessions
        if expired_sessions > 0:
            logger.info("Revoked %d expired sessions", expired_sessions)
    except Exception as exc:
        logger.error("Error cleaning expired sessions: %s", exc)

    # 3. Clean expired password resets
    try:
        expired_resets = (
            db.query(PasswordReset)
            .filter(
                PasswordReset.expires_at < now,
                PasswordReset.is_used == False,  # noqa: E712
            )
            .delete(synchronize_session=False)
        )
        results["expired_password_resets"] = expired_resets
        if expired_resets > 0:
            logger.info("Cleaned %d expired password resets", expired_resets)
    except Exception as exc:
        logger.error("Error cleaning expired password resets: %s", exc)

    db.commit()
    
    total = sum(results.values())
    logger.info("Token cleanup complete: %d total items cleaned", total)
    
    return results


def cleanup_user_sessions(db: Session, user_id: int, *, keep_session_id: str | None = None) -> int:
    """Revoke all sessions for a user except the current one.
    
    Useful when user changes password or reports suspicious activity.
    """
    now = datetime.now(timezone.utc)
    
    query = (
        db.query(AuthSession)
        .filter(
            AuthSession.user_id == user_id,
            AuthSession.is_active == True,  # noqa: E712
        )
    )
    
    if keep_session_id:
        query = query.filter(AuthSession.session_id != keep_session_id)
    
    revoked = query.update(
        {
            "is_active": False,
            "is_revoked": True,
            "revoked_reason": "security_action",
            "revoked_by": "system",
            "revoked_at": now,
        },
        synchronize_session=False,
    )
    
    db.commit()
    
    if revoked > 0:
        logger.info("Revoked %d sessions for user %d", revoked, user_id)
    
    return revoked


def get_active_session_count(db: Session, user_id: int) -> int:
    """Get count of active sessions for a user."""
    return (
        db.query(AuthSession)
        .filter(
            AuthSession.user_id == user_id,
            AuthSession.is_active == True,  # noqa: E712
            AuthSession.is_revoked == False,  # noqa: E712
        )
        .count()
    )


def get_oldest_active_session(db: Session, user_id: int) -> AuthSession | None:
    """Get the oldest active session for a user."""
    return (
        db.query(AuthSession)
        .filter(
            AuthSession.user_id == user_id,
            AuthSession.is_active == True,  # noqa: E712
            AuthSession.is_revoked == False,  # noqa: E712
        )
        .order_by(AuthSession.created_at.asc())
        .first()
    )
