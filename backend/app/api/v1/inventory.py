"""Inventory surfaces, including the shop-scoped drill-down."""

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.pagination import Pagination, pagination
from app.core.responses import ok, paged
from app.core.serializers import serialise_inventory, to_dict
from app.core.security import get_current_admin
from app.models import AdminUser, InventoryHistory, Shop, ShopInventory

router = APIRouter(prefix="/admin/inventory", tags=["inventory"])

# A record untouched for this long is reported as stale. One constant so the
# summary and the stale list cannot drift apart.
STALE_AFTER_HOURS = 72


@router.get("/summary")
def inventory_summary(db: Session = Depends(get_db), _: AdminUser = Depends(get_current_admin)):
    cutoff = datetime.now(timezone.utc) - timedelta(hours=STALE_AFTER_HOURS)
    total = db.scalar(select(func.count()).select_from(ShopInventory)) or 0
    stale = (
        db.scalar(
            select(func.count())
            .select_from(ShopInventory)
            .where(ShopInventory.last_updated < cutoff)
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
            "stale_count": stale,
            "missing_prices": missing_prices,
            "out_of_stock": out_of_stock,
            "stale_after_hours": STALE_AFTER_HOURS,
        }
    )


@router.get("/stale")
def stale_inventory(
    page: Pagination = Depends(pagination),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    cutoff = datetime.now(timezone.utc) - timedelta(hours=STALE_AFTER_HOURS)
    stmt = select(ShopInventory).where(ShopInventory.last_updated < cutoff)
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
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    stmt = select(ShopInventory).where(ShopInventory.price.is_(None))
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
