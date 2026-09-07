"""Merchant Onboarding Service — Core orchestration layer.

Orchestrates the tiered merchant onboarding flow:
  DRAFT → PHONE_VERIFIED → IDENTITY_PENDING → BANK_PENDING
  → CATEGORY_DOCUMENTS_PENDING → PENDING_ADMIN_REVIEW → VERIFIED

All state transitions are validated. Provider failures are handled gracefully
with PENDING_ADMIN_REVIEW fallback.
"""
import hashlib
import uuid
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy.orm import Session

from app.core.exceptions import (
    AppError,
    ConflictError,
    ForbiddenError,
    NotFoundError,
    ValidationError,
)
from app.core.logging import get_logger
from app.models.admin import AuditLog
from app.models.merchant_category import (
    MerchantCategory,
    MerchantCategoryCode,
    MerchantVerificationRequirement,
)
from app.models.merchant_onboarding import (
    MerchantOnboarding,
    OnboardingStatus,
    VALID_ONBOARDING_TRANSITIONS,
)
from app.models.shop import Shop, ShopOwner
from app.models.user import User
from app.services.identity_provider import (
    IdentityVerificationResult,
    get_identity_provider,
)
from app.services.bank_provider import (
    BankVerificationResult,
    get_bank_provider,
)
from app.services.category_provider import (
    CategoryVerificationResult,
    get_category_provider,
)

logger = get_logger("app.services.merchant_onboarding")


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _generate_idempotency_key() -> str:
    return str(uuid.uuid4())


def _hash_identifier(identifier: str) -> str:
    """Create a hash for deduplication without storing raw value."""
    return hashlib.sha256(identifier.encode()).hexdigest()


def _mask_last_four(value: str) -> str:
    """Extract last 4 digits/characters for display."""
    if not value or len(value) < 4:
        return "****"
    return value[-4:]


def _validate_transition(
    current: OnboardingStatus, target: OnboardingStatus
) -> bool:
    """Check if a state transition is valid."""
    valid_targets = VALID_ONBOARDING_TRANSITIONS.get(current, [])
    return target in valid_targets


def get_category_requirements(
    db: Session, category_code: str
) -> list[MerchantVerificationRequirement]:
    """Get active verification requirements for a category."""
    category = (
        db.query(MerchantCategory)
        .filter(
            MerchantCategory.code == category_code,
            MerchantCategory.is_active == True,  # noqa: E712
        )
        .first()
    )
    if not category:
        return []

    return (
        db.query(MerchantVerificationRequirement)
        .filter(
            MerchantVerificationRequirement.category_id == category.id,
            MerchantVerificationRequirement.is_active == True,  # noqa: E712
        )
        .order_by(MerchantVerificationRequirement.sort_order)
        .all()
    )


def resolve_required_steps(
    db: Session, category_code: str
) -> dict[str, bool]:
    """Resolve which verification steps are required for a category."""
    requirements = get_category_requirements(db, category_code)
    steps = {
        "phone_otp": False,
        "identity_verification": False,
        "bank_verification": False,
        "category_documents": False,
        "admin_review": False,
    }

    for req in requirements:
        if req.is_required:
            if req.verification_method in ("PHONE_OTP",):
                steps["phone_otp"] = True
            elif req.verification_method in ("GSTIN_VERIFY", "UDYAM_VERIFY"):
                steps["identity_verification"] = True
            elif req.verification_method in ("BANK_PENNY_DROP",):
                steps["bank_verification"] = True
            elif req.verification_method in (
                "DRUG_LICENSE_VERIFY",
                "FSSAI_LICENSE_VERIFY",
                "DRIVING_LICENSE_VERIFY",
                "VEHICLE_RC_VERIFY",
            ):
                steps["category_documents"] = True

        if req.requires_admin_review:
            steps["admin_review"] = True

    return steps


