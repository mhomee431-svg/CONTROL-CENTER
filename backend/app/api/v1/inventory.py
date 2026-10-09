"""Inventory surfaces, including the shop-scoped drill-down."""

from datetime import datetime, timedelta, timezone
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.inventory_policy import (
    FRESH_WITHIN_HOURS,
    LOW_STOCK_THRESHOLD,
    STALE_AFTER_HOURS,
)
from app.core.pagination import Pagination, pagination
from app.core.responses import ok, paged
from app.core.serializers import serialise_inventory, to_dict
from app.core.security import get_current_admin
from app.models import AdminUser, InventoryHistory, Shop, ShopInventory

router = APIRouter(prefix="/admin/inventory", tags=["inventory"])

# The eight control-center views; "all" is the unfiltered platform list.
InventorySection = Literal[
    "all",
    "in-stock",
    "low-stock",
    "out-of-stock",
    "unknown",
    "stale",
    "recently-updated",
    "failed",
]


@router.get("/summary")
def inventory_summary(db: Session = Depends(get_db), _: AdminUser = Depends(get_current_admin)):
    """Freshness buckets for the control-center dashboard.

    Every record lands in exactly one bucket — FRESH (<24h), RECENT (24-72h),
    STALE (>72h) or UNKNOWN (never updated) — so the four percentages always
    sum to 100% of `total_records`.
    """
    now = datetime.now(timezone.utc)
    cutoff = now - timedelta(hours=STALE_AFTER_HOURS)
    fresh_cutoff = now - timedelta(hours=FRESH_WITHIN_HOURS)
    total = db.scalar(select(func.count()).select_from(ShopInventory)) or 0
    stale = (
        db.scalar(
            select(func.count())
            .select_from(ShopInventory)
            .where(ShopInventory.last_updated < cutoff)
        )
        or 0
    )
    fresh = (
        db.scalar(
            select(func.count())
            .select_from(ShopInventory)
            .where(ShopInventory.last_updated >= fresh_cutoff)
        )
        or 0
    )
    recent = (
        db.scalar(
            select(func.count())
            .select_from(ShopInventory)
            .where(ShopInventory.last_updated >= cutoff, ShopInventory.last_updated < fresh_cutoff)
        )
        or 0
    )
    unknown = (
        db.scalar(
            select(func.count())
            .select_from(ShopInventory)
            .where(ShopInventory.last_updated.is_(None))
        )
        or 0
    )
    missing_prices = (
        db.scalar(
            select(func.count())
            .select_from(ShopInventory)
            .where(ShopInventory.price.is_(None))
        )
        or 0
    )
    out_of_stock = (
        db.scalar(
            select(func.count())
            .select_from(ShopInventory)
            .where(ShopInventory.quantity <= 0)
        )
        or 0
    )
    return ok(
        {
            "total_records": total,
            "fresh_count": fresh,
            "recent_count": recent,
            "stale_count": stale,
            "unknown_count": unknown,
            "missing_prices": missing_prices,
            "out_of_stock": out_of_stock,
            "stale_after_hours": STALE_AFTER_HOURS,
            "fresh_after_hours": FRESH_WITHIN_HOURS,
            "low_stock_threshold": LOW_STOCK_THRESHOLD,
        }
    )


