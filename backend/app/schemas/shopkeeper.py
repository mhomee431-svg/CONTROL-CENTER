"""Phase 22/23 — Pydantic schemas for the Shopkeeper App API."""

from datetime import datetime, timezone
from typing import ClassVar
import re

from pydantic import BaseModel, Field, field_validator, model_validator


# ── Auth ─────────────────────────────────────────────────────────────────
class ShopkeeperSendOTPRequest(BaseModel):
    phone_number: str = Field(..., min_length=10, max_length=20)


class ShopkeeperProfileCreateRequest(BaseModel):
    """First-time profile creation payload (no location required).

    Sent by the Flutter profile-creation screen after the shopkeeper's first
    Google sign-in. Creates the sole business shop and updates the user's
    profile fields.
    """

    shop_name: str = Field(..., min_length=1, max_length=255)
    name: str | None = Field(None, max_length=100, description="Override display name")
    email: str | None = Field(None, max_length=255, description="Override email")
    phone: str | None = Field(None, max_length=20, description="Contact number")
    category: str | None = Field(None, max_length=50, description="Merchant category code")
    business_type: str | None = Field(None, max_length=50, description="Retail | Wholesale | Retail + Wholesale | Service | Other")
    description: str | None = Field(None, max_length=2000)
class ShopkeeperRegisterRequest(BaseModel):
    """First-time shopkeeper registration.

    Phone verification is performed client-side by Firebase Phone Auth — the
    Flutter app sends the resulting Firebase ID token (``firebase_id_token``).
    The backend verifies the token to extract and trust the phone number.

    The new ``verify-phone`` → ``register`` flow also accepts the verified
    ``firebase_uid`` / ``phone_number`` (cross-checked against the token) and
    a ``role`` (defaults to ``shopkeeper``).
    """

    firebase_id_token: str | None = Field(
        None,
        min_length=20,
        description="Firebase ID token from a completed phone-OTP sign-in (also accepted in the Authorization header)",
    )
    phone_number: str = Field(..., min_length=10, max_length=20, description="Must match the token's phone")
    name: str = Field(..., min_length=1, max_length=100)
    email: str | None = Field(None, max_length=255)
    password: str | None = Field(None, min_length=8, max_length=128, description="Optional password (8+ chars; not required for Firebase-verified users)")
    firebase_uid: str | None = Field(
        None,
        max_length=128,
        description="Verified Firebase UID (cross-checked against the token)",
    )
    role: str | None = Field("shopkeeper", description="Role to assign (shopkeeper)")
    device_id: str | None = Field(None, description="Stable device identifier")
    device_name: str | None = None
    device_type: str | None = Field(None, description="android, ios, web")
    platform: str | None = None
    app_version: str | None = None

    @field_validator('password')
    @classmethod
    def validate_password(cls, v):
        """Validate password strength (only when a password is provided)."""
        if v is None:
            return v
        if len(v) < 8:
            raise ValueError('Password must be at least 8 characters')
        if not re.search(r'[A-Za-z]', v):
            raise ValueError('Password must contain at least one letter')
        if not re.search(r'[0-9]', v):
            raise ValueError('Password must contain at least one number')
        return v


class ShopkeeperLoginRequest(BaseModel):
    """Password-based login for shopkeeper (identifier can be email or phone)."""

    identifier: str = Field(..., min_length=3, max_length=255, description="Email or phone number")
    password: str = Field(..., min_length=8, max_length=128)
    device_id: str | None = None
    device_name: str | None = None
    device_type: str | None = None
    platform: str | None = None
    app_version: str | None = None


class ShopkeeperOTPLoginRequest(BaseModel):
    """Firebase-phone-OTP login for an EXISTING account via the Shopkeeper App.

    The Flutter app completes the OTP flow client-side with ``firebase_auth``
    and sends the resulting Firebase ID token (``firebase_id_token``).
    """

    firebase_id_token: str = Field(
        ...,
        min_length=20,
        description="Firebase ID token from a completed phone-OTP sign-in",
    )
    device_id: str | None = None
    device_name: str | None = None
    device_type: str | None = None
    platform: str | None = None
    app_version: str | None = None


