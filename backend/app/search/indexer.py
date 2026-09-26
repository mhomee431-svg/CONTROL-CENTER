"""Search indexer — builds and syncs the denormalized search_indexes table.

PostgreSQL remains the source of truth. This module proactively propagates
changes from product/shop/inventory tables into the search layer, either via
full rebuild or incremental events.
"""

from datetime import datetime, timezone
from typing import Optional

from sqlalchemy.orm import Session, selectinload

from app.core.logging import get_logger
from app.models.product import (
    ProductMaster,
    ProductStatus,
    ShopProduct,
)
from app.models.search import (
    SearchIndex,
    SearchIndexEntityType,
    SearchIndexSync,
    SearchIndexSyncStatus,
)
from app.models.shop import Shop
from app.search.normalizer import build_discovery_text, build_search_text

logger = get_logger("app.search.indexer")


# ── Helpers ────────────────────────────────────────────────────────────────
def _extract_coords_from_location(location) -> tuple[float | None, float | None]:
    """Parse (longitude, latitude) from a PostGIS Geography POINT field."""
    try:
        raw = str(location)
        if raw.startswith("POINT"):
            inner = raw[6:-1].strip()
            parts = inner.split()
            if len(parts) == 2:
                return float(parts[0]), float(parts[1])
        return None, None
    except (ValueError, TypeError, IndexError):
        return None, None


def _customer_stock(value: str):
    """Map a stock status enum value to customer-facing string."""
    mapping = {
        "IN_STOCK": "IN_STOCK",
        "LOW_STOCK": "LIMITED_STOCK",
        "LIMITED_STOCK": "LIMITED_STOCK",
        "OUT_OF_STOCK": "OUT_OF_STOCK",
        "PRE_ORDER": "UNKNOWN",
        "BACK_ORDER": "UNKNOWN",
        "UNKNOWN": "UNKNOWN",
    }
    return mapping.get(value, "UNKNOWN")


# ── Build index entry from ORM objects ─────────────────────────────────────
def build_shop_product_index(
    db: Session,
    sp: ShopProduct,
    *,
    product: Optional[ProductMaster] = None,
    shop: Optional[Shop] = None,
) -> dict:
    """Build the denormalized index fields for a shop-product pair."""
    if product is None:
        product = sp.product_master
    if product is None:
        raise ValueError(f"ShopProduct {sp.id} has no product master")

    if shop is None:
        shop = sp.shop
    if shop is None:
        raise ValueError(f"ShopProduct {sp.id} has no shop")

    # Inventory
    inv = sp.inventory
    quantity = inv.quantity if inv else 0
    is_available = bool((inv and inv.is_available) and sp.is_available and sp.is_visible)
    is_in_stock = bool(inv and inv.quantity > 0 and inv.is_available)

    # Freshness
    freshness_status = None
    if inv and inv.freshness_status:
        freshness_status = inv.freshness_status.value
    elif sp.freshness_status:
        freshness_status = sp.freshness_status.value

    # Keep every active identifier in the canonical search document. The
    # singular ``barcode`` remains the preferred scanner target for the fast
    # dedicated barcode endpoint, while general product search can match any
    # supported EAN/UPC/other identifier.
    identifier_values = [
        ident.identifier_value.strip()
        for ident in product.identifiers
        if ident.is_active and ident.identifier_value and ident.identifier_value.strip()
    ]
    identifier_values.extend(
        relationship.barcode.strip()
        for relationship in product.barcode_relationships
        if relationship.is_active and relationship.barcode and relationship.barcode.strip()
    )
    # Preserve stable order while avoiding duplicate normalized source values.
    identifier_values = list(dict.fromkeys(identifier_values))

    # Barcode (preferred scanner target: SKU, first active product identifier,
    # then the first active barcode relationship).
    barcode = sp.sku or next(iter(identifier_values), None)

    # Shop geo
    longitude, latitude = _extract_coords_from_location(shop.location)

    # Search text
    category_name = product.category.name if product.category else None
    subcategory_name = product.subcategory.name if product.subcategory else None
    brand_name = product.brand.name if product.brand else None
    variant_name = sp.variant.name if sp.variant else None

    search_text = build_search_text(
        product.name,
        brand=brand_name,
        category=category_name,
        subcategory=subcategory_name,
        variant=variant_name,
        sku=sp.sku,
        barcode=barcode,
        description=product.short_description or product.description,
    )
    discovery_text = build_discovery_text(
        product.name,
        brand=brand_name,
        category=category_name,
        subcategory=subcategory_name,
        variant=variant_name,
        sku=sp.sku,
        identifiers=identifier_values,
    )

    last_inventory_update = None
    if inv and inv.last_synced_at:
        last_inventory_update = inv.last_synced_at
    elif inv and inv.updated_at:
        last_inventory_update = inv.updated_at
    elif sp.last_inventory_update:
        last_inventory_update = sp.last_inventory_update

    return {
        "entity_type": SearchIndexEntityType.SHOP_PRODUCT,
        "entity_id": sp.id,
        "product_id": product.id,
        "shop_product_id": sp.id,
        "shop_id": shop.id,
        "brand_id": product.brand_id,
        "category_id": product.category_id,
        "variant_id": sp.variant_id,
        "product_name": product.name,
        "brand_name": brand_name,
        "category_name": category_name,
        "subcategory_name": subcategory_name,
        "variant_name": variant_name,
        "search_text": search_text,
        "discovery_text": discovery_text,
        "search_vector": search_text,
        "barcode": barcode,
        "sku": sp.sku,
        "is_product_searchable": bool(product.is_searchable and product.is_active and product.status == ProductStatus.APPROVED),
        "is_shop_visible": bool(shop.is_accepting_orders),
        "price": float(sp.price) if sp.price is not None else None,
        "mrp": float(sp.mrp) if sp.mrp is not None else None,
        "is_available": is_available,
        "stock_status": _customer_stock(inv.stock_status.value if inv and hasattr(inv.stock_status, "value") else "UNKNOWN"),
        "freshness_status": freshness_status,
        "last_inventory_update": last_inventory_update,
        "shop_name": shop.name,
        "shop_rating": shop.rating,
        "shop_review_count": shop.review_count,
        "is_shop_accepting_orders": shop.is_accepting_orders,
        "location": shop.location,
        "latitude": latitude,
        "longitude": longitude,
        "popularity_score": _popularity(db, product.id),
        "is_synced": True,
        "last_synced_at": datetime.now(timezone.utc),
    }


