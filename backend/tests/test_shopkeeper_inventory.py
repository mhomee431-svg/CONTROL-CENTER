"""Phase 23 — Shopkeeper Inventory Management tests.

Covers:
  - Product-master search (name/slug match, variants, no-match)
  - Add known product from catalog (reuses master, never duplicates it)
  - Variant selection + foreign-variant rejection
  - Duplicate listing rejection (ConflictError)
  - create_product dedupe guard (links to matching master)
  - Price update (writes PriceHistory), MRP validation
  - Stock update (writes InventoryMovement), availability update
  - Delta stock adjustments (InventoryAdjustment audit trail, negative guard)
  - Remove product (soft delete + deactivation + REMOVE movement)
  - Inventory list: search / filter / sort + source + last-updated
  - Inventory history (movements + adjustments + price changes)
  - Bulk operations foundation (price_update / stock_set / availability)
  - Offer assignment (owner-only, validation, cross-shop rejection)
  - Unauthorized access (stranger → ForbiddenError, cross-shop → NotFoundError)
  - VERIFY: shopkeeper updates are visible through the platform's
    inventory system (inventory_service.get_shop_inventory)
"""

import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402

from app.core.config import settings  # noqa: E402

settings.RATE_LIMIT_ENABLED = False


# ── Mock infrastructure (mirrors Phase 22 pattern) ───────────────────────


class MockQuery:
    """Chainable query mock with FIFO `first()` queues and fixed `all()`."""

    def __init__(self, db, model):
        self._db = db
        self._model = model

    def filter(self, *args, **kwargs):
        return self

    def filter_by(self, **kwargs):
        return self

    def join(self, *args, **kwargs):
        return self

    def options(self, *args, **kwargs):
        return self

    def order_by(self, *args):
        return self

    def offset(self, *args):
        return self

    def limit(self, *args):
        return self

    def first(self):
        queue = self._db.first_queues.get(self._model)
        if queue:
            return queue.pop(0)
        matches = [o for o in self._db.added if isinstance(o, self._model)]
        return matches[0] if matches else None

    def all(self):
        return list(self._db.all_results.get(self._model, []))

    def count(self):
        return len(self.all())

    def delete(self, synchronize_session=False):
        return 0


class InventoryMockDB:
    """DB mock tuned for shopkeeper_service inventory call patterns."""

    def __init__(self):
        self.added = []
        self.committed = 0
        self.flushes = 0
        self.first_queues: dict = {}
        self.all_results: dict = {}
        self._next_id = 500

    def queue_first(self, model, items):
        self.first_queues.setdefault(model, []).extend(items)

    def set_all(self, model, items):
        self.all_results[model] = list(items)

    def query(self, model):
        return MockQuery(self, model)

    def add(self, obj):
        self.added.append(obj)

    def add_all(self, objs):
        self.added.extend(objs)

    def flush(self):
        self.flushes += 1
        for obj in self.added:
            if getattr(obj, "id", None) is None:
                obj.id = self._next_id
                self._next_id += 1

    def commit(self):
        self.committed += 1

    def rollback(self):
        pass


def make_user(user_id=1, phone="+919000000001", role_name=None, name="Shop Owner"):
    from app.models.role import Role
    from app.models.user import User, UserStatus

    user = User(phone_number=phone, name=name)
    user.id = user_id
    user.is_active = True
    user.status = UserStatus.ACTIVE
    if role_name:
        role = Role(name=role_name)
        user.role = role
    return user


def make_shop(shop_id=10, name="Kirana Corner"):
    from app.models.shop import Shop, ShopCategory, ShopStatus

    shop = Shop(
        name=name,
        slug=f"kirana-corner-{shop_id}",
        status=ShopStatus.REGISTERED,
        category=ShopCategory.GROCERY,
        rating=4.2,
        review_count=12,
    )
    shop.id = shop_id
    return shop


def owner_access(shop_id=10):
    from app.core.shopkeeper_permissions import effective_shop_permissions
    from app.services.shopkeeper_service import ShopAccess

    return ShopAccess(
        shop=make_shop(shop_id),
        role_name="shopkeeper",
        is_owner=True,
        permissions=effective_shop_permissions("shopkeeper", True, None),
    )


def limited_access(perms):
    """A non-owner (e.g. restricted manager) with only *perms* granted."""
    from app.services.shopkeeper_service import ShopAccess

    return ShopAccess(
        shop=make_shop(),
        role_name="shopkeeper",
        is_owner=False,
        permissions=set(perms),
    )


def make_variant(variant_id=31, name="5 kg pack", sku="VAR-31"):
    from app.models.product import ProductVariant

    v = ProductVariant(name=name, sku=sku)
    v.id = variant_id
    return v


def make_master(master_id=7, name="Basmati Rice 1kg", variants=None):
    from app.models.product import ProductMaster, ProductStatus

    m = ProductMaster(
        name=name,
        slug=name.lower().replace(" ", "-"),
        status=ProductStatus.APPROVED,
        is_active=True,
    )
    m.id = master_id
    m.variants = list(variants or [])
    return m


def make_shop_product(sp_id=100, master=None, price=120.0, quantity=25,
                      threshold=5, active=True, available=True, shop_id=10):
    from app.models.product import Inventory, ProductMaster, ShopProduct, StockStatus

    if master is None:
        master = ProductMaster(name="Basmati Rice 1kg", slug="basmati-rice-1kg")
        master.id = sp_id * 7
    sp = ShopProduct(
        product_master_id=master.id,
        shop_id=shop_id,
        price=price,
        mrp=price * 1.2,
        is_active=active,
        is_available=available,
    )
    sp.product_master = master
    sp.id = sp_id
    inv = Inventory(quantity=quantity, low_stock_threshold=threshold, available_quantity=quantity)
    inv.stock_status = (
        StockStatus.IN_STOCK if quantity > threshold else (
            StockStatus.LOW_STOCK if quantity > 0 else StockStatus.OUT_OF_STOCK
        )
    )
    sp.inventory = inv
    sp.last_inventory_update = datetime.now(timezone.utc) - timedelta(hours=2)
    return sp


# ── Product-master search ────────────────────────────────────────────────


