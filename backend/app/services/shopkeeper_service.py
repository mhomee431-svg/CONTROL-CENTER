"""Phase 22 — Shopkeeper App business logic.

All shopkeeper operations are SHOP-SCOPED and ASSOCIATION-CHECKED:
``resolve_shop_access`` must pass before any resource is read or mutated,
guaranteeing a shopkeeper can only manage authorized shops.

This module contains no customer-app logic — customer features live in
their own services/routes.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass, field
from datetime import datetime, timedelta, time, timezone
import re
import uuid
from typing import Any

from sqlalchemy import func, or_
from sqlalchemy.orm import Session, defer, joinedload, selectinload

from app.core.exceptions import (
    AppError,
    ConflictError,
    ForbiddenError,
    NotFoundError,
    ValidationError,
)
from app.core.logging import get_logger
from app.core.shopkeeper_permissions import (
    effective_shop_permissions,
    ensure_shopkeeper_role,
    has_permission,
    sync_owner_role,
)
from app.models.product import (
    Category,
    FreshnessStatus,
    IdentifierType,
    Inventory,
    InventoryAdjustment,
    InventoryMovement,
    InventorySource,
    Offer,
    OfferProduct,
    OfferStatus,
    OfferType,
    PriceHistory,
    ProductAttribute,
    ProductAttributeValue,
    ProductIdentifier,
    ProductImage,
    ProductMaster,
    ProductStatus,
    ShopProduct,
)
from app.services.inventory_service import compute_freshness
from app.models.shop import (
    Shop,
    ShopAddress,
    ShopManager,
    ShopOwner,
    ShopStatus,  # noqa: F401 - registers shops table + status enum on Base.metadata  # pyright: ignore[reportUnusedImport]
    ShopVerification,
    VerificationStatus,
)
from app.models.merchant_category import MerchantCategoryCode
from app.models.subscription import Subscription
from app.models.user import User, UserStatus
from app.services import shop_service
from app.services import product_attribute_writer
from app.services import product_convergence
from app.models import product_attributes

logger = get_logger("app.services.shopkeeper")


# ── Merchant categories → legacy shop categories ───────────────────────────
# The shop-registration wizard lists the 11 approved merchant categories
# (MerchantCategoryCode). The shops.category column stores the legacy
# ShopCategory enum for catalog compatibility; this map is the only place
# that translates between the two. The authoritative merchant code itself is
# persisted on the merchant-onboarding record.
MERCHANT_CATEGORY_TO_LEGACY_SHOP_CATEGORY = {
    "PHARMACY_HEALTHCARE": "PHARMACY",
    "BEAUTY_PERSONAL_CARE": "BEAUTY",
    "FURNITURE_HOME_CARE": "OTHER",
    "HOUSEHOLD_GOODS": "OTHER",
    "SPORTS_FITNESS_OUTDOOR": "OTHER",
    "BOOKS_MEDIA_STATIONERY": "STATIONERY",
    "AUTOMOTIVE_PARTS_TOOLS": "OTHER",
    "HARDWARE": "HARDWARE",
    "RESTAURANTS": "RESTAURANT",
    "TRANSPORT": "OTHER",
    "PERSONAL_TRANSPORT_TRAVEL": "OTHER",
}

# ONE source of truth guards for the migration map above. It must (a) cover
# EXACTLY the 11 approved MerchantCategoryCode values and (b) never map an
# approved category onto a legacy grocery / general-food enum member
# (GROCERY, DAIRY, MEAT, VEGETABLES, BAKERY), which would silently let Grocery
# flow through as a business category. The authoritative merchant code itself is
# persisted on the merchant-onboarding record, never on Shop.category alone.
_FOREIGN_GROCERY_LEGACY = {"GROCERY", "DAIRY", "MEAT", "VEGETABLES", "BAKERY"}
assert set(MERCHANT_CATEGORY_TO_LEGACY_SHOP_CATEGORY) == {
    c.value for c in MerchantCategoryCode
}, "MERCHANT_CATEGORY_TO_LEGACY_SHOP_CATEGORY must map exactly the 11 MerchantCategoryCode values"
assert not {
    legacy.upper() for legacy in MERCHANT_CATEGORY_TO_LEGACY_SHOP_CATEGORY.values()
} & _FOREIGN_GROCERY_LEGACY, (
    "category map must never map an approved category to a grocery legacy category"
)

logger = get_logger("app.services.shopkeeper")
# ── Access resolution ────────────────────────────────────────────────────


@dataclass
class ShopAccess:
    """Resolved authorization context for a user ↔ shop pair."""

    shop: Shop
    role_name: str | None  # "owner" | "manager" | "admin"
    is_owner: bool = False
    permissions: set[str] = field(default_factory=set)  # pyright: ignore[reportUnknownVariableType]

    def can(self, resource: str, action: str) -> bool:
        return has_permission(self.permissions, resource, action)

    def require(self, resource: str, action: str) -> None:
        if not self.can(resource, action):
            raise ForbiddenError(f"Missing shopkeeper permission: {action}:{resource}")


def resolve_shop_access(db: Session, user: User, shop_id: int) -> ShopAccess:
    """Authorize *user* against *shop_id*.

    Allowed:
      - admins (global bypass)
      - active owners of the shop (full catalog)
      - active managers of the shop (manager catalog ∩ granted subset)
    Everyone else — including plain customers — gets ``ForbiddenError``.
    """
    # Defer the PostGIS geometry column — SQLite dev has no AsBinary(), so
    # loading it crashes. The location is irrelevant to access resolution.
    shop = (
        db.query(Shop)
        .options(defer(Shop.location))
        .filter(Shop.id == shop_id, Shop.is_deleted == False)  # noqa: E712
        .first()
    )
    if shop is None:
        raise NotFoundError("Shop not found")

    role_name = user.role.name if user.role else None

    owner = (
        db.query(ShopOwner)
        .filter(
            ShopOwner.shop_id == shop_id,
            ShopOwner.user_id == user.id,
            ShopOwner.is_active == True,  # noqa: E712
        )
        .first()
    )
    if owner is not None:
        owner_permissions: set[str] = set(effective_shop_permissions(role_name, True, None))  # pyright: ignore[reportUnknownArgumentType]
        return ShopAccess(
            shop=shop,
            role_name="admin" if role_name == "admin" else "owner",
            is_owner=True,
            permissions=owner_permissions,
        )

    manager = (
        db.query(ShopManager)
        .filter(
            ShopManager.shop_id == shop_id,
            ShopManager.user_id == user.id,
            ShopManager.is_active == True,  # noqa: E712
        )
        .first()
    )
    if manager is not None:
        perms: set[str] = set(effective_shop_permissions(role_name, False, manager))  # pyright: ignore[reportUnknownArgumentType]
        if not perms:
            raise ForbiddenError("You do not have access to this shop")
        return ShopAccess(
            shop=shop, role_name="manager", is_owner=False, permissions=perms
        )

    if role_name == "admin":
        admin_permissions: set[str] = set(effective_shop_permissions("admin", True, None))  # pyright: ignore[reportUnknownArgumentType]
        return ShopAccess(
            shop=shop,
            role_name="admin",
            is_owner=True,
            permissions=admin_permissions,
        )

    raise ForbiddenError("You do not have access to this shop")


def list_authorized_shops(db: Session, user: User) -> list[dict[str, Any]]:
    """Serialize every shop the user owns or manages."""
    entries: dict[int, dict[str, Any]] = {}

    owner_rows = (
        db.query(ShopOwner)
        .filter(
            ShopOwner.user_id == user.id,
            ShopOwner.is_active == True,  # noqa: E712
        )
        .all()
    )
    for row in owner_rows:
        # Defer PostGIS geometry (AsBinary unavailable on SQLite dev).
        shop = db.query(Shop).options(defer(Shop.location)).filter(
            Shop.id == row.shop_id
        ).first()
        if shop is None or getattr(shop, "is_deleted", False):
            continue
        entries[row.shop_id] = _shop_summary(
            shop,
            membership="owner",
            permissions=effective_shop_permissions(
                user.role.name if user.role else None, True, None
            ),
        )

    manager_rows = (
        db.query(ShopManager)
        .filter(
            ShopManager.user_id == user.id,
            ShopManager.is_active == True,  # noqa: E712
        )
        .all()
    )
    for row in manager_rows:
        if row.shop_id in entries:
            continue
        # Defer PostGIS geometry (AsBinary unavailable on SQLite dev).
        shop = db.query(Shop).options(defer(Shop.location)).filter(
            Shop.id == row.shop_id
        ).first()
        if shop is None or getattr(shop, "is_deleted", False):
            continue
        perms = effective_shop_permissions(
            user.role.name if user.role else None, False, row
        )
        if not perms:
            continue
        entries[row.shop_id] = _shop_summary(shop, membership="manager", permissions=perms)

    return sorted(entries.values(), key=lambda s: s["id"])


# ── Account registration ─────────────────────────────────────────────────


def generate_business_id(db: Session, phone_number: str | None) -> str:
    """Generate a unique Business ID mapped to the shopkeeper's phone number.

    Primary format: ``SHOP_<last 10 digits of phone>`` (e.g. SHOP_919000000011).
    If that candidate is already taken (legacy collision), fall back to a random
    ``SHOP_<hex>`` suffix until unique.
    """
    digits = re.sub(r"\D", "", phone_number or "")
    candidate = (
        f"SHOP_{digits[-10:]}"
        if len(digits) >= 10
        else f"SHOP_{digits or uuid.uuid4().hex[:10].upper()}"
    )
    # Bounded search so a pathological DB never loops forever.
    for _attempt in range(100):
        if db.query(User).filter(User.business_id == candidate).first() is None:
            return candidate
        candidate = f"SHOP_{uuid.uuid4().hex[:10].upper()}"
    raise RuntimeError("Could not generate a unique business_id")


def create_shopkeeper_account(
    db: Session,
    phone_number: str | None,
    name: str,
    email: str | None = None,
    password_hash: str | None = None,
    firebase_uid: str | None = None,
    avatar_url: str | None = None,
) -> User:
    """Create a new user carrying the shopkeeper role.

    Shopkeepers deliberately get NO Customer profile — they are business
    accounts on the platform.

    Supports both phone-OTP and Google Sign-In:
    - Phone OTP: phone_number + name
    - Google Sign-In: firebase_uid + email + name + avatar (phone may be empty)
    """
    role = ensure_shopkeeper_role(db)
    user = User(
        phone_number=phone_number,
        name=name.strip(),
        email=email,
        avatar_url=avatar_url,
        password_hash=password_hash,
        firebase_uid=firebase_uid,
        role_id=role.id,
        status=UserStatus.ACTIVE,
        is_active=True,
    )
    db.add(user)
    db.flush()
    logger.info("Shopkeeper account created: user=%s firebase_uid=%s", user.id, firebase_uid)
    return user


# ── Shop registration (wraps shared shop_service) ────────────────────────


def register_shop_for_shopkeeper(db: Session, user: User, data: dict[str, Any]) -> Shop:
    """Register a new shop owned by *user* (becomes primary owner)."""
    from app.models.shop import ShopCategory

    payload: dict[str, Any] = dict(data)
    address: dict[str, Any] = payload.pop("address", None) or {}
    category = payload.get("category")
    merchant_category_code: str | None = None
    if isinstance(category, str):
        normalized = category.strip().upper()
        # Approved merchant categories (see MerchantCategoryCode) map onto the
        # legacy shop.category enum for catalog compatibility; the authoritative
        # merchant code is persisted on the onboarding record that drives the
        # post-registration verification flow (documents, bank, approval).
        legacy = MERCHANT_CATEGORY_TO_LEGACY_SHOP_CATEGORY.get(normalized)
        if legacy is not None:
            merchant_category_code = normalized
            # The map values are plain strings ("PHARMACY", "HARDWARE", …).
            # ShopCategory is a `str`-mixin enum, so the raw string IS a valid
            # category everywhere downstream (SQLAlchemy coerces it). Calling
            # `.value` on the string crashed with AttributeError → 500.
            payload["category"] = legacy
        else:
            valid = {c.name for c in ShopCategory}
            if normalized and normalized not in valid:
                raise ValidationError(f"Invalid shop category: {category}")
            payload["category"] = normalized or None

    hours = [
        {
            "day_of_week": day,
            "open_time": time(9, 0),
            "close_time": time(21, 0),
            "is_closed": False,
        }
        for day in range(7)
    ]

    shop = shop_service.register_shop(
        db,
        {**payload, "address": address, "hours": hours},
        owner_user_id=user.id,
    )
    sync_owner_role(db, user)

    # Category-driven verification starts here: when the shop was registered
    # under an approved merchant category, bind it to an onboarding record so
    # the documents/bank/approval timeline (shown on the wizard's success
    # screen) is driven by the real category. Idempotent & side-effect free —
    # a later explicit onboarding start returns the same record.
    if merchant_category_code is not None:
        from app.services import merchant_onboarding_service

        merchant_onboarding_service.get_or_create_onboarding(
            db, user, shop.id, merchant_category_code
        )

    return shop


# ── Shop location update (controlled Edit-Location workflow) ─────────────


def _location_snapshot(shop: Shop) -> dict[str, Any]:
    """Audit-safe snapshot of a shop's current location state."""
    from app.services.geo_service import resolve_shop_coordinates

    longitude, latitude = resolve_shop_coordinates(shop)
    return {
        "latitude": latitude if latitude is not None else shop.latitude,
        "longitude": longitude if longitude is not None else shop.longitude,
        "accuracy_meters": getattr(shop, "accuracy_meters", None),
        "location_source": getattr(shop, "location_source", None),
        "location_type": getattr(shop, "location_type", None),
        "location_status": getattr(shop, "location_status", None),
        "location_integrity_status": getattr(shop, "location_integrity_status", None),
        "location_captured_at": _iso(getattr(shop, "location_captured_at", None)),
        "location_verified": bool(getattr(shop, "location_verified", False)),
    }


