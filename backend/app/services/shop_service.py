"""Shop Management System service — business logic for shop lifecycle, ownership, verification, and management."""

import json
import re
from datetime import date, datetime, time, timedelta, timezone
from typing import Optional

from geoalchemy2 import WKTElement
from sqlalchemy import exists as sa_exists, or_, select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session, selectinload

from app.core.logging import get_logger
from app.models.merchant_category import (
    MERCHANT_CATEGORY_NAMES,
    resolve_customer_capabilities,
)
from app.models.merchant_onboarding import MerchantOnboarding
from app.models.shop import (
    LocationIntegrityStatus,
    LocationSource,
    LocationStatus,
    LocationType,
    Shop,
    ShopAddress,
    ShopCategory,
    ShopDocument,
    ShopHoliday,
    ShopHour,
    ShopManager,
    ShopOwner,
    ShopStatus,
    ShopVerification,
    VerificationStatus,
)
from app.models.user import User
from app.services.geo_service import haversine_km, resolve_shop_coordinates

logger = get_logger("app.services.shop")


# ── Helpers ────────────────────────────────────────────────────────────────
def slugify(value: str) -> str:
    """Convert a string to a URL-safe slug."""
    value = value.strip().lower()
    value = re.sub(r"[^a-z0-9]+", "-", value)
    value = re.sub(r"-+", "-", value).strip("-")
    return value


def validate_address(data: dict) -> None:
    """Validate shop address fields."""
    if not data.get("address_line1") or not data["address_line1"].strip():
        raise ValueError("Address line 1 is required")
    if not data.get("city") or not data["city"].strip():
        raise ValueError("City is required")
    if not data.get("state") or not data["state"].strip():
        raise ValueError("State is required")
    if not data.get("pincode") or not data["pincode"].strip():
        raise ValueError("Pincode is required")
    pincode = data["pincode"].strip()
    if not re.match(r"^\d{6}$", pincode):
        raise ValueError("Pincode must be a 6-digit number")


def validate_geolocation(latitude: Optional[float], longitude: Optional[float]) -> None:
    """Validate geolocation coordinates."""
    if latitude is None or longitude is None:
        raise ValueError("Latitude and longitude are required")
    if not (-90 <= latitude <= 90):
        raise ValueError("Latitude must be between -90 and 90")
    if not (-180 <= longitude <= 180):
        raise ValueError("Longitude must be between -180 and 180")


def validate_hours(hours: list) -> None:
    """Validate shop opening hours."""
    seen_days = set()
    for h in hours:
        day = h.get("day_of_week")
        if day is None or not (0 <= day <= 6):
            raise ValueError("day_of_week must be between 0 (Monday) and 6 (Sunday)")
        if day in seen_days:
            raise ValueError(f"Duplicate hours for day_of_week {day}")
        seen_days.add(day)
        if not h.get("is_closed"):
            open_time = h.get("open_time")
            close_time = h.get("close_time")
            if open_time is None or close_time is None:
                raise ValueError(f"open_time and close_time required for day {day}")
            # Compare as strings since time objects from dict may lack date
            if str(close_time) <= str(open_time):
                raise ValueError(f"close_time must be after open_time for day {day}")


def is_shop_open(shop: Shop, at_time: Optional[datetime] = None) -> bool:
    """Determine if a shop is currently open based on hours and holidays."""
    if shop.is_open_24x7:
        return True
    at = at_time or datetime.now(timezone.utc)
    today = at.date()
    # Check holiday schedule
    for holiday in shop.holidays:
        if holiday.holiday_date == today:
            return False
        if (
            holiday.is_recurring_yearly
            and holiday.holiday_date.month == today.month
            and holiday.holiday_date.day == today.day
        ):
            return False
    # Check opening hours
    day_of_week = at.weekday()  # 0=Monday ... 6=Sunday
    for hour in shop.hours:
        if hour.day_of_week == day_of_week:
            if hour.is_closed:
                return False
            current = at.time()
            if hour.open_time <= current <= hour.close_time:
                return True
            return False
    return False


def _get_wkt_point(latitude: float, longitude: float) -> WKTElement:
    """Create a PostGIS POINT WKT element (longitude first)."""
    return WKTElement(f"POINT({longitude} {latitude})", srid=4326)