def _popularity(db: Session, product_id: int) -> float:
    """Popularity score helper (0–1)."""
    from app.models.analytics import ProductClick, ProductView
    try:
        clicks = db.query(ProductClick).filter(ProductClick.product_id == product_id).count()
        views = db.query(ProductView).filter(ProductView.product_id == product_id).count()
        total = clicks + views
        if total <= 0:
            return 0.0
        return round(min(1.0, total / 200.0), 4)
    except Exception:
        return 0.0


# ── CRUD operations ────────────────────────────────────────────────────────
def upsert_shop_product(db: Session, shop_product_id: int) -> Optional[SearchIndex]:
    """Insert or update a single SHOP_PRODUCT index entry."""
    sp = (
        db.query(ShopProduct)
        .options(
            selectinload(ShopProduct.product_master).selectinload(ProductMaster.brand),
            selectinload(ShopProduct.product_master).selectinload(ProductMaster.category),
            selectinload(ShopProduct.product_master).selectinload(ProductMaster.subcategory),
            selectinload(ShopProduct.product_master).selectinload(ProductMaster.identifiers),
            selectinload(ShopProduct.product_master).selectinload(ProductMaster.barcode_relationships),
            selectinload(ShopProduct.shop),
            selectinload(ShopProduct.variant),
            selectinload(ShopProduct.inventory),
        )
        .filter(ShopProduct.id == shop_product_id)
        .first()
    )
    if sp is None:
        return None

    try:
        payload = build_shop_product_index(db, sp)
    except ValueError as exc:
        logger.warning("Skipping index for shop_product %s: %s", shop_product_id, exc)
        return None

    existing = (
        db.query(SearchIndex)
        .filter(
            SearchIndex.entity_type == SearchIndexEntityType.SHOP_PRODUCT,
            SearchIndex.entity_id == shop_product_id,
        )
        .first()
    )
    if existing:
        for k, v in payload.items():
            setattr(existing, k, v)
        db.flush()
        return existing

    entry = SearchIndex(**payload)
    db.add(entry)
    db.flush()
    return entry


def remove_shop_product_index(db: Session, shop_product_id: int) -> bool:
    """Remove index entries for a shop product (e.g., soft-deleted / discontinued)."""
    deleted = (
        db.query(SearchIndex)
        .filter(
            SearchIndex.entity_type == SearchIndexEntityType.SHOP_PRODUCT,
            SearchIndex.entity_id == shop_product_id,
        )
        .delete(synchronize_session=False)
    )
    return deleted > 0


def upsert_product_index(db: Session, product_id: int) -> list[SearchIndex]:
    """Index (or re-index) a product across all its shop products."""
    entries = []
    sp_ids = db.query(ShopProduct.id).filter(ShopProduct.product_master_id == product_id).all()
    for (sid,) in sp_ids:
        entry = upsert_shop_product(db, sid)
        if entry:
            entries.append(entry)
    return entries


def upsert_shop_index(db: Session, shop_id: int) -> list[SearchIndex]:
    """Index (or re-index) all products of a shop."""
    entries = []
    sp_ids = db.query(ShopProduct.id).filter(ShopProduct.shop_id == shop_id).all()
    for (sid,) in sp_ids:
        entry = upsert_shop_product(db, sid)
        if entry:
            entries.append(entry)
    return entries


def remove_product_indexes(db: Session, product_id: int) -> int:
    """Remove index entries for a product (soft-deleted / inactive)."""
    return (
        db.query(SearchIndex)
        .filter(SearchIndex.entity_type == SearchIndexEntityType.SHOP_PRODUCT, SearchIndex.product_id == product_id)
        .delete(synchronize_session=False)
    )


