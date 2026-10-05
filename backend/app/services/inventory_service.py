"""Inventory and Pricing Engine service — business logic for inventory, price history, offers, and freshness."""

import asyncio
import contextlib
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

from sqlalchemy.orm import Session, selectinload

from app.core.config import settings
from app.core.logging import get_logger
from app.models.product import (
    CustomerStockStatus,
    FreshnessStatus,
    Inventory,
    InventoryAdjustment,
    InventoryMovement,
    InventorySource,
    Offer,
    OfferCondition,
    OfferProduct,
    OfferStatus,
    OfferType,
    PriceHistory,
    ShopProduct,
    StockStatus,
)
from app.models.shop import Shop

logger = get_logger("app.services.inventory")


# ── Freshness rules ─────────────────────────────────────────────────────────
# Stale-data rules: how long before inventory is considered stale, per source.
FRESHNESS_THRESHOLDS: dict[InventorySource, timedelta] = {
    InventorySource.MANUAL: timedelta(hours=24),
    InventorySource.BARCODE_SCAN: timedelta(hours=12),
    InventorySource.EXCEL_UPLOAD: timedelta(hours=48),
    InventorySource.POS_INTEGRATION: timedelta(minutes=30),
    InventorySource.SYSTEM: timedelta(hours=24),
}

DEFAULT_FRESHNESS_THRESHOLD = timedelta(hours=24)


def get_freshness_threshold(source: InventorySource) -> timedelta:
    """Return the staleness threshold for a given inventory source."""
    return FRESHNESS_THRESHOLDS.get(source, DEFAULT_FRESHNESS_THRESHOLD)


def _as_utc(dt: datetime) -> datetime:
    """Normalize a datetime to timezone-aware UTC (naive assumed UTC).

    Production (PostgreSQL TIMESTAMPTZ) returns aware datetimes; SQLite returns
    naive ones. Comparing the two raises ``TypeError``.
    """
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt


def compute_freshness(
    last_updated: Optional[datetime],
    source: InventorySource = InventorySource.MANUAL,
    now: Optional[datetime] = None,
) -> Optional[FreshnessStatus]:
    """Classify inventory freshness based on last-updated time and source."""
    if last_updated is None:
        return None
    now = now or datetime.now(timezone.utc)
    if last_updated.tzinfo is None:
        last_updated = last_updated.replace(tzinfo=timezone.utc)
    threshold = get_freshness_threshold(source)
    if now - last_updated > threshold:
        return FreshnessStatus.STALE
    return FreshnessStatus.RECENTLY_UPDATED


def map_to_customer_stock_status(stock_status: StockStatus, quantity: int = 0) -> CustomerStockStatus:
    """Map internal stock status to customer-facing status."""
    if stock_status == StockStatus.IN_STOCK:
        if quantity > 0 and quantity <= 5:
            return CustomerStockStatus.LIMITED_STOCK
        return CustomerStockStatus.IN_STOCK
    if stock_status == StockStatus.LOW_STOCK:
        return CustomerStockStatus.LIMITED_STOCK
    if stock_status == StockStatus.LIMITED_STOCK:
        return CustomerStockStatus.LIMITED_STOCK
    if stock_status == StockStatus.OUT_OF_STOCK:
        return CustomerStockStatus.OUT_OF_STOCK
    if stock_status in (StockStatus.PRE_ORDER, StockStatus.BACK_ORDER):
        return CustomerStockStatus.UNKNOWN
    return CustomerStockStatus.UNKNOWN


def derive_stock_status(quantity: int, low_stock_threshold: Optional[int] = None) -> StockStatus:
    """Derive stock status from quantity and low-stock threshold."""
    if quantity <= 0:
        return StockStatus.OUT_OF_STOCK
    threshold = low_stock_threshold if low_stock_threshold is not None else 5
    if quantity <= threshold:
        return StockStatus.LOW_STOCK
    return StockStatus.IN_STOCK