# ── Shop creation / registration ─────────────────────────────────────────
def register_shop(db: Session, data: dict, owner_user_id: int) -> Shop:
    """Register a new shop and assign the creator as primary owner.

    Lifecycle:
        Registered → Documents Submitted → Pending Verification → Verified → Active
    """
    # ── Validations ──
    # Location and address are OPTIONAL for the first-stage profile-creation
    # flow (POST /shopkeeper/shops via register_shop_for_shopkeeper). Only
    # validate + persist them when the caller actually supplied coordinates
    # and/or a primary address. The full shop-registration flow (shops.py)
    # still provides both, so its behaviour is unchanged.
    latitude = data.get("latitude")
    longitude = data.get("longitude")
    if latitude is not None and longitude is not None:
        validate_geolocation(latitude, longitude)

    address_data = data.get("address") or {}
    if address_data:
        # ANY supplied address data is validated strictly (a partial/malformed
        # address is a client error); a fully absent address is allowed for the
        # first-stage profile-creation flow and filled in later.
        validate_address(address_data)

    logger.info(
        "register_shop: name=%s category=%s has_location=%s has_address=%s",
        data.get("name"),
        data.get("category"),
        latitude is not None and longitude is not None,
        bool(address_data.get("address_line1")),
    )

    if data.get("hours"):
        validate_hours(data["hours"])

    # Unique slug — use exists() to avoid loading the Shop geometry column
    # (PostGIS AsBinary()), which fails on non-PostGIS engines (SQLite dev).
    base_slug = data.get("slug") or slugify(data["name"])
    slug = base_slug
    counter = 1
    while db.query(sa_exists().where(Shop.slug == slug)).scalar():
        slug = f"{base_slug}-{counter}"
        counter += 1

    # ── Create Shop (status=REGISTERED) ──
    # Location capture provenance (Phase: Shop Location System). `location` is
    # the optional metadata block; coordinates + geometry are always set
    # regardless of provenance.
    loc_meta = data.pop("location", None) or {}
    shop = Shop(
        name=data["name"],
        slug=slug,
        description=data.get("description"),
        tagline=data.get("tagline"),
        image_url=data.get("image_url"),
        cover_image_url=data.get("cover_image_url"),
        logo_url=data.get("logo_url"),
        phone=data.get("phone"),
        alternate_phone=data.get("alternate_phone"),
        email=data.get("email"),
        website_url=data.get("website_url"),
        whatsapp_number=data.get("whatsapp_number"),
        status=ShopStatus.REGISTERED,
        category=data.get("category"),
        subcategories=json.dumps(data.get("subcategories")) if data.get("subcategories") else None,
        latitude=latitude,
        longitude=longitude,
        # PostGIS geometry is only meaningful when coordinates exist. The
        # profile-creation flow omits them, so the geometry column stays NULL
        # until the later location-capture step fills it.
        location=_get_wkt_point(latitude, longitude)
            if latitude is not None and longitude is not None else None,
        accuracy_meters=loc_meta.get("accuracy_meters"),
        location_captured_at=loc_meta.get("location_captured_at"),
        location_source=loc_meta.get("location_source") or LocationSource.GPS.value,
        location_type=loc_meta.get("location_type") or LocationType.SHOP_ENTRANCE.value,
        location_status=loc_meta.get("location_status") or LocationStatus.CAPTURED.value,
        location_integrity_status=loc_meta.get("location_integrity_status") or LocationIntegrityStatus.UNKNOWN.value,
        location_verified=bool(loc_meta.get("location_verified", False)),
        is_open_24x7=data.get("is_open_24x7", False),
        is_accepting_orders=data.get("is_accepting_orders", True),
        min_order_amount=data.get("min_order_amount", 0.0),
        delivery_radius_km=data.get("delivery_radius_km", 5.0),
        delivery_fee=data.get("delivery_fee", 0.0),
        free_delivery_above=data.get("free_delivery_above", 0.0),
        is_delivery_available=data.get("is_delivery_available", True),
        is_pickup_available=data.get("is_pickup_available", True),
        gstin=data.get("gstin"),
        fssai_license=data.get("fssai_license"),
        established_year=data.get("established_year"),
        created_by=owner_user_id,
    )
    db.add(shop)
    db.flush()

    # ── Assign primary owner ──
    db.add(
        ShopOwner(
            shop_id=shop.id,
            user_id=owner_user_id,
            is_primary=True,
            is_active=True,
        )
    )

    # ── Create primary address ──
    # Address is optional for the first-stage profile-creation flow. When
    # absent, skip address creation entirely — the shop is still fully
    # functional and the address is captured later via the location flow.
    if address_data.get("address_line1"):
      db.add(
          ShopAddress(
              shop_id=shop.id,
              address_line1=address_data["address_line1"],
              address_line2=address_data.get("address_line2"),
              landmark=address_data.get("landmark"),
              city=address_data["city"],
              state=address_data["state"],
              pincode=address_data["pincode"],
              country=address_data.get("country", "India"),
              latitude=address_data.get("latitude", latitude),
              longitude=address_data.get("longitude", longitude),
              is_primary=True,
          )
      )

    # ── Create opening hours ──
    for h in data.get("hours", []):
        db.add(
            ShopHour(
                shop_id=shop.id,
                day_of_week=h["day_of_week"],
                open_time=h.get("open_time", time(9, 0)),
                close_time=h.get("close_time", time(21, 0)),
                is_closed=h.get("is_closed", False),
            )
        )

    # ── Create initial verification record ──
    db.add(
        ShopVerification(
            shop_id=shop.id,
            status=VerificationStatus.PENDING,
            submitted_by=owner_user_id,
            submitted_at=datetime.now(timezone.utc),
        )
    )

    db.flush()
    logger.info("Shop registered: %s (id=%s) owner=%s", shop.name, shop.id, owner_user_id)
    return shop