class TestCatalogSearch:
    def test_search_matches_name_and_slug(self):
        from app.models.product import ProductMaster
        from app.services import shopkeeper_service as svc

        rice = make_master(master_id=7, name="Basmati Rice 1kg")
        dal = make_master(master_id=8, name="Toor Dal 500g")
        db = InventoryMockDB()
        db.set_all(ProductMaster, [rice, dal])

        results = svc.search_product_masters(db, "rice")
        assert [r["product_master_id"] for r in results] == [7]

        exact = svc.search_product_masters(db, "basmati rice 1kg")
        assert exact and exact[0]["product_master_id"] == 7

    def test_search_returns_variants(self):
        from app.models.product import ProductMaster
        from app.services import shopkeeper_service as svc

        variant = make_variant()
        master = make_master(master_id=9, name="Sunflower Oil 1L", variants=[variant])
        db = InventoryMockDB()
        db.set_all(ProductMaster, [master])

        results = svc.search_product_masters(db, "oil")
        assert len(results) == 1
        assert results[0]["variants"][0]["variant_id"] == 31

    def test_search_no_match_returns_empty(self):
        from app.models.product import ProductMaster
        from app.services import shopkeeper_service as svc

        db = InventoryMockDB()
        db.set_all(ProductMaster, [make_master(name="Basmati Rice 1kg")])
        assert svc.search_product_masters(db, "toothpaste") == []


# ── Add product from catalog (master selection) ──────────────────────────


class TestAddProductFromCatalog:
    def test_add_known_product_reuses_master(self):
        from app.models.product import ProductMaster
        from app.services import shopkeeper_service as svc

        master = make_master(master_id=7, name="Basmati Rice 1kg")
        db = InventoryMockDB()
        db.queue_first(ProductMaster, [master])  # master lookup

        result = svc.add_product_from_master(
            owner_access(), db, make_user(),
            {"product_master_id": 7, "price": 125.0, "mrp": 140.0,
             "quantity": 20, "low_stock_threshold": 5},
        )

        # No new ProductMaster record was created — the known one is reused.
        assert not any(isinstance(o, ProductMaster) for o in db.added)
        sp = next(o for o in db.added if type(o).__name__ == "ShopProduct")
        assert sp.product_master_id == 7
        inv = next(o for o in db.added if type(o).__name__ == "Inventory")
        assert inv.quantity == 20
        assert result["price"] == 125.0
        assert result["quantity"] == 20
        assert result["stock_status"] == "IN_STOCK"
        # Initial movement recorded for the platform inventory history.
        movements = [o for o in db.added if type(o).__name__ == "InventoryMovement"]
        assert len(movements) == 1
        assert movements[0].movement_type == "INITIAL"

    def test_add_variant_selection(self):
        from app.models.product import ProductMaster
        from app.services import shopkeeper_service as svc

        variant = make_variant(variant_id=31)
        master = make_master(master_id=7, variants=[variant])
        db = InventoryMockDB()
        db.queue_first(ProductMaster, [master])

        result = svc.add_product_from_master(
            owner_access(), db, make_user(),
            {"product_master_id": 7, "variant_id": 31, "price": 300.0, "quantity": 4},
        )
        sp = next(o for o in db.added if type(o).__name__ == "ShopProduct")
        assert sp.variant_id == 31
        assert sp.variant is variant
        assert result["stock_status"] == "LOW_STOCK"  # qty 4 <= threshold 5

    def test_add_rejects_foreign_variant(self):
        from app.core.exceptions import ValidationError
        from app.models.product import ProductMaster
        from app.services import shopkeeper_service as svc

        master = make_master(master_id=7, variants=[make_variant(variant_id=31)])
        db = InventoryMockDB()
        db.queue_first(ProductMaster, [master])

        with pytest.raises(ValidationError):
            svc.add_product_from_master(
                owner_access(), db, make_user(),
                {"product_master_id": 7, "variant_id": 999, "price": 100.0},
            )

    def test_add_unknown_master_is_not_found(self):
        from app.core.exceptions import NotFoundError
        from app.models.product import ProductMaster
        from app.services import shopkeeper_service as svc

        db = InventoryMockDB()
        db.queue_first(ProductMaster, [None])
        with pytest.raises(NotFoundError):
            svc.add_product_from_master(
                owner_access(), db, make_user(),
                {"product_master_id": 404, "price": 10.0},
            )

    def test_add_duplicate_listing_rejected(self):
        from app.core.exceptions import ConflictError
        from app.models.product import ProductMaster, ShopProduct
        from app.services import shopkeeper_service as svc

        master = make_master(master_id=7)
        existing = make_shop_product(sp_id=100, master=master)
        db = InventoryMockDB()
        db.queue_first(ProductMaster, [master])
        db.queue_first(ShopProduct, [existing])  # duplicate check

        with pytest.raises(ConflictError):
            svc.add_product_from_master(
                owner_access(), db, make_user(),
                {"product_master_id": 7, "price": 125.0},
            )

    def test_add_rejects_mrp_below_price(self):
        from app.core.exceptions import ValidationError
        from app.models.product import ProductMaster
        from app.services import shopkeeper_service as svc

        db = InventoryMockDB()
        db.queue_first(ProductMaster, [make_master(master_id=7)])
        with pytest.raises(ValidationError):
            svc.add_product_from_master(
                owner_access(), db, make_user(),
                {"product_master_id": 7, "price": 150.0, "mrp": 140.0},
            )

    def test_add_requires_product_create_permission(self):
        from app.core.exceptions import ForbiddenError
        from app.services import shopkeeper_service as svc

        db = InventoryMockDB()
        with pytest.raises(ForbiddenError):
            svc.add_product_from_master(
                limited_access({"read:product"}), db, make_user(),
                {"product_master_id": 7, "price": 10.0},
            )


# ── create_product dedupe guard ──────────────────────────────────────────


class TestCreateProductDedupes:
    def test_create_product_links_to_existing_master(self):
        from app.models.product import ProductMaster
        from app.services import shopkeeper_service as svc

        existing = make_master(master_id=7, name="Basmati Rice 1kg")
        db = InventoryMockDB()
        db.set_all(ProductMaster, [existing])  # find_matching_master candidates

        result = svc.create_product(
            owner_access(), db, make_user(),
            {"name": "Basmati Rice 1kg", "price": 120.0, "quantity": 10},
        )
        assert not any(isinstance(o, ProductMaster) for o in db.added)  # no duplicate master
        sp = next(o for o in db.added if type(o).__name__ == "ShopProduct")
        assert sp.product_master_id == 7
        assert result["name"] == "Basmati Rice 1kg"

    def test_create_product_conflicts_when_already_listed(self):
        from app.core.exceptions import ConflictError
        from app.models.product import ProductMaster, ShopProduct
        from app.services import shopkeeper_service as svc

        existing_master = make_master(master_id=7, name="Basmati Rice 1kg")
        listed = make_shop_product(sp_id=100, master=existing_master)
        db = InventoryMockDB()
        db.set_all(ProductMaster, [existing_master])
        db.queue_first(ShopProduct, [listed])  # duplicate check

        with pytest.raises(ConflictError):
            svc.create_product(
                owner_access(), db, make_user(),
                {"name": "Basmati Rice 1kg", "price": 120.0},
            )

    def test_create_product_makes_master_only_when_no_match(self):
        from app.models.product import ProductMaster
        from app.services import shopkeeper_service as svc

        db = InventoryMockDB()  # empty catalog → no match
        svc.create_product(
            owner_access(), db, make_user(),
            {"name": "Brand New Gadget", "price": 999.0},
        )
        masters = [o for o in db.added if isinstance(o, ProductMaster)]
        assert len(masters) == 1
        assert masters[0].name == "Brand New Gadget"