class ShopkeeperFirebaseLoginRequest(BaseModel):
    """Combined Firebase login-or-register request.

    Supports BOTH Phone-OTP and Google Sign-In:
    - Phone OTP: sends firebase_id_token, backend extracts phone number
    - Google Sign-In: sends firebase_id_token + email + name, backend extracts firebase_uid

    The backend verifies the token and either logs in an existing shopkeeper
    or auto-registers a new one. This "login or register on first use" flow
    means users don't need a separate registration step.
    """

    firebase_id_token: str = Field(
        ...,
        min_length=20,
        description="Firebase ID token from a completed Google Sign-In or phone-OTP sign-in",
    )
    name: str | None = Field(None, max_length=100, description="Required when auto-registering (Google Sign-In)")
    email: str | None = Field(None, max_length=255, description="Email from Google Sign-In")
    photo_url: str | None = Field(None, max_length=500, description="Google profile picture URL (avatar)")
    device_id: str | None = Field(None, description="Stable device identifier")
    device_name: str | None = None
    device_type: str | None = Field(None, description="android, ios, web")
    platform: str | None = None
    app_version: str | None = None


class ShopkeeperRefreshRequest(BaseModel):
    refresh_token: str
    device_id: str | None = None


class ShopkeeperLogoutRequest(BaseModel):
    refresh_token: str | None = None
    session_id: str | None = None
    revoke_all: bool = False


class ShopkeeperForgotPasswordRequest(BaseModel):
    """Request password reset (identifier can be email or phone)."""

    identifier: str = Field(..., min_length=3, max_length=255, description="Email or phone number")


class ShopkeeperResetPasswordRequest(BaseModel):
    """Reset password using token from forgot-password email/SMS."""

    token: str = Field(..., description="Password reset token")
    new_password: str = Field(..., min_length=8, max_length=128, description="New password")

    @field_validator('new_password')
    @classmethod
    def validate_password(cls, v):
        """Validate password strength."""
        if len(v) < 8:
            raise ValueError('Password must be at least 8 characters')
        if not re.search(r'[A-Za-z]', v):
            raise ValueError('Password must contain at least one letter')
        if not re.search(r'[0-9]', v):
            raise ValueError('Password must contain at least one number')
        return v


# ── Token Response ──────────────────────────────────────────────────────────
class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int
    session_id: str | None = None


class LoginResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int
    session_id: str | None = None
    user: dict
    shops: list[dict] = []


# ── Shop registration / profile / settings ───────────────────────────────
class ShopAddressInput(BaseModel):
    address_line1: str = Field(..., min_length=1, max_length=255)
    address_line2: str | None = Field(None, max_length=255)
    landmark: str | None = Field(None, max_length=255)
    city: str = Field(..., min_length=1, max_length=100)
    state: str = Field(..., min_length=1, max_length=100)
    pincode: str = Field(..., min_length=3, max_length=10)
    country: str | None = Field("India", max_length=100)


# ── Location capture metadata (Phase: Shop Location System) ─────────────────
class ShopLocationMeta(BaseModel):
    """Provenance/quality metadata for a captured shop location.

    GPS coordinates remain the primary source of truth; this block is
    supporting metadata used by admin review and accuracy auditing.
    """

    location_source: str | None = Field(
        None, max_length=20, description="GPS | MANUAL | ADDRESS"
    )
    location_type: str | None = Field(
        None, max_length=30, description="SHOP_ENTRANCE | BUILDING_CENTER | OTHER"
    )
    location_status: str | None = Field(
        None, max_length=20, description="CAPTURED | CONFIRMED | CORRECTED | STALE"
    )
    location_integrity_status: str | None = Field(
        None, max_length=20, description="NORMAL | SUSPICIOUS | UNKNOWN"
    )
    accuracy_meters: float | None = Field(None, ge=0, le=10000)
    location_captured_at: datetime | None = Field(
        None, description="Device timestamp of the fix (ISO-8601, UTC)"
    )
    location_verified: bool | None = Field(
        None, description="Shopkeeper confirmed the pin at the access point"
    )