def _notify_back_in_stock(db: Session, shop_product: ShopProduct) -> None:
    """Phase 27 — fire the PRODUCT_AVAILABLE fan-out when stock returns.

    Never raises: notification failures must not break inventory writes.
    """
    if not shop_product.is_available or not shop_product.product_master_id:
        return
    try:
        from app.services import notification_service

        shop = (
            db.query(Shop).filter(Shop.id == shop_product.shop_id).first()
            if shop_product.shop_id
            else None
        )
        notification_service.notify_product_available(
            db,
            product_master_id=shop_product.product_master_id,
            shop_name=shop.name if shop else "a nearby shop",
        )
    except Exception:  # noqa: BLE001
        logger.warning(
            "Failed to fan out product-available notifications for shop_product %s",
            shop_product.id,
        )




# ── Inventory CRUD ──────────────────────────────────────────────────────────


def _enqueue_search_index_update(shop_product_id: int) -> None:
    """Invalidate cached search results, then fire the index update.

    Two jobs, one call site, because every mutation in this module already
    funnels through here: create/update/remove inventory, movements,
    adjustments, price changes and offers all change what a search WOULD
    return, so they all have to invalidate it.

    WHY INVALIDATION IS NOT OPTIONAL
    ---------------------------------
    ``GET /search/v2/products`` caches its result set for ``CACHE_DEFAULT_TTL``.
    A shopkeeper marking an item out of stock or changing its price does NOT
    change any cached key — the cache key is built from the QUERY
    parameters, not from the data. So without this line the customer keeps
    seeing the old price and "In Stock" for the whole TTL: they drive to the
    shop for something that is no longer there. The index update alone does not
    help, because it refreshes the INDEX, not the cached HTTP response.

    WHY IT IS BEST-EFFORT AND INSIDE A TRY
    --------------------------------------
    A cache outage must never fail a write. If invalidation fails the entry
    simply ages out on its TTL — degraded freshness for at most one TTL, not a
    lost inventory update. Read paths are never allowed to become a dependency
    of write paths.
    """
    # Best-effort: never let a cache problem fail a business write.
    #
    # `invalidate_domain` is async, but this hook is called from SYNC service
    # functions (a sync SQLAlchemy Session), which usually run in a threadpool
    # with no running event loop — so `asyncio.run` is the correct way to drive
    # it here. Where a loop IS already running (an async caller), we skip rather
    # than nest loops; the TTL then bounds the staleness.
    try:
        from app.api.routes.search import SEARCH_CACHE_DOMAIN
        from app.core.cache import cache

        # The invalidation is bounded end to end, not just per Redis command.
        # A down cache costs a socket connect timeout (and, with
        # REDIS_RETRY_ON_TIMEOUT, a retry), which adds seconds to EVERY
        # inventory write: a caller would wait on a cache the write does not
        # need. This ceiling is what keeps write latency independent of a cache
        # outage, which is the whole reason the invalidation is best-effort.
        async def _invalidate() -> None:
            with contextlib.suppress(asyncio.TimeoutError):
                await asyncio.wait_for(
                    cache.invalidate_domain(SEARCH_CACHE_DOMAIN),
                    settings.REDIS_WRITE_PATH_BUDGET_SECONDS,
                )

        try:
            asyncio.get_running_loop()
        except RuntimeError:
            # No loop on this thread: safe to drive the coroutine to completion.
            asyncio.run(_invalidate())
        else:
            pass  # Loop already running; the TTL will expire it instead.
    except Exception as exc:  # noqa: BLE001 - correctness must not depend on cache
        logger.warning(
            "Search cache invalidation failed; results may be stale for up to "
            "one TTL: %s",
            exc,
        )

    from app.core.celery_app import celery_app, publish_task_nonblocking

    publish_task_nonblocking(
        lambda: celery_app.send_task(
            "app.services.tasks.index_shop_product",
            args=[shop_product_id],
            ignore_result=True,
        ),
        label=f"index_shop_product({shop_product_id})",
    )