# ── Update listing: price / stock / availability + history writes ────────


class TestUpdateListing:
    def _queued(self, sp):
        db = InventoryMockDB()
        db.queue_first(type(sp), [sp])
        db.queue_first(type(sp.inventory), [sp.inventory])
        return db

    def test_price_update_writes_price_history(self):
        from app.models.product import PriceHistory
        from app.services import shopkeeper_service as svc

        sp = make_shop_product(sp_id=100, price=120.0)
        old_price_stamp = sp.last_price_update
        db = self._queued(sp)

        result = svc.update_product(
            owner_access(), db, make_user(), 100, {"price": 130.0}
        )
        assert result["price"] == 130.0
        assert sp.last_price_update is not old_price_stamp
        history = [o for o in db.added if isinstance(o, PriceHistory)]
        assert len(history) == 1
        assert float(history[0].old_price) == 120.0
        assert float(history[0].new_price) == 130.0
        assert history[0].effective_to is None  # open record

    def test_mrp_cannot_go_below_price(self):
        from app.core.exceptions import ValidationError
        from app.services import shopkeeper_service as svc

        sp = make_shop_product(sp_id=101, price=120.0)
        with pytest.raises(ValidationError):
            svc.update_product(
                owner_access(), self._queued(sp), make_user(), 101, {"mrp": 10.0}
            )

    def test_stock_update_records_movement_and_syncs_platform(self):
        from app.models.product import InventorySource, InventoryMovement
        from app.services import shopkeeper_service as svc

        sp = make_shop_product(sp_id=102, quantity=25)
        inv = sp.inventory
        db = self._queued(sp)

        result = svc.update_product(
            owner_access(), db, make_user(), 102, {"quantity": 50}
        )
        assert result["quantity"] == 50
        assert inv.quantity == 50
        movements = [o for o in db.added if isinstance(o, InventoryMovement)]
        assert len(movements) == 1
        assert movements[0].movement_type == "UPDATE"
        assert movements[0].quantity_change == 25
        assert movements[0].quantity_before == 25
        assert movements[0].quantity_after == 50
        # Platform inventory row stays in sync (source + freshness).
        assert inv.last_updated_source == InventorySource.MANUAL
        assert inv.freshness_status.value == "RECENTLY_UPDATED"
        assert sp.freshness_status == inv.freshness_status

    def test_availability_update_syncs_inventory_row(self):
        from app.models.product import InventorySource
        from app.services import shopkeeper_service as svc

        sp = make_shop_product(sp_id=103, quantity=25)
        inv = sp.inventory
        db = self._queued(sp)

        result = svc.update_product(
            owner_access(), db, make_user(), 103, {"is_available": False}
        )
        assert result["is_available"] is False
        assert sp.is_available is False
        assert inv.is_available is False
        assert inv.last_updated_source == InventorySource.MANUAL


# ── Stock adjustments ────────────────────────────────────────────────────


class TestStockAdjustments:
    def _adjust(self, sp, data):
        from app.services import shopkeeper_service as svc

        db = InventoryMockDB()
        db.queue_first(type(sp), [sp])
        db.queue_first(type(sp.inventory), [sp.inventory])
        return svc.adjust_stock(owner_access(), db, make_user(), sp.id, data), db

    def test_restock_increases_stock_with_audit_trail(self):
        from app.models.product import InventoryAdjustment, InventoryMovement

        sp = make_shop_product(sp_id=110, quantity=25)
        result, db = self._adjust(
            sp, {"adjustment_type": "RESTOCK", "quantity_adjustment": 10,
                 "reason": "weekly delivery"}
        )
        assert result["previous_quantity"] == 25
        assert result["new_quantity"] == 35
        adjustments = [o for o in db.added if isinstance(o, InventoryAdjustment)]
        assert len(adjustments) == 1
        assert adjustments[0].adjustment_type == "RESTOCK"
        assert adjustments[0].quantity_adjustment == 10
        assert adjustments[0].reason == "weekly delivery"
        movements = [o for o in db.added if isinstance(o, InventoryMovement)]
        assert len(movements) == 1
        assert movements[0].movement_type == "ADJUSTMENT"

    def test_damage_reduces_stock(self):
        sp = make_shop_product(sp_id=111, quantity=20)
        result, _ = self._adjust(
            sp, {"adjustment_type": "DAMAGE", "quantity_adjustment": -5}
        )
        assert result["new_quantity"] == 15
        assert result["stock_status"] == "IN_STOCK"

    def test_adjustment_cannot_result_in_negative_stock(self):
        from app.core.exceptions import ValidationError

        sp = make_shop_product(sp_id=112, quantity=3)
        with pytest.raises(ValidationError):
            self._adjust(sp, {"adjustment_type": "SALE", "quantity_adjustment": -10})

    def test_invalid_adjustment_type_rejected(self):
        from app.core.exceptions import ValidationError

        sp = make_shop_product(sp_id=113)
        with pytest.raises(ValidationError):
            self._adjust(sp, {"adjustment_type": "MAGIC", "quantity_adjustment": 5})

    def test_zero_delta_rejected(self):
        from app.core.exceptions import ValidationError

        sp = make_shop_product(sp_id=114)
        with pytest.raises(ValidationError):
            self._adjust(sp, {"adjustment_type": "CORRECTION", "quantity_adjustment": 0})

    def test_adjust_without_inventory_row_rejected(self):
        from app.core.exceptions import ValidationError
        from app.models.product import Inventory, ShopProduct
        from app.services import shopkeeper_service as svc

        sp = make_shop_product(sp_id=115)
        db = InventoryMockDB()
        db.queue_first(ShopProduct, [sp])
        db.queue_first(Inventory, [None])
        with pytest.raises(ValidationError):
            svc.adjust_stock(
                owner_access(), db, make_user(), 115,
                {"adjustment_type": "CORRECTION", "quantity_adjustment": 5},
            )


