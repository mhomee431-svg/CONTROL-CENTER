"""Admin Merchant Onboarding Review API routes.

/api/v1/admin/merchant-onboarding/*

All endpoints require admin authentication with appropriate permissions.
"""
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.dependencies import require_admin_permission
from app.core.responses import error_response, success_response
from app.database.session import get_db
from app.models.user import User
from app.schemas.merchant_onboarding import AdminOnboardingReviewRequest
from app.services import admin_merchant_review_service

logger = __import__("app.core.logging", fromlist=["get_logger"]).get_logger(
    "app.api.admin_merchant_onboarding"
)

router = APIRouter(prefix="/admin/merchant-onboarding", tags=["admin-merchant-onboarding"])


@router.get("")
def list_pending_onboardings(
    status: str | None = Query(None),
    category_code: str | None = Query(None),
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    _: User = Depends(require_admin_permission("merchant_onboarding", "read")),
    db: Session = Depends(get_db),
):
    """List merchant onboardings pending admin review."""
    items, total = admin_merchant_review_service.list_pending_onboardings(
        db, _, status=status, category_code=category_code,
        limit=limit, offset=offset,
    )
    return success_response(
        data={"items": items, "total": total, "limit": limit, "offset": offset},
        message="OK",
    )


@router.get("/{onboarding_id}")
def get_onboarding_detail(
    onboarding_id: int,
    _: User = Depends(require_admin_permission("merchant_onboarding", "read")),
    db: Session = Depends(get_db),
):
    """Get full onboarding detail for admin review."""
    detail = admin_merchant_review_service.get_onboarding_detail(db, _, onboarding_id)
    return success_response(data=detail, message="OK")


@router.post("/{onboarding_id}/review")
def review_onboarding(
    onboarding_id: int,
    payload: AdminOnboardingReviewRequest,
    current_user: User = Depends(require_admin_permission("merchant_onboarding", "review")),
    db: Session = Depends(get_db),
):
    """Admin review decision on a merchant onboarding.

    Actions: APPROVE, REJECT, REQUEST_RESUBMISSION, SUSPEND
    """
    onboarding = admin_merchant_review_service.review_onboarding(
        db, current_user, onboarding_id,
        decision=payload.decision,
        reason=payload.reason,
        notes=payload.notes,
    )
    db.commit()
    return success_response(
        data={
            "onboarding_id": onboarding.id,
            "status": onboarding.status.value,
            "next_action": onboarding.next_action,
            "admin_reviewed": onboarding.admin_reviewed,
        },
        message=f"Onboarding {payload.decision.lower()} successful",
    )