def get_or_create_onboarding(
    db: Session,
    user: User,
    shop_id: int,
    category_code: str,
    idempotency_key: Optional[str] = None,
) -> MerchantOnboarding:
    """Get existing onboarding or create a new one.

    Prevents duplicate onboarding via idempotency key.
    """
    # Check for existing onboarding
    existing = (
        db.query(MerchantOnboarding)
        .filter(MerchantOnboarding.shop_id == shop_id)
        .first()
    )
    if existing:
        # Verify ownership
        if existing.user_id != user.id:
            raise ForbiddenError("Not authorized to access this business")
        return existing

    # Check idempotency key
    if idempotency_key:
        existing_by_key = (
            db.query(MerchantOnboarding)
            .filter(MerchantOnboarding.idempotency_key == idempotency_key)
            .first()
        )
        if existing_by_key:
            return existing_by_key

    # Validate category exists
    category = (
        db.query(MerchantCategory)
        .filter(MerchantCategory.code == category_code)
        .first()
    )
    if not category:
        raise ValidationError(f"Invalid category code: {category_code}")

    # Verify shop exists and user owns it
    shop = (
        db.query(Shop)
        .filter(Shop.id == shop_id, Shop.is_deleted == False)  # noqa: E712
        .first()
    )
    if not shop:
        raise NotFoundError("Shop not found")

    owner = (
        db.query(ShopOwner)
        .filter(
            ShopOwner.shop_id == shop_id,
            ShopOwner.user_id == user.id,
            ShopOwner.is_active == True,  # noqa: E712
        )
        .first()
    )
    if not owner:
        raise ForbiddenError("Not authorized — not an owner of this shop")

    # Create new onboarding
    onboarding = MerchantOnboarding(
        shop_id=shop_id,
        user_id=user.id,
        category_code=category_code,
        status=OnboardingStatus.DRAFT,
        idempotency_key=idempotency_key or _generate_idempotency_key(),
        next_action="VERIFY_PHONE",
    )
    db.add(onboarding)
    db.flush()

    logger.info(
        "Merchant onboarding created: id=%s shop=%s category=%s user=%s",
        onboarding.id,
        shop_id,
        category_code,
        user.id,
    )

    return onboarding


def verify_phone(
    db: Session, onboarding: MerchantOnboarding, user: User
) -> MerchantOnboarding:
    """Mark phone as verified (phone OTP done via Firebase client-side)."""
    if onboarding.user_id != user.id:
        raise ForbiddenError("Not authorized")

    if not _validate_transition(onboarding.status, OnboardingStatus.PHONE_VERIFIED):
        raise ValidationError(
            f"Cannot verify phone from status: {onboarding.status.value}"
        )

    onboarding.phone_verified = True
    onboarding.phone_verified_at = _utcnow()
    onboarding.status = OnboardingStatus.PHONE_VERIFIED
    onboarding.next_action = "VERIFY_IDENTITY"

    _record_audit(db, user.id, "PHONE_VERIFIED", "merchant_onboarding", onboarding.id)
    db.flush()
    return onboarding