def create_inventory(db: Session, data: dict[str, Any]) -> Inventory:
    """Create a new inventory record for a shop product."""
    shop_product = db.query(ShopProduct).filter(ShopProduct.id == data["shop_product_id"]).first()
    if shop_product is None:
        raise ValueError("Shop product not found")

    # Check if inventory already exists
    existing = db.query(Inventory).filter(Inventory.shop_product_id == data["shop_product_id"]).first()
    if existing:
        raise ValueError("Inventory already exists for this shop product")

    quantity = data.get("quantity", 0)
    reserved = data.get("reserved_quantity", 0)
    available = max(quantity - reserved, 0)
    source = data.get("source", InventorySource.MANUAL)
    now = datetime.now(timezone.utc)

    inv = Inventory(
        shop_product_id=data["shop_product_id"],
        quantity=quantity,
        reserved_quantity=reserved,
        available_quantity=available,
        is_available=data.get("is_available", True),
        stock_status=derive_stock_status(quantity, data.get("low_stock_threshold")),
        low_stock_threshold=data.get("low_stock_threshold"),
        last_updated_by=data.get("created_by"),
        last_updated_source=source,
        last_synced_at=now if source != InventorySource.MANUAL else None,
        freshness_status=compute_freshness(now, source),
        freshness_checked_at=now,
    )
    db.add(inv)
    db.flush()

    # Create initial movement
    db.add(
        InventoryMovement(
            inventory_id=inv.id,
            quantity_change=quantity,
            quantity_before=0,
            quantity_after=quantity,
            movement_type="INITIAL",
            source=source,
            reference_type=data.get("reference_type"),
            reference_id=data.get("reference_id"),
            notes=data.get("notes"),
            created_by=data.get("created_by"),
        )
    )

    # Update shop product
    shop_product.stock_status = inv.stock_status
    shop_product.is_available = inv.is_available
    shop_product.last_inventory_update = now
    shop_product.source = source
    shop_product.freshness_status = inv.freshness_status
    db.flush()
    _enqueue_search_index_update(inv.shop_product_id)
    return inv


def update_inventory(db: Session, inventory_id: int, data: dict[str, Any]) -> Optional[Inventory]:
    """Update inventory quantity and related fields."""
    inv = db.query(Inventory).filter(Inventory.id == inventory_id).first()
    if inv is None:
        return None

    old_quantity = inv.quantity
    was_available = bool(inv.is_available)
    new_quantity = data.get("quantity", inv.quantity)
    new_reserved = data.get("reserved_quantity", inv.reserved_quantity)
    source = data.get("source", inv.last_updated_source)
    now = datetime.now(timezone.utc)

    # Update fields
    inv.quantity = new_quantity
    inv.reserved_quantity = new_reserved
    inv.available_quantity = max(new_quantity - new_reserved, 0)
    if "low_stock_threshold" in data:
        inv.low_stock_threshold = data["low_stock_threshold"]
    if "is_available" in data:
        inv.is_available = data["is_available"]
    inv.last_updated_by = data.get("created_by", inv.last_updated_by)
    inv.last_updated_source = source
    inv.last_synced_at = now if source != InventorySource.MANUAL else inv.last_synced_at
    inv.stock_status = derive_stock_status(inv.quantity, inv.low_stock_threshold)
    inv.freshness_status = compute_freshness(now, source)
    inv.freshness_checked_at = now

    # Record movement if quantity changed
    if new_quantity != old_quantity:
        db.add(
            InventoryMovement(
                inventory_id=inv.id,
                quantity_change=new_quantity - old_quantity,
                quantity_before=old_quantity,
                quantity_after=new_quantity,
                movement_type="UPDATE",
                source=source,
                reference_type=data.get("reference_type"),
                reference_id=data.get("reference_id"),
                notes=data.get("notes"),
                created_by=data.get("created_by"),
            )
        )

    # Update shop product
    sp = db.query(ShopProduct).filter(ShopProduct.id == inv.shop_product_id).first()
    if sp:
        sp.stock_status = inv.stock_status
        sp.is_available = inv.is_available
        sp.last_inventory_update = now
        sp.source = source
        sp.freshness_status = inv.freshness_status
        db.flush()
        if not was_available and inv.is_available:
            # Phase 27 — restock transition → notify customers who saved it.
            _notify_back_in_stock(db, sp)
    _enqueue_search_index_update(inv.shop_product_id)
    return inv


