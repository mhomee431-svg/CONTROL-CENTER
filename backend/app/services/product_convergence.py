"""The one product-entry funnel every route converges on.

The spec draws four flows — manual, barcode, Excel/CSV, POS — and closes with
"All four methods must converge on the same backend domain model." Before this
module existed, each route hand-rolled the same four steps:

    resolve-or-create master -> attach to shop -> set price -> set inventory

Six copies of `ShopProduct(...)` existed across the codebase, and they did not
agree. A divergence audit of the four entry routes found:

    route     writes source   freshness   InventoryMovement
    manual    yes             no*         no*
    barcode   yes             yes         yes
    excel     yes             yes         yes
    POS       yes             NO          NO

(*manual sets some of these elsewhere in the file, but not on the create path.)

So the same product entered by hand and by POS ended up with different
inventory rows — POS-sourced stock carried no movement audit trail and no
freshness stamp. That is exactly the "same domain model" the spec forbids, and
it is invisible per-route: each route looked correct on its own.

Everything shared now lives here so the four routes cannot drift again.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from sqlalchemy.orm import Session

from app.models.product import (
    Inventory,
    InventoryMovement,
    InventorySource,
    ProductMaster,
    ProductVariant,
    ShopProduct,
    ShopProductStatus,
)

__all__ = [
    "attach_product_to_shop",
    "attach_product_to_shop_reporting_creation",
    "set_inventory",
    "set_price",
]


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def attach_product_to_shop(
    db: Session,
    *,
    shop_id: int,
    master: ProductMaster,
    variant: ProductVariant | None = None,
    sku: str | None = None,
    source: InventorySource = InventorySource.MANUAL,
    price: float | None = None,
    mrp: float | None = None,
    publish: bool = True,
    is_available: bool = True,
    stock_status: Any = None,
) -> ShopProduct:
    """Create the shop's listing for *master*, or return the one it already has.

    The lookup key is (shop, master, variant) — the rule all four routes used
    independently. It lives here because this is the single place a duplicate
    listing can be born, and each route previously had its own copy of the
    check with its own idea of what to filter on.

    Callers that need to distinguish "created" from "already there" (POS reports
    this in its per-item result) should use
    :func:`attach_product_to_shop_reporting_creation`, which shares this body
    rather than repeating the lookup.
    """
    listing, _created = _attach(
        db,
        shop_id=shop_id,
        master=master,
        variant=variant,
        sku=sku,
        source=source,
        price=price,
        mrp=mrp,
        publish=publish,
        is_available=is_available,
        stock_status=stock_status,
    )
    return listing


def attach_product_to_shop_reporting_creation(
    db: Session,
    *,
    shop_id: int,
    master: ProductMaster,
    variant: ProductVariant | None = None,
    sku: str | None = None,
    source: InventorySource = InventorySource.MANUAL,
    price: float | None = None,
    mrp: float | None = None,
    publish: bool = True,
    is_available: bool = True,
    stock_status: Any = None,
) -> tuple[ShopProduct, bool]:
    """Same as :func:`attach_product_to_shop`, plus whether it was created.

    Returns ``(listing, created)``. The POS route surfaces ``CREATED`` /
    ``UPDATED`` per synced item, so it needs the distinction the plain call
    throws away.
    """
    return _attach(
        db,
        shop_id=shop_id,
        master=master,
        variant=variant,
        sku=sku,
        source=source,
        price=price,
        mrp=mrp,
        publish=publish,
        is_available=is_available,
        stock_status=stock_status,
    )


def _attach(
    db: Session,
    *,
    shop_id: int,
    master: ProductMaster,
    variant: ProductVariant | None,
    sku: str | None,
    source: InventorySource,
    price: float | None,
    mrp: float | None,
    publish: bool,
    is_available: bool,
    stock_status: Any,
) -> tuple[ShopProduct, bool]:
    existing = (
        db.query(ShopProduct)
        .filter(
            ShopProduct.shop_id == shop_id,
            ShopProduct.product_master_id == master.id,
            ShopProduct.variant_id == (variant.id if variant else None),
            ShopProduct.is_deleted == False,
        )
        .first()
    )
    if existing is not None:
        return existing, False

    now = _utcnow()
    # `shop_products.price` is NOT NULL, so a listing cannot be created without
    # one. A feed that omits the price still needs a listing to hang stock on;
    # 0.0 is the same placeholder the POS path has always used, and the real
    # price is applied by `set_price` once the shop or POS supplies one.
    sp = ShopProduct(
        shop_id=shop_id,
        product_master_id=master.id,
        variant_id=variant.id if variant else None,
        sku=sku,
        status=ShopProductStatus.ACTIVE if publish else ShopProductStatus.INACTIVE,
        price=0.0 if price is None else price,
        mrp=mrp,
        is_active=publish,
        is_available=is_available,
        stock_status=stock_status,
        source=source,
        last_inventory_update=now,
        last_price_update=now,
    )
    # Link eagerly so serialization and the search indexer see the master name
    # without a lazy load.
    sp.product_master = master
    if variant is not None:
        sp.variant = variant
    db.add(sp)
    db.flush()
    return sp, True


def set_price(
    db: Session,
    shop_product: ShopProduct,
    *,
    price: float | None = None,
    mrp: float | None = None,
    now: datetime | None = None,
) -> None:
    """Apply a price change to the shop listing and stamp it."""
    if price is not None:
        shop_product.price = price
    if mrp is not None:
        shop_product.mrp = mrp
    shop_product.last_price_update = now or _utcnow()
    # Deliberately no `db.add`: the listing is always persistent here (it was
    # just created by `attach_product_to_shop` or read back from a query), and
    # re-adding a tracked row is a no-op that only makes call-site double-counts
    # look like a second product.


def set_inventory(
    db: Session,
    shop_product: ShopProduct,
    *,
    quantity: int,
    low_stock_threshold: int = 5,
    source: InventorySource = InventorySource.MANUAL,
    is_available: bool | None = None,
    stock_status: Any = None,
    user_id: int | None = None,
    reference_type: str | None = None,
    reference_id: int | None = None,
    notes: str | None = None,
) -> Inventory:
    """Set absolute stock for a listing, with the full provenance every route owes.

    `quantity` is absolute, never a delta — re-importing the same sheet must land
    on the same number rather than double it.

    The provenance fields and the `InventoryMovement` audit row are written for
    every source. POS used to set only `source`, leaving synced stock with no
    movement record and no freshness stamp while barcode and Excel wrote both.
    """
    from app.services.inventory_service import compute_freshness

    now = _utcnow()
    quantity = max(int(quantity), 0)
    if is_available is None:
        is_available = quantity > 0

    inv = (
        db.query(Inventory)
        .filter(Inventory.shop_product_id == shop_product.id)
        .first()
    )

    if inv is None:
        inv = Inventory(
            shop_product_id=shop_product.id,
            quantity=quantity,
            reserved_quantity=0,
            available_quantity=quantity,
            is_available=is_available,
            stock_status=stock_status,
            low_stock_threshold=low_stock_threshold,
        )
        db.add(inv)
        db.flush()
        quantity_before = 0
    else:
        quantity_before = int(inv.quantity)
        inv.quantity = quantity
        inv.available_quantity = quantity
        inv.is_available = is_available
        if stock_status is not None:
            inv.stock_status = stock_status
        inv.low_stock_threshold = low_stock_threshold
        # `inv` came from the query above, so it is already tracked.

    # Provenance — identical for every source, POS included.
    inv.last_updated_by = user_id
    inv.last_updated_source = source
    inv.last_synced_at = now
    inv.freshness_status = compute_freshness(now, source)
    inv.freshness_checked_at = now

    # Audit trail — every stock change leaves a movement, whatever the source.
    change = quantity - quantity_before
    if change != 0 or quantity_before == 0:
        db.add(
            InventoryMovement(
                inventory_id=inv.id,
                quantity_change=change,
                quantity_before=quantity_before,
                quantity_after=quantity,
                movement_type="INITIAL" if quantity_before == 0 else "ADJUSTMENT",
                source=source,
                reference_type=reference_type,
                reference_id=reference_id,
                notes=notes,
                created_by=user_id,
            )
        )

    shop_product.last_inventory_update = now
    shop_product.source = source
    db.flush()
    return inv