class ShopkeeperShopCreate(BaseModel):
    """Payload to create a shop during first-time profile setup.

    Location and address are OPTIONAL for the initial profile-creation flow —
    they are filled in later via the location-capture screen. This keeps the
    first-stage form fast and unblockable.
    """

    name: str = Field(..., min_length=1, max_length=255)
    description: str | None = None
    tagline: str | None = Field(None, max_length=255)
    category: str | None = Field(None, max_length=50)
    business_type: str | None = Field(None, max_length=50, description="Retail | Wholesale | Retail + Wholesale | Service | Other")
    phone: str | None = Field(None, max_length=20)
    whatsapp_number: str | None = Field(None, max_length=20)
    email: str | None = Field(None, max_length=255)
    image_url: str | None = Field(None, max_length=500)
    latitude: float | None = Field(None, ge=-90, le=90)
    longitude: float | None = Field(None, ge=-180, le=180)
    gstin: str | None = Field(None, max_length=50)
    address: ShopAddressInput | None = None
    # Optional capture provenance — populated by the shopkeeper location flow.
    location: ShopLocationMeta | None = None


class ShopkeeperShopLocationUpdate(BaseModel):
    """Controlled, IDOR-safe edit of a shop's location.

    Only ``latitude``/``longitude`` are required; the remaining fields are
    accepted so the controlled Edit-Location flow can persist the new
    accuracy/timestamp/source in a single request.
    """

    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    location: ShopLocationMeta | None = None


class ShopkeeperProfileUpdate(BaseModel):
    """Editable shop profile fields (whitelist enforced in service)."""

    name: str | None = Field(None, min_length=1, max_length=255)
    description: str | None = None
    tagline: str | None = Field(None, max_length=255)
    phone: str | None = Field(None, max_length=20)
    alternate_phone: str | None = Field(None, max_length=20)
    whatsapp_number: str | None = Field(None, max_length=20)
    email: str | None = Field(None, max_length=255)
    website_url: str | None = Field(None, max_length=500)
    image_url: str | None = Field(None, max_length=500)
    logo_url: str | None = Field(None, max_length=500)
    # Phase 7 — signed-upload integration: pass the server-minted object key
    # returned by POST /media/confirm. Validated (category + ownership +
    # existence) and converted to a durable s3:// storage reference.
    image_key: str | None = Field(None, max_length=512)
    logo_key: str | None = Field(None, max_length=512)


class ShopkeeperSettingsUpdate(BaseModel):
    """Operational settings toggles for a shop."""

    is_accepting_orders: bool | None = None
    is_delivery_available: bool | None = None
    is_pickup_available: bool | None = None
    is_open_24x7: bool | None = None
    min_order_amount: float | None = Field(None, ge=0)
    delivery_radius_km: float | None = Field(None, ge=0, le=100)
    delivery_fee: float | None = Field(None, ge=0)
    free_delivery_above: float | None = Field(None, ge=0)


# ── Products ─────────────────────────────────────────────────────────────
class ShopkeeperProductCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    description: str | None = None
    brand_name: str | None = Field(None, max_length=120)
    unit: str | None = Field(None, max_length=50)
    price: float = Field(..., ge=0)
    mrp: float | None = Field(None, ge=0)
    sku: str | None = Field(None, max_length=100)
    quantity: int = Field(0, ge=0, le=999_999, description="Initial stock quantity (0-999,999)")
    low_stock_threshold: int = Field(5, ge=0, le=999_999, description="Alert threshold (0-999,999)")
    is_available: bool = True
    publish: bool = Field(False, description="Publish immediately (APPROVED) vs keep as DRAFT")
    # Phase 7 — PRODUCT_IMAGE object key from POST /media/confirm.
    image_key: str | None = Field(None, max_length=512)
    # Taxonomy — optional. `categories` already stores both levels in one
    # table, so a subcategory is a row whose `parent_id` is the category.
    # Both are OPTIONAL: a shopkeeper can list a product before the catalog
    # is fully classified, and existing clients keep working unchanged.
    category_id: int | None = Field(None, ge=1)
    subcategory_id: int | None = Field(None, ge=1)
    # Barcode — optional. The first barcode supplied for a product becomes its
    # primary identifier, so a scan can resolve it later. Only digits are
    # meaningful for retail symbologies (EAN/UPC/GTIN/JAN/ITF).
    barcode: str | None = Field(None, min_length=4, max_length=100)
    barcode_type: str | None = Field(
        None,
        max_length=20,
        description="Optional explicit identifier type (EAN/UPC/GTIN/JAN/ITF/CUSTOM); "
        "inferred from the barcode length when omitted",
    )