def remove_inventory(db: Session, inventory_id: int) -> bool:
    """Soft-remove inventory by setting quantity to 0 and marking unavailable."""
    inv = db.query(Inventory).filter(Inventory.id == inventory_id).first()
    if inv is None:
        return False

    old_quantity = inv.quantity
    inv.quantity = 0
    inv.reserved_quantity = 0
    inv.available_quantity = 0
    inv.is_available = False
    inv.stock_status = StockStatus.OUT_OF_STOCK
    now = datetime.now(timezone.utc)
    inv.freshness_status = compute_freshness(now, inv.last_updated_source)
    inv.freshness_checked_at = now

    db.add(
        InventoryMovement(
            inventory_id=inv.id,
            quantity_change=-old_quantity,
            quantity_before=old_quantity,
            quantity_after=0,
            movement_type="REMOVE",
            source=inv.last_updated_source,
            notes="Inventory removed",
        )
    )

    sp = db.query(ShopProduct).filter(ShopProduct.id == inv.shop_product_id).first()
    if sp:
        sp.stock_status = StockStatus.OUT_OF_STOCK
        sp.is_available = False
        sp.last_inventory_update = now
        sp.freshness_status = inv.freshness_status
        db.flush()
    _enqueue_search_index_update(inv.shop_product_id)
    return True


# ── Inventory movements ─────────────────────────────────────────────────────
def record_movement(db: Session, data: dict) -> InventoryMovement:
    """Record an inventory movement (sale, restock, return, damage, etc.)."""
    inv = db.query(Inventory).filter(Inventory.id == data["inventory_id"]).first()
    if inv is None:
        raise ValueError("Inventory not found")

    quantity_change = data["quantity_change"]
    new_quantity = inv.quantity + quantity_change
    if new_quantity < 0:
        raise ValueError("Insufficient stock for this movement")

    old_quantity = inv.quantity
    was_out_of_stock = inv.stock_status == StockStatus.OUT_OF_STOCK
    inv.quantity = new_quantity
    inv.available_quantity = max(new_quantity - inv.reserved_quantity, 0)
    inv.stock_status = derive_stock_status(inv.quantity, inv.low_stock_threshold)
    now = datetime.now(timezone.utc)
    inv.freshness_status = compute_freshness(now, data.get("source", inv.last_updated_source))
    inv.freshness_checked_at = now

    movement = InventoryMovement(
        inventory_id=inv.id,
        quantity_change=quantity_change,
        quantity_before=old_quantity,
        quantity_after=new_quantity,
        movement_type=data["movement_type"],
        source=data.get("source", inv.last_updated_source),
        reference_type=data.get("reference_type"),
        reference_id=data.get("reference_id"),
        notes=data.get("notes"),
        created_by=data.get("created_by"),
    )
    db.add(movement)

    sp = db.query(ShopProduct).filter(ShopProduct.id == inv.shop_product_id).first()
    if sp:
        sp.stock_status = inv.stock_status
        sp.is_available = inv.is_available
        sp.last_inventory_update = now
        sp.freshness_status = inv.freshness_status
        db.flush()
        if was_out_of_stock and inv.stock_status != StockStatus.OUT_OF_STOCK:
            # Phase 27 — movement brought an out-of-stock item back.
            _notify_back_in_stock(db, sp)
    _enqueue_search_index_update(inv.shop_product_id)
    return movement


