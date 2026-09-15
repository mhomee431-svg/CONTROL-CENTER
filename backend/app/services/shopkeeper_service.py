"""Phase 22 — Shopkeeper App business logic.

All shopkeeper operations are SHOP-SCOPED and ASSOCIATION-CHECKED:
``resolve_shop_access`` must pass before any resource is read or mutated,
guaranteeing a shopkeeper can only manage authorized shops.

This module contains no customer-app logic — customer features live in
their own services/routes.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, time, timezone
import re
import uuid
from typing import Any

from sqlalchemy import func, or_
from sqlalchemy.orm import Session, defer

from app.core.exceptions import (
    AppError,
    ConflictError,
    ForbiddenError,
    NotFoundError,
    ValidationError,
)
from app.core.logging import get_logger
from app.core.shopkeeper_permissions import (
    SHOPKEEPER_PERMISSIONS,
    effective_shop_permissions,
    ensure_shopkeeper_role,
    has_permission,
    permission_key,
    sync_owner_role,
)
from app.models.product import (
    Inventory,
    InventoryAdjustment,
    InventoryMovement,
    InventorySource,
    Offer,
    OfferProduct,
    OfferStatus,
    OfferType,
    PriceHistory,
    ProductImage,
    ProductMaster,
    ProductStatus,
    ShopProduct,
)
from app.services.inventory_service import compute_freshness
from app.models.shop import (
    Shop,
    ShopManager,
    ShopOwner,
    ShopStatus,
    ShopVerification,
    VerificationStatus,
)
from app.models.subscription import Subscription
from app.models.user import User, UserStatus
from app.services import shop_service

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

logger = get_logger("app.services.shopkeeper")
# ── Access resolution ────────────────────────────────────────────────────


@dataclass
class ShopAccess:
    """Resolved authorization context for a user ↔ shop pair."""

    shop: Shop
    role_name: str | None  # "owner" | "manager" | "admin"
    is_owner: bool = False
    permissions: set[str] = field(default_factory=set)

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
        return ShopAccess(
            shop=shop,
            role_name="admin" if role_name == "admin" else "owner",
            is_owner=True,
            permissions=effective_shop_permissions(role_name, True, None),
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
        perms = effective_shop_permissions(role_name, False, manager)
        if not perms:
            raise ForbiddenError("You do not have access to this shop")
        return ShopAccess(
            shop=shop, role_name="manager", is_owner=False, permissions=perms
        )

    if role_name == "admin":
        return ShopAccess(
            shop=shop,
            role_name="admin",
            is_owner=True,
            permissions=effective_shop_permissions("admin", True, None),
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


def register_shop_for_shopkeeper(db: Session, user: User, data: dict) -> Shop:
    """Register a new shop owned by *user* (becomes primary owner)."""
    from app.models.shop import ShopCategory

    payload = dict(data)
    address = payload.pop("address", None) or {}
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
    meta: dict | None = None,
    request_meta: dict | None = None,
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


def _iso(value) -> str | None:
    if value is None:
        return None
    if isinstance(value, str):
        return value
    if isinstance(value, datetime):
        return value.isoformat()
    return str(value)


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
            "verification": verification_payload(db, shop),
            "subscription": subscription_payload(db, shop),
            "rating": shop.rating,
            "review_count": shop.review_count,
            "created_at": _iso(getattr(shop, "created_at", None)),
        }
    )
    return payload


# ── Dashboard ────────────────────────────────────────────────────────────


def _derive_stock_status(quantity: int, threshold: int) -> str:
    if quantity <= 0:
        return "OUT_OF_STOCK"
    if quantity <= max(threshold, 1):
        return "LOW_STOCK"
    return "IN_STOCK"


def _enum_from_name(enum_class_name: str, name: str):
    import app.models.product as product_models

    enum_cls = getattr(product_models, enum_class_name)
    return enum_cls[name]


def _display_name(sp: ShopProduct) -> str:
    master = getattr(sp, "product_master", None)
    if master is not None and getattr(master, "name", None):
        return master.name
    return f"Product #{sp.product_master_id}"


def _product_counts(
    products: list[ShopProduct], inventories: dict[int, Inventory]
) -> dict[str, Any]:
    total = len(products)
    active = sum(1 for p in products if p.is_active and p.is_available)
    inactive = total - active

    in_stock = low_stock = out_of_stock = unknown = 0
    units = 0
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
        if status in ("IN_STOCK", "PRE_ORDER", "BACK_ORDER"):
            in_stock += 1
        elif status in ("LOW_STOCK", "LIMITED_STOCK"):
            low_stock += 1
        elif status == "OUT_OF_STOCK":
            out_of_stock += 1
        else:
            unknown += 1
        units += qty
        if status in ("LOW_STOCK", "LIMITED_STOCK", "OUT_OF_STOCK") and p.is_active:
            needs_attention.append(
                {
                    "shop_product_id": p.id,
                    "name": _display_name(p),
                    "quantity": qty,
                    "stock_status": status,
                }
            )

    return {
        "total": total,
        "active": active,
        "inactive": inactive,
        "in_stock": in_stock,
        "low_stock": low_stock,
        "out_of_stock": out_of_stock,
        "unknown": unknown,
        "total_units": units,
        "needs_attention": sorted(
            needs_attention,
            key=lambda x: (x["stock_status"] != "OUT_OF_STOCK", -x["quantity"]),
        )[:10],
    }


def _iso(value) -> str | None:
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

    recent_updates = []
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
            if o.status == OfferStatus.ACTIVE and o.end_date is not None and o.end_date >= now
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


# ── Inventory overview & products ────────────────────────────────────────


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
                "last_inventory_update": _iso(sp.last_inventory_update),
            }
        )
    items.sort(key=lambda i: (i["stock_status"] != "OUT_OF_STOCK", -i["quantity"]))
    stats = _product_counts(products, inventories)
    return {"items": items, "summary": stats}


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
    next_sort = (
        max((i.sort_order or 0) for i in (master.images or [])) + 1
        if getattr(master, "images", None)
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


def serialize_product(sp: ShopProduct, inv: Inventory | None) -> dict[str, Any]:
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
        "status": getattr(sp.status, "value", str(sp.status)),
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
        "last_inventory_update": _iso(sp.last_inventory_update),
        "last_price_update": _iso(sp.last_price_update),
        "created_at": _iso(getattr(sp, "created_at", None)),
    }


def list_products(
    access: ShopAccess,
    db: Session,
    search: str | None = None,
    status_filter: str | None = None,
    stock_filter: str | None = None,
) -> list[dict[str, Any]]:
    products: list[ShopProduct] = (
        db.query(ShopProduct).filter(ShopProduct.shop_id == access.shop.id).all()
    )
    result = []
    for sp in products:
        inv = db.query(Inventory).filter(Inventory.shop_product_id == sp.id).first()
        item = serialize_product(sp, inv)
        if search and search.lower() not in item["name"].lower():
            continue
        if status_filter and item["status"] != status_filter.upper():
            continue
        if stock_filter and item["stock_status"] != stock_filter.upper():
            continue
        result.append(item)
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


def _normalize(value) -> str:
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


def _shop_entitlements(db: Session, access: ShopAccess) -> dict:
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


class _ShopIdStub:
    """Minimal shop-like object for entitlement resolution by id."""

    def __init__(self, shop_id: int):
        self.id = shop_id


def create_product(
    access: ShopAccess, db: Session, user: User, data: dict
) -> dict[str, Any]:
    """Create a ProductMaster + ShopProduct + Inventory row for the shop.

    Phase 23 guard: when a valid product-master already exists in the shared
    catalog (normalized name match), the shopkeeper's listing is LINKED to it —
    a duplicate master record is never created.
    Phase 28 guard: the shop's plan ``max_products`` entitlement is enforced.
    """
    from app.models.product import ShopProductStatus

    # Phase 28 — subscription entitlement enforcement (product limit).
    _enforce_product_limit(db, access)

    price = float(data["price"])
    mrp = float(data["mrp"]) if data.get("mrp") is not None else None
    if mrp is not None and mrp < price:
        raise ValidationError("MRP cannot be lower than selling price")

    publish = bool(data.get("publish"))
    quantity = int(data.get("quantity", 0))
    threshold = int(data.get("low_stock_threshold", 5))
    stock_enum = _enum_from_name("StockStatus", _derive_stock_status(quantity, threshold))
    now = datetime.now(timezone.utc)

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
    else:
        master = ProductMaster(
            name=data["name"].strip(),
            slug=_unique_master_slug(db, data["name"]),
            description=data.get("description"),
            base_unit=data.get("unit"),
            status=ProductStatus.APPROVED if publish else ProductStatus.DRAFT,
            is_active=publish,
        )
        db.add(master)
        db.flush()

    sp = ShopProduct(
        shop_id=access.shop.id,
        product_master_id=master.id,
        sku=_unique_sku(db, access.shop.id, data.get("sku")),
        status=ShopProductStatus.ACTIVE,
        price=price,
        mrp=mrp,
        is_active=publish,
        is_available=bool(data.get("is_available", True)) and publish and quantity > 0,
        stock_status=stock_enum,
        last_inventory_update=now,
        last_price_update=now,
    )
    # Link eagerly so serialization sees the master name immediately.
    sp.product_master = master
    db.add(sp)
    db.flush()

    # Phase 7 — persist the (route-validated) uploaded image as the
    # master's primary catalog image.
    if data.get("image_url"):
        _attach_master_image(db, master, data["image_url"])

    db.add(
        Inventory(
            shop_product_id=sp.id,
            quantity=quantity,
            available_quantity=quantity,
            stock_status=stock_enum,
            low_stock_threshold=threshold,
            last_updated_by=user.id,
        )
    )
    db.flush()

    inv = db.query(Inventory).filter(Inventory.shop_product_id == sp.id).first()
    logger.info(
        "Product created: shop=%s shop_product=%s by user=%s",
        access.shop.id, sp.id, user.id,
    )
    return serialize_product(sp, inv)


def update_product(
    access: ShopAccess, db: Session, user: User, shop_product_id: int, data: dict
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
    old_price = float(sp.price) if sp.price is not None else 0.0
    old_mrp = float(sp.mrp) if sp.mrp is not None else None

    new_price = float(data["price"]) if data.get("price") is not None else None
    if data.get("mrp") is not None:
        mrp = float(data["mrp"])
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

    # Phase 7 — attach a newly uploaded image (route-validated) if provided.
    if data.get("image_url"):
        master = getattr(sp, "product_master", None)
        if master is not None:
            _attach_master_image(db, master, data["image_url"])

    db.flush()
    logger.info(
        "Product updated: shop=%s shop_product=%s by user=%s",
        access.shop.id, sp.id, user.id,
    )
    return serialize_product(sp, inv)


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
        variants = [
            {
                "variant_id": v.id,
                "name": v.name,
                "sku": v.sku,
                "is_active": bool(getattr(v, "is_active", True)),
            }
            for v in (master.variants or [])
            if getattr(v, "is_deleted", False) is not True
            and getattr(v, "is_active", True) is not False
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
                    if master.status is not None
                    else None,
                    "variants": variants,
                },
            )
        )
    scored.sort(key=lambda pair: (pair[0], _normalize(pair[1]["name"])))
    return [item for _, item in scored[: max(limit, 1)]]


def add_product_from_master(
    access: ShopAccess, db: Session, user: User, data: dict
) -> dict[str, Any]:
    """Link an EXISTING catalog product (master + optional variant) to the shop.

    The product master record itself is never created or duplicated here —
    shopkeepers select from the platform catalog and set shop-level price,
    MRP, availability and quantity.
    """
    from app.models.product import ShopProductStatus

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

    variant = None
    variant_id = data.get("variant_id")
    if variant_id is not None:
        variant = next(
            (v for v in (master.variants or []) if v.id == int(variant_id)),
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
            ShopProduct.variant_id == (variant.id if variant else None),
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
    now = datetime.now(timezone.utc)

    sp = ShopProduct(
        shop_id=access.shop.id,
        product_master_id=master.id,
        variant_id=variant.id if variant else None,
        sku=_unique_sku(db, access.shop.id, data.get("sku")),
        status=ShopProductStatus.ACTIVE,
        price=price,
        mrp=mrp,
        is_active=True,
        is_available=available,
        stock_status=stock_enum,
        source=InventorySource.MANUAL,
        last_inventory_update=now,
        last_price_update=now,
    )
    sp.product_master = master
    if variant is not None:
        sp.variant = variant
    db.add(sp)
    db.flush()

    inv = Inventory(
        shop_product_id=sp.id,
        quantity=quantity,
        reserved_quantity=0,
        available_quantity=quantity,
        is_available=available,
        stock_status=stock_enum,
        low_stock_threshold=threshold,
        last_updated_by=user.id,
        last_updated_source=InventorySource.MANUAL,
        freshness_status=compute_freshness(now, InventorySource.MANUAL),
        freshness_checked_at=now,
    )
    db.add(inv)
    db.flush()

    db.add(
        InventoryMovement(
            inventory_id=inv.id,
            quantity_change=quantity,
            quantity_before=0,
            quantity_after=quantity,
            movement_type="INITIAL",
            source=InventorySource.MANUAL,
            notes="Product added to shop inventory",
            created_by=user.id,
        )
    )

    # Link eagerly so serialization sees master/variant immediately.
    sp.inventory = inv
    logger.info(
        "Product added from catalog: shop=%s shop_product=%s master=%s by user=%s",
        access.shop.id, sp.id, master.id, user.id,
    )
    return serialize_product(sp, inv)


def adjust_stock(
    access: ShopAccess, db: Session, user: User, shop_product_id: int, data: dict
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
    return {
        "shop_product_id": sp.id,
        "previous_quantity": previous_quantity,
        "quantity_adjustment": delta,
        "new_quantity": updated_quantity,
        "stock_status": inv.stock_status.value,
        "adjustment_type": adjustment_type,
        "last_inventory_update": _iso(now),
    }


def remove_product(
    access: ShopAccess, db: Session, user: User, shop_product_id: int
) -> dict[str, Any]:
    """Deactivate + soft-delete a shop product listing."""
    from app.models.product import ShopProductStatus

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
    sort_by: str = "updated_at",
    sort_order: str = "desc",
) -> dict[str, Any]:
    """View / search / filter / sort the shop inventory.

    Every item carries its last-updated time and inventory source.
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
    for sp in products:
        inv = db.query(Inventory).filter(Inventory.shop_product_id == sp.id).first()
        per_product_inv[sp.id] = inv
        updater = getattr(inv, "last_updated_by", None) if inv is not None else None
        if updater:
            updater_ids.add(int(updater))
    updater_names: dict[int, str] = {}
    if updater_ids:
        from app.models.user import User

        for u in db.query(User).filter(User.id.in_(updater_ids)).all():
            updater_names[u.id] = u.name or f"User #{u.id}"

    entries: list[tuple[datetime, dict[str, Any]]] = []
    for sp in products:
        inv = per_product_inv[sp.id]
        item = serialize_product(sp, inv)
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
        item["source"] = (
            inv.last_updated_source.value
            if inv is not None and getattr(inv, "last_updated_source", None) is not None
            else getattr(sp.source, "value", str(sp.source))
        )
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
        if stock_filter and item["stock_status"] != str(stock_filter).upper():
            continue
        if availability_filter is not None and item["is_available"] != bool(availability_filter):
            continue
        if active_filter is not None and item["is_active"] != bool(active_filter):
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
    return {"items": items, "count": len(items)}


