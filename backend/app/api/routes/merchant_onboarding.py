"""Merchant Onboarding API routes — Shopkeeper endpoints.

/api/v1/shopkeeper/businesses/*

All endpoints require shopkeeper authentication and business ownership.
"""
from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.core.exceptions import AppError, ForbiddenError
from app.core.responses import error_response, success_response
from app.database.session import get_db
from app.models.merchant_onboarding import MerchantOnboarding
from app.models.user import User
from app.schemas.merchant_onboarding import (
    AdminOnboardingListItem,
    AdminOnboardingReviewRequest,
    BankVerificationRequest,
    CategoryDocumentsRequest,
    IdentityVerificationRequest,
    MerchantOnboardingRequest,
    OnboardingStatusResponse,
)
from app.services import merchant_onboarding_service

logger = __import__("app.core.logging", fromlist=["get_logger"]).get_logger(
    "app.api.merchant_onboarding"
)

router = APIRouter(prefix="/shopkeeper/businesses", tags=["merchant-onboarding"])


def _get_onboarding_for_user(
    db: Session, user: User, business_id: int
) -> MerchantOnboarding:
    """Get onboarding record and verify ownership."""
    onboarding = (
        db.query(MerchantOnboarding)
        .filter(MerchantOnboarding.shop_id == business_id)
        .first()
    )
    if not onboarding:
        raise AppError("Onboarding not found", "NOT_FOUND", 404)
    if onboarding.user_id != user.id:
        raise ForbiddenError("Not authorized to access this business")
    return onboarding


@router.post("/{business_id}/onboarding", status_code=201)
async def start_onboarding(
    business_id: int,
    payload: MerchantOnboardingRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Start merchant onboarding for a business.

    Creates an onboarding record and initiates the verification flow.
    Idempotent — returns existing onboarding if already started.
    """
    onboarding = merchant_onboarding_service.get_or_create_onboarding(
        db=db,
        user=current_user,
        shop_id=business_id,
        category_code=payload.category_code,
        idempotency_key=payload.idempotency_key,
    )

    # If newly created, update with initial data from payload
    if onboarding.status.value == "DRAFT":
        # Update category details if provided
        if payload.category_details:
            onboarding.category_details = payload.category_details
        db.commit()

    return success_response(
        data={
            "onboarding_id": onboarding.id,
            "business_id": business_id,
            "status": onboarding.status.value,
            "next_action": onboarding.next_action,
            "category_code": onboarding.category_code,
        },
        message="Onboarding started",
        status_code=201,
    )


@router.get("/{business_id}/onboarding-status")
async def get_onboarding_status(
    business_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Get current onboarding status and next action."""
    onboarding = _get_onboarding_for_user(db, current_user, business_id)
    status = merchant_onboarding_service.get_onboarding_status(
        db, onboarding, current_user
    )
    return success_response(data=status, message="OK")


@router.get("/{business_id}/verification/requirements")
async def get_verification_requirements(
    business_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Get verification requirements for the business category."""
    onboarding = _get_onboarding_for_user(db, current_user, business_id)
    requirements = merchant_onboarding_service.get_category_requirements(
        db, onboarding.category_code
    )
    return success_response(
        data={
            "category_code": onboarding.category_code,
            "requirements": [
                {
                    "requirement_code": r.requirement_code,
                    "requirement_name": r.requirement_name,
                    "is_required": r.is_required,
                    "verification_method": r.verification_method,
                    "requires_admin_review": r.requires_admin_review,
                }
                for r in requirements
            ],
        },
        message="OK",
    )


@router.post("/{business_id}/verification/phone")
async def verify_phone(
    business_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Mark phone as verified (phone OTP done via Firebase client-side)."""
    onboarding = _get_onboarding_for_user(db, current_user, business_id)
    onboarding = merchant_onboarding_service.verify_phone(
        db, onboarding, current_user
    )
    db.commit()
    return success_response(
        data={
            "onboarding_id": onboarding.id,
            "status": onboarding.status.value,
            "next_action": onboarding.next_action,
            "phone_verified": onboarding.phone_verified,
        },
        message="Phone verified",
    )


@router.post("/{business_id}/verification/identity")
async def submit_identity(
    business_id: int,
    payload: IdentityVerificationRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Submit GSTIN/UDYAM for verification."""
    if not payload.gstin and not payload.udyam_number:
        return error_response(
            message="Please provide either GSTIN or UDYAM number",
            error_code="MISSING_IDENTITY",
            status_code=400,
        )

    onboarding = _get_onboarding_for_user(db, current_user, business_id)
    result = merchant_onboarding_service.submit_identity_verification(
        db, onboarding, current_user,
        gstin=payload.gstin, udyam_number=payload.udyam_number,
    )
    db.commit()

    onboarding = result["onboarding"]
    return success_response(
        data={
            "onboarding_id": onboarding.id,
            "status": onboarding.status.value,
            "next_action": onboarding.next_action,
            "identity_verified": onboarding.identity_verified,
            "results": result["results"],
        },
        message="Identity verification submitted",
    )


@router.post("/{business_id}/verification/bank")
async def submit_bank(
    business_id: int,
    payload: BankVerificationRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Submit bank account for penny-drop verification."""
    onboarding = _get_onboarding_for_user(db, current_user, business_id)
    result = merchant_onboarding_service.submit_bank_verification(
        db, onboarding, current_user,
        account_number=payload.account_number,
        ifsc_code=payload.ifsc_code,
        account_holder_name=payload.account_holder_name,
    )
    db.commit()

    onboarding = result["onboarding"]
    return success_response(
        data={
            "onboarding_id": onboarding.id,
            "status": onboarding.status.value,
            "next_action": onboarding.next_action,
            "bank_verified": onboarding.bank_verified,
            "result": result["result"],
        },
        message="Bank verification submitted",
    )


@router.post("/{business_id}/verification/category")
async def submit_category_documents(
    business_id: int,
    payload: CategoryDocumentsRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Submit category-specific documents for verification."""
    onboarding = _get_onboarding_for_user(db, current_user, business_id)
    result = merchant_onboarding_service.submit_category_documents(
        db, onboarding, current_user,
        category_details=payload.category_details,
    )
    db.commit()

    onboarding = result["onboarding"]
    return success_response(
        data={
            "onboarding_id": onboarding.id,
            "status": onboarding.status.value,
            "next_action": onboarding.next_action,
            "category_verified": onboarding.category_verified,
            "results": result["results"],
        },
        message="Category documents submitted",
    )


@router.post("/{business_id}/verification/retry")
async def retry_verification(
    business_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retry the current failed verification step."""
    onboarding = _get_onboarding_for_user(db, current_user, business_id)

    if onboarding.status.value not in ("IDENTITY_PENDING", "BANK_PENDING", "CATEGORY_DOCUMENTS_PENDING", "RESUBMISSION_REQUIRED"):
        return error_response(
            message=f"Cannot retry from status: {onboarding.status.value}",
            error_code="INVALID_STATE",
            status_code=400,
        )

    # Move back to the appropriate pending state for retry
    from app.models.merchant_onboarding import OnboardingStatus
    if onboarding.status == OnboardingStatus.RESUBMISSION_REQUIRED:
        onboarding.status = OnboardingStatus.DRAFT
        onboarding.next_action = "VERIFY_PHONE"

    db.commit()
    return success_response(
        data={
            "onboarding_id": onboarding.id,
            "status": onboarding.status.value,
            "next_action": onboarding.next_action,
        },
        message="Ready to retry verification",
    )
