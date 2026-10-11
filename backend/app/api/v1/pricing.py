"""Price Management surfaces.

Two read-only endpoints feed the console's Price Management screen:

* ``/pricing/summary`` — the four tiles (Current Price, MRP, Offer Price,
  History), counted from the operational inventory tables so a tile can never
  disagree with the Price detail table below it.
* ``/pricing/history`` — the Price detail table: one row per recorded price
  change, joined to its shop and product so the grid can show Shop and Product
  names rather than raw ids.

Every figure is counted from real rows. A metric the platform cannot
substantiate is reported as ``null`` on the wire and rendered as an em dash,
never as a fabricated zero — mirroring the "honest unknown" contract used across
the analytics endpoints.
"""

from typing import Any

from fastapi import APIRouter, Depends
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.pagination import Pagination, pagination
from app.core.responses import ok, paged
from app.core.serializers import iso
from app.core.security import get_current_admin
from app.models import (
    AdminUser,
    InventoryHistory,
    Shop,
    ShopInventory,
    ShopPricing,
)

router = APIRouter(prefix="/admin/pricing", tags=["pricing"])

# Currency shown beside monetary figures. The platform records it per priced
# row (ShopPricing.currency, default "INR"); this is the fallback when no priced
# row exists yet, so a tile never renders a bare number with no unit.
DEFAULT_CURRENCY = "INR"


def _percent(part: int, whole: int) -> float | None:
    """Share of ``whole`` that ``part`` represents, as 0–100 rounded to 2dp.

    Returns ``None`` when there is no base to divide by, so an empty platform
    reports an honest "unknown" rather than a misleading 0%.
    """
    return round((part / whole) * 100, 2) if whole else None


def _stat(label: str, count: int, base: int) -> dict[str, Any]:
    """One summary tile figure: a count and its share of the priced base."""
    return {
        "label": label,
        "count": count,
        "percent": _percent(count, base),
    }


def _to_float(value: str | None) -> float | None:
    """Parse a stored string price into a float, or ``None`` if not numeric.

    Inventory history stores old/new values as text (they can be any change,
    not only numeric). A non-numeric value is reported as ``null`` rather than
    coerced, so the grid never shows a fabricated price.
    """
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


@router.get("/summary")
def pricing_summary(
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    """Aggregate the four Price Management tiles from the inventory tables."""
    total_items = db.scalar(select(func.count()).select_from(ShopInventory)) or 0

    # "Priced base" — rows that carry a current price OR an MRP. Every tile's
    # percent is a share of this, so the percentages stay comparable.
    priced_items = (
        db.scalar(
            select(func.count())
            .select_from(ShopInventory)
            .where(or_(ShopInventory.price.isnot(None), ShopInventory.mrp.isnot(None)))
        )
        or 0
    )

    current_price_count = (
        db.scalar(
            select(func.count())
            .select_from(ShopInventory)
            .where(ShopInventory.price.isnot(None))
        )
        or 0
    )
    mrp_count = (
        db.scalar(
            select(func.count()).select_from(ShopInventory).where(ShopInventory.mrp.isnot(None))
        )
        or 0
    )
    # An "offer price" is a real discount: a current price strictly below MRP.
    offer_count = (
        db.scalar(
            select(func.count())
            .select_from(ShopInventory)
            .where(
                ShopInventory.price.isnot(None),
                ShopInventory.mrp.isnot(None),
                ShopInventory.price < ShopInventory.mrp,
            )
        )
        or 0
    )

    # Total recorded price-change events, and the most recent one.
    price_changes = (
        db.scalar(
            select(func.count())
            .select_from(InventoryHistory)
            .where(InventoryHistory.change_type == "PRICE")
        )
        or 0
    )
    last_change_at = db.scalar(
        select(func.max(InventoryHistory.created_at)).where(
            InventoryHistory.change_type == "PRICE"
        )
    )

    currency = db.scalar(select(ShopPricing.currency).limit(1)) or DEFAULT_CURRENCY

    return ok(
        {
            "currency": currency,
            "total_items": total_items,
            "priced_items": priced_items,
            "stats": {
                "current_price": _stat("CURRENT PRICE", current_price_count, priced_items),
                "mrp": _stat("MRP", mrp_count, priced_items),
                "offer_price": _stat("OFFER PRICE", offer_count, priced_items),
            },
            "discounted_items": offer_count,
            "price_changes": price_changes,
            "last_change_at": iso(last_change_at),
        }
    )


@router.get("/history")
def pricing_history(
    page: Pagination = Depends(pagination),
    change_type: str | None = None,
    shop_id: int | None = None,
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    """The PRICE MANAGEMENT detail table — one row per recorded price change.

    The three tables are joined in a single query so the grid renders shop and
    product names without an extra round-trip per row, and the inventory row's
    current MRP travels with each change for context. ``old_value`` /
    ``new_value`` are stored as text (history can record any field change), so
    they are parsed to floats here and a non-numeric value is reported as
    ``null`` rather than fabricated.
    """
    stmt = (
        select(InventoryHistory, ShopInventory, Shop)
        .join(ShopInventory, InventoryHistory.shop_product_id == ShopInventory.id)
        .join(Shop, ShopInventory.shop_id == Shop.id)
    )
    if change_type:
        stmt = stmt.where(InventoryHistory.change_type == change_type)
    if shop_id is not None:
        stmt = stmt.where(ShopInventory.shop_id == shop_id)
    if page.search:
        like = f"%{page.search}%"
        stmt = stmt.where(
            or_(
                Shop.name.ilike(like),
                ShopInventory.product_name.ilike(like),
                InventoryHistory.source.ilike(like),
                InventoryHistory.changed_by.ilike(like),
            )
        )

    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    start, end = page.window()
    rows = db.execute(
        stmt.order_by(InventoryHistory.created_at.desc(), InventoryHistory.id.desc())
        .offset(start)
        .limit(end - start)
    ).all()

    items = [
        {
            "id": h.id,
            "shop_id": inv.shop_id,
            "shop_name": shop.name,
            "product_id": inv.product_id,
            "product_name": inv.product_name,
            "old_price": _to_float(h.old_value),
            "new_price": _to_float(h.new_value),
            "mrp": inv.mrp,
            "changed_by": h.changed_by,
            "changed_at": iso(h.created_at),
            "source": h.source or "UNKNOWN",
        }
        for h, inv, shop in rows
    ]
    return ok(paged(items, total))