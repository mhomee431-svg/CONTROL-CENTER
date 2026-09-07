"""Password reset service — forgot password, reset password, and password validation."""
import hashlib
import logging
import secrets
from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.exceptions import (
    NotFoundError,
    UnauthorizedError,
    ValidationError,
)
from app.core.security import (
    hash_password,
    verify_password,
)
from app.models.user import User, UserStatus
from app.models.password_reset import PasswordReset

logger = logging.getLogger("app.services.password")


def _normalize_identifier(identifier: str) -> str:
    """Normalize email or phone identifier."""
    identifier = identifier.strip().lower()
    if "@" in identifier:
        return identifier
    if identifier.startswith("+"):
        return "+" + "".join(c for c in identifier[1:] if c.isdigit())
    return "".join(c for c in identifier if c.isdigit())


def _hash_reset_token(token: str) -> str:
    """SHA-256 hash of a reset token for storage."""
    return hashlib.sha256(token.encode()).hexdigest()


def request_password_reset(db: Session, identifier: str) -> dict:
    """Request a password reset for the given identifier (email or phone).
    
    Generates a secure random token, stores its hash in the database,
    and returns the raw token (which would be sent via email/SMS in production).
    """
    normalized = _normalize_identifier(identifier)
    
    # Find user by email or phone
    user = (
        db.query(User).filter(
            (User.email == normalized) | (User.phone_number == normalized)
        ).first()
    )
    
    # Don't reveal if user exists — return generic response
    if user is None:
        logger.info("Password reset requested for non-existent identifier: %s", normalized)
        return {
            "message": "If an account exists, a reset link has been sent",
            "sent": True,
        }
    
    # Check account status
    if user.status in (UserStatus.SUSPENDED, UserStatus.BANNED):
        logger.info("Password reset blocked for inactive user: %s", user.id)
        return {
            "message": "If an account exists, a reset link has been sent",
            "sent": True,
        }
    
    # Invalidate any existing unused reset tokens for this user
    db.query(PasswordReset).filter(
        PasswordReset.user_id == user.id,
        PasswordReset.is_used == False,  # noqa: E712
    ).update({"is_used": True}, synchronize_session=False)
    
    # Generate secure random token
    raw_token = secrets.token_urlsafe(48)
    token_hash = _hash_reset_token(raw_token)
    expires_at = datetime.now(timezone.utc) + timedelta(
        minutes=settings.PASSWORD_RESET_TOKEN_EXPIRE_MINUTES
    )
    
    # Store token hash in database
    reset_record = PasswordReset(
        user_id=user.id,
        token_hash=token_hash,
        expires_at=expires_at,
        is_used=False,
    )
    db.add(reset_record)
    db.commit()
    
    logger.info(
        "Password reset token created for user %s (expires in %d minutes)",
        user.id, settings.PASSWORD_RESET_TOKEN_EXPIRE_MINUTES,
    )
    
    return {
        "message": "If an account exists, a reset link has been sent",
        "sent": True,
        # Only return token in development mode
        "token": raw_token if not settings.is_production else None,
    }


def _as_utc(dt: datetime) -> datetime:
    """Normalize a datetime to timezone-aware UTC (naive assumed UTC).

    Production (PostgreSQL TIMESTAMPTZ) returns aware datetimes; SQLite and
    some legacy rows return naive ones. Comparisons must never mix the two.
    """
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt


def reset_password(db: Session, token: str, new_password: str) -> dict:
    """Reset password using a valid reset token."""
    # Hash the provided token to look it up
    token_hash = _hash_reset_token(token)
    
    # Find the reset record
    reset_record = (
        db.query(PasswordReset)
        .filter(
            PasswordReset.token_hash == token_hash,
            PasswordReset.is_used == False,  # noqa: E712
        )
        .first()
    )
    
    if reset_record is None:
        raise UnauthorizedError("Invalid or expired reset token")
    
    # Check expiry (normalize naive/aware before comparing)
    if datetime.now(timezone.utc) > _as_utc(reset_record.expires_at):
        reset_record.is_used = True
        db.commit()
        raise UnauthorizedError("Reset token has expired")
    
    # Get user
    user = db.query(User).filter(User.id == reset_record.user_id).first()
    if user is None:
        raise NotFoundError("User not found")
    
    # Check account status
    if user.status in (UserStatus.SUSPENDED, UserStatus.BANNED):
        raise UnauthorizedError("Account is not active")
    
    # Validate new password
    if len(new_password) < settings.PASSWORD_MIN_LENGTH:
        raise ValidationError(f"Password must be at least {settings.PASSWORD_MIN_LENGTH} characters")
    
    # Hash and set new password
    user.password_hash = hash_password(new_password)
    user.updated_at = datetime.now(timezone.utc)
    
    # Mark token as used
    reset_record.is_used = True
    reset_record.used_at = datetime.now(timezone.utc)
    
    db.commit()
    
    logger.info("Password reset successful for user %s", user.id)
    
    return {
        "message": "Password has been reset successfully",
        "success": True,
    }


def change_password(
    db: Session,
    user: User,
    current_password: str,
    new_password: str,
) -> dict:
    """Change password (requires current password)."""
    # Verify current password
    if not user.password_hash:
        raise ValidationError("No password set for this account")
    
    if not verify_password(current_password, user.password_hash):
        raise UnauthorizedError("Current password is incorrect")
    
    # Validate new password
    if len(new_password) < settings.PASSWORD_MIN_LENGTH:
        raise ValidationError(f"Password must be at least {settings.PASSWORD_MIN_LENGTH} characters")
    
    # Hash and set new password
    user.password_hash = hash_password(new_password)
    user.updated_at = datetime.now(timezone.utc)
    db.commit()
    
    logger.info("Password changed for user %s", user.id)
    
    return {
        "message": "Password changed successfully",
        "success": True,
    }