def submit_identity_verification(
    db: Session,
    onboarding: MerchantOnboarding,
    user: User,
    gstin: Optional[str] = None,
    udyam_number: Optional[str] = None,
) -> dict:
    """Submit GSTIN/UDYAM for verification."""
    if onboarding.user_id != user.id:
        raise ForbiddenError("Not authorized")

    if onboarding.status not in (
        OnboardingStatus.PHONE_VERIFIED,
        OnboardingStatus.IDENTITY_PENDING,
        OnboardingStatus.RESUBMISSION_REQUIRED,
    ):
        raise ValidationError(
            f"Cannot verify identity from status: {onboarding.status.value}"
        )

    from app.models.business_identity_verification import (
        BusinessIdentityVerification,
        IdentityVerificationStatus,
        IdentityVerificationType,
    )
    from app.models.verification_attempt import (
        VerificationAttempt,
        VerificationAttemptStatus,
        VerificationAttemptType,
    )

    onboarding.status = OnboardingStatus.IDENTITY_PENDING
    results = {}

    provider = get_identity_provider()

    # Verify GSTIN if provided
    if gstin:
        # Validate format
        if not provider.validate_gstin_format(gstin):
            raise ValidationError(
                "Invalid GSTIN format. Expected 15 characters.",
                data={"field": "gstin"},
            )

        # Create verification record
        identity_ver = BusinessIdentityVerification(
            onboarding_id=onboarding.id,
            verification_type=IdentityVerificationType.GSTIN,
            identifier_hash=_hash_identifier(gstin.upper()),
            identifier_last_four=_mask_last_four(gstin),
            status=IdentityVerificationStatus.PENDING,
            provider=provider.name,
            attempt_number=_get_next_attempt_number(
                db, onboarding.id, "GSTIN_VERIFY"
            ),
        )
        db.add(identity_ver)
        db.flush()

        # Create attempt record
        attempt = VerificationAttempt(
            onboarding_id=onboarding.id,
            attempt_type=VerificationAttemptType.GSTIN_VERIFY,
            status=VerificationAttemptStatus.IN_PROGRESS,
            request_id=str(uuid.uuid4()),
            provider_code=provider.name,
        )
        db.add(attempt)
        db.flush()

        try:
            # Call provider
            result = provider.verify_gstin(gstin)

            # Update verification record
            identity_ver.status = IdentityVerificationStatus(result.status)
            identity_ver.provider_reference_id = result.reference_id
            identity_ver.verified_name = result.verified_name
            identity_ver.verified_at = result.verified_at
            identity_ver.failure_reason = result.failure_reason
            identity_ver.failure_code = result.failure_code

            # Update attempt
            attempt.status = (
                VerificationAttemptStatus.SUCCESS
                if result.status == "VERIFIED"
                else VerificationAttemptStatus.FAILED
            )
            attempt.completed_at = _utcnow()
            attempt.provider_reference_id = result.reference_id

            results["gstin"] = {
                "status": result.status,
                "reference_id": result.reference_id,
                "verified_name": result.verified_name,
                "failure_reason": result.failure_reason,
                "failure_code": result.failure_code,
            }

        except Exception as exc:
            logger.error("GSTIN verification error: %s", exc)
            identity_ver.status = IdentityVerificationStatus.FAILED
            identity_ver.failure_reason = str(exc)
            identity_ver.failure_code = "PROVIDER_ERROR"
            attempt.status = VerificationAttemptStatus.ERROR
            attempt.error_message = str(exc)
            attempt.completed_at = _utcnow()
            results["gstin"] = {
                "status": "FAILED",
                "failure_reason": "Provider error",
                "failure_code": "PROVIDER_ERROR",
            }

    # Verify UDYAM if provided
    if udyam_number:
        if not provider.validate_udyam_format(udyam_number):
            raise ValidationError(
                "Invalid UDYAM format. Expected UDYAM-XX-XXXXXXXXXX.",
                data={"field": "udyam_number"},
            )

        identity_ver = BusinessIdentityVerification(
            onboarding_id=onboarding.id,
            verification_type=IdentityVerificationType.UDYAM,
            identifier_hash=_hash_identifier(udyam_number.upper()),
            identifier_last_four=_mask_last_four(udyam_number),
            status=IdentityVerificationStatus.PENDING,
            provider=provider.name,
            attempt_number=_get_next_attempt_number(
                db, onboarding.id, "UDYAM_VERIFY"
            ),
        )
        db.add(identity_ver)
        db.flush()

        attempt = VerificationAttempt(
            onboarding_id=onboarding.id,
            attempt_type=VerificationAttemptType.UDYAM_VERIFY,
            status=VerificationAttemptStatus.IN_PROGRESS,
            request_id=str(uuid.uuid4()),
            provider_code=provider.name,
        )
        db.add(attempt)
        db.flush()

        try:
            result = provider.verify_udyam(udyam_number)

            identity_ver.status = IdentityVerificationStatus(result.status)
            identity_ver.provider_reference_id = result.reference_id
            identity_ver.verified_name = result.verified_name
            identity_ver.verified_at = result.verified_at
            identity_ver.failure_reason = result.failure_reason
            identity_ver.failure_code = result.failure_code

            attempt.status = (
                VerificationAttemptStatus.SUCCESS
                if result.status == "VERIFIED"
                else VerificationAttemptStatus.FAILED
            )
            attempt.completed_at = _utcnow()
            attempt.provider_reference_id = result.reference_id

            results["udyam"] = {
                "status": result.status,
                "reference_id": result.reference_id,
                "verified_name": result.verified_name,
                "failure_reason": result.failure_reason,
                "failure_code": result.failure_code,
            }

        except Exception as exc:
            logger.error("UDYAM verification error: %s", exc)
            identity_ver.status = IdentityVerificationStatus.FAILED
            identity_ver.failure_reason = str(exc)
            identity_ver.failure_code = "PROVIDER_ERROR"
            attempt.status = VerificationAttemptStatus.ERROR
            attempt.error_message = str(exc)
            attempt.completed_at = _utcnow()
            results["udyam"] = {
                "status": "FAILED",
                "failure_reason": "Provider error",
                "failure_code": "PROVIDER_ERROR",
            }

    # Determine next state
    any_verified = any(
        r.get("status") == "VERIFIED" for r in results.values()
    )
    any_pending = any(
        r.get("status") in ("PENDING", "UNABLE_TO_VERIFY") for r in results.values()
    )

    if any_verified:
        onboarding.identity_verified = True
        onboarding.identity_verified_at = _utcnow()
        onboarding.status = OnboardingStatus.IDENTITY_VERIFIED
        onboarding.next_action = "VERIFY_BANK"
    elif any_pending:
        onboarding.status = OnboardingStatus.IDENTITY_PENDING
        onboarding.next_action = "WAIT_FOR_IDENTITY_VERIFICATION"
    else:
        onboarding.status = OnboardingStatus.IDENTITY_PENDING
        onboarding.next_action = "RESUBMIT_IDENTITY"

    _record_audit(
        db, user.id, "IDENTITY_SUBMITTED", "merchant_onboarding", onboarding.id
    )
    db.flush()
    return {"onboarding": onboarding, "results": results}