def remove_shop_indexes(db: Session, shop_id: int) -> int:
    """Remove index entries for shops that are no longer active/visible."""
    return (
        db.query(SearchIndex)
        .filter(SearchIndex.shop_id == shop_id)
        .delete(synchronize_session=False)
    )


# ── Full / incremental rebuild ─────────────────────────────────────────────
def full_rebuild(db: Session) -> SearchIndexSync:
    """
    Rebuild the entire search index.
    Removes stale entries and re-indexes all visible shop products.
    """
    run = SearchIndexSync(
        sync_type="FULL",
        status=SearchIndexSyncStatus.RUNNING,
    )
    db.add(run)
    db.flush()

    try:
        # Clear existing index inside a transaction-safe way
        db.query(SearchIndex).delete(synchronize_session=False)
        db.flush()

        sps = (
            db.query(ShopProduct)
            .options(
                selectinload(ShopProduct.product_master).selectinload(ProductMaster.brand),
                selectinload(ShopProduct.product_master).selectinload(ProductMaster.category),
                selectinload(ShopProduct.product_master).selectinload(ProductMaster.subcategory),
                selectinload(ShopProduct.product_master).selectinload(ProductMaster.identifiers),
                selectinload(ShopProduct.product_master).selectinload(ProductMaster.barcode_relationships),
                selectinload(ShopProduct.shop),
                selectinload(ShopProduct.variant),
                selectinload(ShopProduct.inventory),
            )
            .filter(ShopProduct.is_deleted == False)  # noqa: E712
            .all()
        )

        created = 0
        for sp in sps:
            try:
                payload = build_shop_product_index(db, sp)
                db.add(SearchIndex(**payload))
                created += 1
            except (ValueError, Exception) as exc:  # noqa: BLE001
                run.error_count += 1
                logger.warning("Index build error for shop_product %s: %s", sp.id, exc)
            run.total_processed += 1

            # Flush in batches to avoid large transaction
            if created % 500 == 0:
                db.flush()

        db.flush()
        run.status = SearchIndexSyncStatus.COMPLETED
        run.total_created = created
        run.completed_at = datetime.now(timezone.utc)
        db.flush()
        return run

    except Exception as exc:  # noqa: BLE001
        db.rollback()
        run.status = SearchIndexSyncStatus.FAILED
        run.error_message = str(exc)
        run.completed_at = datetime.now(timezone.utc)
        db.add(run)
        db.flush()
        raise


def incremental_sync(db: Session, since: Optional[datetime] = None) -> SearchIndexSync:
    """
    Incremental sync — re-index only entries that changed since `since`.
    """
    run = SearchIndexSync(
        sync_type="INCREMENTAL",
        status=SearchIndexSyncStatus.RUNNING,
    )
    db.add(run)
    db.flush()

    try:
        since = since or datetime.now(timezone.utc)

        # Determine which shop products changed recently
        changed = (
            db.query(ShopProduct)
            .options(
                selectinload(ShopProduct.product_master).selectinload(ProductMaster.brand),
                selectinload(ShopProduct.product_master).selectinload(ProductMaster.category),
                selectinload(ShopProduct.product_master).selectinload(ProductMaster.subcategory),
                selectinload(ShopProduct.product_master).selectinload(ProductMaster.identifiers),
                selectinload(ShopProduct.product_master).selectinload(ProductMaster.barcode_relationships),
                selectinload(ShopProduct.shop),
                selectinload(ShopProduct.variant),
                selectinload(ShopProduct.inventory),
            )
            .filter(
                ShopProduct.updated_at >= since,
                ShopProduct.is_deleted == False,  # noqa: E712
            )
            .all()
        )
        for sp in changed:
            existing = (
                db.query(SearchIndex)
                .filter(
                    SearchIndex.entity_type == SearchIndexEntityType.SHOP_PRODUCT,
                    SearchIndex.entity_id == sp.id,
                )
                .first()
            )
            try:
                payload = build_shop_product_index(db, sp)
                if existing:
                    for k, v in payload.items():
                        setattr(existing, k, v)
                    run.total_updated += 1
                else:
                    db.add(SearchIndex(**payload))
                    run.total_created += 1
            except ValueError as exc:
                # Product or shop missing — remove stale index if present
                if existing:
                    db.delete(existing)
                    run.total_removed += 1
                logger.warning("Incremental sync error for shop_product %s: %s", sp.id, exc)
                run.error_count += 1
            run.total_processed += 1

        db.flush()
        run.status = SearchIndexSyncStatus.COMPLETED
        run.completed_at = datetime.now(timezone.utc)
        db.flush()
        return run

    except Exception as exc:  # noqa: BLE001
        db.rollback()
        run.status = SearchIndexSyncStatus.FAILED
        run.error_message = str(exc)
        run.completed_at = datetime.now(timezone.utc)
        db.add(run)
        db.flush()
        raise