# ── Remove / deactivate product ──────────────────────────────────────────


class TestRemoveProduct:
    def test_remove_deactivates_soft_deletes_and_zeroes_stock(self):
        from app.models.product import InventoryMovement
        from app.services import shopkeeper_service as svc

        sp = make_shop_product(sp_id=120, quantity=18)
        inv = sp.inventory
        db = InventoryMockDB()
        db.queue_first(type(sp), [sp])
        db.queue_first(type(inv), [inv])

        result = svc.remove_product(owner_access(), db, make_user(), 120)
        assert result["is_active"] is False
        assert result["status"] == "INACTIVE"
        assert result["removed_at"]
        assert sp.is_deleted is True
        assert sp.deleted_at is not None
        assert sp.is_active is False
        assert sp.is_available is False
        assert inv.quantity == 0
        assert inv.available_quantity == 0
        movements = [o for o in db.added if isinstance(o, InventoryMovement)]
        assert len(movements) == 1
        assert movements[0].movement_type == "REMOVE"
        assert movements[0].quantity_after == 0

    def test_remove_cross_shop_product_not_found(self):
        from app.core.exceptions import NotFoundError
        from app.models.product import ShopProduct
        from app.services import shopkeeper_service as svc

        db = InventoryMockDB()
        db.queue_first(ShopProduct, [None])
        with pytest.raises(NotFoundError):
            svc.remove_product(owner_access(), db, make_user(), 999)


# ── Inventory list: view / search / filter / sort ────────────────────────


class TestInventoryList:
    def _listing_db(self):
        from app.models.product import Inventory, ProductMaster, ShopProduct

        sp_rice = make_shop_product(sp_id=130, price=120.0, quantity=40)
        dal_master = ProductMaster(name="Toor Dal 500g", slug="toor-dal-500g")
        dal_master.id = 88
        sp_dal = make_shop_product(sp_id=131, master=dal_master, price=90.0, quantity=3)
        db = InventoryMockDB()
        db.set_all(ShopProduct, [sp_rice, sp_dal])
        db.queue_first(Inventory, [sp_rice.inventory, sp_dal.inventory])
        return db, sp_rice, sp_dal

    def test_list_returns_items_with_source_and_last_updated(self):
        from app.services import shopkeeper_service as svc

        db, _, _ = self._listing_db()
        result = svc.list_inventory(owner_access(), db)
        assert result["count"] == 2
        for item in result["items"]:
            assert "source" in item and item["source"] is not None
            assert item["last_updated"]

    def test_list_search_filters_by_name(self):
        from app.services import shopkeeper_service as svc

        db, _, _ = self._listing_db()
        result = svc.list_inventory(owner_access(), db, search="dal")
        assert result["count"] == 1
        assert result["items"][0]["name"] == "Toor Dal 500g"

    def test_list_filter_by_stock_status(self):
        from app.services import shopkeeper_service as svc

        db, _, _ = self._listing_db()
        low = svc.list_inventory(owner_access(), db, stock_filter="LOW_STOCK")
        assert low["count"] == 1
        assert low["items"][0]["name"] == "Toor Dal 500g"

    def test_list_sort_by_price(self):
        from app.services import shopkeeper_service as svc

        db, _, _ = self._listing_db()
        asc = svc.list_inventory(owner_access(), db, sort_by="price", sort_order="asc")
        prices = [item["price"] for item in asc["items"]]
        assert prices == sorted(prices)
        desc = svc.list_inventory(owner_access(), db, sort_by="price", sort_order="desc")
        prices_desc = [item["price"] for item in desc["items"]]
        assert prices_desc == sorted(prices_desc, reverse=True)

    def test_list_sort_by_quantity(self):
        from app.services import shopkeeper_service as svc

        db, _, _ = self._listing_db()
        asc = svc.list_inventory(owner_access(), db, sort_by="quantity", sort_order="asc")
        quantities = [item["quantity"] for item in asc["items"]]
        assert quantities == sorted(quantities)

    # ── Low-stock restock query (quantity <= low_stock_threshold) ─────────

    def test_low_below_threshold_returns_only_restock_needs(self):
        """Rice (40/5) stays out; Dal (3/5) and an out-of-stock row come in."""
        from app.models.product import Inventory, ShopProduct
        from app.services import shopkeeper_service as svc

        db, rice, dal = self._listing_db()
        # An out-of-stock listing (0 <= threshold) is also a restock need.
        empty = make_shop_product(sp_id=132, price=60.0, quantity=0)
        db.set_all(ShopProduct, [rice, dal, empty])
        db.queue_first(
            Inventory, [rice.inventory, dal.inventory, empty.inventory]
        )

        result = svc.list_inventory(owner_access(), db, low_below_threshold=True)
        names = [item["name"] for item in result["items"]]
        assert "Toor Dal 500g" in names  # 3 <= 5
        assert "Basmati Rice 1kg" not in names  # 40 > 5

    def test_low_below_threshold_includes_boundary_quantity_equal_threshold(self):
        """The rule is `<=`: a listing exactly at its threshold needs restocking."""
        from app.services import shopkeeper_service as svc

        # Fresh mock: the shared listing db pre-queues other inventories.
        exact = make_shop_product(sp_id=133, price=30.0, quantity=5)
        db = InventoryMockDB()
        db.set_all(type(exact), [exact])
        db.queue_first(type(exact.inventory), [exact.inventory])

        result = svc.list_inventory(owner_access(), db, low_below_threshold=True)
        assert result["count"] == 1
        assert result["items"][0]["quantity"] == 5
        assert result["items"][0]["low_stock_threshold"] == 5

    def test_low_below_threshold_carries_the_full_restock_payload(self):
        """Every row answers the restock card: what, how many, how low, how it looks."""
        from app.services import shopkeeper_service as svc

        db, _, _ = self._listing_db()
        result = svc.list_inventory(owner_access(), db, low_below_threshold=True)
        assert result["count"] >= 1
        for item in result["items"]:
            assert isinstance(item["id"], int)
            assert isinstance(item["name"], str) and item["name"]
            assert "sku" in item
            assert "image_url" in item
            assert isinstance(item["quantity"], int)
            assert isinstance(item["low_stock_threshold"], int)
            assert isinstance(item["stock_status"], str)

    def test_low_below_threshold_false_returns_everything(self):
        """Omitting / explicitly disabling the flag never filters."""
        from app.services import shopkeeper_service as svc

        db, _, _ = self._listing_db()
        assert svc.list_inventory(owner_access(), db)["count"] == 2
        assert svc.list_inventory(
            owner_access(), db, low_below_threshold=False
        )["count"] == 2