def submit_bank_verification(
    db: Session,
    onboarding: MerchantOnboarding,
    user: User,
    account_number: str,
    ifsc_code: str,
    account_holder_name: str,
) -> dict:
    """Submit bank account for penny-drop verification."""
    if onboarding.user_id != user.id:
        raise ForbiddenError("Not authorized")

    if onboarding.status not in (
        OnboardingStatus.IDENTITY_VERIFIED,
        OnboardingStatus.BANK_PENDING,
        OnboardingStatus.RESUBMISSION_REQUIRED,
    ):
        raise ValidationError(
            f"Cannot verify bank from status: {onboarding.status.value}"
        )

    from app.models.business_identity_verification import BankAccountVerification
    from app.models.verification_attempt import (
        VerificationAttempt,
        VerificationAttemptStatus,
        VerificationAttemptType,
    )

    # Validate IFSC
    provider = get_bank_provider()
    if not provider.validate_ifsc_format(ifsc_code):
        raise ValidationError(
            "Invalid IFSC format.", data={"field": "ifsc_code"}
        )

    onboarding.status = OnboardingStatus.BANK_PENDING

    # Create verification record (NEVER store full account number)
    bank_ver = BankAccountVerification(
        onboarding_id=onboarding.id,
        account_number_hash=provider.hash_account_number(account_number),
        account_number_last_four=_mask_last_four(account_number),
        ifsc_code=ifsc_code.upper(),
        account_holder_name=account_holder_name,
        status="PENDING",
        provider=provider.name,
        attempt_number=_get_next_attempt_number(
            db, onboarding.id, "BANK_PENNY_DROP"
        ),
    )
    db.add(bank_ver)
    db.flush()

    # Create attempt
    attempt = VerificationAttempt(
        onboarding_id=onboarding.id,
        attempt_type=VerificationAttemptType.BANK_PENNY_DROP,
        status=VerificationAttemptStatus.IN_PROGRESS,
        request_id=str(uuid.uuid4()),
        provider_code=provider.name,
    )
    db.add(attempt)
    db.flush()

    try:
        result = provider.verify_bank_account(
            account_holder_name=account_holder_name,
            account_number=account_number,
            ifsc_code=ifsc_code,
        )

        bank_ver.status = result.status
        bank_ver.provider_reference_id = result.reference_id
        bank_ver.verified_at = result.verified_at
        bank_ver.account_holder_name = result.verified_account_name or account_holder_name
        bank_ver.failure_reason = result.failure_reason
        bank_ver.failure_code = result.failure_code
        bank_ver.penny_drop_amount = result.penny_drop_amount

        attempt.status = (
            VerificationAttemptStatus.SUCCESS
            if result.status == "VERIFIED"
            else VerificationAttemptStatus.FAILED
        )
        attempt.completed_at = _utcnow()
        attempt.provider_reference_id = result.reference_id

        if result.status == "VERIFIED":
            onboarding.bank_verified = True
            onboarding.bank_verified_at = _utcnow()
            onboarding.status = OnboardingStatus.BANK_VERIFIED
            onboarding.next_action = "VERIFY_CATEGORY_DOCUMENTS"
        else:
            onboarding.status = OnboardingStatus.BANK_PENDING
            onboarding.next_action = "RESUBMIT_BANK"

        result_data = {
            "status": result.status,
            "reference_id": result.reference_id,
            "failure_reason": result.failure_reason,
            "failure_code": result.failure_code,
        }

    except Exception as exc:
        logger.error("Bank verification error: %s", exc)
        bank_ver.status = "FAILED"
        bank_ver.failure_reason = str(exc)
        bank_ver.failure_code = "PROVIDER_ERROR"
        attempt.status = VerificationAttemptStatus.ERROR
        attempt.error_message = str(exc)
        attempt.completed_at = _utcnow()
        onboarding.status = OnboardingStatus.BANK_PENDING
        onboarding.next_action = "RESUBMIT_BANK"
        result_data = {
            "status": "FAILED",
            "failure_reason": "Provider error",
            "failure_code": "PROVIDER_ERROR",
        }

    _record_audit(
        db, user.id, "BANK_SUBMITTED", "merchant_onboarding", onboarding.id
    )
    db.flush()
    return {"onboarding": onboarding, "result": result_data}