# ── Inventory adjustments ───────────────────────────────────────────────────
def create_adjustment(db: Session, data: dict) -> InventoryAdjustment:
    """Create an inventory adjustment (stock count, damage, expiry, theft)."""
    inv = db.query(Inventory).filter(Inventory.id == data["inventory_id"]).first()
    if inv is None:
        raise ValueError("Inventory not found")

    adjustment = InventoryAdjustment(
        inventory_id=inv.id,
        adjustment_type=data["adjustment_type"],
        quantity_adjustment=data["quantity_adjustment"],
        reason=data.get("reason"),
        approved_by=data.get("approved_by"),
        approved_at=datetime.now(timezone.utc) if data.get("approved_by") else None,
    )
    db.add(adjustment)

    # Apply adjustment to quantity
    old_quantity = inv.quantity
    new_quantity = old_quantity + data["quantity_adjustment"]
    if new_quantity < 0:
        raise ValueError("Adjustment would result in negative inventory")
    inv.quantity = new_quantity
    inv.available_quantity = max(new_quantity - inv.reserved_quantity, 0)
    inv.stock_status = derive_stock_status(inv.quantity, inv.low_stock_threshold)
    now = datetime.now(timezone.utc)
    inv.freshness_status = compute_freshness(now, inv.last_updated_source)
    inv.freshness_checked_at = now

    db.add(
        InventoryMovement(
            inventory_id=inv.id,
            quantity_change=data["quantity_adjustment"],
            quantity_before=old_quantity,
            quantity_after=new_quantity,
            movement_type="ADJUSTMENT",
            source=inv.last_updated_source,
            notes=f"Adjustment: {data['adjustment_type']} - {data.get('reason', '')}",
        )
    )

    sp = db.query(ShopProduct).filter(ShopProduct.id == inv.shop_product_id).first()
    if sp:
        sp.stock_status = inv.stock_status
        sp.is_available = inv.is_available
        sp.last_inventory_update = now
        sp.freshness_status = inv.freshness_status
        db.flush()
    _enqueue_search_index_update(inv.shop_product_id)
    return adjustment


# ── Price history ───────────────────────────────────────────────────────────
def update_price(db: Session, shop_product_id: int, data: dict) -> Optional[PriceHistory]:
    """Update the selling price (and optionally MRP) of a shop product, preserving history."""
    sp = db.query(ShopProduct).filter(ShopProduct.id == shop_product_id).first()
    if sp is None:
        return None

    old_price = float(sp.price)
    old_mrp = float(sp.mrp) if sp.mrp is not None else None
    new_price = data["new_price"]
    new_mrp = data.get("new_mrp")
    source = data.get("change_source", InventorySource.MANUAL)
    now = datetime.now(timezone.utc)

    # Close out any open price history records
    open_records = (
        db.query(PriceHistory)
        .filter(PriceHistory.shop_product_id == shop_product_id, PriceHistory.effective_to.is_(None))
        .all()
    )
    for rec in open_records:
        rec.effective_to = now

    # Create new price history record
    history = PriceHistory(
        shop_product_id=shop_product_id,
        old_price=old_price,
        new_price=new_price,
        old_mrp=old_mrp,
        new_mrp=new_mrp,
        changed_by=data.get("changed_by"),
        change_source=source,
        effective_from=now,
        effective_to=None,
    )
    db.add(history)

    # Update shop product
    sp.price = new_price
    if new_mrp is not None:
        sp.mrp = new_mrp
    sp.last_price_update = now
    sp.source = source
    db.flush()

    if float(new_price) < float(old_price):
        # Phase 27 — price decrease → notify customers who saved this product.
        try:
            from app.services import notification_service

            shop = db.query(Shop).filter(Shop.id == sp.shop_id).first() if sp.shop_id else None
            notification_service.notify_price_drop(
                db,
                product_master_id=sp.product_master_id,
                shop_name=shop.name if shop else "a nearby shop",
                old_price=float(old_price),
                new_price=float(new_price),
            )
        except Exception:  # noqa: BLE001 — pricing flow must never break on notifications
            logger.warning(
                "Failed to fan out price-drop notifications for shop_product %s", shop_product_id
            )

    _enqueue_search_index_update(shop_product_id)
    return history