class ShopkeeperProductUpdate(BaseModel):
    price: float | None = Field(None, ge=0)
    mrp: float | None = Field(None, ge=0)
    quantity: int | None = Field(None, ge=0, le=999_999, description="Updated stock quantity (0-999,999)")
    low_stock_threshold: int | None = Field(None, ge=0, le=999_999, description="Alert threshold (0-999,999)")
    is_available: bool | None = None
    is_featured: bool | None = None
    status: str | None = Field(None, max_length=30)
    # Phase 7 — replace the product image with a confirmed PRODUCT_IMAGE key.
    image_key: str | None = Field(None, max_length=512)


class ShopkeeperLowStockThresholdUpdate(BaseModel):
    """Set the per-listing low-stock threshold (the quantity that flips a
    listing into LOW_STOCK)."""

    low_stock_threshold: int = Field(..., ge=0, le=999_999)


# ── Phase 23 — Inventory management ───────────────────────────────────────
class ShopkeeperAddFromMaster(BaseModel):
    """Add an EXISTING product-master record (optionally a variant) to a shop.

    Shopkeepers must select from the platform catalog — arbitrary duplicate
    product-master creation is not allowed through this endpoint.
    """

    product_master_id: int
    variant_id: int | None = None
    price: float = Field(..., ge=0, description="Shop selling price")
    mrp: float | None = Field(None, ge=0)
    sku: str | None = Field(None, max_length=100)
    quantity: int = Field(0, ge=0, le=999_999)
    low_stock_threshold: int = Field(5, ge=0, le=999_999)
    is_available: bool = True


class ShopkeeperStockAdjustment(BaseModel):
    """Delta stock adjustment with audit trail (type + reason)."""

    allowed_adjustment_types: ClassVar[set[str]] = {
        "RESTOCK", "DAMAGE", "EXPIRY", "STOCK_COUNT", "CORRECTION",
        "RETURN", "TRANSFER_OUT", "TRANSFER_IN", "SPOILAGE",
    }

    adjustment_type: str = Field("CORRECTION", max_length=50)
    quantity_adjustment: int = Field(
        ...,
        ge=-999_999,
        le=999_999,
        description="Delta units (+restock / -damage); result must stay >= 0",
    )
    reason: str | None = Field(None, max_length=255)

    @model_validator(mode="after")
    def _validate_adjustment(self) -> "ShopkeeperStockAdjustment":
        if self.quantity_adjustment == 0:
            raise ValueError("Quantity adjustment cannot be zero")
        adj_type = self.adjustment_type.upper()
        if adj_type not in self.allowed_adjustment_types:
            raise ValueError(f"Invalid adjustment type: {self.adjustment_type}")
        # Positive deltas (restock, return, correction) are always fine.
        # Negative deltas (damage, expiry, transfer out, spoilage) are allowed —
        # the service layer rejects only if the RESULT goes negative.
        return self


class ShopkeeperOfferStatusUpdate(BaseModel):
    """Change an offer's lifecycle state (shopkeeper-owned)."""

    status: str = Field(..., max_length=20)


class ShopkeeperBulkOperation(BaseModel):
    """Bulk operations foundation: apply one change to many shop products."""

    operation: str = Field(..., description="price_update | stock_set | availability")
    shop_product_ids: list[int] = Field(..., min_length=1, max_length=200)
    price: float | None = Field(None, ge=0)
    mrp: float | None = Field(None, ge=0)
    quantity: int | None = Field(None, ge=0, le=999_999)
    is_available: bool | None = None