def update_shop(db: Session, shop_id: int, data: dict) -> Optional[Shop]:
    """Update shop profile / operational fields."""
    shop = db.query(Shop).filter(Shop.id == shop_id, Shop.is_deleted == False).first()  # noqa: E712
    if shop is None:
        return None

    # Handle geolocation update
    latitude = data.pop("latitude", None)
    longitude = data.pop("longitude", None)
    if latitude is not None and longitude is not None:
        validate_geolocation(latitude, longitude)
        shop.latitude = latitude
        shop.longitude = longitude
        shop.location = _get_wkt_point(latitude, longitude)

    # Handle subcategories (JSON encoded)
    if "subcategories" in data and data["subcategories"] is not None:
        data["subcategories"] = json.dumps(data["subcategories"])

    for key, value in data.items():
        if value is not None and hasattr(shop, key):
            setattr(shop, key, value)

    db.flush()
    return shop


def update_shop_location(
    db: Session, shop_id: int, latitude: float, longitude: float, meta: dict | None = None
) -> Optional[Shop]:
    """Controlled, ownership-checked location update (Phase: Shop Location System).

    Replaces the shop's spatial anchor and scalar lat/long with the
    shopkeeper-confirmed coordinates and persists the accompanying capture
    metadata. Ownership is enforced by the caller (shopkeeper_service resolves a
    ``ShopAccess`` first), so this function never trusts a caller-supplied
    ``shop_id`` on its own.

    Args:
        db: SQLAlchemy session.
        shop_id: Target shop (already authorized by the caller).
        latitude / longitude: Shop-entrance coordinates confirmed by the shopkeeper.
        meta: Optional capture provenance dict (accuracy_meters,
            location_captured_at, location_source, location_type,
            location_status, location_integrity_status, location_verified).
    """
    validate_geolocation(latitude, longitude)
    shop = db.query(Shop).filter(Shop.id == shop_id, Shop.is_deleted == False).first()  # noqa: E712
    if shop is None:
        return None

    meta = meta or {}
    shop.latitude = latitude
    shop.longitude = longitude
    shop.location = _get_wkt_point(latitude, longitude)
    shop.accuracy_meters = meta.get("accuracy_meters", shop.accuracy_meters)
    shop.location_captured_at = meta.get("location_captured_at", shop.location_captured_at)
    if "location_source" in meta and meta["location_source"]:
        shop.location_source = str(meta["location_source"])
    if "location_type" in meta and meta["location_type"]:
        shop.location_type = str(meta["location_type"])
    # A corrected location is no longer "stale".
    shop.location_status = LocationStatus.CORRECTED.value
    if "location_integrity_status" in meta and meta["location_integrity_status"]:
        shop.location_integrity_status = str(meta["location_integrity_status"])
    if "location_verified" in meta:
        shop.location_verified = bool(meta["location_verified"])

    db.flush()
    return shop
