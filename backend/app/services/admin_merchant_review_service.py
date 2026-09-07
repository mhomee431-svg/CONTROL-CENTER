"""Admin Review Service for Merchant Onboarding.

Handles admin review workflow for merchant verification.
Admins can approve, reject, request resubmission, or suspend.
"""
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy.orm import Session

from app.core.exceptions import (
    ConflictError,
    ForbiddenError,
    NotFoundError,
    ValidationError,
)
from app.core.logging import get_logger
from app.models.admin import AdminAction, AuditLog
from app.models.merchant_onboarding import (
    MerchantOnboarding,
    OnboardingStatus,
    VALID_ONBOARDING_TRANSITIONS,
)
from app.models.user import User

logger = get_logger("app.services.admin_merchant_review")


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _validate_transition(
    current: OnboardingStatus, target: OnboardingStatus
) -> bool:
    valid_targets = VALID_ONBOARDING_TRANSITIONS.get(current, [])
    return target in valid_targets


def list_pending_onboardings(
    db: Session,
    admin_user: User,
    status: Optional[str] = None,
    category_code: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
) -> tuple[list[dict], int]:
    query = db.query(MerchantOnboarding).filter(
        MerchantOnboarding.status.in_([
            OnboardingStatus.PENDING_ADMIN_REVIEW,
            OnboardingStatus.CATEGORY_DOCUMENTS_VERIFIED,
        ])
    )
    if status:
        try:
            query = query.filter(
                MerchantOnboarding.status == OnboardingStatus(status)
            )
        except ValueError:
            raise ValidationError(f"Invalid status filter: {status}")
    if category_code:
        query = query.filter(
            MerchantOnboarding.category_code == category_code
        )
    total = query.count()
    items = (
        query.order_by(MerchantOnboarding.created_at.asc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    result = []
    for item in items:
        result.append({
            "onboarding_id": item.id,
            "business_id": item.shop_id,
            "business_name": item.shop.name if item.shop else None,
            "category_code": item.category_code,
            "status": item.status.value,
            "phone_verified": item.phone_verified,
            "identity_verified": item.identity_verified,
            "bank_verified": item.bank_verified,
            "category_verified": item.category_verified,
            "submitted_at": item.updated_at.isoformat() if item.updated_at else None,
        })
    return result, total


def get_onboarding_detail(
    db: Session, admin_user: User, onboarding_id: int
) -> dict:
    onboarding = db.query(MerchantOnboarding).filter(
        MerchantOnboarding.id == onboarding_id
    ).first()
    if not onboarding:
        raise NotFoundError("Onboarding not found")
    identity_vers = [
        {
            "type": iv.verification_type.value,
            "status": iv.status.value,
            "provider": iv.provider,
            "reference_id": iv.provider_reference_id,
            "verified_name": iv.verified_name,
            "attempt_number": iv.attempt_number,
        }
        for iv in onboarding.identity_verifications
        if iv.is_latest_attempt
    ]
    bank_vers = [
        {
            "status": bv.status,
            "provider": bv.provider,
            "reference_id": bv.provider_reference_id,
            "account_last_four": bv.account_number_last_four,
            "ifsc_code": bv.ifsc_code,
            "attempt_number": bv.attempt_number,
        }
        for bv in onboarding.bank_verifications
        if bv.is_latest_attempt
    ]
    category_vers = [
        {
            "document_type": cv.document_type,
            "status": cv.status,
            "provider": cv.provider,
            "reference_id": cv.provider_reference_id,
            "requires_admin_review": cv.requires_admin_review,
            "attempt_number": cv.attempt_number,
        }
        for cv in onboarding.category_verifications
        if cv.is_latest_attempt
    ]
    recent_attempts = [
        {
            "type": a.attempt_type.value,
            "status": a.status.value,
            "provider": a.provider_code,
            "reference_id": a.provider_reference_id,
            "created_at": a.created_at.isoformat() if a.created_at else None,
        }
        for a in sorted(
            onboarding.verification_attempts,
            key=lambda x: x.created_at or datetime.min.replace(tzinfo=timezone.utc),
            reverse=True,
        )[:10]
    ]
    return {
        "onboarding_id": onboarding.id,
        "business_id": onboarding.shop_id,
        "business_name": onboarding.shop.name if onboarding.shop else None,
        "owner_id": onboarding.user_id,
        "category_code": onboarding.category_code,
        "status": onboarding.status.value,
        "phone_verified": onboarding.phone_verified,
        "identity_verified": onboarding.identity_verified,
        "bank_verified": onboarding.bank_verified,
        "category_verified": onboarding.category_verified,
        "identity_verifications": identity_vers,
        "bank_verifications": bank_vers,
        "category_verifications": category_vers,
        "verification_attempts": recent_attempts,
        "rejection_reason": onboarding.rejection_reason,
        "admin_reviewed": onboarding.admin_reviewed,
        "admin_review_notes": onboarding.admin_review_notes,
        "created_at": onboarding.created_at.isoformat() if onboarding.created_at else None,
        "updated_at": onboarding.updated_at.isoformat() if onboarding.updated_at else None,
    }


def review_onboarding(
    db: Session,
    admin_user: User,
    onboarding_id: int,
    decision: str,
    reason: Optional[str] = None,
    notes: Optional[str] = None,
) -> MerchantOnboarding:
    onboarding = db.query(MerchantOnboarding).filter(
        MerchantOnboarding.id == onboarding_id
    ).first()
    if not onboarding:
        raise NotFoundError("Onboarding not found")
    valid_decisions = {"APPROVE", "REJECT", "REQUEST_RESUBMISSION", "SUSPEND"}
    if decision not in valid_decisions:
        raise ValidationError(f"Invalid decision: {decision}")
    if decision == "REJECT" and not reason:
        raise ValidationError("Rejection requires a reason")
    status_map = {
        "APPROVE": OnboardingStatus.VERIFIED,
        "REJECT": OnboardingStatus.REJECTED,
        "REQUEST_RESUBMISSION": OnboardingStatus.RESUBMISSION_REQUIRED,
        "SUSPEND": OnboardingStatus.SUSPENDED,
    }
    target_status = status_map[decision]
    if not _validate_transition(onboarding.status, target_status):
        raise ValidationError(
            f"Cannot transition from {onboarding.status.value} to {target_status.value}"
        )
    onboarding.status = target_status
    onboarding.admin_reviewed = True
    onboarding.admin_reviewed_at = _utcnow()
    onboarding.admin_reviewed_by = admin_user.id
    onboarding.admin_review_notes = notes
    if decision == "REJECT":
        onboarding.rejection_reason = reason
        onboarding.rejection_code = "ADMIN_REJECTED"
        onboarding.next_action = "RESUBMIT"
    elif decision == "APPROVE":
        onboarding.category_verified = True
        onboarding.category_verified_at = _utcnow()
        onboarding.next_action = "ONBOARDING_COMPLETE"
    elif decision == "REQUEST_RESUBMISSION":
        onboarding.rejection_reason = reason
        onboarding.next_action = "RESUBMIT_REQUIRED"
    elif decision == "SUSPEND":
        onboarding.next_action = "CONTACT_SUPPORT"
    # Record admin action
    desc_text = notes or reason or "No notes"
    admin_action = AdminAction(
        admin_user_id=admin_user.id,
        action_type=f"MERCHANT_{decision}",
        target_type="MERCHANT_ONBOARDING",
        target_id=onboarding.id,
        action_data={
            "decision": decision,
            "reason": reason,
            "notes": notes,
            "from_status": onboarding.status.value,
            "to_status": target_status.value,
        },
        description=f"Merchant onboarding {decision}: {desc_text}",
    )
    db.add(admin_action)
    # Record audit
    audit = AuditLog(
        user_id=admin_user.id,
        action=f"MERCHANT_ONBOARDING_{decision}",
        entity_type="merchant_onboarding",
        entity_id=onboarding.id,
        description=f"Admin {decision} for onboarding {onboarding_id}",
        is_success=True,
    )
    db.add(audit)
    logger.info(
        "Admin %s reviewed onboarding %s: decision=%s",
        admin_user.id,
        onboarding_id,
        decision,
    )
    db.flush()
    return onboarding