def list_price_history(db: Session, shop_product_id: int, limit: int = 50) -> list[PriceHistory]:
    """Return price history for a shop product, newest first."""
    return (
        db.query(PriceHistory)
        .filter(PriceHistory.shop_product_id == shop_product_id)
        .order_by(PriceHistory.effective_from.desc())
        .limit(limit)
        .all()
    )


# ── Offers ──────────────────────────────────────────────────────────────────
def create_offer(db: Session, data: dict) -> Offer:
    """Create a new offer with product mappings and conditions."""
    if data["end_date"] <= data["start_date"]:
        raise ValueError("end_date must be after start_date")
    _offer_type_value = data["offer_type"].value if hasattr(data["offer_type"], "value") else str(data["offer_type"])
    if _offer_type_value == "PERCENTAGE_DISCOUNT" and not data.get("discount_percentage"):
        raise ValueError("Percentage offers require discount_percentage")
    if _offer_type_value == "FLAT_DISCOUNT" and data.get("discount_value") in (None, 0):
        raise ValueError("Flat-discount offers require discount_value")
    if _offer_type_value == "PROMOTIONAL_PRICE" and data.get("promotional_price") in (None, 0):
        raise ValueError("Promotional-price offers require promotional_price")

    offer = Offer(
        shop_id=data["shop_id"],
        title=data["title"],
        description=data.get("description"),
        offer_type=data["offer_type"],
        discount_value=data.get("discount_value"),
        discount_percentage=data.get("discount_percentage"),
        promotional_price=data.get("promotional_price"),
        min_purchase_amount=data.get("min_purchase_amount"),
        max_discount_amount=data.get("max_discount_amount"),
        buy_quantity=data.get("buy_quantity"),
        get_quantity=data.get("get_quantity"),
        status=OfferStatus.DRAFT,
        start_date=data["start_date"],
        end_date=data["end_date"],
        is_visible=data.get("is_visible", True),
        terms_conditions=data.get("terms_conditions"),
    )
    db.add(offer)
    db.flush()

    # Product mappings
    for mapping in data.get("product_mappings", []):
        db.add(
            OfferProduct(
                offer_id=offer.id,
                shop_product_id=mapping["shop_product_id"],
                is_excluded=mapping.get("is_excluded", False),
            )
        )

    # Conditions
    for cond in data.get("conditions", []):
        db.add(
            OfferCondition(
                offer_id=offer.id,
                condition_type=cond["condition_type"],
                condition_value=cond["condition_value"],
                operator=cond.get("operator"),
            )
        )

    db.flush()
    return offer


def update_offer(db: Session, offer_id: int, data: dict) -> Optional[Offer]:
    """Update an offer."""
    offer = db.query(Offer).filter(Offer.id == offer_id, Offer.is_deleted == False).first()  # noqa: E712
    if offer is None:
        return None

    for key, value in data.items():
        if value is not None and hasattr(offer, key):
            setattr(offer, key, value)

    if "end_date" in data and "start_date" in data:
        if data["end_date"] <= data["start_date"]:
            raise ValueError("end_date must be after start_date")

    db.flush()
    return offer


def activate_offer(db: Session, offer_id: int) -> Optional[Offer]:
    """Activate an offer (set status to ACTIVE)."""
    offer = db.query(Offer).filter(Offer.id == offer_id, Offer.is_deleted == False).first()  # noqa: E712
    if offer is None:
        return None
    now = datetime.now(timezone.utc)
    if now < _as_utc(offer.start_date):
        offer.status = OfferStatus.DRAFT
    elif now > _as_utc(offer.end_date):
        offer.status = OfferStatus.EXPIRED
    else:
        offer.status = OfferStatus.ACTIVE
    db.flush()
    return offer