# ── Address management ─────────────────────────────────────────────────────
def add_shop_address(db: Session, shop_id: int, data: dict) -> ShopAddress:
    """Add a new address to the shop."""
    validate_address(data)

    addr = ShopAddress(
        shop_id=shop_id,
        address_line1=data["address_line1"],
        address_line2=data.get("address_line2"),
        landmark=data.get("landmark"),
        city=data["city"],
        state=data["state"],
        pincode=data["pincode"],
        country=data.get("country", "India"),
        latitude=data.get("latitude"),
        longitude=data.get("longitude"),
        is_primary=data.get("is_primary", False),
    )

    # If this is primary, unset existing primary
    if addr.is_primary:
        for existing in db.query(ShopAddress).filter(
            ShopAddress.shop_id == shop_id,
            ShopAddress.is_primary == True,  # noqa: E712
            ShopAddress.is_deleted == False,  # noqa: E712
        ).all():
            existing.is_primary = False

    db.add(addr)
    db.flush()
    return addr


def update_shop_address(db: Session, address_id: int, data: dict) -> Optional[ShopAddress]:
    """Update a shop address."""
    addr = db.query(ShopAddress).filter(
        ShopAddress.id == address_id,
        ShopAddress.is_deleted == False,  # noqa: E712
    ).first()
    if addr is None:
        return None

    if "is_primary" in data and data["is_primary"] is True:
        # Unset existing primary for this shop
        for existing in db.query(ShopAddress).filter(
            ShopAddress.shop_id == addr.shop_id,
            ShopAddress.is_primary == True,  # noqa: E712
            ShopAddress.id != addr.id,
            ShopAddress.is_deleted == False,  # noqa: E712
        ).all():
            existing.is_primary = False

    for key, value in data.items():
        if value is not None and hasattr(addr, key):
            setattr(addr, key, value)

    db.flush()
    return addr


def delete_shop_address(db: Session, address_id: int) -> bool:
    """Soft-delete a shop address."""
    addr = db.query(ShopAddress).filter(ShopAddress.id == address_id).first()
    if addr is None:
        return False
    addr.is_deleted = True
    addr.deleted_at = datetime.now(timezone.utc)
    if addr.is_primary:
        # Promote the next available address to primary
        next_addr = (
            db.query(ShopAddress)
            .filter(
                ShopAddress.shop_id == addr.shop_id,
                ShopAddress.is_deleted == False,  # noqa: E712
                ShopAddress.id != addr.id,
            )
            .first()
        )
        if next_addr:
            next_addr.is_primary = True
    db.flush()
    return True


# ── Hours management ───────────────────────────────────────────────────────
def set_shop_hours(db: Session, shop_id: int, hours: list) -> list[ShopHour]:
    """Replace all opening hours for a shop."""
    validate_hours(hours)

    # Delete existing hours
    for existing in db.query(ShopHour).filter(ShopHour.shop_id == shop_id).all():
        db.delete(existing)

    created = []
    for h in hours:
        hour = ShopHour(
            shop_id=shop_id,
            day_of_week=h["day_of_week"],
            open_time=h.get("open_time", time(9, 0)),
            close_time=h.get("close_time", time(21, 0)),
            is_closed=h.get("is_closed", False),
        )
        db.add(hour)
        created.append(hour)

    db.flush()
    return created


# ── Holidays management ────────────────────────────────────────────────────
def add_shop_holiday(db: Session, shop_id: int, data: dict) -> ShopHoliday:
    """Add a holiday to the shop's schedule."""
    holiday = ShopHoliday(
        shop_id=shop_id,
        holiday_date=data["holiday_date"],
        reason=data.get("reason"),
        is_recurring_yearly=data.get("is_recurring_yearly", False),
    )
    db.add(holiday)
    db.flush()
    return holiday


def remove_shop_holiday(db: Session, holiday_id: int) -> bool:
    """Delete a holiday from the shop's schedule."""
    holiday = db.query(ShopHoliday).filter(ShopHoliday.id == holiday_id).first()
    if holiday is None:
        return False
    db.delete(holiday)
    db.flush()
    return True