def submit_category_documents(
    db: Session,
    onboarding: MerchantOnboarding,
    user: User,
    category_details: dict,
) -> dict:
    """Submit category-specific documents for verification."""
    if onboarding.user_id != user.id:
        raise ForbiddenError("Not authorized")

    if onboarding.status not in (
        OnboardingStatus.BANK_VERIFIED,
        OnboardingStatus.CATEGORY_DOCUMENTS_PENDING,
        OnboardingStatus.RESUBMISSION_REQUIRED,
    ):
        raise ValidationError(
            f"Cannot submit category documents from status: {onboarding.status.value}"
        )

    from app.models.business_identity_verification import CategoryDocumentVerification
    from app.models.verification_attempt import (
        VerificationAttempt,
        VerificationAttemptStatus,
        VerificationAttemptType,
    )

    onboarding.status = OnboardingStatus.CATEGORY_DOCUMENTS_PENDING
    onboarding.category_details = category_details

    provider = get_category_provider()
    results = {}
    requires_admin_review = False

    # Pharmacy: drug_license_no
    if "drug_license_no" in category_details:
        drug_no = category_details["drug_license_no"]
        if not provider.validate_drug_license_format(drug_no):
            raise ValidationError(
                "Invalid drug license format.",
                data={"field": "drug_license_no"},
            )

        doc_ver = CategoryDocumentVerification(
            onboarding_id=onboarding.id,
            document_type="DRUG_LICENSE",
            document_number_hash=_hash_identifier(drug_no.upper()),
            document_number_last_four=_mask_last_four(drug_no),
            status="PENDING",
            provider=provider.name,
            requires_admin_review=True,
            attempt_number=_get_next_attempt_number(
                db, onboarding.id, "DRUG_LICENSE_VERIFY"
            ),
        )
        db.add(doc_ver)
        db.flush()

        attempt = VerificationAttempt(
            onboarding_id=onboarding.id,
            attempt_type=VerificationAttemptType.DRUG_LICENSE_VERIFY,
            status=VerificationAttemptStatus.IN_PROGRESS,
            request_id=str(uuid.uuid4()),
            provider_code=provider.name,
        )
        db.add(attempt)
        db.flush()

        try:
            result = provider.verify_drug_license(drug_no)
            doc_ver.status = result.status
            doc_ver.provider_reference_id = result.reference_id
            doc_ver.requires_admin_review = result.requires_admin_review
            attempt.status = VerificationAttemptStatus.SUCCESS
            attempt.completed_at = _utcnow()
            if result.requires_admin_review:
                requires_admin_review = True
            results["drug_license"] = {
                "status": result.status,
                "requires_admin_review": result.requires_admin_review,
            }
        except Exception as exc:
            logger.error("Drug license verification error: %s", exc)
            doc_ver.status = "FAILED"
            doc_ver.requires_admin_review = True
            requires_admin_review = True
            attempt.status = VerificationAttemptStatus.ERROR
            attempt.completed_at = _utcnow()
            results["drug_license"] = {
                "status": "FAILED",
                "requires_admin_review": True,
            }

    # Restaurant: fssai_license_no
    if "fssai_license_no" in category_details:
        fssai_no = category_details["fssai_license_no"]
        if not provider.validate_fssai_format(fssai_no):
            raise ValidationError(
                "Invalid FSSAI license format. Expected 10-20 digits.",
                data={"field": "fssai_license_no"},
            )

        doc_ver = CategoryDocumentVerification(
            onboarding_id=onboarding.id,
            document_type="FSSAI_LICENSE",
            document_number_hash=_hash_identifier(fssai_no.upper()),
            document_number_last_four=_mask_last_four(fssai_no),
            status="PENDING",
            provider=provider.name,
            requires_admin_review=True,
            attempt_number=_get_next_attempt_number(
                db, onboarding.id, "FSSAI_LICENSE_VERIFY"
            ),
        )
        db.add(doc_ver)
        db.flush()

        attempt = VerificationAttempt(
            onboarding_id=onboarding.id,
            attempt_type=VerificationAttemptType.FSSAI_LICENSE_VERIFY,
            status=VerificationAttemptStatus.IN_PROGRESS,
            request_id=str(uuid.uuid4()),
            provider_code=provider.name,
        )
        db.add(attempt)
        db.flush()

        try:
            result = provider.verify_fssai_license(fssai_no)
            doc_ver.status = result.status
            doc_ver.provider_reference_id = result.reference_id
            doc_ver.requires_admin_review = result.requires_admin_review
            attempt.status = VerificationAttemptStatus.SUCCESS
            attempt.completed_at = _utcnow()
            if result.requires_admin_review:
                requires_admin_review = True
            results["fssai_license"] = {
                "status": result.status,
                "requires_admin_review": result.requires_admin_review,
            }
        except Exception as exc:
            logger.error("FSSAI verification error: %s", exc)
            doc_ver.status = "FAILED"
            doc_ver.requires_admin_review = True
            requires_admin_review = True
            attempt.status = VerificationAttemptStatus.ERROR
            attempt.completed_at = _utcnow()
            results["fssai_license"] = {
                "status": "FAILED",
                "requires_admin_review": True,
            }

    # Transport: driving_license_no, vehicle_rc_no
    if "driving_license_no" in category_details:
        dl_no = category_details["driving_license_no"]
        if not provider.validate_driving_license_format(dl_no):
            raise ValidationError(
                "Invalid driving license format.",
                data={"field": "driving_license_no"},
            )

        doc_ver = CategoryDocumentVerification(
            onboarding_id=onboarding.id,
            document_type="DRIVING_LICENSE",
            document_number_hash=_hash_identifier(dl_no.upper()),
            document_number_last_four=_mask_last_four(dl_no),
            status="PENDING",
            provider=provider.name,
            requires_admin_review=True,
            attempt_number=_get_next_attempt_number(
                db, onboarding.id, "DRIVING_LICENSE_VERIFY"
            ),
        )
        db.add(doc_ver)
        db.flush()

        attempt = VerificationAttempt(
            onboarding_id=onboarding.id,
            attempt_type=VerificationAttemptType.DRIVING_LICENSE_VERIFY,
            status=VerificationAttemptStatus.IN_PROGRESS,
            request_id=str(uuid.uuid4()),
            provider_code=provider.name,
        )
        db.add(attempt)
        db.flush()

        try:
            result = provider.verify_driving_license(dl_no)
            doc_ver.status = result.status
            doc_ver.provider_reference_id = result.reference_id
            doc_ver.requires_admin_review = result.requires_admin_review
            attempt.status = VerificationAttemptStatus.SUCCESS
            attempt.completed_at = _utcnow()
            if result.requires_admin_review:
                requires_admin_review = True
            results["driving_license"] = {
                "status": result.status,
                "requires_admin_review": result.requires_admin_review,
            }
        except Exception as exc:
            logger.error("DL verification error: %s", exc)
            doc_ver.status = "FAILED"
            doc_ver.requires_admin_review = True
            requires_admin_review = True
            attempt.status = VerificationAttemptStatus.ERROR
            attempt.completed_at = _utcnow()
            results["driving_license"] = {
                "status": "FAILED",
                "requires_admin_review": True,
            }

    if "vehicle_rc_no" in category_details:
        rc_no = category_details["vehicle_rc_no"]
        if not provider.validate_vehicle_rc_format(rc_no):
            raise ValidationError(
                "Invalid vehicle RC format.",
                data={"field": "vehicle_rc_no"},
            )

        doc_ver = CategoryDocumentVerification(
            onboarding_id=onboarding.id,
            document_type="VEHICLE_RC",
            document_number_hash=_hash_identifier(rc_no.upper()),
            document_number_last_four=_mask_last_four(rc_no),
            status="PENDING",
            provider=provider.name,
            requires_admin_review=True,
            attempt_number=_get_next_attempt_number(
                db, onboarding.id, "VEHICLE_RC_VERIFY"
            ),
        )
        db.add(doc_ver)
        db.flush()

        attempt = VerificationAttempt(
            onboarding_id=onboarding.id,
            attempt_type=VerificationAttemptType.VEHICLE_RC_VERIFY,
            status=VerificationAttemptStatus.IN_PROGRESS,
            request_id=str(uuid.uuid4()),
            provider_code=provider.name,
        )
        db.add(attempt)
        db.flush()

        try:
            result = provider.verify_vehicle_rc(rc_no)
            doc_ver.status = result.status
            doc_ver.provider_reference_id = result.reference_id
            doc_ver.requires_admin_review = result.requires_admin_review
            attempt.status = VerificationAttemptStatus.SUCCESS
            attempt.completed_at = _utcnow()
            if result.requires_admin_review:
                requires_admin_review = True
            results["vehicle_rc"] = {
                "status": result.status,
                "requires_admin_review": result.requires_admin_review,
            }
        except Exception as exc:
            logger.error("RC verification error: %s", exc)
            doc_ver.status = "FAILED"
            doc_ver.requires_admin_review = True
            requires_admin_review = True
            attempt.status = VerificationAttemptStatus.ERROR
            attempt.completed_at = _utcnow()
            results["vehicle_rc"] = {
                "status": "FAILED",
                "requires_admin_review": True,
            }

    # Determine next state
    if requires_admin_review:
        onboarding.status = OnboardingStatus.PENDING_ADMIN_REVIEW
        onboarding.next_action = "WAIT_FOR_ADMIN_REVIEW"
    else:
        onboarding.category_verified = True
        onboarding.category_verified_at = _utcnow()
        onboarding.status = OnboardingStatus.CATEGORY_DOCUMENTS_VERIFIED
        onboarding.next_action = "PENDING_ADMIN_REVIEW"

    _record_audit(
        db, user.id, "CATEGORY_DOCS_SUBMITTED", "merchant_onboarding", onboarding.id
    )
    db.flush()
    return {"onboarding": onboarding, "results": results}