# ── Inventory history ────────────────────────────────────────────────────


class TestInventoryHistory:
    def test_history_combines_movements_adjustments_price_changes(self):
        from app.models.product import (
            Inventory,
            InventoryAdjustment,
            InventoryMovement,
            PriceHistory,
            ShopProduct,
        )
        from app.services import shopkeeper_service as svc

        now = datetime.now(timezone.utc)
        sp = make_shop_product(sp_id=140)
        inv = sp.inventory
        inv.id = 777

        mv = InventoryMovement(
            inventory_id=777, quantity_change=10, quantity_before=5,
            quantity_after=15, movement_type="RESTOCK",
        )
        mv.created_at = now - timedelta(hours=1)
        adj = InventoryAdjustment(
            inventory_id=777, adjustment_type="STOCK_COUNT",
            quantity_adjustment=2, reason="audit",
        )
        adj.approved_at = now
        ph = PriceHistory(shop_product_id=140, old_price=100.0, new_price=110.0)
        ph.effective_from = now - timedelta(hours=2)

        db = InventoryMockDB()
        db.queue_first(ShopProduct, [sp])
        db.queue_first(Inventory, [inv])
        db.set_all(InventoryMovement, [mv])
        db.set_all(InventoryAdjustment, [adj])
        db.set_all(PriceHistory, [ph])

        result = svc.product_history(owner_access(), db, make_user(), 140)
        types = [e["type"] for e in result["entries"]]
        assert set(types) == {"movement", "adjustment", "price_change"}
        # newest first: adjustment (now) > movement (-1h) > price (-2h)
        assert types[0] == "adjustment"
        assert types[1] == "movement"
        assert types[2] == "price_change"

    def test_history_cross_shop_not_found(self):
        from app.core.exceptions import NotFoundError
        from app.models.product import ShopProduct
        from app.services import shopkeeper_service as svc

        db = InventoryMockDB()
        db.queue_first(ShopProduct, [None])
        with pytest.raises(NotFoundError):
            svc.product_history(owner_access(), db, make_user(), 999)

    # ── Audit fields: who / when / what / why ─────────────────────────────

    def test_history_names_the_actor_who_changed_stock(self):
        """A movement stores created_by; the trail must resolve it to a name."""
        from app.models.product import Inventory, InventoryMovement, ShopProduct
        from app.models.user import User
        from app.services import shopkeeper_service as svc

        now = datetime.now(timezone.utc)
        sp = make_shop_product(sp_id=150)
        inv = sp.inventory
        inv.id = 778

        mv = InventoryMovement(
            inventory_id=778, quantity_change=5, quantity_before=10,
            quantity_after=15, movement_type="RESTOCK",
        )
        mv.created_at = now
        mv.created_by = 42

        db = InventoryMockDB()
        db.queue_first(ShopProduct, [sp])
        db.queue_first(Inventory, [inv])
        db.set_all(InventoryMovement, [mv])
        db.set_all(User, [make_user(user_id=42, name="Akash")])

        result = svc.product_history(owner_access(), db, make_user(), 150)
        entry = result["entries"][0]
        assert entry["actor"] == "Akash"
        assert entry["actor_id"] == 42

    def test_history_actor_is_null_for_automated_change(self):
        """No created_by means an import / POS sync — never the reading user."""
        from app.models.product import Inventory, InventoryMovement, ShopProduct
        from app.services import shopkeeper_service as svc

        now = datetime.now(timezone.utc)
        sp = make_shop_product(sp_id=151)
        inv = sp.inventory
        inv.id = 779

        mv = InventoryMovement(
            inventory_id=779, quantity_change=3, quantity_before=0,
            quantity_after=3, movement_type="RESTOCK",
        )
        mv.created_at = now
        mv.created_by = None

        db = InventoryMockDB()
        db.queue_first(ShopProduct, [sp])
        db.queue_first(Inventory, [inv])
        db.set_all(InventoryMovement, [mv])

        result = svc.product_history(owner_access(), db, make_user(), 151)
        entry = result["entries"][0]
        assert entry["actor"] is None
        assert entry["actor_id"] is None

    def test_history_paginates_and_reports_has_more(self):
        """limit + offset page the trail; has_more tells the client to ask again."""
        from app.models.product import Inventory, InventoryMovement, ShopProduct
        from app.services import shopkeeper_service as svc

        now = datetime.now(timezone.utc)
        sp = make_shop_product(sp_id=152)
        inv = sp.inventory
        inv.id = 780

        movements = []
        for i in range(3):
            mv = InventoryMovement(
                inventory_id=780, quantity_change=1, quantity_before=i,
                quantity_after=i + 1, movement_type="RESTOCK",
            )
            mv.created_at = now - timedelta(minutes=i)
            movements.append(mv)

        db = InventoryMockDB()
        db.set_all(InventoryMovement, movements)

        db.queue_first(ShopProduct, [sp])
        db.queue_first(Inventory, [inv])
        first = svc.product_history(owner_access(), db, make_user(), 152, limit=2)
        assert first["count"] == 2
        assert first["total"] == 3
        assert first["offset"] == 0
        assert first["has_more"] is True

        db.queue_first(ShopProduct, [sp])
        db.queue_first(Inventory, [inv])
        last = svc.product_history(
            owner_access(), db, make_user(), 152, limit=2, offset=2
        )
        assert last["count"] == 1
        assert last["total"] == 3
        assert last["offset"] == 2
        assert last["has_more"] is False

    def test_history_reports_current_stock_for_the_summary_tile(self):
        """The summary tile reads live stock + the server's stock state."""
        from app.models.product import Inventory, InventoryMovement, ShopProduct
        from app.services import shopkeeper_service as svc

        now = datetime.now(timezone.utc)
        sp = make_shop_product(sp_id=153, quantity=25)
        inv = sp.inventory
        inv.id = 781

        mv = InventoryMovement(
            inventory_id=781, quantity_change=5, quantity_before=20,
            quantity_after=25, movement_type="RESTOCK",
        )
        mv.created_at = now

        db = InventoryMockDB()
        db.queue_first(ShopProduct, [sp])
        db.queue_first(Inventory, [inv])
        db.set_all(InventoryMovement, [mv])

        result = svc.product_history(owner_access(), db, make_user(), 153)
        assert result["current_quantity"] == 25
        assert result["stock_status"] == "IN_STOCK"


# ── Bulk operations foundation ───────────────────────────────────────────