# ── Documents management ───────────────────────────────────────────────────
def submit_shop_document(db: Session, shop_id: int, data: dict) -> ShopDocument:
    """Submit a verification document for the shop."""
    doc = ShopDocument(
        shop_id=shop_id,
        document_type=data["document_type"],
        document_url=data["document_url"],
        document_number=data.get("document_number"),
        expires_at=data.get("expires_at"),
    )
    db.add(doc)
    db.flush()

    # Update shop status to DOCUMENTS_SUBMITTED
    shop = db.query(Shop).filter(Shop.id == shop_id).first()
    if shop and shop.status == ShopStatus.REGISTERED:
        shop.status = ShopStatus.DOCUMENTS_SUBMITTED

    return doc


def verify_document(db: Session, document_id: int, reviewer_id: int, is_verified: bool,
                    rejection_reason: Optional[str] = None) -> Optional[ShopDocument]:
    """Admin verifies/rejects a shop document."""
    doc = db.query(ShopDocument).filter(ShopDocument.id == document_id).first()
    if doc is None:
        return None

    doc.is_verified = is_verified
    doc.verified_at = datetime.now(timezone.utc) if is_verified else None
    doc.verified_by = reviewer_id if is_verified else None
    doc.rejection_reason = None if is_verified else rejection_reason
    db.flush()
    return doc


# ── Verification workflow ──────────────────────────────────────────────────
def submit_for_verification(db: Session, shop_id: int, submitted_by: int) -> Optional[ShopVerification]:
    """Submit shop for admin verification (move to PENDING_VERIFICATION)."""
    shop = db.query(Shop).filter(Shop.id == shop_id).first()
    if shop is None:
        return None

    # Transition: DOCUMENTS_SUBMITTED → PENDING_VERIFICATION
    shop.status = ShopStatus.PENDING_VERIFICATION

    verification = ShopVerification(
        shop_id=shop_id,
        status=VerificationStatus.SUBMITTED,
        submitted_by=submitted_by,
        submitted_at=datetime.now(timezone.utc),
    )
    db.add(verification)
    db.flush()
    return verification


def review_verification(
    db: Session,
    shop_id: int,
    reviewer_id: int,
    decision: str,
    review_notes: Optional[str] = None,
) -> Optional[ShopVerification]:
    """Admin reviews shop verification.

    decision: APPROVE | REJECT | SUSPEND | REACTIVATE
    """
    shop = db.query(Shop).filter(Shop.id == shop_id).first()
    if shop is None:
        return None

    now = datetime.now(timezone.utc)

    verification = ShopVerification(
        shop_id=shop_id,
        status=VerificationStatus.UNDER_REVIEW,
        reviewed_by=reviewer_id,
        review_notes=review_notes,
        reviewed_at=now,
    )

    if decision == "APPROVE":
        verification.status = VerificationStatus.VERIFIED
        verification.verified_at = now
        shop.status = ShopStatus.ACTIVE
        shop.is_verified = True
        shop.verified_at = now
        shop.rejection_reason = None
        shop.suspension_reason = None
        shop.suspended_at = None
        shop.reactivated_at = now

    elif decision == "REJECT":
        verification.status = VerificationStatus.REJECTED
        shop.status = ShopStatus.REJECTED
        shop.is_verified = False
        shop.rejection_reason = review_notes

    elif decision == "SUSPEND":
        verification.status = VerificationStatus.REJECTED
        shop.status = ShopStatus.SUSPENDED
        shop.is_verified = False
        shop.suspension_reason = review_notes
        shop.suspended_at = now

    elif decision == "REACTIVATE":
        verification.status = VerificationStatus.VERIFIED
        verification.verified_at = now
        shop.status = ShopStatus.ACTIVE
        shop.is_verified = True
        shop.verified_at = now
        shop.suspension_reason = None
        shop.suspended_at = None
        shop.reactivated_at = now

    else:
        raise ValueError(f"Unknown verification decision: {decision}")

    db.add(verification)
    db.flush()
    return verification


def update_shop_status(db: Session, shop_id: int, status: ShopStatus, reason: Optional[str] = None) -> Optional[Shop]:
    """Admin updates shop status directly (suspend, reactivate, close)."""
    shop = db.query(Shop).filter(Shop.id == shop_id).first()
    if shop is None:
        return None

    shop.status = status
    now = datetime.now(timezone.utc)

    if status == ShopStatus.ACTIVE:
        shop.is_verified = True
        shop.verified_at = shop.verified_at or now
        shop.suspension_reason = None
        shop.suspended_at = None
        shop.reactivated_at = now

    elif status == ShopStatus.SUSPENDED:
        shop.is_verified = False
        shop.suspension_reason = reason
        shop.suspended_at = now

    elif status == ShopStatus.REJECTED:
        shop.is_verified = False
        shop.rejection_reason = reason

    elif status == ShopStatus.CLOSED:
        shop.is_accepting_orders = False
        shop.closed_at = now

    db.flush()
    return shop