def get_onboarding_status(
    db: Session, onboarding: MerchantOnboarding, user: User
) -> dict:
    """Get full onboarding status with next action."""
    if onboarding.user_id != user.id:
        raise ForbiddenError("Not authorized")

    # Get requirements for the category
    requirements = get_category_requirements(db, onboarding.category_code)

    # Build verification status
    verification = {
        "phone": "VERIFIED" if onboarding.phone_verified else "PENDING",
        "business_identity": "VERIFIED"
        if onboarding.identity_verified
        else ("PENDING" if onboarding.status in (
            OnboardingStatus.PHONE_VERIFIED,
            OnboardingStatus.IDENTITY_PENDING,
        ) else "NOT_STARTED"),
        "bank_account": "VERIFIED"
        if onboarding.bank_verified
        else ("PENDING" if onboarding.status in (
            OnboardingStatus.IDENTITY_VERIFIED,
            OnboardingStatus.BANK_PENDING,
        ) else "NOT_STARTED"),
        "category_verification": "VERIFIED"
        if onboarding.category_verified
        else ("PENDING" if onboarding.status in (
            OnboardingStatus.BANK_VERIFIED,
            OnboardingStatus.CATEGORY_DOCUMENTS_PENDING,
            OnboardingStatus.PENDING_ADMIN_REVIEW,
        ) else "NOT_STARTED"),
    }

    return {
        "business_id": onboarding.shop_id,
        "onboarding_id": onboarding.id,
        "onboarding_status": onboarding.status.value,
        "verification": verification,
        "next_action": onboarding.next_action,
        "category_code": onboarding.category_code,
        "admin_reviewed": onboarding.admin_reviewed,
        "rejection_reason": onboarding.rejection_reason,
    }


def _get_next_attempt_number(
    db: Session, onboarding_id: int, attempt_type: str
) -> int:
    """Get the next attempt number for a verification type."""
    from app.models.verification_attempt import VerificationAttempt

    last_attempt = (
        db.query(VerificationAttempt)
        .filter(
            VerificationAttempt.onboarding_id == onboarding_id,
            VerificationAttempt.attempt_type == attempt_type,
        )
        .order_by(VerificationAttempt.attempt_number.desc())
        .first()
    )
    return (last_attempt.attempt_number + 1) if last_attempt else 1


def _record_audit(
    db: Session,
    user_id: int,
    action: str,
    entity_type: str,
    entity_id: int,
    description: str | None = None,
) -> None:
    """Record an audit log entry."""
    audit = AuditLog(
        user_id=user_id,
        action=action,
        entity_type=entity_type,
        entity_id=entity_id,
        description=description,
        is_success=True,
    )
    db.add(audit)