class ShopkeeperOfferAssign(BaseModel):
    """Assign (create + link) an offer to selected shop products."""

    title: str = Field(..., min_length=1, max_length=255)
    offer_type: str = Field(..., max_length=40)
    discount_value: float | None = Field(None, ge=0)
    discount_percentage: float | None = Field(None, gt=0, le=100)
    promotional_price: float | None = Field(None, ge=0)
    status: str | None = Field(None, max_length=20)
    start_date: datetime
    end_date: datetime
    shop_product_ids: list[int] = Field(..., min_length=1, max_length=200)
    terms_conditions: str | None = None

    @model_validator(mode="after")
    def _validate_offer_window(self) -> "ShopkeeperOfferAssign":
        start = self.start_date
        end = self.end_date
        aware_start = start if start.tzinfo is not None else start.replace(tzinfo=timezone.utc)
        aware_end = end if end.tzinfo is not None else end.replace(tzinfo=timezone.utc)
        if aware_end <= aware_start:
            raise ValueError("Offer end date must be after start date")
        return self


class ShopkeeperSupportTicketCreate(BaseModel):
    """A support ticket filed from the shopkeeper app.

    Sent by *Report an issue* and *Contact support*. Field limits mirror
    ``app.services.support_service``: the schema rejects an obviously malformed
    request early (FastAPI 422 with a field-level message), and the service
    re-validates because it is also reachable from tests and admin tooling.
    """

    category: str = Field(
        ...,
        min_length=1,
        max_length=50,
        description="Issue category code (APP_PRODUCTS, APP_INVENTORY, ...)",
    )
    description: str = Field(
        ...,
        min_length=10,
        max_length=4000,
        description="What happened, in the shopkeeper's own words",
    )
    priority: str | None = Field(
        None, max_length=20, description="LOW | MEDIUM | HIGH | URGENT"
    )
    subject: str | None = Field(
        None, max_length=255, description="Optional one-line title"
    )
    steps: str | None = Field(
        None, max_length=2000, description="Optional steps to reproduce"
    )
    app_version: str | None = Field(
        None, max_length=50, description="Client build the report came from"
    )
    shop_id: int | None = Field(
        None,
        ge=1,
        description=(
            "Shop the report belongs to. Authorized through the standard "
            "shop-access check, so a foreign shop id is rejected with 403."
        ),
    )
    attachment_key: str | None = Field(
        None,
        min_length=8,
        max_length=512,
        description=(
            "Optional screenshot/evidence, as a media key from the signed "
            "upload flow (``support/{your_user_id}/....png``). The key is "
            "validated (category + self scope + object exists) before it is "
            "stored, so a foreign or phantom key is rejected."
        ),
    )


class CustomerSupportTicketCreate(BaseModel):
    """A support ticket filed from the customer app.

    The shopper-facing twin of :class:`ShopkeeperSupportTicketCreate`. Field
    limits deliberately match the shopkeeper schema and the service constants so
    one set of validation rules covers both audiences — a limit that differs
    between the two intake routes is a limit that will eventually differ from
    the database column too.

    The two differences that matter:

    * ``category`` accepts only the ``CUST_*`` codes (enforced by the service,
      which is passed ``CUSTOMER_CATEGORIES``), so a shopper cannot file a
      ticket the shopkeeper triage queue is watching; and
    * ``shop_id`` is context, not subject. A shopper may name the shop a ticket
      is about, but unlike a merchant they do not *own* a shop, so the id is
      never treated as proof of anything — see the field description.
    """

    category: str = Field(
        ...,
        min_length=1,
        max_length=50,
        description=(
            "Issue category code (CUST_WRONG_PRICE, CUST_AVAILABILITY, ...). "
            "Validated against CUSTOMER_CATEGORIES by the service."
        ),
    )
    description: str = Field(
        ...,
        min_length=10,
        max_length=4000,
        description="What happened, in the customer's own words",
    )
    subject: str | None = Field(
        None, max_length=255, description="Optional one-line title"
    )
    steps: str | None = Field(
        None, max_length=2000, description="Optional steps to reproduce"
    )
    app_version: str | None = Field(
        None, max_length=50, description="Client build the report came from"
    )
    contact_email: str | None = Field(
        None,
        max_length=254,
        description=(
            "Optional reply address. Recorded on the ticket as context; it is "
            "NOT used to identify the reporter, which is always the "
            "authenticated user."
        ),
    )
    shop_id: int | None = Field(
        None,
        ge=1,
        description=(
            "Optional shop the report is about. Recorded as context only — a "
            "shopkeeper filing against their own shop is authorized through the "
            "shop-access check, so a shopper supplying this id is NOT "
            "authorized against it and must not be treated as a shop owner."
        ),
    )