# ── Ownership / manager management ─────────────────────────────────────────
def add_owner(db: Session, shop_id: int, user_id: int, is_primary: bool = False) -> ShopOwner:
    """Add an owner to the shop. Validates uniqueness."""
    existing = (
        db.query(ShopOwner)
        .filter(ShopOwner.shop_id == shop_id, ShopOwner.user_id == user_id)
        .first()
    )
    if existing:
        if existing.is_deleted:
            existing.is_deleted = False
            existing.deleted_at = None
            existing.is_active = True
            if is_primary:
                existing.is_primary = True
            db.flush()
            return existing
        raise ValueError("User is already an owner of this shop")

    if is_primary:
        # Unset existing primary owner
        for owner in db.query(ShopOwner).filter(
            ShopOwner.shop_id == shop_id,
            ShopOwner.is_primary == True,  # noqa: E712
            ShopOwner.is_deleted == False,  # noqa: E712
        ).all():
            owner.is_primary = False

    owner = ShopOwner(
        shop_id=shop_id,
        user_id=user_id,
        is_primary=is_primary,
        is_active=True,
    )
    db.add(owner)
    db.flush()
    return owner


def remove_owner(db: Session, shop_id: int, user_id: int) -> bool:
    """Remove an owner from the shop (soft delete)."""
    owner = (
        db.query(ShopOwner)
        .filter(
            ShopOwner.shop_id == shop_id,
            ShopOwner.user_id == user_id,
            ShopOwner.is_deleted == False,  # noqa: E712
        )
        .first()
    )
    if owner is None:
        return False
    owner.is_active = False
    owner.is_deleted = True
    owner.deleted_at = datetime.now(timezone.utc)

    # If primary owner removed, promote another
    if owner.is_primary:
        next_owner = (
            db.query(ShopOwner)
            .filter(
                ShopOwner.shop_id == shop_id,
                ShopOwner.is_deleted == False,  # noqa: E712
                ShopOwner.id != owner.id,
            )
            .first()
        )
        if next_owner:
            next_owner.is_primary = True

    db.flush()
    return True


def add_manager(db: Session, shop_id: int, user_id: int, permissions: Optional[list] = None) -> ShopManager:
    """Add a manager to the shop."""
    existing = (
        db.query(ShopManager)
        .filter(ShopManager.shop_id == shop_id, ShopManager.user_id == user_id)
        .first()
    )
    if existing:
        if existing.is_deleted:
            existing.is_deleted = False
            existing.deleted_at = None
            existing.is_active = True
            if permissions:
                existing.permissions = json.dumps(permissions)
            db.flush()
            return existing
        raise ValueError("User is already a manager of this shop")

    manager = ShopManager(
        shop_id=shop_id,
        user_id=user_id,
        permissions=json.dumps(permissions) if permissions else None,
        is_active=True,
    )
    db.add(manager)
    db.flush()
    return manager


def update_manager_permissions(db: Session, manager_id: int, permissions: list) -> Optional[ShopManager]:
    """Update permissions for a shop manager."""
    manager = db.query(ShopManager).filter(
        ShopManager.id == manager_id,
        ShopManager.is_deleted == False,  # noqa: E712
    ).first()
    if manager is None:
        return None
    manager.permissions = json.dumps(permissions)
    db.flush()
    return manager


def remove_manager(db: Session, shop_id: int, user_id: int) -> bool:
    """Remove a manager from the shop (soft delete)."""
    manager = (
        db.query(ShopManager)
        .filter(
            ShopManager.shop_id == shop_id,
            ShopManager.user_id == user_id,
            ShopManager.is_deleted == False,  # noqa: E712
        )
        .first()
    )
    if manager is None:
        return False
    manager.is_active = False
    manager.is_deleted = True
    manager.deleted_at = datetime.now(timezone.utc)
    db.flush()
    return True