class TestBulkOperations:
    def test_bulk_price_update_applies_to_all(self):
        from app.services import shopkeeper_service as svc

        sp_a = make_shop_product(sp_id=150, price=100.0)
        sp_b = make_shop_product(sp_id=151, price=200.0)
        db = InventoryMockDB()
        db.queue_first(type(sp_a), [sp_a, sp_b])
        db.queue_first(type(sp_a.inventory), [sp_a.inventory, sp_b.inventory])

        result = svc.bulk_operation(
            owner_access(), db, make_user(),
            {"operation": "price_update", "shop_product_ids": [150, 151], "price": 111.0},
        )
        assert result["succeeded"] == 2
        assert result["failed_count"] == 0
        assert float(sp_a.price) == 111.0
        assert float(sp_b.price) == 111.0

    def test_bulk_reports_partial_failures(self):
        from app.services import shopkeeper_service as svc

        sp_a = make_shop_product(sp_id=152, quantity=10)
        db = InventoryMockDB()
        db.queue_first(type(sp_a), [sp_a])  # only the first id resolves

        result = svc.bulk_operation(
            owner_access(), db, make_user(),
            {"operation": "stock_set", "shop_product_ids": [152, 9999], "quantity": 7},
        )
        assert result["succeeded"] == 1
        assert result["failed_count"] == 1
        assert "not found" in result["failed"][0]["error"].lower()

    def test_bulk_unknown_operation_rejected(self):
        from app.core.exceptions import ValidationError
        from app.services import shopkeeper_service as svc

        with pytest.raises(ValidationError):
            svc.bulk_operation(
                owner_access(), InventoryMockDB(), make_user(),
                {"operation": "delete_everything", "shop_product_ids": [1]},
            )


# ── Offer assignment ─────────────────────────────────────────────────────


class TestOfferAssignment:
    def _offer_data(self, **overrides):
        start = datetime.now(timezone.utc)
        data = {
            "title": "Monsoon Sale",
            "offer_type": "PERCENTAGE_DISCOUNT",
            "discount_percentage": 10.0,
            "start_date": start,
            "end_date": start + timedelta(days=7),
            "shop_product_ids": [160],
        }
        data.update(overrides)
        return data

    def test_assign_offer_creates_offer_and_links_products(self):
        from app.models.product import Offer, OfferProduct
        from app.services import shopkeeper_service as svc

        sp = make_shop_product(sp_id=160)
        db = InventoryMockDB()
        db.queue_first(type(sp), [sp])

        result = svc.assign_offer(owner_access(), db, make_user(), self._offer_data())
        offers = [o for o in db.added if isinstance(o, Offer)]
        links = [o for o in db.added if isinstance(o, OfferProduct)]
        assert len(offers) == 1
        assert offers[0].status.value == "ACTIVE"
        assert offers[0].shop_id == 10
        assert len(links) == 1
        assert links[0].shop_product_id == 160
        assert result["product_count"] == 1

    def test_percentage_offer_requires_discount(self):
        from app.core.exceptions import ValidationError
        from app.services import shopkeeper_service as svc

        with pytest.raises(ValidationError):
            svc.assign_offer(
                owner_access(), InventoryMockDB(), make_user(),
                self._offer_data(discount_percentage=None),
            )

    def test_end_date_must_be_after_start(self):
        from app.core.exceptions import ValidationError
        from app.services import shopkeeper_service as svc

        start = datetime.now(timezone.utc)
        with pytest.raises(ValidationError):
            svc.assign_offer(
                owner_access(), InventoryMockDB(), make_user(),
                self._offer_data(start_date=start, end_date=start),
            )

    def test_cannot_attach_other_shops_product(self):
        from app.core.exceptions import NotFoundError
        from app.models.product import ShopProduct
        from app.services import shopkeeper_service as svc

        db = InventoryMockDB()
        db.queue_first(ShopProduct, [None])
        with pytest.raises(NotFoundError):
            svc.assign_offer(owner_access(), db, make_user(), self._offer_data())

    def test_manager_without_update_offer_permission_forbidden(self):
        from app.core.exceptions import ForbiddenError
        from app.core.shopkeeper_permissions import effective_shop_permissions
        from app.services import shopkeeper_service as svc

        class FakeManager:
            permissions = None  # full manager catalog

        perms = effective_shop_permissions("shopkeeper", False, FakeManager())
        assert "update:offer" not in perms
        with pytest.raises(ForbiddenError):
            svc.assign_offer(
                limited_access(perms), InventoryMockDB(), make_user(), self._offer_data()
            )


# ── Unauthorized shop / product access ───────────────────────────────────


class TestUnauthorizedAccess:
    def test_stranger_cannot_resolve_shop_access(self):
        from app.core.exceptions import ForbiddenError
        from app.models.shop import ShopManager, ShopOwner
        from app.services import shopkeeper_service as svc

        customer = make_user(user_id=42, role_name="customer")
        db = InventoryMockDB()
        from app.models.shop import Shop as _Shop  # noqa: N813

        db.queue_first(_Shop, [make_shop()])  # shop exists
        db.queue_first(ShopOwner, [None])
        db.queue_first(ShopManager, [None])
        with pytest.raises(ForbiddenError):
            svc.resolve_shop_access(db, customer, 10)

    def test_cross_shop_product_operations_are_scoped(self):
        from app.core.exceptions import NotFoundError
        from app.models.product import ShopProduct
        from app.services import shopkeeper_service as svc

        db = InventoryMockDB()
        db.queue_first(ShopProduct, [None])  # scoped query misses the foreign row
        with pytest.raises(NotFoundError):
            svc.adjust_stock(
                owner_access(), db, make_user(), 170,
                {"adjustment_type": "CORRECTION", "quantity_adjustment": 1},
            )


# ── VERIFY: platform visibility of shopkeeper updates ────────────────────


class TestPlatformVisibility:
    def test_updates_visible_through_platform_inventory_system(self):
        from app.models.product import ShopProduct
        from app.services import inventory_service
        from app.services import shopkeeper_service as svc

        sp = make_shop_product(sp_id=180, price=120.0, quantity=25)
        db = InventoryMockDB()

        # Shopkeeper updates price and stock.
        db.queue_first(type(sp), [sp])
        db.queue_first(type(sp.inventory), [sp.inventory])
        svc.update_product(
            owner_access(), db, make_user(), 180, {"price": 135.0, "quantity": 60}
        )

        # The platform's own inventory system reads the same rows.
        from app.models.product import Inventory as _Inventory  # noqa: N813

        db.set_all(ShopProduct, [sp])
        db.first_queues[type(sp)] = []
        db.first_queues[_Inventory] = [sp.inventory]
        platform_view = inventory_service.get_shop_inventory(db, 10)

        assert len(platform_view) == 1
        entry = platform_view[0]
        assert entry["shop_product_id"] == 180
        assert entry["product_name"] == "Basmati Rice 1kg"
        assert entry["price"] == 135.0
        assert entry["quantity"] == 60
        assert entry["is_available"] is True
        assert entry["stock_status"] == "IN_STOCK"
        assert entry["source"] == "MANUAL"
