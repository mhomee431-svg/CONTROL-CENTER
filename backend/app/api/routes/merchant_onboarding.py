"""Merchant Onboarding API routes — Shopkeeper endpoints.

/api/v1/shopkeeper/businesses/*

All endpoints require shopkeeper authentication and business ownership.
"""
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user, require_shop_access
from app.core.exceptions import AppError, ForbiddenError
from app.core.responses import error_response, success_response
from app.database.session import get_db
from app.models import merchant_category, product_attributes
from app.models.merchant_onboarding import MerchantOnboarding
from app.models.shop import Shop
from app.models.user import User
from app.services import capability_field_specs, capability_fields_service
from app.schemas.merchant_onboarding import (
    BankVerificationRequest,
    CategoryDocumentsRequest,
    IdentityVerificationRequest,
    MerchantOnboardingRequest,
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


@router.get("/categories")
async def list_registration_categories(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Active merchant categories for the shop-registration dropdown.

    The wizard renders exactly what this returns — no category codes are
    hardcoded in the Flutter app.
    """
    categories = merchant_onboarding_service.list_active_categories(db)
    return success_response(
        data={
            "business_types": list(merchant_category.BUSINESS_TYPES),
            "categories": [
                {
                    "code": c.code,
                    "name": c.name,
                    "description": c.description,
                    "sort_order": c.sort_order,
                    # Shipped WITH the category so the wizard can render the
                    # right fields on the same round trip it already makes — it
                    # never has to hardcode which fields a category has.
                    "capabilities": [
                        cap.value
                        for cap in (merchant_category.resolve_capabilities(c.code) or ())
                    ],
                }
                for c in categories
            ],
        },
        message="OK",
    )


@router.get("/categories/{category_code}/capabilities")
async def get_category_capabilities(
    category_code: str,
    business_type: str | None = None,
    current_user: User = Depends(get_current_user),
):
    """Resolved capabilities for one category, optionally narrowed by business type.

    This is the second half of the capability contract. The category list above
    ships each category's base capabilities; this answers the actual question the
    data-entry forms ask — "given this category AND this business type, what may
    the shopkeeper enter?" — so the client never has to hold that rule itself.
    """
    data = merchant_category.capabilities_for_category(category_code, business_type)
    if data is None:
        return error_response(
            message=f"Unknown category: {category_code}",
            error_code="CATEGORY_NOT_FOUND",
            status_code=404,
        )
    return success_response(data=data, message="OK")


@router.get("/categories/{category_code}/product-attributes")
async def get_category_product_attributes(
    category_code: str,
    current_user: User = Depends(get_current_user),
):
    """The product attributes one business category actually uses.

    Business category and product category are not the same thing, so this
    answers a different question than the capability endpoint above: not "what
    may this shop enter?" but "when this shop records a product, which
    attributes does the schema store for it?"

    It is deliberately category-driven rather than uniform. A pharmacy item
    carries prescription and regulatory columns; a book carries a publisher and
    an edition; furniture has no scannable barcode and no unit-level stock. A
    restaurant, a transport provider or a travel service gets an empty list —
    they sell services, and forcing an inventory form on them is the bug this
    endpoint exists to prevent.

    Every key names a real destination (a column, or a key of
    `product_variants.attributes_json`). Nothing here is invented, and
    regulatory verification is deliberately absent until the backend defines it.
    """
    normalised = (category_code or "").strip().upper()
    known = {c.value for c in merchant_category.MerchantCategoryCode}
    if normalised not in known:
        return error_response(
            message=f"Unknown category: {category_code}",
            error_code="CATEGORY_NOT_FOUND",
            status_code=404,
        )

    specs = product_attributes.product_attributes_for(normalised)
    return success_response(
        data={
            "category_code": normalised,
            # The shopkeeper app keys off this to decide whether to offer a
            # product form at all, so it ships even when the list is empty.
            "has_product_form": bool(specs),
            "attributes": [spec.as_dict() for spec in specs],
        },
        message="OK",
    )


@router.get("/categories/{category_code}/fields")
async def get_category_fields(
    category_code: str,
    business_type: str | None = None,
    current_user: User = Depends(get_current_user),
):
    """The exact field set this category/business type may submit.

    The third leg of the capability contract. `/capabilities` says what a trade
    can DO; `/product-attributes` says what a PRODUCT stores; this says what the
    SHOP PROFILE stores. All three come from the backend registry, so the form the
    shopkeeper fills is the form the backend validates — a client that guessed a
    field name would otherwise discover the mismatch only as a rejected save.
    """
    resolved = merchant_category.capabilities_for_category(
        category_code, business_type
    )
    if resolved is None:
        return error_response(
            message=f"Unknown category: {category_code}",
            error_code="CATEGORY_NOT_FOUND",
            status_code=404,
        )

    specs = capability_field_specs.capability_fields_for(category_code, business_type)
    return success_response(
        data={
            "category_code": (category_code or "").strip().upper(),
            "business_type": business_type,
            "fields": [spec.as_dict() for spec in specs],
            # Ships so the app can decide whether to offer a product form at all
            # without a second round trip.
            "has_product_form": capability_fields_service.has_product_form(
                category_code, business_type
            ),
        },
        message="OK",
    )


def _may_write_capability_fields(db: Session, shop: Shop, user: User) -> bool:
    """Whether this user may write [shop]'s capability fields.

    Mirrors `require_shop_access` — admin, an owner, or a manager. Re-implemented
    inline rather than reused as a dependency because that factory reads
    `shop_id` from FastAPI's path parameters, which a dependency declared beside
    the path parameter itself cannot see.
    """
    if user.role is not None and user.role.name == "admin":
        return True
    if any(owner.user_id == user.id for owner in shop.owners):
        return True
    return any(manager.user_id == user.id for manager in shop.managers)


@router.put("/shops/{shop_id}/capability-fields")
async def update_shop_capability_fields(
    shop_id: int,
    payload: dict,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Persist the capability-driven fields for one shop.

    Two things make this safe to expose:

      * only keys the registry approves for THIS shop's category are stored, so
        the JSON document cannot become an unvalidated blob any client can fill;
      * validation runs first and rejects the whole request, so a half-saved form
        is impossible.

    A malformed or unapproved key rejects the WHOLE request with a 422 carrying
    the per-field errors, rather than saving what it can and mentioning the rest
    in passing. Partial saves are how a shopkeeper ends up with a profile that
    silently lost half its fields.
    """
    shop = db.get(Shop, shop_id)
    if shop is None:
        return error_response(
            message="Shop not found",
            error_code="SHOP_NOT_FOUND",
            status_code=404,
        )
    if not _may_write_capability_fields(db, shop, current_user):
        return error_response(
            message="Not your shop",
            error_code="FORBIDDEN",
            status_code=403,
        )

    category_code = str(payload.get("category_code") or "").strip().upper()
    if not category_code:
        return error_response(
            message="category_code is required",
            error_code="CATEGORY_REQUIRED",
            status_code=400,
        )

    submitted = payload.get("fields")
    if not isinstance(submitted, dict):
        return error_response(
            message="fields must be an object of key/value pairs",
            error_code="FIELDS_INVALID",
            status_code=400,
        )

    business_type = payload.get("business_type")
    errors = capability_field_specs.validate_capability_fields(
        category_code, business_type, submitted
    )
    if errors:
        return error_response(
            message="; ".join(errors),
            error_code="VALIDATION_FAILED",
            status_code=422,
            # Per-field errors travel in `data` so the client can show each one
            # against its input instead of dumping a joined sentence.
            data={"errors": errors},
        )

    stored, _rejected = capability_fields_service.sanitise_capability_fields(
        category_code, business_type, submitted
    )
    # Merged rather than replaced: a partial update (the shopkeeper fixed their
    # hours) must not wipe the service area they entered earlier.
    shop.capability_fields = {**(shop.capability_fields or {}), **stored}
    db.commit()
    db.refresh(shop)

    return success_response(
        data={
            "shop_id": shop.id,
            "category_code": category_code,
            "capability_fields": shop.capability_fields,
        },
        message="OK",
    )


@router.get("/categories/{category_code}/requirements")
async def get_registration_category_requirements(
    category_code: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Backend-driven document/info requirements for a merchant category.

    The registration wizard's Documents step is rendered from this contract —
    required/optional documents and the verification steps (OTP, identity,
    bank, category documents, admin review) all originate here.
    """
    data = merchant_onboarding_service.registration_requirements(
        db, category_code.upper()
    )
    if data is None:
        return error_response(
            message=f"Unknown category: {category_code}",
            error_code="CATEGORY_NOT_FOUND",
            status_code=404,
        )
    return success_response(data=data, message="OK")
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
    result = await merchant_onboarding_service.submit_identity_verification(
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
    result = await merchant_onboarding_service.submit_bank_verification(
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
    result = await merchant_onboarding_service.submit_category_documents(
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