# ── Query helpers ──────────────────────────────────────────────────────────
def get_shop_detail(db: Session, shop_id: int) -> Optional[Shop]:
    """Get a shop with all nested relationships loaded."""
    return (
        db.query(Shop)
        .filter(Shop.id == shop_id, Shop.is_deleted == False)  # noqa: E712
        .options(
            selectinload(Shop.addresses),
            selectinload(Shop.hours),
            selectinload(Shop.holidays),
            selectinload(Shop.documents),
            selectinload(Shop.owners),
            selectinload(Shop.managers),
            selectinload(Shop.verifications),
        )
        .first()
    )


def list_shops(
    db: Session,
    *,
    owned_by: Optional[int] = None,
    status: Optional[ShopStatus] = None,
    category: Optional[ShopCategory] = None,
    search: Optional[str] = None,
    skip: int = 0,
    limit: int = 50,
) -> list[Shop]:
    """List shops with optional filters."""
    query = db.query(Shop).filter(Shop.is_deleted == False)  # noqa: E712

    if owned_by is not None:
        query = query.join(ShopOwner).filter(
            ShopOwner.user_id == owned_by,
            ShopOwner.is_active == True,  # noqa: E712
            ShopOwner.is_deleted == False,  # noqa: E712
        )

    if status is not None:
        query = query.filter(Shop.status == status)

    if category is not None:
        query = query.filter(Shop.category == category)

    if search:
        pattern = f"%{search.strip()}%"
        query = query.filter(
            or_(
                Shop.name.ilike(pattern),
                Shop.slug.ilike(pattern),
                Shop.description.ilike(pattern),
            )
        )

    return query.offset(skip).limit(limit).all()


def is_user_owner(db: Session, user_id: int, shop_id: int) -> bool:
    """Check if a user is an active owner of a shop."""
    return (
        db.query(ShopOwner)
        .filter(
            ShopOwner.shop_id == shop_id,
            ShopOwner.user_id == user_id,
            ShopOwner.is_active == True,  # noqa: E712
            ShopOwner.is_deleted == False,  # noqa: E712
        )
        .first()
        is not None
    )


def is_user_manager(db: Session, user_id: int, shop_id: int) -> bool:
    """Check if a user is an active manager of a shop."""
    return (
        db.query(ShopManager)
        .filter(
            ShopManager.shop_id == shop_id,
            ShopManager.user_id == user_id,
            ShopManager.is_active == True,  # noqa: E712
            ShopManager.is_deleted == False,  # noqa: E712
        )
        .first()
        is not None
    )


def has_shop_access(db: Session, user: User, shop_id: int) -> bool:
    """Check if a user has owner/manager/admin access to a shop."""
    if user.role is not None and user.role.name == "admin":
        return True
    return is_user_owner(db, user.id, shop_id) or is_user_manager(db, user.id, shop_id)


def user_shop_ids(db: Session, user_id: int) -> list[int]:
    """Return all shop IDs the user owns or manages."""
    owner_ids = [
        r.shop_id
        for r in db.query(ShopOwner).filter(
            ShopOwner.user_id == user_id,
            ShopOwner.is_active == True,  # noqa: E712
            ShopOwner.is_deleted == False,  # noqa: E712
        ).all()
    ]
    manager_ids = [
        r.shop_id
        for r in db.query(ShopManager).filter(
            ShopManager.user_id == user_id,
            ShopManager.is_active == True,  # noqa: E712
            ShopManager.is_deleted == False,  # noqa: E712
        ).all()
    ]
    return list(set(owner_ids + manager_ids))


def nearby_shops(
    db: Session,
    latitude: float,
    longitude: float,
    radius_km: float = 5.0,
    limit: int = 50,
) -> list[dict]:
    """Return active/verified shops near a location with distance."""
    shops = db.query(Shop).filter(
        Shop.is_deleted == False,  # noqa: E712
        Shop.status.in_([ShopStatus.ACTIVE, ShopStatus.VERIFIED]),
        Shop.is_verified == True,  # noqa: E712
        Shop.is_accepting_orders == True,  # noqa: E712
    ).all()

    results = []
    # Resolved once for every candidate rather than per row appended: the
    # customer-facing capability block is what tells the app whether this is a
    # product shop, a restaurant or a service provider.
    business_blocks = customer_facing_business_batch(db, shops)
    for shop in shops:
        shop_longitude, shop_latitude = resolve_shop_coordinates(shop)
        if shop_longitude is None or shop_latitude is None:
            continue
        dist = haversine_km(latitude, longitude, shop_latitude, shop_longitude)
        if dist <= radius_km:
            entry = {
                "id": shop.id,
                "name": shop.name,
                "image_url": shop.image_url,
                "latitude": shop_latitude,
                "longitude": shop_longitude,
                "distance_km": round(dist, 2),
                "rating": shop.rating,
                "is_verified": shop.is_verified,
                "category": shop.category.value if shop.category else None,
                "is_open_now": is_shop_open(shop),
            }
            entry.update(business_blocks.get(shop.id, {}))
            results.append(entry)

    results.sort(key=lambda s: s["distance_km"])
    return results[:limit]