def update_shop_location_for_shopkeeper(
    access: ShopAccess,
    db: Session,
    user: User,
    latitude: float,
    longitude: float,
    meta: dict[str, Any] | None = None,
    request_meta: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Persist a confirmed location change for an AUTHORIZED shop.

    Flow: ownership/permission is enforced by ``access`` (resolved from the
    path ``shop_id`` — never from the body), preventing IDOR. Managers without
    ``update:shop`` are rejected. Every change is written to the hash-chained
    audit trail with old/new coordinates, accuracies and actor.
    """
    from app.services import audit_service

    # Owners/admins hold update:shop; plain managers do not.
    access.require("shop", "update")

    shop = access.shop
    old_values = _location_snapshot(shop)

    updated = shop_service.update_shop_location(
        db, shop.id, latitude, longitude, meta
    )
    if updated is None:
        raise NotFoundError("Shop not found")

    new_values = _location_snapshot(updated)
    request_meta = request_meta or {}

    audit_service.record_critical_action(
        db,
        action="UPDATE",
        entity_type="SHOP_LOCATION",
        entity_id=updated.id,
        user_id=user.id,
        old_values=old_values,
        new_values=new_values,
        description="Shop location updated via controlled edit-location flow",
        ip_address=request_meta.get("ip_address"),
        user_agent=request_meta.get("user_agent"),
    )

    return new_values


# ── Serialization helpers ────────────────────────────────────────────────


def _iso(value: Any) -> str | None:  # pyright: ignore[reportRedeclaration]
    if value is None:
        return None
    if isinstance(value, str):
        return value
    if isinstance(value, datetime):
        return value.isoformat()
    return str(value)


def _enum_value(value: Any) -> str | None:
    """Enum (or plain string) → its wire value.

    Same `getattr(..., "value", ...)` shape used by `_shop_summary` below, so a
    plain string column and a real enum both serialise without branching.
    """
    if value is None:
        return None
    return str(getattr(value, "value", value))


def _shop_summary(shop: Shop, membership: str, permissions: set[str]) -> dict[str, Any]:
    status = getattr(shop.status, "value", shop.status)
    category = getattr(shop.category, "value", None) if shop.category is not None else None
    return {
        "id": shop.id,
        "name": shop.name,
        "status": status,
        "is_verified": bool(getattr(shop, "is_verified", False)),
        "category": category,
        "image_url": _media_resolver().resolve_media_url(getattr(shop, "image_url", None)),
        "logo_url": _media_resolver().resolve_media_url(getattr(shop, "logo_url", None)),
        "membership": membership,
        "permissions": sorted(permissions),
    }


def capabilities_payload(db: Session, shop: Shop) -> dict[str, bool]:
    """Backend-driven feature flags for one shop (spec section 103).

    Single source of truth: ``entitlements.derive_shop_capabilities`` over
    the resolved subscription entitlements. Never raises - a lookup failure
    degrades to the permissive legacy set so an outage cannot lock a
    shopkeeper out of their own screens (backend stays authoritative via
    403 on actual violations).
    """
    from app.services.subscription import entitlements

    try:
        resolved = entitlements.resolve_shop_entitlements(db, shop)
        return entitlements.derive_shop_capabilities(resolved)
    except Exception:  # noqa: BLE001
        return entitlements.derive_shop_capabilities(
            {"grandfathered": True, "entitlements": {}}
        )


def verification_payload(db: Session, shop: Shop) -> dict[str, Any]:
    """Latest verification record for a shop (or a synthesized PENDING one)."""
    record = (
        db.query(ShopVerification)
        .filter(ShopVerification.shop_id == shop.id)
        .order_by(ShopVerification.id.desc())
        .first()
    )
    if record is None:
        return {
            "status": VerificationStatus.PENDING.value,
            "submitted_at": None,
            "reviewed_at": None,
            "verified_at": None,
            "expires_at": None,
            "review_notes": None,
        }
    return {
        "status": record.status.value,
        "submitted_at": _iso(record.submitted_at),
        "reviewed_at": _iso(record.reviewed_at),
        "verified_at": _iso(record.verified_at),
        "expires_at": _iso(record.expires_at),
        "review_notes": record.review_notes,
    }


def subscription_payload(db: Session, shop: Shop) -> dict[str, Any]:
    sub = (
        db.query(Subscription)
        .filter(Subscription.shop_id == shop.id)
        .order_by(Subscription.id.desc())
        .first()
    )
    if sub is None:
        return {"status": "NONE", "plan": None, "current_period_end": None}
    plan_name = sub.plan.name if sub.plan is not None else None
    return {
        "status": sub.status.value,
        "plan": plan_name,
        "current_period_end": _iso(sub.current_period_end),
    }


def shop_detail_payload(access: ShopAccess, db: Session) -> dict[str, Any]:
    shop = access.shop
    payload = _shop_summary(shop, access.role_name or "none", access.permissions)
    payload.update(
        {
            "description": shop.description,
            "tagline": shop.tagline,
            "phone": shop.phone,
            "alternate_phone": shop.alternate_phone,
            "whatsapp_number": shop.whatsapp_number,
            "email": shop.email,
            "website_url": shop.website_url,
            "latitude": shop.latitude,
            "longitude": shop.longitude,
            "gstin": shop.gstin,
            "is_accepting_orders": shop.is_accepting_orders,
            "is_delivery_available": shop.is_delivery_available,
            "is_pickup_available": shop.is_pickup_available,
            "is_open_24x7": shop.is_open_24x7,
            "min_order_amount": float(shop.min_order_amount or 0),
            "delivery_radius_km": float(shop.delivery_radius_km or 0),
            "delivery_fee": float(shop.delivery_fee or 0),
            "free_delivery_above": float(shop.free_delivery_above or 0),
            # Business Profile facts: business type, registered address and
            # the location-capture metadata the app's profile screen shows.
            "business_type": shop.business_type,
            "address": _primary_address_payload(db, shop),
            "accuracy_meters": shop.accuracy_meters,
            "location_source": shop.location_source,
            "location_type": shop.location_type,
            "location_status": shop.location_status,
            "location_verified": bool(shop.location_verified),
            "location_captured_at": _iso(shop.location_captured_at),
            "verification": verification_payload(db, shop),
            "subscription": subscription_payload(db, shop),
            "capabilities": capabilities_payload(db, shop),
            "rating": shop.rating,
            "review_count": shop.review_count,
            "created_at": _iso(getattr(shop, "created_at", None)),
        }
    )
    return payload


def _primary_address_payload(db: Session, shop: Shop) -> dict[str, Any] | None:
    """The shop's primary registered address, or None when none is stored.

    The registration flow writes one `ShopAddress` per shop; the profile screen
    renders it verbatim — a missing row is absent from the payload rather than
    fabricated as empty strings.
    """
    addr = (
        db.query(ShopAddress)
        .filter(ShopAddress.shop_id == shop.id, ShopAddress.deleted_at.is_(None))
        .order_by(ShopAddress.is_primary.desc(), ShopAddress.id.asc())
        .first()
    )
    if addr is None:
        return None
    return {
        "address_line1": addr.address_line1,
        "address_line2": addr.address_line2,
        "landmark": addr.landmark,
        "city": addr.city,
        "state": addr.state,
        "pincode": addr.pincode,
        "country": addr.country,
    }


# ── Dashboard ────────────────────────────────────────────────────────────


def _derive_stock_status(quantity: int, threshold: int) -> str:
    if quantity <= 0:
        return "OUT_OF_STOCK"
    if quantity <= max(threshold, 1):
        return "LOW_STOCK"
    return "IN_STOCK"


def _enum_from_name(enum_class_name: str, name: str) -> Any:
    import app.models.product as product_models

    enum_cls = getattr(product_models, enum_class_name)
    return enum_cls[name]


def _display_name(sp: ShopProduct) -> str:
    master = getattr(sp, "product_master", None)
    if master is not None and getattr(master, "name", None):
        return master.name
    return f"Product #{sp.product_master_id}"


def _shop_product_status_value(sp: ShopProduct) -> str:
    """``ShopProduct.status`` as a plain string (defaults to ACTIVE when unset)."""
    return str(getattr(sp.status, "value", sp.status) or "ACTIVE").upper()


def is_discontinued(sp: ShopProduct) -> bool:
    """True when the shopkeeper stopped selling this listing.

    ``DISCONTINUED`` lives on ``ShopProduct.status`` — the stock enum has no
    such member — so every count and filter that wants to treat a withdrawn
    listing specially must ask here instead of comparing ``stock_status``.
    """
    return _shop_product_status_value(sp) == "DISCONTINUED"


def _product_counts(
    products: list[ShopProduct],
    inventories: Mapping[int, Inventory | None],
    *,
    include_attention: bool = True,
) -> dict[str, Any]:
    total = len(products)
    active = 0
    in_stock = low_stock = out_of_stock = unknown = discontinued = 0
    units = 0
    stale = 0
    needs_attention: list[dict[str, Any]] = []
    for p in products:
        inv = inventories.get(p.id)
        qty = int(inv.quantity) if inv is not None else 0
        threshold = (
            int(inv.low_stock_threshold)
            if inv is not None and inv.low_stock_threshold
            else 5
        )
        raw_status = (
            inv.stock_status.value
            if inv is not None and getattr(inv, "stock_status", None) is not None
            else None
        )
        status = raw_status or _derive_stock_status(qty, threshold)
        units += qty
        # Freshness is a per-Inventory tier, so the STALE count is the same
        # number the client used to derive by walking every item of
        # `view=list`. Counting it here is what lets the home screen ask for a
        # summary instead of downloading the whole catalogue to count rows.
        if inv is not None and getattr(inv, "freshness_status", None) is not None:
            freshness = inv.freshness_status
            if hasattr(freshness, "value"):
                freshness = freshness.value
            if str(freshness) == FreshnessStatus.STALE.value:
                stale += 1
        # A withdrawn listing is not "in stock" however many units remain: it
        # is counted once, in its own bucket, and never becomes a restock task.
        if is_discontinued(p):
            discontinued += 1
            continue
        if p.is_active and p.is_available:
            active += 1
        if status in ("IN_STOCK", "PRE_ORDER", "BACK_ORDER"):
            in_stock += 1
        elif status in ("LOW_STOCK", "LIMITED_STOCK"):
            low_stock += 1
        elif status == "OUT_OF_STOCK":
            out_of_stock += 1
        else:
            unknown += 1
        if status in ("LOW_STOCK", "LIMITED_STOCK", "OUT_OF_STOCK") and p.is_active:
            needs_attention.append(
                {
                    "shop_product_id": p.id,
                    "name": _display_name(p),
                    "quantity": qty,
                    "stock_status": status,
                }
            )

    inactive = total - active - discontinued
    counts: dict[str, Any] = {
        "total": total,
        "active": active,
        "inactive": inactive,
        "discontinued": discontinued,
        "in_stock": in_stock,
        "low_stock": low_stock,
        "out_of_stock": out_of_stock,
        "unknown": unknown,
        "total_units": units,
        "stale": stale,
    }
    if include_attention:
        counts["needs_attention"] = sorted(
            needs_attention,
            key=lambda x: (x["stock_status"] != "OUT_OF_STOCK", -x["quantity"]),
        )[:10]
    else:
        # Counts-only views ship the SIZE of the restock queue, not the rows:
        # a home-screen badge never renders them, and the rows stay available
        # from `view=overview` / `view=list` for the screens that do.
        counts["needs_attention_count"] = len(needs_attention)
    return counts


def _iso(value: Any) -> str | None:  # pyright: ignore[reportRedeclaration]
    if value is None:
        return None
    if isinstance(value, str):
        return value
    if isinstance(value, datetime):
        return value.isoformat()
    return str(value)


def dashboard_payload(access: ShopAccess, db: Session) -> dict[str, Any]:
    """Operational dashboard: counts, inventory health, recents, statuses."""
    shop = access.shop
    products: list[ShopProduct] = (
        db.query(ShopProduct).filter(ShopProduct.shop_id == shop.id).all()
    )
    inventories: dict[int, Inventory] = {}
    for sp in products:
        inv = db.query(Inventory).filter(Inventory.shop_product_id == sp.id).first()
        if inv is not None:
            inventories[sp.id] = inv

    stats = _product_counts(products, inventories)

    epoch = datetime.min.replace(tzinfo=timezone.utc)

    def _stamp(sp: ShopProduct) -> datetime:
        candidates = [
            s
            for s in (
                sp.last_inventory_update,
                sp.last_price_update,
                getattr(sp, "updated_at", None),
                getattr(sp, "created_at", None),
            )
            if s is not None
        ]
        return max(candidates) if candidates else epoch

    def _kind(sp: ShopProduct) -> str:
        stamps = [s for s in (sp.last_inventory_update, sp.last_price_update) if s is not None]
        latest = max(stamps) if stamps else None
        if latest is None:
            return "product_created"
        if sp.last_inventory_update is not None and latest == sp.last_inventory_update:
            return "stock_update"
        return "price_update"

    recent_updates: list[dict[str, Any]] = []
    for sp in sorted(products, key=_stamp, reverse=True)[:8]:
        inv = inventories.get(sp.id)
        recent_updates.append(
            {
                "type": _kind(sp),
                "shop_product_id": sp.id,
                "label": f"{_display_name(sp)} · {_kind(sp).replace('_', ' ')}",
                "at": _iso(_stamp(sp)),
                "quantity": int(inv.quantity) if inv is not None else None,
            }
        )

    offers: list[Offer] = db.query(Offer).filter(Offer.shop_id == shop.id).all()
    now = datetime.now(timezone.utc)
    offers_summary = {
                "total": len(offers),
        "active": sum(
            1
            for o in offers
            if (
                o.status == OfferStatus.ACTIVE
                and o.end_date is not None  # pyright: ignore[reportUnnecessaryComparison]
                and _to_utc(o.end_date) >= now
            )
        ),
        "draft": sum(1 for o in offers if o.status == OfferStatus.DRAFT),
    }

    return {
        "shop": {
            "id": shop.id,
            "name": shop.name,
            "status": shop.status.value,
            "is_verified": bool(shop.is_verified),
        },
        "verification": verification_payload(db, shop),
        "subscription": subscription_payload(db, shop),
        "capabilities": capabilities_payload(db, shop),
        "products": stats,
        "inventory_status": {
            "in_stock": stats["in_stock"],
            "low_stock": stats["low_stock"],
            "out_of_stock": stats["out_of_stock"],
            "total_units": stats["total_units"],
            "needs_attention": stats["needs_attention"],
        },
        "recent_updates": recent_updates,
        "offers": offers_summary,
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }


def business_insights(access: ShopAccess, db: Session) -> dict[str, Any]:
    """Shopkeeper business insights — data-driven insight cards.

    Returns a list of insight cards, each with a status (``healthy`` /
    ``warning`` / ``critical`` / ``info``), key metrics, and (where relevant)
    the specific items that triggered the insight. All numbers are derived from
    the live database — no hardcoded values.
    """
    shop = access.shop

    # Fetch all products + inventories for this shop (same pattern as dashboard)
    products = db.query(ShopProduct).filter(ShopProduct.shop_id == shop.id).all()
    inventories: dict[int, Inventory] = {}
    for sp in products:
        inv = db.query(Inventory).filter(Inventory.shop_product_id == sp.id).first()
        if inv is not None:
            inventories[sp.id] = inv

    now = datetime.now(timezone.utc)
    insights: list[dict[str, Any]] = []

    # ── 1. Top Products ────────────────────────────────────────────────────────
    # Rank active, non-discontinued products by a composite of stock value and
    # recent activity. Without a sales ledger, "top" = highest inventory value
    # with a recency boost for recently-touched products.
    active_products = [sp for sp in products if sp.is_active and not is_discontinued(sp)]

    def _top_score(sp: ShopProduct) -> tuple[float, datetime]:
        inv = inventories.get(sp.id)
        quantity = inv.quantity if inv is not None else 0
        stock_value = quantity * (sp.price or 0.0)
        # recency: more recent last update → higher score
        last_ts = None
        for ts in (sp.last_inventory_update, sp.last_price_update, sp.updated_at, sp.created_at):
            if ts is not None:
                if last_ts is None or ts > last_ts:
                    last_ts = ts
        age_days = (now - last_ts).total_seconds() / 86400 if last_ts else 9999
        return stock_value - (age_days * 0.01 * (sp.price or 0.0)), last_ts or datetime.min.replace(tzinfo=timezone.utc)

    ranked = sorted(active_products, key=_top_score, reverse=True)[:5]
    top_items: list[dict[str, Any]] = []
    for sp in ranked:
        inv = inventories.get(sp.id)
        top_items.append({
            "shop_product_id": sp.id,
            "name": _display_name(sp),
            "sku": sp.sku,
            "status": _shop_product_status_value(sp),
            "quantity": inv.quantity if inv is not None else 0,
            "price": sp.price,
            "stock_value": (inv.quantity * (sp.price or 0.0)) if inv is not None else 0,
            "last_updated": _iso(
                max(
                    (ts for ts in (sp.last_inventory_update, sp.last_price_update, sp.updated_at, sp.created_at) if ts is not None),
                    default=datetime.min.replace(tzinfo=timezone.utc),
                    key=lambda ts: ts,
                )
            ),
        })

    insights.append({
        "id": "top_products",
        "title": "Top Products",
        "description": "Your highest-value products ranked by inventory value and recent activity.",
        "status": "healthy" if len(active_products) >= 5 else ("warning" if len(active_products) >= 1 else "info"),
        "metrics": {
            "total_products": len(products),
            "active_products": len(active_products),
            "ranked_count": len(top_items),
            "top_product_value": top_items[0]["stock_value"] if top_items else 0,
        },
        "items": top_items,
        "suggestion": None,
    })
    # ── 2. Low Stock ────────────────────────────────────────────────────────────
    low_stock_items: list[dict[str, Any]] = []
    for sp in products:
        inv = inventories.get(sp.id)
        if inv is None:
            continue
        threshold = inv.low_stock_threshold
        if threshold is not None and inv.quantity <= threshold and inv.quantity > 0:
            low_stock_items.append({
                "shop_product_id": sp.id,
                "name": _display_name(sp),
                "sku": sp.sku,
                "quantity": inv.quantity,
                "low_stock_threshold": (inv.low_stock_threshold if inv.low_stock_threshold is not None else 0),  # pyright: ignore[reportUnnecessaryComparison]
                "gap": (inv.low_stock_threshold if inv.low_stock_threshold is not None else 0) - inv.quantity,  # pyright: ignore[reportUnnecessaryComparison, reportOptionalOperand]
                "status": _shop_product_status_value(sp),
            })
    low_stock_items.sort(key=lambda x: x["gap"], reverse=True)  # pyright: ignore[reportUnknownLambdaType, reportUnknownMemberType]

    low_stock_count = len(low_stock_items)
    insights.append({
        "id": "low_stock",
        "title": "Low Stock Alert",
        "description": "Products at or below their low-stock threshold — restock soon to avoid lost sales.",
        "status": (
            "critical" if low_stock_count >= 10
            else "warning" if low_stock_count >= 1
            else "healthy" if low_stock_count == 0
            else "info"
        ),
        "metrics": {
            "count": low_stock_count,
            "total_products": len(products),
            "percentage": round(low_stock_count / max(len(products), 1) * 100, 1),
            "total_gap_units": sum(item["gap"] for item in low_stock_items),
        },
        "items": low_stock_items[:10],
        "suggestion": (
            "Restock the items above. Consider raising low-stock thresholds for fast-moving products."
            if low_stock_count > 0 else None
        ),
    })
    # ── 3. Stale Inventory ──────────────────────────────────────────────────────
    STALE_DAYS = 30
    stale_cutoff = now - timedelta(days=STALE_DAYS)
    stale_items: list[dict[str, Any]] = []
    for sp in products:
        if not sp.is_active or is_discontinued(sp):
            continue
        inv = inventories.get(sp.id)
        if inv is None or inv.quantity <= 0:
            continue
        # Find most recent update timestamp
        last_ts = None
        for ts in (sp.last_inventory_update, sp.last_price_update, sp.updated_at, sp.created_at):
            if ts is not None:
                if last_ts is None or ts > last_ts:
                    last_ts = ts
        if last_ts is None or last_ts < stale_cutoff:
            stale_items.append({
                "shop_product_id": sp.id,
                "name": _display_name(sp),
                "sku": sp.sku,
                "quantity": inv.quantity,
                "last_inventory_update": _iso(sp.last_inventory_update),
                "last_price_update": _iso(sp.last_price_update),
                "days_since_update": round((now - last_ts).total_seconds() / 86400) if last_ts else None,
                "status": _shop_product_status_value(sp),
            })
    stale_items.sort(key=lambda x: x["days_since_update"] or 0, reverse=True)  # pyright: ignore[reportUnknownLambdaType, reportUnknownMemberType]

    stale_count = len(stale_items)
    active_in_stock = sum(
        1 for sp in products
        if sp.is_active and not is_discontinued(sp) and inventories.get(sp.id) is not None and inventories[sp.id].quantity > 0
    )
    insights.append({
        "id": "stale_inventory",
        "title": "Stale Inventory",
        "description": f"Active, in-stock products not updated in {STALE_DAYS} days — review pricing, stock levels, or discontinue.",
        "status": (
            "critical" if stale_count >= 10
            else "warning" if stale_count >= 1
            else "healthy" if stale_count == 0
            else "info"
        ),
        "metrics": {
            "count": stale_count,
            "total_active_in_stock": active_in_stock,
            "percentage": round(stale_count / max(active_in_stock, 1) * 100, 1),
            "oldest_stale_days": max((item["days_since_update"] or 0) for item in stale_items) if stale_items else 0,
        },
        "items": stale_items[:10],
        "suggestion": (
            "Update stock counts, refresh prices, or mark stale items as discontinued."
            if stale_count > 0 else None
        ),
    })
    # ── 4. Product Search Visibility ────────────────────────────────────────────
    status_counts: dict[str, int] = {}
    missing_images = 0
    visible_count = 0
    for sp in products:
        status_val = _shop_product_status_value(sp)
        status_counts[status_val] = status_counts.get(status_val, 0) + 1
        # Visible = the listing is active AND carries an approved/active status.
        # Compared via the status helper (not the enum object) because the
        # SQLAlchemy column default is only applied at INSERT time — an
        # in-memory / not-yet-flushed row can legitimately have status unset.
        if sp.is_active and _shop_product_status_value(sp) in ("ACTIVE", "APPROVED"):
            visible_count += 1
        # Image data lives on the master and is read from the loaded
        # relationship (not a per-row query). Only ACTIVE listings are counted:
        # an inactive listing cannot be "hidden from search for lack of image".
        if sp.is_active:
            master = getattr(sp, "product_master", None)
            if master is None or not getattr(master, "image_url", None):
                missing_images += 1

    total_products = len(products)
    visibility_pct = round(visible_count / max(total_products, 1) * 100, 1) if total_products else 0.0

    insights.append({
        "id": "search_visibility",
        "title": "Product Search Visibility",
        "description": "How many of your products are visible in search — approved, active, and with images.",
        "status": (
            "healthy" if visibility_pct >= 80
            else "warning" if visibility_pct >= 50
            else "critical" if visibility_pct > 0
            else "info"
        ),
        "metrics": {
            "total_products": total_products,
            "visible_products": visible_count,
            "visibility_percentage": visibility_pct,
            "products_without_images": missing_images,
            "by_status": status_counts,
        },
        "items": [],
        "suggestion": (
            "Products in PENDING_REVIEW, REJECTED, or INACTIVE status are hidden from search. "
            "Review and approve/reactivate them, and add images to improve visibility."
            if visibility_pct < 100 else None
        ),
    })

    # ── 5. Offers Performance ───────────────────────────────────────────────────
    offers = db.query(Offer).filter(Offer.shop_id == shop.id).all()
    # "Active" requires the approved status AND a window that has not ended:
    # an ACTIVE-status offer whose end_date has already passed is expired, not
    # active, so it must not be advertised (or counted) as a running offer.
    active_offers = [
        o
        for o in offers
        if (
            o.status == OfferStatus.ACTIVE
            and o.end_date is not None  # pyright: ignore[reportUnnecessaryComparison]
            and _to_utc(o.end_date) >= now
        )
    ]
    expiring_soon = [
        o for o in active_offers
        if o.end_date is not None and _to_utc(o.end_date) <= now + timedelta(days=7)  # pyright: ignore[reportUnnecessaryComparison]
    ]

    # Offer coverage: % of active products that have at least one offer
    product_ids_with_offers: set[int] = set()
    for o in offers:
        for op in o.offer_products:
            product_ids_with_offers.add(op.shop_product_id)

    total_active_products = len([sp for sp in products if sp.is_active and not is_discontinued(sp)])
    offer_coverage_pct = round(len(product_ids_with_offers) / max(total_active_products, 1) * 100, 1) if total_active_products else 0.0

    by_type: dict[str, int] = {}
    for o in offers:
        by_type[o.offer_type.value] = by_type.get(o.offer_type.value, 0) + 1

    expiring_count = len(expiring_soon)
    insights.append({
        "id": "offers_performance",
        "title": "Offers Performance",
        "description": "Overview of your active, draft, and expiring offers — and how much of your catalog they cover.",
        "status": (
            "healthy" if len(active_offers) >= 1
            else "warning" if total_active_products >= 5
            else "info"
        ),
        "metrics": {
            "total_offers": len(offers),
            "active_offers": len(active_offers),
            "draft_offers": sum(1 for o in offers if o.status == OfferStatus.DRAFT),
            "expiring_soon": expiring_count,
            "offer_coverage_percentage": offer_coverage_pct,
            "products_with_offers": len(product_ids_with_offers),
            "by_type": by_type,
        },
        "items": [
            {
                "offer_id": o.id,
                "title": o.title,
                "offer_type": o.offer_type.value,
                "status": o.status.value,
                "start_date": _iso(o.start_date),
                "end_date": _iso(o.end_date),
                "discount_value": float(o.discount_value) if o.discount_value is not None else None,
                "discount_percentage": float(o.discount_percentage) if o.discount_percentage is not None else None,
                "product_count": len(o.offer_products),
                "is_expiring_soon": o in expiring_soon,
            }
            for o in sorted(active_offers, key=lambda o: o.end_date)[:5]
        ],
        "suggestion": (
            "You have no active offers. Create offers to boost sales and move inventory — "
            "especially on products flagged as low stock or stale."
            if len(active_offers) == 0 and total_active_products >= 5
            else None
        ),
    })
    # ── 6. Profile Completeness ─────────────────────────────────────────────────
    profile_fields = [
        ("name", "Store name", shop.name is not None and shop.name.strip() != ""),  # pyright: ignore[reportUnnecessaryComparison]
        ("description", "Description", shop.description is not None and shop.description.strip() != ""),
        ("tagline", "Tagline", shop.tagline is not None and shop.tagline.strip() != ""),
        ("logo_url", "Logo image", shop.logo_url is not None and shop.logo_url.strip() != ""),
        ("cover_image_url", "Cover image", shop.cover_image_url is not None and shop.cover_image_url.strip() != ""),
        ("image_url", "Store image", shop.image_url is not None and shop.image_url.strip() != ""),
        ("phone", "Phone number", shop.phone is not None and shop.phone.strip() != ""),
        ("email", "Email address", shop.email is not None and shop.email.strip() != ""),
        ("website_url", "Website", shop.website_url is not None and shop.website_url.strip() != ""),
        ("whatsapp_number", "WhatsApp number", shop.whatsapp_number is not None and shop.whatsapp_number.strip() != ""),
        ("category", "Shop category", shop.category is not None),
        ("business_type", "Business type", shop.business_type is not None and shop.business_type.strip() != ""),
    ]

    completed_fields = sum(1 for _, _, filled in profile_fields if filled)
    total_fields = len(profile_fields)
    completeness_pct = round(completed_fields / max(total_fields, 1) * 100, 1)

    missing: list[dict[str, Any]] = [
        {"field": field, "label": label, "value": None}
        for field, label, filled in profile_fields
        if not filled
    ]

    insights.append({
        "id": "profile_completeness",
        "title": "Profile Completeness",
        "description": "How complete your shop profile is — a complete profile builds customer trust and improves search visibility.",
        "status": (
            "healthy" if completeness_pct >= 80
            else "warning" if completeness_pct >= 50
            else "critical" if completeness_pct > 0
            else "info"
        ),
        "metrics": {
            "completed_fields": completed_fields,
            "total_fields": total_fields,
            "completeness_percentage": completeness_pct,
            "missing_fields_count": len(missing),
        },
        "items": missing,
        "suggestion": (
            "Complete the missing profile fields above — especially name, description, logo, "
            "and contact details — to improve customer trust and search visibility."
            if missing else None
        ),
    })

    return {
        "shop": {
            "id": shop.id,
            "name": shop.name,
            "status": shop.status.value,
        },
        "generated_at": now.isoformat(),
        "insights": insights,
    }




def inventory_overview(access: ShopAccess, db: Session) -> dict[str, Any]:
    products: list[ShopProduct] = (
        db.query(ShopProduct).filter(ShopProduct.shop_id == access.shop.id).all()
    )
    items: list[dict[str, Any]] = []
    inventories: dict[int, Inventory] = {}
    for sp in products:
        inv = db.query(Inventory).filter(Inventory.shop_product_id == sp.id).first()
        if inv is not None:
            inventories[sp.id] = inv
        qty = int(inv.quantity) if inv is not None else 0
        threshold = (
            int(inv.low_stock_threshold)
            if inv is not None and inv.low_stock_threshold
            else 5
        )
        status = (
            inv.stock_status.value
            if inv is not None and getattr(inv, "stock_status", None) is not None
            else _derive_stock_status(qty, threshold)
        )
        items.append(
            {
                "shop_product_id": sp.id,
                "name": _display_name(sp),
                "sku": sp.sku,
                "price": float(sp.price or 0),
                "mrp": float(sp.mrp) if sp.mrp is not None else None,
                "is_active": sp.is_active,
                "is_available": sp.is_available,
                "quantity": qty,
                "low_stock_threshold": threshold,
                "stock_status": status,
                "freshness_status": _enum_value(
                    getattr(sp, "freshness_status", None)
                ),
                "source": _enum_value(getattr(sp, "source", None)),
                "last_inventory_update": _iso(sp.last_inventory_update),
            }
        )
    items.sort(key=lambda i: (i["stock_status"] != "OUT_OF_STOCK", -i["quantity"]))
    stats = _product_counts(products, inventories)
    return {"items": items, "summary": stats}


def inventory_summary(access: ShopAccess, db: Session) -> dict[str, Any]:
    """Counts ONLY — no ``items`` row is ever built or serialised.

    This exists for the shopkeeper HOME screen. The dashboard's "needs
    attention" card wants a single number — how many listings are STALE — and
    used to get it by calling :func:`inventory_overview`, which downloads every
    listing in the shop. For a catalogue of any size that is a full-catalogue
    payload on the very first screen after login, purely to count rows the
    server already has.

    ``view=summary`` answers the same question with a fixed-size body: the
    server's own counts, plus the STALE tally. The response is the SAME SHAPE
    for every shop, so it stays small as the catalogue grows.

    Inventories are fetched in ONE query rather than one-per-listing
    (``inventory`` is 1:1 with ``shop_product`` via ``uq_inventory_shop_product``),
    which also removes the N+1 this path would otherwise inherit.
    """
    products: list[ShopProduct] = (
        db.query(ShopProduct).filter(ShopProduct.shop_id == access.shop.id).all()
    )
    inventories: dict[int, Inventory] = {}
    if products:
        rows = (
            db.query(Inventory)
            .filter(Inventory.shop_product_id.in_([p.id for p in products]))
            .all()
        )
        for inv in rows:
            inventories[inv.shop_product_id] = inv
    counts = _product_counts(products, inventories, include_attention=False)
    return {"summary": counts}


def _media_resolver():
    """Lazy import — media_service imports this module, so resolve at call time."""
    from app.services import media_service

    return media_service


def _primary_image_url(master: ProductMaster | None) -> str | None:
    """Resolved (presigned) primary image URL for a product master, if any."""
    if master is None:
        return None
    images = sorted(
        getattr(master, "images", []) or [],
        key=lambda i: (not i.is_primary, i.sort_order or 0),
    )
    if not images:
        return None
    return _media_resolver().resolve_media_url(images[0].image_url)


def _attach_master_image(db: Session, master: ProductMaster, image_ref: str) -> None:
    """Persist an uploaded image ref as the master's primary catalog image.

    ``image_ref`` arrives already validated/authorized by the route layer
    (``media_service.attach_media``) — either an ``s3://{bucket}/{key}`` ref
    or a local-provider key. Existing primary images are demoted so the newly
    attached image becomes the single catalog face.
    """
    for existing in getattr(master, "images", []) or []:
        if existing.is_primary:
            existing.is_primary = False
    master_images: Any = getattr(master, "images", None) or []  # pyright: ignore[reportUnknownMemberType]
    next_sort: int = (
        max((i.sort_order or 0) for i in master_images) + 1  # pyright: ignore[reportUnknownMemberType, reportUnknownVariableType, reportUnknownArgumentType]
        if master_images
        else 0
    )
    db.add(
        ProductImage(
            product_master_id=master.id,
            image_url=image_ref,
            is_primary=True,
            sort_order=next_sort,
        )
    )
    db.flush()


def _detach_master_images(master: ProductMaster) -> int:
    """Remove every catalog image from a product master.

    Detaching is an explicit user action, so the rows are deleted rather than
    merely demoted: ``_primary_image_url`` falls back to the highest-sort
    non-primary image, which would keep showing the photo the shopkeeper just
    asked to remove. The relationship cascades delete-orphan, so clearing the
    collection deletes the rows. Returns how many were removed.
    """
    images = list(getattr(master, "images", []) or [])
    if not images:
        return 0
    master.images.clear()
    return len(images)


def _variant_label(sp: ShopProduct) -> str | None:
    """Best-effort variant name for a shop product (falls back to SKU)."""
    variant = getattr(sp, "variant", None)
    if variant is not None:
        name = getattr(variant, "name", None)
        if name:
            return name
        sku = getattr(variant, "sku", None)
        if sku:
            return sku
    return sp.sku


def read_master_attributes(
    db: Session, master: ProductMaster | None, category_code: str | None = None
) -> dict[str, str]:
    """The category attributes stored against a product master.

    Without this the write path is a one-way street: the shopkeeper enters a part
    number, the row is saved, and nothing ever hands it back — so an edit form
    opens blank and a listing shows none of what was recorded.

    Stored identifiers are keyed back by the ATTRIBUTE key that declared them,
    not by their `IdentifierType`. An MPN filed under `oem_reference_number` has
    to come back under that name, because that is the key the form submits; the
    raw type would leave the field blank while its row sat right there.
    """
    if master is None:
        return {}
    out: dict[str, str] = {}

    attributes = (
        db.query(ProductAttribute)
        .filter(ProductAttribute.product_master_id == master.id)
        .all()
    )
    if attributes:
        values = (
            db.query(ProductAttributeValue)
            .filter(
                ProductAttributeValue.attribute_id.in_([a.id for a in attributes])
            )
            .all()
        )
        by_attribute: dict[int, list[str]] = {}
        for value in values:
            by_attribute.setdefault(value.attribute_id, []).append(value.value)
        for attribute in attributes:
            stored = by_attribute.get(attribute.id) or []
            if stored:
                out[attribute.name] = stored[0]

    # Which attribute key stands for each identifier type in this category.
    keys_by_type: dict[str, str] = {}
    if category_code:
        for spec in product_attributes.product_attributes_for(
            str(category_code).strip().upper()
        ):
            if spec.identifier_type:
                keys_by_type.setdefault(spec.identifier_type, spec.key.value)

    identifiers = (
        db.query(ProductIdentifier)
        .filter(
            ProductIdentifier.product_master_id == master.id,
            ProductIdentifier.is_primary.is_(False),
            ProductIdentifier.is_active.is_(True),
        )
        .all()
    )
    for identifier in identifiers:
        key = keys_by_type.get(identifier.identifier_type)
        if key:
            out.setdefault(key, identifier.identifier_value)

    return out


def serialize_product(
    sp: ShopProduct,
    inv: Inventory | None,
    attributes: dict[str, str] | None = None,
    price_source: InventorySource | str | None = None,
) -> dict[str, Any]:
    """Serialise one listing, with provenance split by FIELD.

    ``price_source`` is the source of the last PRICE change and ``inv``'s
    ``last_updated_source`` is the source of the last STOCK change. They are
    different facts: a POS sync routinely pushes a new price and leaves stock
    alone, and a barcode scan does the reverse. Collapsing them into one
    ``source`` is what made a POS price change render as a manual edit.

    ``price_source`` is optional because resolving it needs a PriceHistory
    lookup, and a caller that has none (an untouched price) still has an
    honest answer: the listing source.
    """
    qty = int(inv.quantity) if inv is not None else 0
    threshold = (
        int(inv.low_stock_threshold) if inv is not None and inv.low_stock_threshold else 5
    )
    status = (
        inv.stock_status.value
        if inv is not None and getattr(inv, "stock_status", None) is not None
        else _derive_stock_status(qty, threshold)
    )
    master = getattr(sp, "product_master", None)
    brand = getattr(master, "brand", None) if master is not None else None
    category = getattr(master, "category", None) if master is not None else None
    freshness = (
        getattr(inv, "freshness_status", None)
        if inv is not None
        else getattr(sp, "freshness_status", None)
    )
    return {
        "id": sp.id,
        "shop_id": sp.shop_id,
        "name": _display_name(sp),
        "sku": sp.sku,
        "variant": _variant_label(sp),
        "brand": getattr(brand, "name", None) if brand is not None else None,
        "category": getattr(category, "name", None) if category is not None else None,
        # Category attributes, echoed back so an edit form reopens populated.
        # Empty rather than absent when there are none, so a client never has to
        # distinguish "no attributes" from "an older server that omits the key".
        "attributes": attributes or {},
        "status": _shop_product_status_value(sp),
        "image_url": _primary_image_url(master),
        "price": float(sp.price or 0),
        "mrp": float(sp.mrp) if sp.mrp is not None else None,
        "is_active": sp.is_active,
        "is_available": sp.is_available,
        "is_featured": sp.is_featured,
        "quantity": qty,
        "low_stock_threshold": threshold,
        "stock_status": status,
        "freshness_status": freshness.value if freshness is not None and hasattr(freshness, "value") else (str(freshness) if freshness is not None else None),
        # Who last wrote this row. Without it the client falls back to "Updated
        # in app" for EVERY listing, so a price pushed by POS reads as a manual
        # edit -- an indicator that is confidently wrong beats no indicator only
        # because it is louder.
        # `source` is the STOCK axis, falling back to the listing source when
        # there is no inventory row. `list_inventory` resolves it the same way,
        # so the list and the detail screen cannot disagree about it.
        "source": _enum_value(getattr(inv, "last_updated_source", None))
        or _enum_value(getattr(sp, "source", None)),
        "inventory_source": _enum_value(
            getattr(inv, "last_updated_source", None)
        )
        or _enum_value(getattr(sp, "source", None)),
        "price_source": _enum_value(price_source)
        or _enum_value(getattr(sp, "source", None)),
        "last_inventory_update": _iso(sp.last_inventory_update),
        "last_price_update": _iso(sp.last_price_update),
        "created_at": _iso(getattr(sp, "created_at", None)),
    }


# A product row is not expensive to SERIALISE; it is expensive to LOAD. Every
# relation below is one query per product otherwise, and this function runs on
# the shop's most-opened screen. `selectinload` collapses each relation to one
# batched query for the whole page, which is the difference between ~5 queries
# per product and a constant handful per request.
#
# `inventory` is a collection, so it is eager-loaded the same way rather than
# fetched one-at-a-time in the loop below.
_LOAD_OPTIONS = (
    selectinload(ShopProduct.product_master)
    .selectinload(ProductMaster.brand),
    selectinload(ShopProduct.product_master).selectinload(ProductMaster.category),
    selectinload(ShopProduct.product_master).selectinload(ProductMaster.images),
    # `inventory` is many-to-one (one shop_product has one inventory row), so
    # it is JOINED into the products query rather than batched separately --
    # `selectinload` raises at runtime on a scalar relationship.
    joinedload(ShopProduct.inventory),
)

# A hard ceiling on one response. Without it a shop with tens of thousands of
# rows makes every page load try to render all of them, and one such request is
# enough to starve the connection pool for everyone else.
MAX_PRODUCTS_PER_RESPONSE = 200


def list_products(
    access: ShopAccess,
    db: Session,
    search: str | None = None,
    status_filter: str | None = None,
    stock_filter: str | None = None,
    limit: int | None = None,
    offset: int = 0,
) -> list[dict[str, Any]]:
    cap = MAX_PRODUCTS_PER_RESPONSE if limit is None else max(1, min(limit, MAX_PRODUCTS_PER_RESPONSE))
    products: list[ShopProduct] = (
        db.query(ShopProduct)
        .options(*_LOAD_OPTIONS)
        .filter(
            ShopProduct.shop_id == access.shop.id,
            ShopProduct.is_deleted == False,  # noqa: E712
        )
        .order_by(ShopProduct.id)
        # One extra row to tell the caller whether more exist, so the cap can
        # report truncation instead of silently looking like a complete list.
        .limit(cap + 1)
        .offset(max(0, offset))
        .all()
    )
    truncated = len(products) > cap
    if truncated:
        products = products[:cap]

    result: list[dict[str, Any]] = []
    for sp in products:
        # Already JOINED in by the options above; the fallback only applies to a
        # caller that built the row itself without them.
        inv = sp.inventory
        item = serialize_product(sp, inv)
        if search and search.lower() not in item["name"].lower():
            continue
        if status_filter and item["status"] != status_filter.upper():
            continue
        if stock_filter and item["stock_status"] != stock_filter.upper():
            continue
        result.append(item)
    if truncated and result:
        # Marked in-place rather than by adding a key, so this function's shape
        # stays a plain list of product dicts for every existing caller.
        result[-1]["_truncated"] = True
    return result


def _unique_master_slug(db: Session, name: str) -> str:
    base = shop_service.slugify(name) or "product"
    slug = base
    counter = 1
    while db.query(ProductMaster).filter(ProductMaster.slug == slug).first():
        slug = f"{base}-{counter}"
        counter += 1
    return slug


def _unique_sku(db: Session, shop_id: int, sku: str | None) -> str | None:
    if sku:
        return sku
    while True:
        candidate = f"SP-{shop_id}-{int(datetime.now(timezone.utc).timestamp() * 1000)}"
        exists = (
            db.query(ShopProduct)
            .filter(ShopProduct.shop_id == shop_id, ShopProduct.sku == candidate)
            .first()
        )
        if not exists:
            return candidate


def _normalize(value: Any) -> str:
    """Lowercase + whitespace-collapse for product-master name matching."""
    return " ".join(str(value or "").lower().split())


def find_matching_master(db: Session, name: str) -> ProductMaster | None:
    """Return an existing non-deleted product-master whose normalized name
    matches *name* exactly — used to prevent duplicate master records."""
    needle = _normalize(name)
    if not needle:
        return None
    candidates = (
        db.query(ProductMaster)
        .filter(ProductMaster.is_deleted == False)  # noqa: E712
        .all()
    )
    for master in candidates:
        if _normalize(master.name) == needle:
            return master
    return None


# ── Subscription entitlement enforcement (Phase 28) ─────────────────────────


def _shop_entitlements(db: Session, access: ShopAccess) -> dict[str, Any]:
    """Effective plan entitlements for the shop (rules live in entitlements)."""
    from app.services.subscription import entitlements

    return entitlements.resolve_shop_entitlements(db, access.shop)


def _enforce_product_limit(db: Session, access: ShopAccess) -> None:
    """Plan guard: ``max_products`` cap on active (non-deleted) listings."""
    from app.services.subscription import entitlements

    resolved = _shop_entitlements(db, access)
    current = (
        db.query(ShopProduct)
        .filter(
            ShopProduct.shop_id == access.shop.id,
            ShopProduct.is_deleted == False,  # noqa: E712
        )
        .count()
    )
    entitlements.enforce_limit(resolved, "max_products", current)


def _enforce_offers(db: Session, access: ShopAccess) -> None:
    """Plan guards: offers allowed at all + concurrent-offer cap."""
    from app.models.product import OfferStatus
    from app.services.subscription import entitlements

    resolved = _shop_entitlements(db, access)
    entitlements.enforce_feature(resolved, "offers")
    current = (
        db.query(Offer)
        .filter(Offer.shop_id == access.shop.id, Offer.status == OfferStatus.ACTIVE)
        .count()
    )
    entitlements.enforce_limit(resolved, "max_active_offers", current)


def enforce_pos_support(db: Session, shop_id: int) -> None:
    """Public plan guard used by POS routes: requires ``pos_support``."""
    from app.services.subscription import entitlements

    resolved = entitlements.resolve_shop_entitlements(db, _ShopIdStub(shop_id))
    entitlements.enforce_feature(resolved, "pos_support")


def shop_allows_pos(db: Session, shop_id: int) -> bool:
    """Grandfather-aware ``pos_support`` predicate (never raises).

    The non-raising twin of :func:`enforce_pos_support`, for callers that must
    DECIDE instead of refuse — the background-sync scheduler skips shops whose
    plan does not grant POS, while grandfathered shops (no subscription rows at
    all) keep legacy behaviour exactly like the enforcing helpers.
    """
    from app.services.subscription import entitlements
    from sqlalchemy.exc import OperationalError

    try:
        resolved = entitlements.resolve_shop_entitlements(db, _ShopIdStub(shop_id))
    except OperationalError:
        # Tables for subscriptions may not exist in lightweight test harnesses
        return True
    if resolved.get("grandfathered"):
        return True
    return entitlements.has_feature(resolved["entitlements"], "pos_support")


class _ShopIdStub:
    """Minimal shop-like object for entitlement resolution by id."""

    def __init__(self, shop_id: int):
        self.id = shop_id


# ── Taxonomy + barcode helpers (manual product create) ───────────────────
#
# The models have always carried `category_id` / `subcategory_id` and a
# `product_identifiers` table; the manual-create path simply never used them.
# These helpers close that gap. The parsing/validation rules are pure so they
# can be tested without a database.

# Retail symbology lengths → the identifier type they imply. A length that is
# not listed falls back to CUSTOM: we never guess an EAN out of a 7-digit code.
_BARCODE_TYPE_BY_LENGTH: dict[int, IdentifierType] = {
    8: IdentifierType.EAN,
    12: IdentifierType.UPC,
    13: IdentifierType.EAN,
    14: IdentifierType.GTIN,
}


def normalize_barcode(raw: str | None) -> str:
    """Drop the spaces/dashes a paste or a scanner can introduce."""
    return re.sub(r"[\s\-]", "", raw or "").strip()


def detect_identifier_type(barcode: str) -> IdentifierType:
    """Infer the symbology from the barcode LENGTH (pure).

    An unlisted length becomes CUSTOM rather than a wrong guess — the value is
    still stored and matchable.
    """
    return _BARCODE_TYPE_BY_LENGTH.get(len(barcode), IdentifierType.CUSTOM)


def resolve_identifier_type(barcode: str, explicit: str | None) -> IdentifierType:
    """Honour an explicit type when it names a real enum member, else infer."""
    if explicit:
        candidate = explicit.strip().upper()
        if candidate in IdentifierType.__members__:
            return IdentifierType[candidate]
    return detect_identifier_type(barcode)


def validate_taxonomy(
    category: Category | None,
    subcategory: Category | None,
    category_id: int | None,
    subcategory_id: int | None,
) -> None:
    """Pure taxonomy guards — every message names what to fix (pure)."""
    if category_id is not None and category is None:
        raise ValidationError("Selected category was not found")
    if category is not None and not category.is_active:
        raise ValidationError("Selected category is no longer available")
    if subcategory_id is None:
        return
    if subcategory is None:
        raise ValidationError("Selected subcategory was not found")
    if not subcategory.is_active:
        raise ValidationError("Selected subcategory is no longer available")
    if category is not None and subcategory.parent_id != category.id:
        raise ValidationError(
            "Selected subcategory does not belong to the selected category",
            data={"reason_code": "SUBCATEGORY_MISMATCH"},
        )


def _load_taxonomy(
    db: Session, category_id: int | None, subcategory_id: int | None
) -> tuple[Category | None, Category | None]:
    """Fetch + validate both optional taxonomy rows in one query."""
    ids = {i for i in (category_id, subcategory_id) if i is not None}
    if not ids:
        return None, None
    rows = db.query(Category).filter(Category.id.in_(ids)).all()
    by_id = {row.id: row for row in rows}
    category = by_id.get(category_id) if category_id is not None else None
    subcategory = by_id.get(subcategory_id) if subcategory_id is not None else None
    validate_taxonomy(category, subcategory, category_id, subcategory_id)
    return category, subcategory


def attach_identifier(
    db: Session, master: ProductMaster, barcode: str | None, explicit_type: str | None
) -> None:
    """Claim [barcode] for [master], or keep an existing own claim.

    `product_identifiers` carries a UNIQUE(type, value) constraint, so a
    barcode can only ever resolve to ONE product. Re-submitting your own
    barcode is idempotent; someone else's is a conflict worth reporting.
    """
    value = normalize_barcode(barcode)
    if not value:
        return
    id_type = resolve_identifier_type(value, explicit_type)
    existing = (
        db.query(ProductIdentifier)
        .filter(
            ProductIdentifier.identifier_type == id_type,
            ProductIdentifier.identifier_value == value,
        )
        .first()
    )
    if existing is not None:
        if existing.product_master_id == master.id:
            return  # already ours — nothing to claim
        raise ConflictError(
            "This barcode is already linked to another product in the catalog"
        )
    db.add(
        ProductIdentifier(
            product_master_id=master.id,
            identifier_type=id_type,
            identifier_value=value,
            is_primary=True,
            is_active=True,
        )
    )
    db.flush()


# ── Notification fan-out (best-effort) ───────────────────────────────────────

def _notification_recipient_id(
    db: Session, access: ShopAccess, user: User | None = None
) -> int | None:
    """Who a shop-facing notification goes to.

    The acting user when known; otherwise the shop's primary active owner (the
    profile/settings updates have no acting user in scope). Returns ``None``
    when neither resolves — the emitters treat that as a no-op.
    """
    if user is not None and getattr(user, "id", None) is not None:
        return int(user.id)
    owner = (
        db.query(ShopOwner)
        .filter(
            ShopOwner.shop_id == access.shop.id,
            ShopOwner.is_active == True,  # noqa: E712
        )
        .order_by(ShopOwner.is_primary.desc(), ShopOwner.id.asc())
        .first()
    )
    return int(owner.user_id) if owner is not None else None


def _notify(
    db: Session,
    access: ShopAccess,
    user: User | None,
    emitter: str,
    **kwargs: Any,
) -> None:
    """Emit one shopkeeper-category notification, never raising.

    A notification is a side-effect of the operation that caused it: losing the
    broker or the push provider must not roll back the product / price / stock
    write, so any failure is logged and swallowed.
    """
    try:
        from app.services import notification_service as notification_service

        getattr(notification_service, emitter)(
            db,
            shopkeeper_user_id=_notification_recipient_id(db, access, user),
            **kwargs,
        )
    except Exception:  # noqa: BLE001 — side-effect isolation
        logger.warning("Notification dispatch failed (%s)", emitter, exc_info=True)


def create_product(
    access: ShopAccess, db: Session, user: User, data: dict[str, Any]
) -> dict[str, Any]:
    """Create a ProductMaster + ShopProduct + Inventory row for the shop.

    Phase 23 guard: when a valid product-master already exists in the shared
    catalog (normalized name match), the shopkeeper's listing is LINKED to it —
    a duplicate master record is never created.
    Phase 28 guard: the shop's plan ``max_products`` entitlement is enforced.
    """
    # Phase 28 — subscription entitlement enforcement (product limit).
    _enforce_product_limit(db, access)

    # Column-width check before anything is written: a 300-character name would
    # otherwise reach INSERT and come back as a 500 from the storage layer.
    from app.core.field_limits import enforce_text_lengths

    enforce_text_lengths(
        {
            "product_name": data.get("name"),
            "sku": data.get("sku"),
            "brand": data.get("brand"),
        }
    )

    price = float(data["price"])
    mrp = float(data["mrp"]) if data.get("mrp") is not None else None
    if mrp is not None and mrp < price:
        raise ValidationError("MRP cannot be lower than selling price")

    # Taxonomy is optional, but when supplied it must be coherent: the
    # subcategory has to be a child of the chosen category.
    category, subcategory = _load_taxonomy(
        db, data.get("category_id"), data.get("subcategory_id")
    )

    publish = bool(data.get("publish"))
    quantity = int(data.get("quantity", 0))
    threshold = int(data.get("low_stock_threshold", 5))
    stock_enum = _enum_from_name("StockStatus", _derive_stock_status(quantity, threshold))

    matched = find_matching_master(db, data["name"])
    if matched is not None:
        duplicate = (
            db.query(ShopProduct)
            .filter(
                ShopProduct.shop_id == access.shop.id,
                ShopProduct.product_master_id == matched.id,
                ShopProduct.variant_id.is_(None),
                ShopProduct.is_deleted == False,  # noqa: E712
            )
            .first()
        )
        if duplicate is not None:
            raise ConflictError(
                "This product already exists in your inventory — update it instead"
            )
        master = matched
        # Non-destructive enrichment: fill in taxonomy the catalog is missing,
        # but never overwrite a classification another shopkeeper already set.
        if master.category_id is None and category is not None:
            master.category_id = category.id
        if master.subcategory_id is None and subcategory is not None:
            master.subcategory_id = subcategory.id
    else:
        master = ProductMaster(
            name=data["name"].strip(),
            slug=_unique_master_slug(db, data["name"]),
            description=data.get("description"),
            base_unit=data.get("unit"),
            category_id=category.id if category is not None else None,
            subcategory_id=subcategory.id if subcategory is not None else None,
            status=ProductStatus.APPROVED if publish else ProductStatus.DRAFT,
            is_active=publish,
        )
        db.add(master)
        db.flush()

    # Barcode → the product's primary identifier, so a later scan resolves it.
    attach_identifier(db, master, data.get("barcode"), data.get("barcode_type"))

    # Category attributes — the fields this shop's category advertises. Anything
    # the backend cannot store is refused here, loudly, rather than dropped: a
    # silently discarded "Part number" is a part the shopkeeper believes exists.
    if data.get("attributes"):
        plan = product_attribute_writer.plan_attribute_write(
            getattr(access.shop, "category", None), data.get("attributes")
        )
        if not plan.ok:
            detail = "; ".join(f"{k}: {v}" for k, v in sorted(plan.rejected.items()))
            raise ValidationError(f"Product attributes were refused — {detail}")
        product_attribute_writer.persist_attribute_values(db, master, plan)

    sp = product_convergence.attach_product_to_shop(
        db,
        shop_id=access.shop.id,
        master=master,
        sku=_unique_sku(db, access.shop.id, data.get("sku")),
        source=InventorySource.MANUAL,
        price=price,
        mrp=mrp,
        publish=publish,
        is_available=bool(data.get("is_available", True)) and publish and quantity > 0,
        stock_status=stock_enum,
    )

    # Phase 7 — persist the (route-validated) uploaded image as the
    # master's primary catalog image.
    if data.get("image_url"):
        _attach_master_image(db, master, data["image_url"])

    product_convergence.set_inventory(
        db,
        sp,
        quantity=quantity,
        low_stock_threshold=threshold,
        source=InventorySource.MANUAL,
        user_id=user.id,
        reference_type="MANUAL_ENTRY",
        stock_status=stock_enum,
    )

    inv = db.query(Inventory).filter(Inventory.shop_product_id == sp.id).first()
    logger.info(
        "Product created: shop=%s shop_product=%s by user=%s",
        access.shop.id, sp.id, user.id,
    )
    payload = serialize_product(
        sp,
        inv,
        read_master_attributes(
            db,
            getattr(sp, "product_master", None),
            getattr(access.shop, "category", None),
        ),
    )
    _notify(
        db, access, user,
        "notify_shop_product_event",
        shop_product_id=sp.id,
        event="ADDED",
        product_name=str(payload.get("name") or ""),
    )
    return payload


def update_product(
    access: ShopAccess, db: Session, user: User, shop_product_id: int, data: dict[str, Any]
) -> dict[str, Any]:
    """Update price / stock / availability for a shop product."""
    sp: ShopProduct | None = (
        db.query(ShopProduct)
        .filter(
            ShopProduct.id == shop_product_id,
            ShopProduct.shop_id == access.shop.id,
        )
        .first()
    )
    if sp is None:
        raise NotFoundError("Product not found in this shop")

    inv = db.query(Inventory).filter(Inventory.shop_product_id == sp.id).first()
    now = datetime.now(timezone.utc)
    touched_price = False
    old_price = float(sp.price) if sp.price is not None else 0.0  # pyright: ignore[reportUnnecessaryComparison]
    old_mrp = float(sp.mrp) if sp.mrp is not None else None

    # Same three rules as every entry route: numeric, non-negative, then the
    # MRP-vs-price relationship. This door only checked the third, so a negative
    # or non-numeric amount either reached the column or crashed mid-request.
    def _amount(raw: Any, label: str) -> float:
        """A money field: numeric and non-negative, or refused at the edge.

        The nested def keeps the wording next to the two call sites instead of
        a module helper five screens away, the way the price entry rules sit
        next to attachment rather than in a shared validators module.
        """
        try:
            value = float(raw)
        except (TypeError, ValueError) as exc:
            raise ValidationError(f"{label} '{raw}' is not a valid number") from exc
        if value < 0:
            raise ValidationError(f"{label} cannot be negative")
        return value

    new_price = (
        _amount(data["price"], "Price") if data.get("price") is not None else None
    )
    if data.get("mrp") is not None:
        mrp = _amount(data["mrp"], "MRP")
        effective_price = new_price if new_price is not None else float(sp.price or 0)
        if mrp < effective_price:
            raise ValidationError("MRP cannot be lower than selling price")
        sp.mrp = mrp
        touched_price = True
    if new_price is not None:
        effective_mrp = float(sp.mrp) if sp.mrp is not None else None
        if effective_mrp is not None and effective_mrp < new_price:
            raise ValidationError("MRP cannot be lower than selling price")
        sp.price = new_price
        touched_price = True
    if touched_price:
        sp.last_price_update = now
        # Phase 23: preserve the platform price history trail.
        open_records = (
            db.query(PriceHistory)
            .filter(
                PriceHistory.shop_product_id == sp.id,
                PriceHistory.effective_to.is_(None),
            )
            .all()
        )
        for rec in open_records:
            rec.effective_to = now
        db.add(
            PriceHistory(
                shop_product_id=sp.id,
                old_price=old_price,
                new_price=float(sp.price),
                old_mrp=old_mrp,
                new_mrp=float(sp.mrp) if sp.mrp is not None else None,
                changed_by=user.id,
                change_source=InventorySource.MANUAL,
                effective_from=now,
                effective_to=None,
            )
        )

    if data.get("is_featured") is not None:
        sp.is_featured = bool(data["is_featured"])

    quantity_changed = data.get("quantity") is not None
    threshold_changed = data.get("low_stock_threshold") is not None
    explicit_availability = data.get("is_available")

    if quantity_changed or threshold_changed:
        previous_quantity = int(inv.quantity) if inv is not None else 0
        qty = (
            int(data["quantity"])
            if quantity_changed
            else (int(inv.quantity) if inv else 0)
        )
        threshold = (
            int(data["low_stock_threshold"])
            if threshold_changed
            else ((int(inv.low_stock_threshold) if inv.low_stock_threshold else 5) if inv else 5)
        )
        if inv is None:
            inv = Inventory(
                shop_product_id=sp.id, reserved_quantity=0, last_updated_by=user.id
            )
            db.add(inv)
            db.flush()
        inv.quantity = qty
        inv.available_quantity = max(qty - int(inv.reserved_quantity or 0), 0)
        inv.low_stock_threshold = threshold
        inv.stock_status = _enum_from_name(
            "StockStatus", _derive_stock_status(qty, threshold)
        )
        inv.is_available = qty > 0
        inv.last_updated_by = user.id
        # Phase 23: keep the platform inventory row in sync (source/freshness).
        inv.last_updated_source = InventorySource.MANUAL
        inv.freshness_status = compute_freshness(now, InventorySource.MANUAL)
        inv.freshness_checked_at = now
        sp.last_inventory_update = now
        sp.source = InventorySource.MANUAL
        sp.freshness_status = inv.freshness_status
        # Availability follows stock unless explicitly overridden below.
        sp.is_available = qty > 0

        if qty != previous_quantity:
            db.add(
                InventoryMovement(
                    inventory_id=inv.id,
                    quantity_change=qty - previous_quantity,
                    quantity_before=previous_quantity,
                    quantity_after=qty,
                    movement_type="UPDATE",
                    source=InventorySource.MANUAL,
                    notes="Shopkeeper stock update",
                    created_by=user.id,
                )
            )

    if data.get("status"):
        wanted = str(data["status"]).upper()
        try:
            sp.status = _enum_from_name("ShopProductStatus", wanted)
        except KeyError as exc:
            raise ValidationError(f"Invalid product status: {data['status']}") from exc

    if explicit_availability is not None:
        sp.is_available = bool(explicit_availability)
        if inv is not None:
            inv.is_available = bool(explicit_availability)
            inv.last_updated_by = user.id
            inv.last_updated_source = InventorySource.MANUAL
            inv.freshness_status = compute_freshness(now, InventorySource.MANUAL)
            inv.freshness_checked_at = now
            sp.source = InventorySource.MANUAL
            sp.freshness_status = inv.freshness_status
            sp.last_inventory_update = now

    master = getattr(sp, "product_master", None)
    if data.get("remove_image"):
        # Explicit detach. The route rejects a payload that asks for both a new
        # key and a removal, so this never races the branch below.
        if master is not None:
            removed = _detach_master_images(master)
            logger.info(
                "Product image detached: master=%s images_removed=%s by user=%s",
                master.id, removed, user.id,
            )
    elif data.get("image_url"):
        # Phase 7 — attach a newly uploaded image (route-validated) if provided.
        if master is not None:
            _attach_master_image(db, master, data["image_url"])

    # Category attributes on update. Only the keys actually sent are written, so
    # a price-only edit never clears a part number stored earlier.
    if data.get("attributes") and master is not None:
        plan = product_attribute_writer.plan_attribute_write(
            getattr(access.shop, "category", None), data.get("attributes")
        )
        if not plan.ok:
            detail = "; ".join(f"{k}: {v}" for k, v in sorted(plan.rejected.items()))
            raise ValidationError(f"Product attributes were refused — {detail}")
        product_attribute_writer.persist_attribute_values(db, master, plan)

    db.flush()
    logger.info(
        "Product updated: shop=%s shop_product=%s by user=%s",
        access.shop.id, sp.id, user.id,
    )
    payload = serialize_product(
        sp, inv, read_master_attributes(db, master, getattr(access.shop, "category", None))
    )
    name = str(payload.get("name") or "")
    if touched_price:
        _notify(
            db, access, user,
            "notify_price_change",
            shop_product_id=sp.id,
            old_price=old_price,
            new_price=float(sp.price or 0),
            product_name=name,
        )
    else:
        _notify(
            db, access, user,
            "notify_shop_product_event",
            shop_product_id=sp.id,
            event="UPDATED",
            product_name=name,
        )
    return payload


# ── Phase 23 — Inventory management workflow ─────────────────────────────

ADJUSTMENT_TYPES = {
    "RESTOCK",
    "SALE",
    "DAMAGE",
    "EXPIRY",
    "RETURN",
    "CORRECTION",
    "STOCK_COUNT",
    "MANUAL",
}
BULK_OPERATIONS = {"price_update", "stock_set", "availability"}
INVENTORY_SORT_FIELDS = {"name", "price", "quantity", "updated_at"}


def search_product_masters(
    db: Session, query: str | None = None, limit: int = 20
) -> list[dict[str, Any]]:
    """Search the shared product-master catalog so shopkeepers can SELECT a
    known product (never re-create it) and pick a variant."""
    masters = (
        db.query(ProductMaster)
        .filter(ProductMaster.is_deleted == False)  # noqa: E712
        .limit(max(limit, 1) * 5)
        .all()
    )
    needle = _normalize(query)
    scored: list[tuple[int, dict[str, Any]]] = []
    for master in masters:
        name = _normalize(master.name)
        slug = _normalize(getattr(master, "slug", ""))
        if needle:
            if name == needle:
                score = 0
            elif needle in name:
                score = 1
            elif needle in slug:
                score = 2
            else:
                continue
        else:
            score = 3
        master_variants: Any = getattr(master, "variants", None) or []  # pyright: ignore[reportUnknownMemberType]
        variants: list[dict[str, Any]] = [
            {
                "variant_id": v.id,  # pyright: ignore[reportUnknownMemberType]
                "name": v.name,  # pyright: ignore[reportUnknownMemberType]
                "sku": v.sku,  # pyright: ignore[reportUnknownMemberType]
                "is_active": bool(getattr(v, "is_active", True)),  # pyright: ignore[reportUnknownArgumentType, reportUnknownMemberType]
            }
            for v in master_variants
            if getattr(v, "is_deleted", False) is not True  # pyright: ignore[reportUnknownArgumentType]
            and getattr(v, "is_active", True) is not False  # pyright: ignore[reportUnknownArgumentType]
        ]
        scored.append(
            (
                score,
                {
                    "product_master_id": master.id,
                    "name": master.name,
                    "slug": getattr(master, "slug", None),
                    "description": getattr(master, "description", None),
                    "base_unit": getattr(master, "base_unit", None),
                    "status": (
                        master.status.value if hasattr(master.status, "value") else str(master.status)
                    )
                    if master.status is not None  # pyright: ignore[reportUnnecessaryComparison]
                    else None,
                    "variants": variants,
                },
            )
        )
    scored.sort(key=lambda pair: (pair[0], _normalize(pair[1]["name"])))
    return [item for _, item in scored[: max(limit, 1)]]


def add_product_from_master(
    access: ShopAccess, db: Session, user: User, data: dict[str, Any]
) -> dict[str, Any]:
    """Link an EXISTING catalog product (master + optional variant) to the shop.

    The product master record itself is never created or duplicated here —
    shopkeepers select from the platform catalog and set shop-level price,
    MRP, availability and quantity.
    """
    access.require("product", "create")

    # Phase 28 — subscription entitlement enforcement (product limit).
    _enforce_product_limit(db, access)

    master = (
        db.query(ProductMaster)
        .filter(
            ProductMaster.id == int(data["product_master_id"]),
            ProductMaster.is_deleted == False,  # noqa: E712
        )
        .first()
    )
    if master is None:
        raise NotFoundError("Product not found in catalog")

    variant: Any = None
    variant_id: Any = data.get("variant_id")  # pyright: ignore[reportUnknownMemberType]
    if variant_id is not None:
        master_variant_rows: Any = getattr(master, "variants", None) or []  # pyright: ignore[reportUnknownMemberType]
        variant = next(
            (v for v in master_variant_rows if v.id == int(variant_id)),  # pyright: ignore[reportUnknownArgumentType, reportUnknownMemberType, reportUnknownVariableType]
            None,
        )
        if variant is None:
            raise ValidationError("Selected variant does not belong to this product")

    price = float(data["price"])
    mrp = float(data["mrp"]) if data.get("mrp") is not None else None
    if mrp is not None and mrp < price:
        raise ValidationError("MRP cannot be lower than selling price")

    duplicate = (
        db.query(ShopProduct)
        .filter(
            ShopProduct.shop_id == access.shop.id,
            ShopProduct.product_master_id == master.id,
            ShopProduct.variant_id == (variant.id if variant else None),  # pyright: ignore[reportUnknownArgumentType]  # pyright: ignore[reportUnknownMemberType]
            ShopProduct.is_deleted == False,  # noqa: E712
        )
        .first()
    )
    if duplicate is not None:
        raise ConflictError("This product is already in your inventory")

    quantity = int(data.get("quantity", 0))
    threshold = int(data.get("low_stock_threshold", 5))
    available = bool(data.get("is_available", True)) and quantity > 0
    stock_enum = _enum_from_name("StockStatus", _derive_stock_status(quantity, threshold))

    sp = product_convergence.attach_product_to_shop(
        db,
        shop_id=access.shop.id,
        master=master,
        variant=variant,
        sku=_unique_sku(db, access.shop.id, data.get("sku")),
        source=InventorySource.MANUAL,
        price=price,
        mrp=mrp,
        publish=True,
        is_available=available,
        stock_status=stock_enum,
    )

    inv = product_convergence.set_inventory(
        db,
        sp,
        quantity=quantity,
        low_stock_threshold=threshold,
        source=InventorySource.MANUAL,
        is_available=available,
        stock_status=stock_enum,
        user_id=user.id,
        reference_type="CATALOG_ADD",
        notes="Product added to shop inventory",
    )

    # Link eagerly so serialization sees master/variant immediately.
    sp.inventory = inv
    logger.info(
        "Product added from catalog: shop=%s shop_product=%s master=%s by user=%s",
        access.shop.id, sp.id, master.id, user.id,
    )
    return serialize_product(sp, inv)


def adjust_stock(
    access: ShopAccess, db: Session, user: User, shop_product_id: int, data: dict[str, Any]
) -> dict[str, Any]:
    """Apply a delta stock adjustment with a full audit trail
    (InventoryAdjustment + InventoryMovement)."""
    access.require("inventory", "update")

    adjustment_type = str(data.get("adjustment_type", "CORRECTION")).upper()
    if adjustment_type not in ADJUSTMENT_TYPES:
        raise ValidationError(f"Invalid adjustment type: {adjustment_type}")
    delta = int(data["quantity_adjustment"])
    if delta == 0:
        raise ValidationError("Quantity adjustment cannot be zero")

    sp: ShopProduct | None = (
        db.query(ShopProduct)
        .filter(
            ShopProduct.id == shop_product_id,
            ShopProduct.shop_id == access.shop.id,
        )
        .first()
    )
    if sp is None:
        raise NotFoundError("Product not found in this shop")

    inv = db.query(Inventory).filter(Inventory.shop_product_id == sp.id).first()
    if inv is None:
        raise ValidationError("No inventory record exists for this product")

    previous_quantity = int(inv.quantity)
    updated_quantity = previous_quantity + delta
    if updated_quantity < 0:
        raise ValidationError(
            f"Adjustment would result in negative inventory ({updated_quantity})"
        )

    now = datetime.now(timezone.utc)
    threshold = int(inv.low_stock_threshold) if inv.low_stock_threshold else 5

    db.add(
        InventoryAdjustment(
            inventory_id=inv.id,
            adjustment_type=adjustment_type,
            quantity_adjustment=delta,
            reason=data.get("reason"),
            approved_by=user.id,
            approved_at=now,
        )
    )

    inv.quantity = updated_quantity
    inv.available_quantity = max(updated_quantity - int(inv.reserved_quantity or 0), 0)
    inv.stock_status = _enum_from_name(
        "StockStatus", _derive_stock_status(updated_quantity, threshold)
    )
    inv.last_updated_by = user.id
    inv.last_updated_source = InventorySource.MANUAL
    inv.freshness_status = compute_freshness(now, InventorySource.MANUAL)
    inv.freshness_checked_at = now

    db.add(
        InventoryMovement(
            inventory_id=inv.id,
            quantity_change=delta,
            quantity_before=previous_quantity,
            quantity_after=updated_quantity,
            movement_type="ADJUSTMENT",
            source=InventorySource.MANUAL,
            notes=f"{adjustment_type}: {data.get('reason') or ''}".strip(": ").strip(),
            created_by=user.id,
        )
    )

    sp.stock_status = inv.stock_status
    sp.is_available = updated_quantity > 0
    inv.is_available = sp.is_available
    sp.source = InventorySource.MANUAL
    sp.freshness_status = inv.freshness_status
    sp.last_inventory_update = now
    db.flush()

    logger.info(
        "Stock adjusted: shop=%s shop_product=%s delta=%s by user=%s",
        access.shop.id, sp.id, delta, user.id,
    )
    status_value = inv.stock_status.value
    if status_value in ("LOW_STOCK", "LIMITED_STOCK", "OUT_OF_STOCK"):
        _notify(
            db, access, user,
            "notify_inventory_update",
            shop_product_id=sp.id,
            message=(
                f"{_display_name(sp)} is out of stock."
                if status_value == "OUT_OF_STOCK"
                else f"{_display_name(sp)} is low on stock — "
                     f"{updated_quantity} left."
            ),
        )
    return {
        "shop_product_id": sp.id,
        "previous_quantity": previous_quantity,
        "quantity_adjustment": delta,
        "new_quantity": updated_quantity,
        "stock_status": inv.stock_status.value,
        "adjustment_type": adjustment_type,
        "last_inventory_update": _iso(now),
        # The spec's "Show: Last Updated, Source, Freshness" needs these three
        # AFTER the save, not just before it. The row already carried them —
        # the payload simply never surfaced them, so the confirmation panel
        # could say "saved" without saying where the number came from.
        "source": _enum_value(inv.last_updated_source),
        "freshness_status": _enum_value(inv.freshness_status),
        "freshness_checked_at": _iso(inv.freshness_checked_at),
    }


def remove_product(
    access: ShopAccess, db: Session, user: User, shop_product_id: int
) -> dict[str, Any]:
    """Deactivate + soft-delete a shop product listing."""
    access.require("product", "delete")
    sp: ShopProduct | None = (
        db.query(ShopProduct)
        .filter(
            ShopProduct.id == shop_product_id,
            ShopProduct.shop_id == access.shop.id,
        )
        .first()
    )
    if sp is None:
        raise NotFoundError("Product not found in this shop")

    now = datetime.now(timezone.utc)
    sp.is_deleted = True
    sp.deleted_at = now
    sp.is_active = False
    sp.is_available = False
    try:
        sp.status = _enum_from_name("ShopProductStatus", "INACTIVE")
    except KeyError:  # pragma: no cover - enum always present
        pass

    inv = db.query(Inventory).filter(Inventory.shop_product_id == sp.id).first()
    if inv is not None:
        remaining = int(inv.quantity)
        inv.quantity = 0
        inv.reserved_quantity = 0
        inv.available_quantity = 0
        inv.is_available = False
        inv.stock_status = _enum_from_name("StockStatus", "OUT_OF_STOCK")
        inv.last_updated_by = user.id
        inv.freshness_status = compute_freshness(now, InventorySource.MANUAL)
        inv.freshness_checked_at = now
        db.add(
            InventoryMovement(
                inventory_id=inv.id,
                quantity_change=-remaining,
                quantity_before=remaining,
                quantity_after=0,
                movement_type="REMOVE",
                source=InventorySource.MANUAL,
                notes="Product removed from shop inventory",
                created_by=user.id,
            )
        )
        sp.stock_status = inv.stock_status
        sp.freshness_status = inv.freshness_status
    sp.last_inventory_update = now
    db.flush()

    logger.info(
        "Product removed: shop=%s shop_product=%s by user=%s",
        access.shop.id, sp.id, user.id,
    )
    _notify(
        db, access, user,
        "notify_shop_product_event",
        shop_product_id=sp.id,
        event="REMOVED",
        product_name=_display_name(sp),
    )
    return {
        "shop_product_id": sp.id,
        "status": getattr(sp.status, "value", str(sp.status)),
        "is_active": False,
        "removed_at": _iso(now),
    }


def list_inventory(
    access: ShopAccess,
    db: Session,
    search: str | None = None,
    stock_filter: str | None = None,
    availability_filter: bool | None = None,
    active_filter: bool | None = None,
    low_below_threshold: bool | None = None,
    sort_by: str = "updated_at",
    sort_order: str = "desc",
) -> dict[str, Any]:
    """View / search / filter / sort the shop inventory.

    Every item carries its last-updated time and inventory source.
    ``low_below_threshold`` selects listings whose current stock has reached
    their own low-stock threshold (``quantity <= low_stock_threshold``) — the
    authoritative restock list, straight from the two numbers that define it.
    """
    access.require("inventory", "read")
    sort_field = sort_by if sort_by in INVENTORY_SORT_FIELDS else "updated_at"
    descending = str(sort_order).lower() != "asc"

    products: list[ShopProduct] = (
        db.query(ShopProduct).filter(ShopProduct.shop_id == access.shop.id).all()
    )
    epoch = datetime.min.replace(tzinfo=timezone.utc)

    # Resolve updater names once (distinct ids → single query) so every item
    # can show "Updated by <name>" without N+1 user lookups.
    updater_ids: set[int] = set()
    per_product_inv: dict[int, Inventory | None] = {}
    discontinued_ids: set[int] = set()
    for sp in products:
        inv = db.query(Inventory).filter(Inventory.shop_product_id == sp.id).first()
        per_product_inv[sp.id] = inv
        if is_discontinued(sp):
            discontinued_ids.add(sp.id)
        updater = getattr(inv, "last_updated_by", None) if inv is not None else None
        if updater:
            updater_ids.add(int(updater))
    # Field-level price provenance: the latest OPEN PriceHistory row per
    # product, resolved in ONE query. Queried per product this would be an
    # N+1 on the inventory list, which is the exact shape that gets slow at
    # the page sizes this screen is used at. Open rows are few by
    # construction: writing a price CLOSES the previous one.
    latest_price_source: dict[int, InventorySource] = {}
    if products:
        open_price_rows = (
            db.query(PriceHistory)
            .filter(
                PriceHistory.shop_product_id.in_([sp.id for sp in products]),
                PriceHistory.effective_to.is_(None),
            )
            .all()
        )
        newest: dict[int, Any] = {}
        for row in open_price_rows:
            sp_id = getattr(row, "shop_product_id", None)
            if sp_id is None:
                continue
            change_source = getattr(row, "change_source", None)
            effective_from = getattr(row, "effective_from", None)
            previous = newest.get(sp_id)
            if previous is None or (
                effective_from is not None and effective_from > previous[1]
            ):
                newest[sp_id] = (change_source, effective_from)
        latest_price_source = {
            sp_id: src for sp_id, (src, _) in newest.items() if src is not None
        }

    updater_names: dict[int, str] = {}
    if updater_ids:
        from app.models.user import User

        for u in db.query(User).filter(User.id.in_(updater_ids)).all():
            updater_names[u.id] = u.name or f"User #{u.id}"

    entries: list[tuple[datetime, dict[str, Any]]] = []
    for sp in products:
        inv = per_product_inv[sp.id]
        item = serialize_product(sp, inv, price_source=latest_price_source.get(sp.id))
        last_updated_raw = (
            sp.last_inventory_update
            or sp.last_price_update
            or getattr(sp, "created_at", None)
            or epoch
        )
        if last_updated_raw.tzinfo is None:
            last_updated_raw = last_updated_raw.replace(tzinfo=timezone.utc)
        item["last_updated"] = _iso(last_updated_raw)
        updater_id = getattr(inv, "last_updated_by", None) if inv is not None else None
        item["updated_by"] = (
            updater_names.get(int(updater_id))
            if updater_id
            else None
        )
        inventory_source = (
            inv.last_updated_source.value
            if inv is not None and getattr(inv, "last_updated_source", None) is not None
            else getattr(sp.source, "value", str(sp.source))
        )
        item["inventory_source"] = inventory_source
        # Price provenance falls back to the listing source when no price was
        # ever changed through a source-tracking path: an untouched price has
        # no history row to speak for it, and the listing source is the only
        # honest answer then.
        price_source = latest_price_source.get(sp.id)
        item["price_source"] = (
            _enum_value(price_source) if price_source is not None else inventory_source
        )
        # The single-axis answer is kept for clients that have not moved to the
        # split fields yet. It is the INVENTORY axis on purpose: stock is what
        # a shopkeeper changes most often, and reporting the price axis here
        # would relabel every untouched product.
        item["source"] = inventory_source
        freshness = (
            getattr(inv, "freshness_status", None)
            if inv is not None
            else getattr(sp, "freshness_status", None)
        )
        item["freshness_status"] = freshness.value if freshness is not None and hasattr(freshness, "value") else None
        entries.append((last_updated_raw, item))

    needle = _normalize(search)
    filtered: list[tuple[datetime, dict[str, Any]]] = []
    for stamp, item in entries:
        if needle and needle not in _normalize(item["name"]) and needle not in _normalize(item.get("sku") or ""):
            continue
        if stock_filter:
            wanted = str(stock_filter).upper()
            # DISCONTINUED is a product status, never a stock status, so an
            # equality test against stock_status could never match it.
            if wanted == "DISCONTINUED":
                if item["id"] not in discontinued_ids:
                    continue
            elif item["stock_status"] != wanted:
                continue
        if availability_filter is not None and item["is_available"] != bool(availability_filter):
            continue
        if active_filter is not None and item["is_active"] != bool(active_filter):
            continue
        if low_below_threshold:
            # The restock rule: a listing needs restocking when its current
            # stock has reached the threshold the shopkeeper set for it.
            # `quantity <= 0` is already OUT_OF_STOCK, which is a subset of
            # "needs restocking", so it is included on purpose.
            if int(item["quantity"] or 0) > int(item["low_stock_threshold"] or 0):
                continue
        filtered.append((stamp, item))

    def _sort_key(pair: tuple[datetime, dict[str, Any]]):
        _, item = pair
        if sort_field == "name":
            return _normalize(item["name"])
        if sort_field == "price":
            return float(item["price"] or 0)
        if sort_field == "quantity":
            return int(item["quantity"] or 0)
        stamp = pair[0]
        return stamp.astimezone(timezone.utc)

    filtered.sort(key=_sort_key, reverse=descending)
    items = [item for _, item in filtered]
    # Ship the server's own counts alongside the list so no client has to
    # re-derive them and drift from the platform's stock vocabulary.
    return {
        "items": items,
        "count": len(items),
        "summary": _product_counts(products, per_product_inv),
    }

def update_low_stock_threshold(
    access: ShopAccess, db: Session, user: User, shop_product_id: int, threshold: int
) -> dict[str, Any]:
    """Set the per-listing low-stock threshold and re-derive the stock state.

    The threshold is what turns a quantity into LOW_STOCK, so changing it can
    change the reported stock state without any units moving. The derived
    status is therefore recomputed here and written back to both the
    ``Inventory`` row and the ``ShopProduct`` projection, and the change is
    stamped as a MANUAL inventory update so freshness stays truthful.
    """
    access.require("inventory", "update")

    if int(threshold) < 0:
        raise ValidationError("Low stock threshold cannot be negative")

    sp: ShopProduct | None = (
        db.query(ShopProduct)
        .filter(
            ShopProduct.id == shop_product_id,
            ShopProduct.shop_id == access.shop.id,
        )
        .first()
    )
    if sp is None:
        raise NotFoundError("Product not found in this shop")

    inv = db.query(Inventory).filter(Inventory.shop_product_id == sp.id).first()
    if inv is None:
        raise ValidationError("No inventory record exists for this product")

    previous = int(inv.low_stock_threshold) if inv.low_stock_threshold else 5
    wanted = int(threshold)
    now = datetime.now(timezone.utc)
    qty = int(inv.quantity or 0)

    inv.low_stock_threshold = wanted
    inv.stock_status = _enum_from_name("StockStatus", _derive_stock_status(qty, wanted))
    inv.last_updated_by = user.id
    inv.last_updated_source = InventorySource.MANUAL
    inv.freshness_status = compute_freshness(now, InventorySource.MANUAL)
    inv.freshness_checked_at = now

    sp.stock_status = inv.stock_status
    sp.last_inventory_update = now
    sp.source = InventorySource.MANUAL
    sp.freshness_status = inv.freshness_status

    logger.info(
        "Low stock threshold updated: shop=%s shop_product=%s %s->%s by user=%s",
        access.shop.id, sp.id, previous, wanted, user.id,
    )
    status_value = inv.stock_status.value
    if status_value in ("LOW_STOCK", "LIMITED_STOCK", "OUT_OF_STOCK"):
        _notify(
            db, access, user,
            "notify_inventory_update",
            shop_product_id=sp.id,
            message=(
                f"{_display_name(sp)} is out of stock."
                if status_value == "OUT_OF_STOCK"
                else f"{_display_name(sp)} is low on stock — {qty} left."
            ),
        )
    return {
        "shop_product_id": sp.id,
        "previous_low_stock_threshold": previous,
        "low_stock_threshold": wanted,
        "quantity": qty,
        "stock_status": inv.stock_status.value,
        "last_inventory_update": _iso(now),
    }


def list_stock_adjustments(
    access: ShopAccess, db: Session, shop_product_id: int, limit: int = 50
) -> dict[str, Any]:
    """Adjustment-only audit trail for one shop product, newest first.

    ``product_history`` interleaves movements, adjustments and price changes;
    this returns just the operator corrections (damage, expiry, stock count…)
    so a dedicated screen can render them without filtering client-side.
    """
    access.require("inventory", "read")

    sp: ShopProduct | None = (
        db.query(ShopProduct)
        .filter(
            ShopProduct.id == shop_product_id,
            ShopProduct.shop_id == access.shop.id,
        )
        .first()
    )
    if sp is None:
        raise NotFoundError("Product not found in this shop")

    inv = db.query(Inventory).filter(Inventory.shop_product_id == sp.id).first()
    if inv is None:
        return {"shop_product_id": sp.id, "adjustments": [], "count": 0}

    rows = (
        db.query(InventoryAdjustment)
        .filter(InventoryAdjustment.inventory_id == inv.id)
        .order_by(InventoryAdjustment.created_at.desc())
        .limit(limit)
        .all()
    )
    adjustments = [
        {
            "id": row.id,
            "adjustment_type": row.adjustment_type,
            "quantity_adjustment": int(row.quantity_adjustment or 0),
            "reason": row.reason,
            "approved_by": row.approved_by,
            "approved_at": _iso(row.approved_at),
            "created_at": _iso(getattr(row, "created_at", None)),
        }
        for row in rows
    ]
    return {
        "shop_product_id": sp.id,
        "adjustments": adjustments,
        "count": len(adjustments),
    }

def product_history(
    access: ShopAccess,
    db: Session,
    user: User,
    shop_product_id: int,
    limit: int = 50,
    offset: int = 0,
) -> dict[str, Any]:
    """Combined audit trail for one shop product: movements, adjustments
    and price changes — newest first, paginated.

    Every returned entry answers the four audit questions the shopkeeper
    needs: *what* changed (delta + before → after), *why* (movement /
    adjustment type + source), *when* (``occurred_at``) and *who*
    (``actor`` — null when the change was automated)."""
    access.require("inventory", "read")
    sp: ShopProduct | None = (
        db.query(ShopProduct)
        .filter(
            ShopProduct.id == shop_product_id,
            ShopProduct.shop_id == access.shop.id,
        )
        .first()
    )
    if sp is None:
        raise NotFoundError("Product not found in this shop")

    entries: list[dict[str, Any]] = []
    inv = db.query(Inventory).filter(Inventory.shop_product_id == sp.id).first()
    if inv is not None:
        for mv in (
            db.query(InventoryMovement)
            .filter(InventoryMovement.inventory_id == inv.id)
            .all()
        ):
            entries.append(
                {
                    "type": "movement",
                    "occurred_at": _iso(getattr(mv, "created_at", None)),
                    "movement_type": mv.movement_type,
                    "quantity_change": mv.quantity_change,
                    "quantity_before": mv.quantity_before,
                    "quantity_after": mv.quantity_after,
                    "source": mv.source.value if hasattr(mv.source, "value") else str(mv.source),
                    "notes": mv.notes,
                    "actor_id": mv.created_by,
                }
            )
        for adj in (
            db.query(InventoryAdjustment)
            .filter(InventoryAdjustment.inventory_id == inv.id)
            .all()
        ):
            entries.append(
                {
                    "type": "adjustment",
                    "occurred_at": _iso(getattr(adj, "approved_at", None)),
                    "adjustment_type": adj.adjustment_type,
                    "quantity_adjustment": adj.quantity_adjustment,
                    "reason": adj.reason,
                    "actor_id": adj.approved_by,
                }
            )
    for ph in (
        db.query(PriceHistory).filter(PriceHistory.shop_product_id == sp.id).all()
    ):
        entries.append(
            {
                "type": "price_change",
                "occurred_at": _iso(ph.effective_from),
                "old_price": float(ph.old_price) if ph.old_price is not None else None,  # pyright: ignore[reportUnnecessaryComparison]
                "new_price": float(ph.new_price) if ph.new_price is not None else None,  # pyright: ignore[reportUnnecessaryComparison]
                "old_mrp": float(ph.old_mrp) if ph.old_mrp is not None else None,
                "new_mrp": float(ph.new_mrp) if ph.new_mrp is not None else None,
                "change_source": (
                    ph.change_source.value
                    if hasattr(ph.change_source, "value")
                    else str(ph.change_source)
                ),
                "actor_id": ph.changed_by,
            }
        )

    epoch = datetime.min.replace(tzinfo=timezone.utc)

    def _stamp(entry: dict[str, Any]) -> datetime:
        raw = entry.get("occurred_at")
        if isinstance(raw, datetime):
            return raw
        if isinstance(raw, str):
            try:
                parsed = datetime.fromisoformat(raw)
                return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
            except ValueError:
                return epoch
        return epoch

    entries.sort(key=_stamp, reverse=True)

    # ── Actor resolution ─────────────────────────────────────────────────
    # Every audit row stores WHO changed the stock (movement.created_by /
    # adjustment.approved_by / price_history.changed_by). Resolve them all in
    # ONE query instead of per-row so a long trail stays a single round trip.
    # A null actor is reported as null — never back-filled with the current
    # user, which would misattribute an automated import or POS sync.
    actor_ids = {
        entry["actor_id"] for entry in entries if entry.get("actor_id") is not None
    }
    actor_names: dict[int, str | None] = {}
    if actor_ids:
        # Single-model query (not a two-column tuple) so it works with both
        # SQLAlchemy and the service's test doubles.
        actor_names = {
            actor.id: actor.name
            for actor in db.query(User).filter(User.id.in_(actor_ids)).all()
        }
    for entry in entries:
        actor_id = entry.get("actor_id")
        entry["actor"] = actor_names.get(actor_id) if actor_id is not None else None

    # ── Pagination ───────────────────────────────────────────────────────
    page_size = max(int(limit), 1)
    start = max(int(offset), 0)
    total = len(entries)
    page = entries[start : start + page_size]

    # Net current stock for the history summary tile. Read from the same
    # Inventory row the trail belongs to, so the header can never disagree
    # with the latest movement.
    current_quantity = int(inv.quantity or 0) if inv is not None else 0
    # Stock state is the server's word: prefer the listing's own column, fall
    # back to the inventory row it is denormalised from, and only then admit
    # UNKNOWN — never guess a state the backend did not declare.
    status_source = sp.stock_status
    if status_source is None and inv is not None:  # pyright: ignore[reportUnnecessaryComparison]
        status_source = inv.stock_status
    stock_status = (
        status_source.value
        if hasattr(status_source, "value")
        else (str(status_source) if status_source else "UNKNOWN")
    )

    return {
        "shop_product_id": sp.id,
        "count": len(page),
        "total": total,
        "offset": start,
        "limit": page_size,
        "has_more": start + len(page) < total,
        "current_quantity": current_quantity,
        "stock_status": stock_status,
        "entries": page,
    }


def bulk_operation(access: ShopAccess, db: Session, user: User, data: dict[str, Any]) -> dict[str, Any]:
    """Bulk operations foundation: apply one change to many shop products.

    Supported operations: ``price_update``, ``stock_set``, ``availability``.
    Per-item results are reported so callers can surface partial failures.
    """
    operation = str(data.get("operation", "")).lower().strip()
    if operation not in BULK_OPERATIONS:
        raise ValidationError(f"Unsupported bulk operation: {operation}")

    raw_ids: Any = data.get("shop_product_ids") or []  # pyright: ignore[reportUnknownMemberType]
    ids = [int(sid) for sid in raw_ids]
    if not ids:
        raise ValidationError("shop_product_ids must not be empty")

    results: list[dict[str, Any]] = []
    failed: list[dict[str, Any]] = []
    for sid in ids:
        try:
            if operation == "price_update":
                payload: dict[str, Any] = {}
                if data.get("price") is not None:
                    payload["price"] = data["price"]
                if data.get("mrp") is not None:
                    payload["mrp"] = data["mrp"]
                if not payload:
                    raise ValidationError("price_update requires price and/or mrp")
            elif operation == "stock_set":
                if data.get("quantity") is None:
                    raise ValidationError("stock_set requires quantity")
                payload = {"quantity": int(data["quantity"])}
            else:  # availability
                if data.get("is_available") is None:
                    raise ValidationError("availability requires is_available")
                payload = {"is_available": bool(data["is_available"])}
            update_product(access, db, user, sid, payload)
            results.append({"shop_product_id": sid, "success": True})
        except AppError as exc:
            failed.append({"shop_product_id": sid, "success": False, "error": exc.message})

    return {
        "operation": operation,
        "requested": len(ids),
        "succeeded": len(results),
        "failed_count": len(failed),
        "results": results,
        "failed": failed,
    }


def assign_offer(access: ShopAccess, db: Session, user: User, data: dict[str, Any]) -> dict[str, Any]:
    """Create an offer for this shop and attach it to selected shop products
    (offer assignment; owner/admin permission)."""
    access.require("offer", "update")

    # Phase 28 — subscription entitlement enforcement (offers + cap).
    _enforce_offers(db, access)

    start_date = _to_utc(data["start_date"])
    end_date = _to_utc(data["end_date"])
    if end_date <= start_date:
        raise ValidationError("Offer end date must be after start date")

    offer_type_name = str(data["offer_type"]).upper()
    try:
        offer_enum = _enum_from_name("OfferType", offer_type_name)
    except KeyError as exc:
        raise ValidationError(f"Invalid offer type: {offer_type_name}") from exc

    discount_value = data.get("discount_value")
    discount_percentage = data.get("discount_percentage")
    promotional_price = data.get("promotional_price")
    if offer_enum == OfferType.PERCENTAGE_DISCOUNT and not discount_percentage:
        raise ValidationError("Percentage offers require discount_percentage")
    if offer_enum == OfferType.FLAT_DISCOUNT and discount_value in (None, 0):
        raise ValidationError("Flat-discount offers require discount_value")
    if offer_enum == OfferType.PROMOTIONAL_PRICE and promotional_price in (None, 0):
        raise ValidationError("Promotional-price offers require promotional_price")

    # Absent status keeps the historical default — a newly assigned offer goes
    # live immediately, which is what the customer search flow expects. DRAFT
    # and DISABLED are opt-in so the app can park an offer before publishing it.
    requested_status = str(data.get("status") or "").strip().upper()
    if requested_status in ("", "ACTIVE"):
        initial_status = OfferStatus.ACTIVE
    elif requested_status in ("DRAFT", "DISABLED"):
        initial_status = OfferStatus[requested_status]
    else:
        raise ValidationError(f"Invalid offer status: {data.get('status')}")

    product_ids: list[int] = []
    raw_sids: Any = data.get("shop_product_ids") or []  # pyright: ignore[reportUnknownMemberType]
    for sid in raw_sids:
        sp = (
            db.query(ShopProduct)
            .filter(
                ShopProduct.id == int(sid),  # pyright: ignore[reportUnknownArgumentType]
                ShopProduct.shop_id == access.shop.id,
                ShopProduct.is_deleted == False,  # noqa: E712
            )
            .first()
        )
        if sp is None:
            raise NotFoundError(f"Product {sid} not found in this shop")
        product_ids.append(sp.id)

    offer = Offer(
        shop_id=access.shop.id,
        title=str(data["title"]).strip(),
        description=data.get("description"),
        offer_type=offer_enum,
        discount_value=discount_value,
        discount_percentage=discount_percentage,
        promotional_price=promotional_price,
        start_date=start_date,
        end_date=end_date,
        status=initial_status,
        terms_conditions=data.get("terms_conditions"),
    )
    db.add(offer)
    db.flush()

    for sid in product_ids:
        db.add(OfferProduct(offer_id=offer.id, shop_product_id=sid))

    logger.info(
        "Offer assigned: shop=%s offer=%s products=%s by user=%s",
        access.shop.id, offer.id, product_ids, user.id,
    )
    return {
        "offer_id": offer.id,
        "title": offer.title,
        "offer_type": offer_enum.value,
        "status": offer.status.value,
        "start_date": _iso(start_date),
        "end_date": _iso(end_date),
        "product_ids": product_ids,
        "product_count": len(product_ids),
    }


def _to_utc(dt: datetime) -> datetime:
    """Normalize a possibly-naive datetime to UTC-aware for comparison.

    The Offer date columns are stored offset-naive, while callers compare them
    against an offset-aware `now`. Comparing the two directly raises
    'can't compare offset-naive and offset-aware datetimes' — the 500 that
    broke the dashboard and offers list. Normalize the column value first so
    the comparison is always aware-vs-aware.
    """
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _offer_display_status(offer: Offer, now: datetime) -> str:
    """Shopkeeper-facing status bucket for one offer.

    The stored ``status`` column cannot express "ACTIVE but not started yet" or
    "ACTIVE but the window already closed", so those two are DERIVED from the
    date window. The shopkeeper app's Active / Scheduled / Expired tabs read
    this field rather than re-deriving dates on the client.
    """
    stored = offer.status if isinstance(offer.status, OfferStatus) else OfferStatus(offer.status)  # pyright: ignore[reportUnnecessaryIsInstance]
    if stored in (OfferStatus.DRAFT, OfferStatus.DISABLED):
        return stored.value
    if offer.status == OfferStatus.ACTIVE:
        if offer.start_date is not None and _to_utc(offer.start_date) > now:  # pyright: ignore[reportUnnecessaryComparison]
            return "SCHEDULED"
        if offer.end_date is not None and _to_utc(offer.end_date) < now:  # pyright: ignore[reportUnnecessaryComparison]
            return "EXPIRED"
    return offer.status.value if isinstance(offer.status, OfferStatus) else str(offer.status)  # pyright: ignore[reportUnnecessaryIsInstance]


def _offer_summary(offer: Offer, product_count: int, now: datetime) -> dict[str, Any]:
    """Wire shape for one offer row (list + detail views share it)."""
    status_value = offer.status.value if isinstance(offer.status, OfferStatus) else str(offer.status)  # pyright: ignore[reportUnnecessaryIsInstance]
    return {
        "id": offer.id,
        "title": offer.title,
        "description": offer.description,
        "offer_type": offer.offer_type.value,
        "discount_value": (
            float(offer.discount_value) if offer.discount_value is not None else None
        ),
        "discount_percentage": (
            float(offer.discount_percentage)
            if offer.discount_percentage is not None
            else None
        ),
        "promotional_price": (
            float(offer.promotional_price)
            if offer.promotional_price is not None
            else None
        ),
        "status": status_value,
        "display_status": _offer_display_status(offer, now),
        "start_date": _iso(offer.start_date),
        "end_date": _iso(offer.end_date),
        "is_visible": bool(offer.is_visible),
        "terms_conditions": offer.terms_conditions,
        "product_count": product_count,
    }


def list_shop_offers(
    access: ShopAccess, db: Session, status_filter: str | None = None
) -> dict[str, Any]:
    """Offers belonging to this shop, newest window first.

    ``status_filter`` accepts the shopkeeper-facing buckets ``active``,
    ``scheduled``, ``expired`` and ``draft``; anything else (or ``None``)
    returns every offer for the shop. Read-only — requires ``offer:read``,
    which both owners and managers hold.
    """
    access.require("offer", "read")

    now = datetime.now(timezone.utc)
    query = (
        db.query(Offer)
        .filter(
            Offer.shop_id == access.shop.id,
            Offer.is_deleted == False,  # noqa: E712
        )
        .order_by(Offer.start_date.desc(), Offer.id.desc())
    )

    bucket = (status_filter or "").strip().lower()
    if bucket == "draft":
        query = query.filter(Offer.status == OfferStatus.DRAFT)
    elif bucket == "disabled":
        query = query.filter(Offer.status == OfferStatus.DISABLED)
    elif bucket == "expired":
        query = query.filter(
            or_(Offer.status == OfferStatus.EXPIRED, Offer.end_date < now)
        )
    elif bucket == "scheduled":
        query = query.filter(
            Offer.status == OfferStatus.ACTIVE, Offer.start_date > now
        )
    elif bucket == "active":
        query = query.filter(
            Offer.status == OfferStatus.ACTIVE,
            Offer.start_date <= now,
            Offer.end_date >= now,
        )

    offers = query.all()

    # One grouped count instead of a per-row query (avoids N+1 on the list).
    counts: dict[int, int] = {}
    if offers:
        rows = (
            db.query(OfferProduct.offer_id, func.count(OfferProduct.id))
            .filter(OfferProduct.offer_id.in_([o.id for o in offers]))
            .group_by(OfferProduct.offer_id)
            .all()
        )
        counts = {offer_id: int(total) for offer_id, total in rows}

    items = [_offer_summary(o, counts.get(o.id, 0), now) for o in offers]
    return {"items": items, "count": len(items)}


_OFFER_STATUS_TRANSITIONS: dict[OfferStatus, set[OfferStatus]] = {
    OfferStatus.DRAFT: {OfferStatus.ACTIVE, OfferStatus.DISABLED},
    OfferStatus.ACTIVE: {
        OfferStatus.PAUSED,
        OfferStatus.DISABLED,
        OfferStatus.CANCELLED,
        OfferStatus.EXPIRED,
    },
    OfferStatus.PAUSED: {OfferStatus.ACTIVE, OfferStatus.DISABLED, OfferStatus.CANCELLED},
    OfferStatus.DISABLED: {OfferStatus.DRAFT, OfferStatus.ACTIVE},
}


def update_shop_offer_status(
    access: ShopAccess, db: Session, user: User, offer_id: int, status: str
) -> dict[str, Any]:
    """Change one shop-owned offer's lifecycle state.

    Draft offers may be activated directly (scheduled when the window starts in
    the future). Active offers may be paused, disabled or cancelled; disabled
    offers may return to draft or go active again. Expired/cancelled offers are
    terminal and can never be re-activated. Expired offers can never be
    re-activated.
    """
    access.require("offer", "update")

    offer = (
        db.query(Offer)
        .filter(
            Offer.id == offer_id,
            Offer.shop_id == access.shop.id,
            Offer.is_deleted == False,  # noqa: E712
        )
        .first()
    )
    if offer is None:
        raise NotFoundError("Offer not found in this shop")

    try:
        target = OfferStatus(str(status).strip().upper())
    except ValueError as exc:
        raise ValidationError(f"Invalid offer status: {status}") from exc

    current = offer.status if isinstance(offer.status, OfferStatus) else OfferStatus(offer.status)  # pyright: ignore[reportUnnecessaryIsInstance]
    if current in (OfferStatus.EXPIRED, OfferStatus.CANCELLED):
        raise ValidationError(f"Cannot move an offer from {current.value}")
    allowed = _OFFER_STATUS_TRANSITIONS.get(current, set())
    if target not in allowed:
        raise ValidationError(f"Cannot move an offer from {current.value} to {target.value}")

    offer.status = target
    db.flush()
    logger.info(
        "Offer status changed: shop=%s offer=%s %s->%s by user=%s",
        access.shop.id, offer.id, current.value, target.value, user.id,
    )
    product_count = (
        db.query(func.count(OfferProduct.id))
        .filter(OfferProduct.offer_id == offer.id)
        .scalar()
    )
    summary = _offer_summary(offer, int(product_count or 0), datetime.now(timezone.utc))
    _notify(
        db, access, user,
        "notify_shop_offer_event",
        offer_id=offer.id,
        event=target.value,
        offer_title=str(offer.title or ""),
    )
    return summary


# ── Profile / settings updates ───────────────────────────────────────────

PROFILE_FIELDS = [
    "name",
    "description",
    "tagline",
    "phone",
    "alternate_phone",
    "whatsapp_number",
    "email",
    "website_url",
    "image_url",
    "logo_url",
]

SETTINGS_FIELDS = [
    "is_accepting_orders",
    "is_delivery_available",
    "is_pickup_available",
    "is_open_24x7",
    "min_order_amount",
    "delivery_radius_km",
    "delivery_fee",
    "free_delivery_above",
]


def update_shop_profile(access: ShopAccess, db: Session, data: dict[str, Any]) -> dict[str, Any]:
    """Whitelisted shop-profile update (requires ``shop:update``)."""
    access.require("shop", "update")
    updates = {k: v for k, v in data.items() if k in PROFILE_FIELDS and v is not None}
    updated = shop_service.update_shop(db, access.shop.id, updates)
    if updated is None:
        raise NotFoundError("Shop not found")
    if updates:
        _notify(
            db, access, None,
            "notify_account_event",
            event="PROFILE_UPDATED",
            message="Your shop profile was updated successfully.",
        )
    return {"updated_fields": sorted(updates.keys())}


def update_shop_settings(access: ShopAccess, db: Session, data: dict[str, Any]) -> dict[str, Any]:
    """Operational settings toggles (requires ``shop:update``)."""
    access.require("shop", "update")
    updates = {k: v for k, v in data.items() if k in SETTINGS_FIELDS and v is not None}
    updated = shop_service.update_shop(db, access.shop.id, updates)
    if updated is None:
        raise NotFoundError("Shop not found")
    logger.info(
        "Shop settings updated: shop=%s fields=%s",
        access.shop.id, sorted(updates.keys()),
    )
    if updates:
        _notify(
            db, access, None,
            "notify_account_event",
            event="SETTINGS_UPDATED",
            message="Your shop settings were updated successfully.",
        )
    return {"updated_fields": sorted(updates.keys())}