def product_history(
    access: ShopAccess,
    db: Session,
    user: User,
    shop_product_id: int,
    limit: int = 50,
) -> dict[str, Any]:
    """Combined audit trail for one shop product: movements, adjustments
    and price changes — newest first."""
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
                }
            )
    for ph in (
        db.query(PriceHistory).filter(PriceHistory.shop_product_id == sp.id).all()
    ):
        entries.append(
            {
                "type": "price_change",
                "occurred_at": _iso(ph.effective_from),
                "old_price": float(ph.old_price) if ph.old_price is not None else None,
                "new_price": float(ph.new_price) if ph.new_price is not None else None,
                "old_mrp": float(ph.old_mrp) if ph.old_mrp is not None else None,
                "new_mrp": float(ph.new_mrp) if ph.new_mrp is not None else None,
                "change_source": (
                    ph.change_source.value
                    if hasattr(ph.change_source, "value")
                    else str(ph.change_source)
                ),
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
    entries = entries[: max(int(limit), 1)]
    return {"shop_product_id": sp.id, "count": len(entries), "entries": entries}


def bulk_operation(access: ShopAccess, db: Session, user: User, data: dict) -> dict[str, Any]:
    """Bulk operations foundation: apply one change to many shop products.

    Supported operations: ``price_update``, ``stock_set``, ``availability``.
    Per-item results are reported so callers can surface partial failures.
    """
    operation = str(data.get("operation", "")).lower().strip()
    if operation not in BULK_OPERATIONS:
        raise ValidationError(f"Unsupported bulk operation: {operation}")

    ids = [int(sid) for sid in data.get("shop_product_ids") or []]
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


def assign_offer(access: ShopAccess, db: Session, user: User, data: dict) -> dict[str, Any]:
    """Create an offer for this shop and attach it to selected shop products
    (offer assignment; owner/admin permission)."""
    access.require("offer", "update")

    # Phase 28 — subscription entitlement enforcement (offers + cap).
    _enforce_offers(db, access)

    start_date = data["start_date"]
    end_date = data["end_date"]
    if end_date <= start_date:
        raise ValidationError("Offer end date must be after start date")

    offer_type_name = str(data["offer_type"]).upper()
    try:
        offer_enum = _enum_from_name("OfferType", offer_type_name)
    except KeyError as exc:
        raise ValidationError(f"Invalid offer type: {offer_type_name}") from exc

    discount_value = data.get("discount_value")
    discount_percentage = data.get("discount_percentage")
    if offer_enum == OfferType.PERCENTAGE_DISCOUNT and not discount_percentage:
        raise ValidationError("Percentage offers require discount_percentage")
    if offer_enum == OfferType.FLAT_DISCOUNT and discount_value in (None, 0):
        raise ValidationError("Flat-discount offers require discount_value")

    product_ids: list[int] = []
    for sid in data.get("shop_product_ids") or []:
        sp = (
            db.query(ShopProduct)
            .filter(
                ShopProduct.id == int(sid),
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
        start_date=start_date,
        end_date=end_date,
        status=OfferStatus.ACTIVE,
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


def _offer_display_status(offer: Offer, now: datetime) -> str:
    """Shopkeeper-facing status bucket for one offer.

    The stored ``status`` column cannot express "ACTIVE but not started yet" or
    "ACTIVE but the window already closed", so those two are DERIVED from the
    date window. The shopkeeper app's Active / Scheduled / Expired tabs read
    this field rather than re-deriving dates on the client.
    """
    if offer.status == OfferStatus.ACTIVE:
        if offer.start_date is not None and offer.start_date > now:
            return "SCHEDULED"
        if offer.end_date is not None and offer.end_date < now:
            return "EXPIRED"
    return offer.status.value


def _offer_summary(offer: Offer, product_count: int, now: datetime) -> dict[str, Any]:
    """Wire shape for one offer row (list + detail views share it)."""
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
        "status": offer.status.value,
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


def update_shop_profile(access: ShopAccess, db: Session, data: dict) -> dict[str, Any]:
    """Whitelisted shop-profile update (requires ``shop:update``)."""
    access.require("shop", "update")
    updates = {k: v for k, v in data.items() if k in PROFILE_FIELDS and v is not None}
    updated = shop_service.update_shop(db, access.shop.id, updates)
    if updated is None:
        raise NotFoundError("Shop not found")
    return {"updated_fields": sorted(updates.keys())}


def update_shop_settings(access: ShopAccess, db: Session, data: dict) -> dict[str, Any]:
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
    return {"updated_fields": sorted(updates.keys())}