@router.get("")
def list_inventory(
    page: Pagination = Depends(pagination),
    section: InventorySection = "all",
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    """The Inventory Control Center list — one route, eight section views.

    Sections partition the platform's stock rows by the question an operator
    is asking (stock level, freshness, sync health) and share one ordering:
    `last_updated` ascending, NULLs first (SQLite), so never-updated and
    stalest records lead every view. Rows carry `stale_hours` exactly like the
    dedicated /stale route so both views tell the same story.
    """
    now = datetime.now(timezone.utc)
    stale_cutoff = now - timedelta(hours=STALE_AFTER_HOURS)
    stmt = select(ShopInventory)
    if section == "in-stock":
        stmt = stmt.where(ShopInventory.quantity > LOW_STOCK_THRESHOLD)
    elif section == "low-stock":
        stmt = stmt.where(ShopInventory.quantity > 0, ShopInventory.quantity <= LOW_STOCK_THRESHOLD)
    elif section == "out-of-stock":
        stmt = stmt.where(ShopInventory.quantity <= 0)
    elif section == "unknown":
        stmt = stmt.where(ShopInventory.last_updated.is_(None))
    elif section == "stale":
        stmt = stmt.where(ShopInventory.last_updated < stale_cutoff)
    elif section == "recently-updated":
        stmt = stmt.where(ShopInventory.last_updated >= stale_cutoff)
    elif section == "failed":
        stmt = stmt.where(ShopInventory.sync_status == "FAILED")
    if page.search:
        needle = f"%{page.search}%"
        stmt = stmt.join(ShopInventory.shop).where(
            or_(ShopInventory.product_name.ilike(needle), Shop.name.ilike(needle))
        )
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    start, end = page.window()
    rows = db.scalars(
        stmt.order_by(ShopInventory.last_updated.asc(), ShopInventory.id.asc())
        .offset(start)
        .limit(end - start)
    ).all()
    items = []
    for r in rows:
        row = serialise_inventory(r)
        if r.last_updated is not None:
            ref = r.last_updated if r.last_updated.tzinfo else r.last_updated.replace(tzinfo=timezone.utc)
            row["stale_hours"] = round((now - ref).total_seconds() / 3600, 1)
        items.append(row)
    return ok(paged(items, total))


@router.get("/stale")
def stale_inventory(
    page: Pagination = Depends(pagination),
    product_id: int | None = Query(None),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    cutoff = datetime.now(timezone.utc) - timedelta(hours=STALE_AFTER_HOURS)
    stmt = select(ShopInventory).where(ShopInventory.last_updated < cutoff)
    # The product drill-down's inventory tab reads this endpoint scoped to one
    # product. Ignoring the filter would show every stale record on the
    # platform inside a single product's tab — plausible-looking, entirely
    # wrong rows.
    if product_id is not None:
        stmt = stmt.where(ShopInventory.product_id == product_id)
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    start, end = page.window()
    rows = db.scalars(stmt.order_by(ShopInventory.last_updated).offset(start).limit(end - start)).all()
    now = datetime.now(timezone.utc)
    items = []
    for r in rows:
        row = serialise_inventory(r)
        if r.last_updated is not None:
            ref = r.last_updated if r.last_updated.tzinfo else r.last_updated.replace(tzinfo=timezone.utc)
            row["stale_hours"] = round((now - ref).total_seconds() / 3600, 1)
        items.append(row)
    return ok(paged(items, total))


@router.get("/missing-prices")
def missing_prices(
    page: Pagination = Depends(pagination),
    product_id: int | None = Query(None),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    stmt = select(ShopInventory).where(ShopInventory.price.is_(None))
    # Same product-scoping as /stale: the product detail's Prices tab reads
    # this endpoint for one product, and an unfiltered response would list
    # every unpriced record on the platform.
    if product_id is not None:
        stmt = stmt.where(ShopInventory.product_id == product_id)
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    start, end = page.window()
    rows = db.scalars(stmt.order_by(ShopInventory.id).offset(start).limit(end - start)).all()
    return ok(paged([serialise_inventory(r) for r in rows], total))


@router.get("/anomalies")
def anomalies(
    page: Pagination = Depends(pagination),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    """Records whose price is above MRP, or zero, with a negative quantity."""
    stmt = select(ShopInventory).where(
        or_(
            ShopInventory.quantity < 0,
            ShopInventory.price < 0,
            (ShopInventory.price.isnot(None)) & (ShopInventory.mrp.isnot(None)) & (ShopInventory.price > ShopInventory.mrp),
        )
    )
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    start, end = page.window()
    rows = db.scalars(stmt.order_by(ShopInventory.id).offset(start).limit(end - start)).all()
    return ok(paged([serialise_inventory(r) for r in rows], total))


@router.get("/sync-failures")
def sync_failures(
    page: Pagination = Depends(pagination),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    stmt = select(ShopInventory).where(ShopInventory.sync_status == "FAILED")
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    start, end = page.window()
    rows = db.scalars(stmt.order_by(ShopInventory.id).offset(start).limit(end - start)).all()
    items = []
    for r in rows:
        row = serialise_inventory(r)
        row["sync_error"] = r.sync_error
        row["sync_source"] = r.sync_source
        items.append(row)
    return ok(paged(items, total))


@router.get("/shop/{shop_id}")
def shop_inventory(
    shop_id: int,
    page: Pagination = Depends(pagination),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    """The Inventory tab of the business drill-down."""
    if db.get(Shop, shop_id) is None:
        raise HTTPException(status_code=404, detail=f"Business {shop_id} not found")
    stmt = select(ShopInventory).where(ShopInventory.shop_id == shop_id)
    if page.search:
        stmt = stmt.where(ShopInventory.product_name.ilike(f"%{page.search}%"))
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    start, end = page.window()
    rows = db.scalars(stmt.order_by(ShopInventory.id).offset(start).limit(end - start)).all()
    return ok(paged([serialise_inventory(r) for r in rows], total))


@router.get("/records/{shop_product_id}")
def inventory_record(
    shop_product_id: int, db: Session = Depends(get_db), _: AdminUser = Depends(get_current_admin)
):
    row = db.get(ShopInventory, shop_product_id)
    if row is None:
        raise HTTPException(status_code=404, detail=f"Inventory record {shop_product_id} not found")
    payload = serialise_inventory(row)
    payload.update(
        {
            "owner_id": row.shop.owner_id if row.shop else None,
            "owner_name": row.shop.owner.name if row.shop and row.shop.owner else None,
            "owner_phone": row.shop.owner.phone if row.shop and row.shop.owner else None,
            "mrp": row.mrp,
            "availability": row.availability,
            "sync_source": row.sync_source,
            "sync_status": row.sync_status,
            "sync_error": row.sync_error,
            "created_at": row.created_at.isoformat() if row.created_at else None,
            "updated_at": row.updated_at.isoformat() if row.updated_at else None,
        }
    )
    return ok(payload)


@router.get("/records/{shop_product_id}/history")
def inventory_record_history(
    shop_product_id: int,
    page: Pagination = Depends(pagination),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    stmt = select(InventoryHistory).where(InventoryHistory.shop_product_id == shop_product_id)
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    start, end = page.window()
    rows = db.scalars(
        stmt.order_by(InventoryHistory.created_at.desc()).offset(start).limit(end - start)
    ).all()
    fields = [
        "id", "shop_product_id", "change_type", "old_value",
        "new_value", "source", "changed_by", "created_at",
    ]
    return ok(paged([to_dict(r, fields) for r in rows], total))