# ── Customer-facing business identity & capabilities ────────────────────────
# The customer app renders a business profile from the CAPABILITIES the backend
# returns, rather than branching on category names itself. Two consequences that
# are the whole reason this exists:
#
#  * a restaurant never inherits a price/stock grid, and a transport provider
#    never inherits one either — enforced server-side, so an app build cannot
#    drift from the policy;
#  * a category (or a capability on it) added later reaches customers without an
#    app release, because the client is rendering data it was given.
def _merchant_category_codes(db: Session, shop_ids: list[int]) -> dict[int, str]:
    """Authoritative merchant-category code per shop, in ONE query.

    Batch rather than per-shop on purpose: this feeds list endpoints
    (``/shops/nearby``), where a query per row would turn one request into N+1.

    The query loads the onboarding RECORDS (a single model argument) and
    projects the two columns in Python, rather than asking the session for two
    columns at once: the two-column form needs a chained mock for every unit
    test double, while this form rides the same ``db.query(Model)`` path every
    service function already uses.
    """
    if not shop_ids:
        return {}
    try:
        records = (
            db.query(MerchantOnboarding)
            .filter(MerchantOnboarding.shop_id.in_(shop_ids))
            .all()
        )
    except SQLAlchemyError:
        # The onboarding table is a later addition, and a deployment can be
        # missing it (a stale migration, a partially applied schema, a test
        # fixture that creates only the tables it needs). A shop profile is a
        # customer-facing read that must not start failing over an optional
        # enrichment, so this degrades to the legacy category / business type
        # signals rather than returning a 500.
        #
        # Deliberately narrow: SQLAlchemy wraps BOTH "no such table" and a real
        # connection failure in the same class, and a connection failure must
        # still surface rather than be swallowed here.
        logger.warning(
            "merchant_onboardings unavailable; falling back to legacy category "
            "signals for %d shop(s)",
            len(shop_ids),
        )
        return {}

    codes: dict[int, str] = {}
    for record in records:
        shop_id = getattr(record, "shop_id", None)
        code = getattr(record, "category_code", None)
        if code:
            codes[shop_id] = code
    return codes


def _business_block(shop: Shop, merchant_category_code: Optional[str]) -> dict:
    """The capability block for one shop, resolved from every available signal."""
    legacy_category = getattr(shop.category, "value", None) if shop.category else None
    business_type = getattr(shop, "business_type", None)
    capabilities = resolve_customer_capabilities(
        merchant_category_code=merchant_category_code,
        legacy_shop_category=legacy_category,
        business_type=business_type,
    )
    return {
        "business_category_code": merchant_category_code,
        "business_category_name": MERCHANT_CATEGORY_NAMES.get(
            merchant_category_code or ""
        ),
        "business_type": business_type,
        "capabilities": list(capabilities),
    }


def customer_facing_business(db: Session, shop: Shop) -> dict:
    """Business identity + capabilities for a single shop."""
    codes = _merchant_category_codes(db, [shop.id])
    return _business_block(shop, codes.get(shop.id))


def customer_facing_business_batch(db: Session, shops: list[Shop]) -> dict[int, dict]:
    """Business identity + capabilities for many shops, in a constant number of
    queries. Keyed by shop id so a caller never has to align two lists."""
    codes = _merchant_category_codes(db, [shop.id for shop in shops])
    return {shop.id: _business_block(shop, codes.get(shop.id)) for shop in shops}


def parse_subcategories(value: Optional[str]) -> Optional[list]:
    """Parse JSON subcategories string to list."""
    if not value:
        return None
    try:
        return json.loads(value)
    except (json.JSONDecodeError, TypeError):
        return [value]