# ── Server summary + DISCONTINUED filter (list view) ─────────────────────


class TestInventoryListSummary:
    """The list response must carry the server's own counts so no client has
    to re-derive them — and a withdrawn listing must be counted once, in its
    own bucket, instead of masquerading as "in stock"."""

    def _listing_db(self):
        from app.models.product import (
            Inventory,
            ShopProduct,
            ShopProductStatus,
        )

        rice = make_shop_product(
            sp_id=130,
            master=make_master(master_id=7, name="Basmati Rice 1kg"),
            price=60.0,
            quantity=40,
        )
        dal = make_shop_product(
            sp_id=131,
            master=make_master(master_id=8, name="Toor Dal 500g"),
            price=90.0,
            quantity=3,
        )
        disc = make_shop_product(
            sp_id=132,
            master=make_master(master_id=9, name="Old Biscuits"),
            price=70.0,
            quantity=11,
        )
        disc.status = ShopProductStatus.DISCONTINUED
        db = InventoryMockDB()
        db.set_all(ShopProduct, [rice, dal, disc])
        db.queue_first(
            Inventory, [rice.inventory, dal.inventory, disc.inventory]
        )
        return db, rice, dal, disc

    def test_list_response_carries_the_server_summary(self):
        from app.services import shopkeeper_service as svc

        db, *_ = self._listing_db()
        result = svc.list_inventory(owner_access(), db)
        summary = result["summary"]
        assert summary["total"] == 3
        assert summary["discontinued"] == 1
        assert (
            summary["active"]
            + summary["inactive"]
            + summary["discontinued"]
            == 3
        )

    def test_summary_never_counts_a_withdrawn_listing_as_stock(self):
        from app.services import shopkeeper_service as svc

        db, *_ = self._listing_db()
        summary = svc.list_inventory(owner_access(), db)["summary"]
        # 11 units remain on the discontinued listing, but it is not in stock.
        assert summary["in_stock"] == 1  # rice only
        assert summary["low_stock"] == 1  # dal only
        assert (
            summary["in_stock"]
            + summary["low_stock"]
            + summary["out_of_stock"]
            + summary["unknown"]
            == 2
        )
        assert summary["total_units"] == 40 + 3 + 11

    def test_summary_never_flags_a_withdrawn_listing_for_restock(self):
        from app.services import shopkeeper_service as svc

        db, *_ = self._listing_db()
        summary = svc.list_inventory(owner_access(), db)["summary"]
        # Only the low-stock listing is a restock task: the withdrawn listing
        # keeps its 11 units but is deliberately out of play.
        assert [p["name"] for p in summary["needs_attention"]] == [
            "Toor Dal 500g"
        ]

    def test_stock_filter_can_select_discontinued(self):
        from app.services import shopkeeper_service as svc

        db, *_ = self._listing_db()
        result = svc.list_inventory(
            owner_access(), db, stock_filter="DISCONTINUED"
        )
        assert result["count"] == 1
        assert result["items"][0]["status"] == "DISCONTINUED"

    def test_stock_filter_excludes_discontinued_from_other_states(self):
        from app.services import shopkeeper_service as svc

        db, *_ = self._listing_db()
        low = svc.list_inventory(owner_access(), db, stock_filter="LOW_STOCK")
        assert low["count"] == 1
        assert low["items"][0]["status"] == "ACTIVE"

# ── Low-stock threshold ──────────────────────────────────────────────────


class TestLowStockThreshold:
    def test_threshold_is_written_and_state_re_derived(self):
        from app.models.product import Inventory, ShopProduct, StockStatus
        from app.services import shopkeeper_service as svc

        sp = make_shop_product(sp_id=150, quantity=8, threshold=5)
        db = InventoryMockDB()
        db.queue_first(ShopProduct, [sp])
        db.queue_first(Inventory, [sp.inventory])

        result = svc.update_low_stock_threshold(
            owner_access(), db, make_user(), 150, 3
        )
        assert result["low_stock_threshold"] == 3
        assert result["quantity"] == 8
        assert result["stock_status"] == "IN_STOCK"
        assert sp.inventory.low_stock_threshold == 3
        assert sp.inventory.stock_status == StockStatus.IN_STOCK

    def test_raising_threshold_flips_in_stock_to_low_stock(self):
        from app.models.product import Inventory, ShopProduct, StockStatus
        from app.services import shopkeeper_service as svc

        sp = make_shop_product(sp_id=151, quantity=8, threshold=5)
        db = InventoryMockDB()
        db.queue_first(ShopProduct, [sp])
        db.queue_first(Inventory, [sp.inventory])

        result = svc.update_low_stock_threshold(
            owner_access(), db, make_user(), 151, 10
        )
        assert result["stock_status"] == "LOW_STOCK"
        assert sp.inventory.stock_status == StockStatus.LOW_STOCK

    def test_negative_threshold_rejected(self):
        from app.core.exceptions import ValidationError
        from app.services import shopkeeper_service as svc

        db = InventoryMockDB()
        with pytest.raises(ValidationError):
            svc.update_low_stock_threshold(
                owner_access(), db, make_user(), 152, -1
            )

    def test_unknown_product_rejected(self):
        from app.core.exceptions import NotFoundError
        from app.models.product import ShopProduct
        from app.services import shopkeeper_service as svc

        db = InventoryMockDB()
        db.queue_first(ShopProduct, [None])
        with pytest.raises(NotFoundError):
            svc.update_low_stock_threshold(
                owner_access(), db, make_user(), 999, 5
            )

    def test_cross_shop_product_rejected(self):
        from app.core.exceptions import NotFoundError
        from app.services import shopkeeper_service as svc

        db = InventoryMockDB()
        with pytest.raises(NotFoundError):
            svc.update_low_stock_threshold(
                owner_access(), db, make_user(), 153, 5
            )


# ── Adjustment-only audit trail ──────────────────────────────────────────