def expire_offer(db: Session, offer_id: int) -> Optional[Offer]:
    """Expire an offer (set status to EXPIRED)."""
    offer = db.query(Offer).filter(Offer.id == offer_id, Offer.is_deleted == False).first()  # noqa: E712
    if offer is None:
        return None
    offer.status = OfferStatus.EXPIRED
    db.flush()
    return offer


def list_offers(
    db: Session,
    *,
    shop_id: Optional[int] = None,
    status: Optional[OfferStatus] = None,
    active_only: bool = False,
    skip: int = 0,
    limit: int = 50,
) -> list[Offer]:
    """List offers with optional filters."""
    query = db.query(Offer).filter(Offer.is_deleted == False)  # noqa: E712
    if shop_id is not None:
        query = query.filter(Offer.shop_id == shop_id)
    if status is not None:
        query = query.filter(Offer.status == status)
    if active_only:
        now = datetime.now(timezone.utc)
        query = query.filter(Offer.status == OfferStatus.ACTIVE, Offer.start_date <= now, Offer.end_date >= now)
    return query.offset(skip).limit(limit).all()


def get_offer_detail(db: Session, offer_id: int) -> Optional[Offer]:
    """Get an offer with product mappings and conditions loaded."""
    return (
        db.query(Offer)
        .filter(Offer.id == offer_id, Offer.is_deleted == False)  # noqa: E712
        .options(
            selectinload(Offer.offer_products),
            selectinload(Offer.conditions),
        )
        .first()
    )


def get_offer_text_for_shop_product(db: Session, shop_product_id: int) -> Optional[str]:
    """Return a human-readable offer text for a shop product, if an active offer applies."""
    now = datetime.now(timezone.utc)
    offer_products = (
        db.query(OfferProduct)
        .join(Offer)
        .filter(
            OfferProduct.shop_product_id == shop_product_id,
            OfferProduct.is_excluded == False,  # noqa: E712
            Offer.status == OfferStatus.ACTIVE,
            Offer.start_date <= now,
            Offer.end_date >= now,
            Offer.is_visible == True,  # noqa: E712
        )
        .all()
    )
    if not offer_products:
        return None
    offer = offer_products[0].offer
    if offer.offer_type == OfferType.PERCENTAGE_DISCOUNT and offer.discount_percentage:
        return f"{offer.discount_percentage:.0f}% off"
    if offer.offer_type == OfferType.FLAT_DISCOUNT and offer.discount_value is not None:
        return f"₹{offer.discount_value:.0f} off"
    if offer.offer_type == OfferType.BUY_X_GET_Y and offer.buy_quantity and offer.get_quantity:
        return f"Buy {offer.buy_quantity} get {offer.get_quantity} free"
    return offer.title


# ── Freshness engine ────────────────────────────────────────────────────────
def refresh_freshness(db: Session, inventory_id: Optional[int] = None) -> int:
    """Recompute freshness status for all (or one) inventory records. Returns count updated."""
    query = db.query(Inventory)
    if inventory_id is not None:
        query = query.filter(Inventory.id == inventory_id)
    inventories = query.all()
    now = datetime.now(timezone.utc)
    count = 0
    for inv in inventories:
        last_updated = inv.last_synced_at or inv.updated_at
        status = compute_freshness(last_updated, inv.last_updated_source, now)
        if status != inv.freshness_status:
            inv.freshness_status = status
            inv.freshness_checked_at = now
            count += 1
        # Also update shop product
        sp = db.query(ShopProduct).filter(ShopProduct.id == inv.shop_product_id).first()
        if sp:
            sp.freshness_status = status
    db.flush()
    return count


