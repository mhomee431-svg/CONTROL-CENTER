"""Upload audit logging service.

Logs all file upload events for security auditing and compliance.
"""
import logging
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy.orm import Session

from app.models.admin import AuditLog

logger = logging.getLogger("app.services.upload_audit")


def log_upload_attempt(
    db: Session,
    *,
    user_id: int,
    filename: str,
    content_type: str,
    size_bytes: int,
    category: str,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> AuditLog:
    """Log a file upload attempt."""
    audit_entry = AuditLog(
        user_id=user_id,
        action="upload:attempt",
        entity_type="media",
        is_success=True,
        details={
            "filename": filename,
            "content_type": content_type,
            "size_bytes": size_bytes,
            "category": category,
        },
        ip_address=ip_address,
        user_agent=user_agent,
    )
    db.add(audit_entry)
    db.flush()
    return audit_entry


def log_upload_success(
    db: Session,
    *,
    user_id: int,
    key: str,
    filename: str,
    content_type: str,
    size_bytes: int,
    ip_address: Optional[str] = None,
) -> AuditLog:
    """Log a successful file upload."""
    audit_entry = AuditLog(
        user_id=user_id,
        action="upload:success",
        entity_type="media",
        is_success=True,
        details={
            "key": key,
            "filename": filename,
            "content_type": content_type,
            "size_bytes": size_bytes,
        },
        ip_address=ip_address,
    )
    db.add(audit_entry)
    db.flush()
    
    logger.info("Upload success: user=%d key=%s size=%d", user_id, key, size_bytes)
    return audit_entry


def log_upload_rejected(
    db: Session,
    *,
    user_id: int,
    filename: str,
    reason: str,
    reason_code: str,
    ip_address: Optional[str] = None,
) -> AuditLog:
    """Log a rejected file upload."""
    audit_entry = AuditLog(
        user_id=user_id,
        action="upload:rejected",
        entity_type="media",
        is_success=False,
        reason=reason,
        details={
            "filename": filename,
            "reason_code": reason_code,
        },
        ip_address=ip_address,
    )
    db.add(audit_entry)
    db.flush()
    
    logger.warning(
        "Upload rejected: user=%d file=%s reason=%s",
        user_id, filename, reason,
    )
    return audit_entry


def log_upload_scan(
    db: Session,
    *,
    user_id: int,
    key: str,
    is_clean: bool,
    scanner: str,
    threats: list[str] | None = None,
) -> AuditLog:
    """Log a virus scan result."""
    audit_entry = AuditLog(
        user_id=user_id,
        action="upload:scan",
        entity_type="media",
        is_success=is_clean,
        details={
            "key": key,
            "scanner": scanner,
            "threats": threats or [],
        },
    )
    db.add(audit_entry)
    db.flush()
    
    if not is_clean:
        logger.warning(
            "Upload scan failed: user=%d key=%s threats=%s",
            user_id, key, threats,
        )
    
    return audit_entry


def log_media_access(
    db: Session,
    *,
    user_id: int,
    key: str,
    action: str,  # read, delete, attach
    ip_address: Optional[str] = None,
) -> AuditLog:
    """Log media access (read, delete, attach)."""
    audit_entry = AuditLog(
        user_id=user_id,
        action=f"media:{action}",
        entity_type="media",
        is_success=True,
        details={"key": key},
        ip_address=ip_address,
    )
    db.add(audit_entry)
    db.flush()
    return audit_entry
