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
from typing import Any

from sqlalchemy.orm import Session

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
    shop = (
        db.query(Shop)
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
        shop = db.query(Shop).filter(Shop.id == row.shop_id).first()
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
        shop = db.query(Shop).filter(Shop.id == row.shop_id).first()
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


def create_shopkeeper_account(
    db: Session,
    phone_number: str,
    name: str,
    email: str | None = None,
) -> User:
    """Create a new user carrying the shopkeeper role.

    Shopkeepers deliberately get NO Customer profile — they are business
    accounts on the platform.
    """
    role = ensure_shopkeeper_role(db)
    user = User(
        phone_number=phone_number,
        name=name.strip(),
        email=email,
        role_id=role.id,
        status=UserStatus.ACTIVE,
        is_active=True,
    )
    db.add(user)
    db.flush()
    logger.info("Shopkeeper account created: user=%s", user.id)
    return user


# ── Shop registration (wraps shared shop_service) ────────────────────────


def register_shop_for_shopkeeper(db: Session, user: User, data: dict) -> Shop:
    """Register a new shop owned by *user* (becomes primary owner)."""
    from app.models.shop import ShopCategory

    payload = dict(data)
    address = payload.pop("address", None) or {}
    category = payload.get("category")
    if isinstance(category, str):
        normalized = category.strip().upper()
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
    return shop


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
        "image_url": getattr(shop, "image_url", None),
        "logo_url": getattr(shop, "logo_url", None),
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
    return {
        "id": sp.id,
        "shop_id": sp.shop_id,
        "name": _display_name(sp),
        "sku": sp.sku,
        "status": getattr(sp.status, "value", str(sp.status)),
        "price": float(sp.price or 0),
        "mrp": float(sp.mrp) if sp.mrp is not None else None,
        "is_active": sp.is_active,
        "is_available": sp.is_available,
        "is_featured": sp.is_featured,
        "quantity": qty,
        "low_stock_threshold": threshold,
        "stock_status": status,
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


def create_product(
    access: ShopAccess, db: Session, user: User, data: dict
) -> dict[str, Any]:
    """Create a ProductMaster + ShopProduct + Inventory row for the shop.

    Phase 23 guard: when a valid product-master already exists in the shared
    catalog (normalized name match), the shopkeeper's listing is LINKED to it —
    a duplicate master record is never created.
    """
    from app.models.product import ShopProductStatus

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

    if data.get("is_featured") is not None:
        sp.is_featured = bool(data["is_featured"])

    quantity_changed = data.get("quantity") is not None
    threshold_changed = data.get("low_stock_threshold") is not None
    explicit_availability = data.get("is_available")

    if quantity_changed or threshold_changed:
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
        inv.last_updated_by = user.id
        sp.last_inventory_update = now
        # Availability follows stock unless explicitly overridden below.
        sp.is_available = qty > 0

    if data.get("status"):
        wanted = str(data["status"]).upper()
        try:
            sp.status = _enum_from_name("ShopProductStatus", wanted)
        except KeyError as exc:
            raise ValidationError(f"Invalid product status: {data['status']}") from exc

    if explicit_availability is not None:
        sp.is_available = bool(explicit_availability)

    db.flush()
    logger.info(
        "Product updated: shop=%s shop_product=%s by user=%s",
        access.shop.id, sp.id, user.id,
    )
    return serialize_product(sp, inv)


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