# ── Customer-facing queries ─────────────────────────────────────────────────
def get_customer_inventory_for_product(
    db: Session,
    product_master_id: int,
    *,
    latitude: Optional[float] = None,
    longitude: Optional[float] = None,
    radius_km: float = 10.0,
) -> list[dict]:
    """Return customer-facing inventory details for a product across shops."""
    shop_products = (
        db.query(ShopProduct)
        .filter(
            ShopProduct.product_master_id == product_master_id,
            ShopProduct.is_visible == True,  # noqa: E712
            ShopProduct.is_active == True,  # noqa: E712
            ShopProduct.is_deleted == False,  # noqa: E712
        )
        .all()
    )

    results = []
    for sp in shop_products:
        inv = db.query(Inventory).filter(Inventory.shop_product_id == sp.id).first()
        shop = db.query(Shop).filter(Shop.id == sp.shop_id).first()
        if shop is None:
            continue

        # Determine stock status
        if inv is None:
            stock_status = CustomerStockStatus.UNKNOWN
            quantity = 0
            is_available = sp.is_available
            last_updated = sp.last_inventory_update
            freshness = sp.freshness_status
        else:
            stock_status = map_to_customer_stock_status(inv.stock_status, inv.quantity)
            quantity = inv.quantity  # noqa: F841 - kept as the single source for the stock-status mapping above
            is_available = inv.is_available and sp.is_available
            last_updated = inv.last_synced_at or inv.updated_at
            freshness = inv.freshness_status

        # Distance (simple haversine if coords provided)
        distance_km = 0.0
        if latitude is not None and longitude is not None and shop.latitude is not None and shop.longitude is not None:
            from app.services.geo_service import haversine_km
            distance_km = round(haversine_km(latitude, longitude, shop.latitude, shop.longitude), 2)
            if distance_km > radius_km:
                continue

        offer_text = get_offer_text_for_shop_product(db, sp.id)

        results.append(
            {
                "shop_product_id": sp.id,
                "shop_id": shop.id,
                "shop_name": shop.name,
                "product_id": product_master_id,
                "product_name": sp.product_master.name if sp.product_master else "",
                "product_image_url": None,
                "sku": sp.sku,
                "price": float(sp.price),
                "mrp": float(sp.mrp) if sp.mrp is not None else None,
                "is_available": is_available,
                "stock_status": stock_status.value,
                "freshness_status": freshness.value if freshness else None,
                "last_updated": last_updated,
                "distance_km": distance_km,
                "shop_rating": shop.rating,
                "offer_text": offer_text,
            }
        )

    results.sort(key=lambda r: r["distance_km"])
    return results


def get_shop_inventory(db: Session, shop_id: int) -> list[dict]:
    """Return all inventory entries for a shop with product details."""
    shop_products = (
        db.query(ShopProduct)
        .filter(ShopProduct.shop_id == shop_id, ShopProduct.is_deleted == False)  # noqa: E712
        .all()
    )
    results = []
    for sp in shop_products:
        inv = db.query(Inventory).filter(Inventory.shop_product_id == sp.id).first()
        product_name = sp.product_master.name if sp.product_master else ""
        results.append(
            {
                "id": inv.id if inv else None,
                "shop_product_id": sp.id,
                "product_id": sp.product_master_id,
                "product_name": product_name,
                "sku": sp.sku,
                "price": float(sp.price),
                "mrp": float(sp.mrp) if sp.mrp is not None else None,
                "quantity": inv.quantity if inv else 0,
                "is_available": inv.is_available if inv else sp.is_available,
                "stock_status": inv.stock_status.value if inv and hasattr(inv.stock_status, "value") else str(sp.stock_status),
                "freshness_status": (inv.freshness_status.value if inv and inv.freshness_status else None),
                "last_updated": inv.last_synced_at or inv.updated_at if inv else sp.last_inventory_update,
                "source": inv.last_updated_source.value if inv and hasattr(inv.last_updated_source, "value") else str(sp.source),
            }
        )
    return results