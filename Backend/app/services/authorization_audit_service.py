"""Authorization audit service.

Logs all authorization decisions for security auditing and compliance.
Tracks:
- Permission checks (allowed/denied)
- Resource access attempts
- Admin actions
- Suspicious access patterns
"""
import logging
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy.orm import Session

from app.models.admin import AuditLog

logger = logging.getLogger("app.services.authorization_audit")


def log_authorization_check(
    db: Session,
    *,
    user_id: int,
    resource: str,
    action: str,
    resource_id: Optional[int] = None,
    is_allowed: bool,
    reason: Optional[str] = None,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> AuditLog:
    """Log an authorization check decision."""
    audit_entry = AuditLog(
        user_id=user_id,
        action=f"authz:{action}:{resource}",
        entity_type=resource,
        entity_id=resource_id,
        is_success=is_allowed,
        reason=reason,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    db.add(audit_entry)
    db.flush()
    
    if not is_allowed:
        logger.warning(
            "Authorization denied: user=%d resource=%s action=%s resource_id=%s reason=%s",
            user_id, resource, action, resource_id, reason,
        )
    
    return audit_entry


def log_admin_action(
    db: Session,
    *,
    admin_user_id: int,
    action: str,
    target_type: str,
    target_id: Optional[int] = None,
    details: Optional[dict] = None,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> AuditLog:
    """Log an admin action for audit trail."""
    audit_entry = AuditLog(
        user_id=admin_user_id,
        action=f"admin:{action}",
        entity_type=target_type,
        entity_id=target_id,
        is_success=True,
        details=details,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    db.add(audit_entry)
    db.flush()
    
    logger.info(
        "Admin action: admin=%d action=%s target=%s:%s",
        admin_user_id, action, target_type, target_id,
    )
    
    return audit_entry


def log_resource_access(
    db: Session,
    *,
    user_id: int,
    resource_type: str,
    resource_id: int,
    action: str,
    is_owner: bool,
    ip_address: Optional[str] = None,
) -> AuditLog:
    """Log a resource access attempt."""
    audit_entry = AuditLog(
        user_id=user_id,
        action=f"access:{action}",
        entity_type=resource_type,
        entity_id=resource_id,
        is_success=True,
        is_owner=is_owner,
        ip_address=ip_address,
    )
    db.add(audit_entry)
    db.flush()
    
    return audit_entry


def get_recent_denials(
    db: Session,
    *,
    user_id: Optional[int] = None,
    resource: Optional[str] = None,
    minutes: int = 60,
    limit: int = 100,
) -> list[AuditLog]:
    """Get recent authorization denials for monitoring."""
    since = datetime.now(timezone.utc) - __import__("datetime").timedelta(minutes=minutes)
    
    query = db.query(AuditLog).filter(
        AuditLog.is_success == False,  # noqa: E712
        AuditLog.created_at >= since,
    )
    
    if user_id is not None:
        query = query.filter(AuditLog.user_id == user_id)
    if resource is not None:
        query = query.filter(AuditLog.entity_type == resource)
    
    return query.order_by(AuditLog.created_at.desc()).limit(limit).all()


def get_user_access_history(
    db: Session,
    *,
    user_id: int,
    limit: int = 50,
) -> list[AuditLog]:
    """Get a user's recent access history."""
    return (
        db.query(AuditLog)
        .filter(AuditLog.user_id == user_id)
        .order_by(AuditLog.created_at.desc())
        .limit(limit)
        .all()
    )


def detect_suspicious_activity(
    db: Session,
    *,
    user_id: int,
    threshold: int = 10,
    minutes: int = 5,
) -> bool:
    """Detect suspicious authorization activity (many denials in short time)."""
    since = datetime.now(timezone.utc) - __import__("datetime").timedelta(minutes=minutes)
    
    denial_count = (
        db.query(AuditLog)
        .filter(
            AuditLog.user_id == user_id,
            AuditLog.is_success == False,  # noqa: E712
            AuditLog.created_at >= since,
        )
        .count()
    )
    
    if denial_count >= threshold:
        logger.warning(
            "Suspicious activity detected: user=%d denials=%d in %d minutes",
            user_id, denial_count, minutes,
        )
        return True
    
    return False