class TestStockAdjustmentHistory:
    def _db_with_adjustments(self, sp):
        from app.models.product import (
            Inventory,
            InventoryAdjustment,
            ShopProduct,
        )

        rows = [
            InventoryAdjustment(
                adjustment_type="RESTOCK",
                quantity_adjustment=10,
                reason="Delivery received",
            ),
            InventoryAdjustment(
                adjustment_type="DAMAGE",
                quantity_adjustment=-2,
                reason="Broken in transit",
            ),
        ]
        for r in rows:
            r.id = 900
            r.inventory_id = 777
        db = InventoryMockDB()
        db.queue_first(ShopProduct, [sp])
        db.queue_first(Inventory, [sp.inventory])
        # The service reads adjustments with `.all()`, so they are fixed
        # results rather than a FIFO `first()` queue.
        db.set_all(InventoryAdjustment, rows)
        return db, rows

    def test_returns_adjustments_with_their_fields(self):
        from app.services import shopkeeper_service as svc

        sp = make_shop_product(sp_id=160, quantity=8, threshold=5)
        db, _ = self._db_with_adjustments(sp)
        result = svc.list_stock_adjustments(owner_access(), db, 160)
        assert result["shop_product_id"] == 160
        assert result["count"] == 2
        for entry in result["adjustments"]:
            assert set(entry) >= {
                "id",
                "adjustment_type",
                "quantity_adjustment",
                "reason",
            }

    def test_missing_inventory_returns_empty_trail(self):
        from app.models.product import Inventory, ShopProduct
        from app.services import shopkeeper_service as svc

        sp = make_shop_product(sp_id=161, quantity=8, threshold=5)
        sp.inventory = None
        db = InventoryMockDB()
        db.queue_first(ShopProduct, [sp])
        db.queue_first(Inventory, [None])
        result = svc.list_stock_adjustments(owner_access(), db, 161)
        assert result["count"] == 0
        assert result["adjustments"] == []

    def test_unknown_product_rejected(self):
        from app.core.exceptions import NotFoundError
        from app.models.product import ShopProduct
        from app.services import shopkeeper_service as svc

        db = InventoryMockDB()
        db.queue_first(ShopProduct, [None])
        with pytest.raises(NotFoundError):
            svc.list_stock_adjustments(owner_access(), db, 999)

    def test_cross_shop_product_rejected(self):
        from app.core.exceptions import NotFoundError
        from app.services import shopkeeper_service as svc

        db = InventoryMockDB()
        with pytest.raises(NotFoundError):
            svc.list_stock_adjustments(owner_access(), db, 162)


# ── Counts-only summary view (view=summary) ──────────────────────────────
#
# The shopkeeper HOME screen needs a single number — how many listings are
# STALE — and used to get it from inventory_overview, which ships EVERY
# listing in the shop. `view=summary` answers it with a body whose size does
# not depend on the catalogue, so these tests pin BOTH halves of that promise:
# no rows, and counts identical to the full view.


def _summary_catalog():
    """Two listings for one shop: one STALE, one with no freshness tier.

    Returns ``(db, shop_products, inventories)``. Both shop_products and
    inventories are registered with the mock, because the summary view reads
    them through two separate `query(...).all()` calls.
    """
    from app.models.product import FreshnessStatus, Inventory, ShopProduct

    fresh = make_shop_product(sp_id=101, quantity=0, price=30.0)
    stale = make_shop_product(sp_id=102, quantity=0, price=40.0)
    for sp, tier in ((fresh, None), (stale, FreshnessStatus.STALE)):
        sp.inventory.shop_product_id = sp.id
        sp.inventory.freshness_status = tier

    db = InventoryMockDB()
    db.set_all(ShopProduct, [fresh, stale])
    db.set_all(Inventory, [fresh.inventory, stale.inventory])
    return db, [fresh, stale], [fresh.inventory, stale.inventory]


class TestInventorySummaryView:
    """`inventory_summary` — the counts-only view behind `view=summary`."""

    def test_returns_counts_and_never_any_items(self):
        from app.services import shopkeeper_service as svc

        db, _, _ = _summary_catalog()
        result = svc.inventory_summary(owner_access(), db)

        # The whole point of the view: a home screen renders its badges
        # without the catalogue travelling to the device.
        assert "items" not in result
        assert isinstance(result["summary"], dict)

    def test_counts_the_stale_tier(self):
        from app.services import shopkeeper_service as svc

        db, _, _ = _summary_catalog()
        summary = svc.inventory_summary(owner_access(), db)["summary"]

        assert summary["total"] == 2
        assert summary["stale"] == 1
        assert summary["out_of_stock"] == 2

    def test_counts_match_the_full_overview_view(self):
        """Two views of one catalogue must never disagree.

        The dashboard reads `stale` from the summary and the rest of the
        numbers from the overview, so a divergence would put a badge next to a
        number that contradicts it.
        """
        from app.models.product import Inventory, ShopProduct
        from app.services import shopkeeper_service as svc

        db, products, inventories = _summary_catalog()
        # The overview path resolves one Inventory PER LISTING via `.first()`;
        # the summary path resolves them in a single batched query. Both are
        # fed the same rows so the comparison is about the two code paths, not
        # about the fixtures.
        db.queue_first(Inventory, list(inventories))

        summary = svc.inventory_summary(owner_access(), db)["summary"]
        overview = svc.inventory_overview(owner_access(), db)["summary"]

        # Every NUMBER must agree. The two views deliberately differ in ONE
        # place: the summary reports the restock queue as a size
        # (`needs_attention_count`) where the overview ships up to ten rows
        # (`needs_attention`), because a badge never renders them.
        attention_keys = {"needs_attention", "needs_attention_count"}
        assert {k: v for k, v in summary.items() if k not in attention_keys} == {
            k: v for k, v in overview.items() if k not in attention_keys
        }
        assert summary["needs_attention_count"] == len(overview["needs_attention"])
        assert summary["stale"] == 1

    def test_needs_attention_is_a_count_not_a_row_list(self):
        """Counts-only ships the SIZE of the restock queue, never the rows."""
        from app.services import shopkeeper_service as svc

        db, _, _ = _summary_catalog()
        summary = svc.inventory_summary(owner_access(), db)["summary"]

        assert "needs_attention" not in summary
        assert summary["needs_attention_count"] == 2

    def test_empty_shop_is_all_zeroes(self):
        """A brand-new shop still gets a complete, renderable payload."""
        from app.models.product import Inventory, ShopProduct
        from app.services import shopkeeper_service as svc

        db = InventoryMockDB()
        db.set_all(ShopProduct, [])
        db.set_all(Inventory, [])

        summary = svc.inventory_summary(owner_access(), db)["summary"]

        assert summary["total"] == 0
        assert summary["stale"] == 0
        assert summary["inactive"] == 0
