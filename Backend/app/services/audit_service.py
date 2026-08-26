"""Phase 29 — Tamper-evident audit log service.

Every critical action writes an ``AuditLog`` row whose ``record_hash`` covers
its content AND the previous record's hash (a blockchain-style chain). Any
casual modification — by a normal user or even a stray UPDATE statement —
breaks the linkage and is detected by :func:`verify_audit_chain`.

Immutability rules:
    * No update/delete path exists for audit entries. The service exposes
      explicit rejection helpers that raise ``ForbiddenError``.
    * Attempting to write an UPDATE/DELETE audit record against the
      AUDIT_LOG entity itself is refused (no self-modifying trails).
    * Reading audit data stays behind admin permissions
      (``require_admin_permission("audit_log", "read")``) in the API layer.

Privacy: only surrogate ids, action metadata and IP are recorded — never
contact details, tokens or precise location.
"""
from __future__ import annotations

import hashlib
import json
from datetime import datetime

from sqlalchemy.orm import Session

from app.core.exceptions import ForbiddenError
from app.models.admin import AuditLog

GENESIS_HASH = "0" * 64


def _canonical(payload: dict) -> bytes:
    return json.dumps(payload, sort_keys=True, separators=(",", ":"), default=str).encode()


def _compute_record_hash(
    *,
    entry_id: int,
    user_id: int | None,
    action: str,
    entity_type: str,
    entity_id: int | None,
    old_values: dict | None,
    new_values: dict | None,
    description: str | None,
    ip_address: str | None,
    request_id: str | None,
    created_at: datetime,
    prev_hash: str,
) -> str:
    payload = {
        "id": entry_id,
        "user_id": user_id,
        "action": action,
        "entity_type": entity_type,
        "entity_id": entity_id,
        "old_values": old_values,
        "new_values": new_values,
        "description": description,
        "ip_address": ip_address,
        "request_id": request_id,
        "created_at": created_at.isoformat() if created_at else None,
        "prev_record_hash": prev_hash,
    }
    return hashlib.sha256(_canonical(payload)).hexdigest()


def record_critical_action(
    db: Session,
    *,
    action: str,
    entity_type: str,
    entity_id: int | None = None,
    user_id: int | None = None,
    old_values: dict | None = None,
    new_values: dict | None = None,
    description: str | None = None,
    ip_address: str | None = None,
    user_agent: str | None = None,
    request_id: str | None = None,
) -> AuditLog:
    """Persist an immutable, hash-chained audit record for a critical action."""
    if entity_type.upper() == "AUDIT_LOG" and action.upper() in {"UPDATE", "DELETE"}:
        raise ForbiddenError("Audit log entries can never be modified or deleted")

    last = db.query(AuditLog.record_hash).order_by(AuditLog.id.desc()).first()
    prev_hash = last[0] if last and last[0] else GENESIS_HASH

    entry = AuditLog(
        user_id=user_id,
        action=action.upper(),
        entity_type=entity_type.upper(),
        entity_id=entity_id,
        old_values=old_values,
        new_values=new_values,
        description=description,
        ip_address=ip_address[:45] if ip_address else None,
        user_agent=user_agent[:255] if user_agent else None,
        request_id=request_id,
        prev_record_hash=prev_hash,
    )
    db.add(entry)
    db.flush()  # assigns id + created_at defaults

    entry.record_hash = _compute_record_hash(
        entry_id=entry.id,
        user_id=entry.user_id,
        action=entry.action,
        entity_type=entry.entity_type,
        entity_id=entry.entity_id,
        old_values=entry.old_values,
        new_values=entry.new_values,
        description=entry.description,
        ip_address=entry.ip_address,
        request_id=entry.request_id,
        created_at=entry.created_at,
        prev_hash=entry.prev_record_hash,
    )
    db.flush()
    return entry


# ── Immutability enforcement ─────────────────────────────────────────────────
def update_audit_entry(*_args, **_kwargs):
    """Audit records are immutable — no caller may ever reach this path."""
    raise ForbiddenError("Audit log entries are immutable")


delete_audit_entry = update_audit_entry


def assert_no_direct_mutation(user_role_name: str | None = None) -> None:
    """Guard rail for any future code path touching audit rows.

    Even administrators cannot casually rewrite history: there is no role,
    including ``admin``, under which editing or removing an audit entry is a
    supported operation.
    """
    raise ForbiddenError(
        f"Audit logs cannot be modified by {user_role_name or 'any user'}"
    )


# ── Chain verification ───────────────────────────────────────────────────────
def verify_audit_chain(db: Session) -> dict:
    """Recompute every record hash and validate chain linkage.

    Returns ``{"valid", "checked", "total", "broken_at"}`` where
    ``broken_at`` is the id of the first tampered/linked-broken record.
    """
    entries = db.query(AuditLog).order_by(AuditLog.id.asc()).all()
    expected_prev = GENESIS_HASH
    checked = 0
    broken_at = None

    for entry in entries:
        if entry.prev_record_hash != expected_prev:
            broken_at = entry.id
            break
        recomputed = _compute_record_hash(
            entry_id=entry.id,
            user_id=entry.user_id,
            action=entry.action,
            entity_type=entry.entity_type,
            entity_id=entry.entity_id,
            old_values=entry.old_values,
            new_values=entry.new_values,
            description=entry.description,
            ip_address=entry.ip_address,
            request_id=entry.request_id,
            created_at=entry.created_at,
            prev_hash=entry.prev_record_hash,
        )
        if recomputed != entry.record_hash:
            broken_at = entry.id
            break
        expected_prev = entry.record_hash
        checked += 1

    total = len(entries)
    if broken_at is not None:
        return {"valid": False, "checked": checked, "total": total, "broken_at": broken_at}
    return {"valid": True, "checked": total, "total": total, "broken_at": None}