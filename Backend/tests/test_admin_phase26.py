"""Phase 26 - Complete Admin Platform tests.

Covers against a real in-memory SQLite database:
  * Dashboard metrics aggregation
  * Customers / users management (list, search, filter, pagination,
    suspend/ban/activate business rules)
  * Shops management (verify/reject/suspend/reactivate lifecycle rules,
    search/filter, bulk actions)
  * Products management (bulk approve/reject/archive, authorized edits,
    listing review queue)
  * Categories / Brands CRUD + referential-integrity rules
  * Inventory monitoring (stale, missing prices, availability anomalies,
    sync failures)
  * Offers / Subscriptions / Payments admin operations
  * Reports (all six types) + Analytics
  * Complaints workflow rules
  * Notifications broadcast/targeting
  * System settings + Feature flags (secret masking, validation)
  * Audit trail generation for every critical operation
  * Admin RBAC (role restrictions, sub-role catalogs)
VERIFY - admins can control the platform without bypassing business rules.
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
from sqlalchemy import create_engine, event  # noqa: E402
from sqlalchemy.orm import Session as _Session, sessionmaker  # noqa: E402

from app.core.config import settings  # noqa: E402

settings.RATE_LIMIT_ENABLED = False

from app.core.admin_permissions import (  # noqa: E402
    ADMIN_MODULE_PERMISSIONS,
    ADMIN_SUBROLE_PERMISSIONS,
    describe_admin_role,
    effective_admin_permissions,
    full_admin_keys,
    has_admin_permission,
    user_is_admin_family,
)
from app.core.exceptions import ConflictError, NotFoundError, ValidationError  # noqa: E402
from app.models.base import Base  # noqa: E402
from app.services import admin_service  # noqa: E402

UTC = timezone.utc


# Adapt PostGIS Geography columns for plain SQLite (shared, reversible helper).
from tests.geo_compat import strip_geo_columns  # noqa: E402

strip_geo_columns()


# Replace literal "now()" server defaults / onupdates with Python-side
# callables so SQLite stores real timestamps (mirrors Postgres semantics).
def _portable_timestamp_defaults():
    from sqlalchemy import ColumnDefault

    def _now(ctx=None):
        return datetime.utcnow()

    for table in Base.metadata.tables.values():
        for col in table.columns:
            sd = getattr(col, "server_default", None)
            sd_arg = getattr(sd, "arg", None)
            if sd_arg == "now()":
                if col.default is None:
                    col.default = ColumnDefault(_now)
                col.server_default = None
            elif isinstance(sd_arg, str) and sd_arg.lower() == "false":
                if col.default is None and (
                    getattr(getattr(col.type, "python_type", None), "__name__", "")
                    == "bool"
                ):
                    col.default = ColumnDefault(False)
                col.server_default = None
            ou = getattr(col, "onupdate", None)
            if ou is not None and getattr(ou, "arg", None) == "now()":
                col.onupdate = ColumnDefault(_now, for_update=True)


_portable_timestamp_defaults()


# Tables required by the admin platform test matrix.
from app.models.admin import (  # noqa: E402
    AdminAction,
    AdminNote,
    AuditLog,
    Complaint,
    ProductApproval,
    Report,
)
from app.models.product import (  # noqa: E402
    Brand,
    Category,
    Inventory,
    Offer,
    ProductIdentifier,
    ProductMaster,
    ProductVariant,
    ShopProduct,
)
from app.models.search import SearchEvent, SearchHistory  # noqa: E402
from app.models.notification import Notification  # noqa: E402
from app.models.analytics import ProductClick, ProductView, ShopView  # noqa: E402
from app.models.pos import POSSyncJob  # noqa: E402
from app.models.inventory_import import InventoryImportJob  # noqa: E402
from app.models.session import AuthSession, TokenBlacklist  # noqa: E402
from app.models.shop import Shop  # noqa: E402
from app.models.subscription import Payment, Subscription, SubscriptionPlan  # noqa: E402
from app.models.system import FeatureFlag, SystemSetting  # noqa: E402
from app.models.user import User  # noqa: E402
from app.models.role import Permission, Role, role_permissions  # noqa: E402

TABLES = [
    Role.__table__,
    Permission.__table__,
    role_permissions,
    User.__table__,
    Shop.__table__,
    Category.__table__,
    Brand.__table__,
    ProductMaster.__table__,
    ProductVariant.__table__,
    ProductIdentifier.__table__,
    ShopProduct.__table__,
    Inventory.__table__,
    Offer.__table__,
    SubscriptionPlan.__table__,
    Subscription.__table__,
    Payment.__table__,
    Complaint.__table__,
    Report.__table__,
    ProductApproval.__table__,
    AdminAction.__table__,
    AdminNote.__table__,
    AuditLog.__table__,
    SystemSetting.__table__,
    FeatureFlag.__table__,
    SearchEvent.__table__,
    SearchHistory.__table__,
    POSSyncJob.__table__,
    InventoryImportJob.__table__,
    Notification.__table__,
    ProductView.__table__,
    ShopView.__table__,
    ProductClick.__table__,
    AuthSession.__table__,
    TokenBlacklist.__table__,
]


@pytest.fixture()
def db():
    from sqlalchemy.pool import StaticPool

    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine, tables=TABLES)
    SessionLocal = sessionmaker(bind=engine)
    session = SessionLocal()
    yield session
    session.close()
    engine.dispose()


# -- Entity factories -------------------------------------------------------
_counter = {"n": 0}


def _next_id():
    _counter["n"] += 1
    return _counter["n"]


def make_role(db, name="admin"):
    from app.models.role import Role

    role = db.query(Role).filter(Role.name == name).first()
    if role is None:
        role = Role(name=name, description=name)
        db.add(role)
        db.flush()
    return role


def make_user(db, role_name="customer", status="ACTIVE", name=None, phone=None):
    from app.models.user import User, UserStatus

    n = _next_id()
    role = make_role(db, role_name)
    user = User(
        phone_number=phone or f"+91123456{n:04d}",
        name=name or f"User {n}",
        role_id=role.id,
        status=UserStatus(status),
        is_active=status == "ACTIVE",
    )
    db.add(user)
    db.flush()
    return user


def make_admin(db):
    return make_user(db, role_name="admin", name="Root Admin")


def make_shop(db, name=None, status="PENDING_VERIFICATION", lat=25.59, lon=85.13):
    from app.models.shop import Shop, ShopStatus

    n = _next_id()
    shop = Shop(
        name=name or f"Shop {n}",
        description=f"desc {n}",
        status=ShopStatus(status),
        latitude=lat,
        longitude=lon,
    )
    db.add(shop)
    db.flush()
    return shop


def make_category(db, name=None):
    from app.models.product import Category

    n = _next_id()
    cat = Category(name=name or f"Cat {n}", slug=(name or f"cat-{n}").lower().replace(" ", "-"))
    db.add(cat)
    db.flush()
    return cat


def make_brand(db, name=None):
    from app.models.product import Brand

    n = _next_id()
    brand = Brand(name=name or f"Brand {n}", slug=(name or f"brand-{n}").lower().replace(" ", "-"))
    db.add(brand)
    db.flush()
    return brand


def make_product(db, category=None, brand=None, status="APPROVED", name=None):
    from app.models.product import ProductMaster, ProductStatus

    n = _next_id()
    pm = ProductMaster(
        name=name or f"Product {n}",
        slug=f"product-{n}",
        status=ProductStatus(status),
        category_id=category.id if category else None,
        brand_id=brand.id if brand else None,
    )
    db.add(pm)
    db.flush()
    return pm


def make_listing(db, shop, product, price="10.00", available=True, qty=5,
                 stock_status="IN_STOCK", listing_status="ACTIVE"):
    """Create a ShopProduct + Inventory pair."""
    from app.models.product import Inventory, InventorySource, ShopProduct, StockStatus

    sp = ShopProduct(
        shop_id=shop.id,
        product_master_id=product.id,
        price=price,
        is_available=available,
        stock_status=StockStatus(stock_status),
        status=listing_status,
    )
    db.add(sp)
    db.flush()
    inv = Inventory(
        shop_product_id=sp.id,
        quantity=qty,
        is_available=available,
        stock_status=StockStatus(stock_status),
        last_updated_source=InventorySource.MANUAL,
    )
    db.add(inv)
    db.flush()
    return sp, inv


def make_offer(db, shop, status="ACTIVE", title=None):
    from datetime import date

    from app.models.product import Offer, OfferStatus, OfferType

    offer = Offer(
        shop_id=shop.id,
        title=title or f"Offer {_next_id()}",
        description="test",
        offer_type=OfferType.PERCENTAGE_DISCOUNT,
        discount_percentage=10.0,
        status=OfferStatus(status),
        start_date=date(2026, 1, 1),
        end_date=date(2026, 12, 31),
    )
    db.add(offer)
    db.flush()
    return offer


def make_subscription_with_payment(db, user, amount=499.0,
                                   pay_status="SUCCESS", sub_status="ACTIVE"):
    from app.models.subscription import (
        Payment, Subscription, SubscriptionPlan, SubscriptionStatus,
    )

    plan = SubscriptionPlan(
        name=f"Plan {_next_id()}", price_monthly=amount, price_annual=amount * 10
    )
    db.add(plan)
    db.flush()
    sub = Subscription(user_id=user.id, plan_id=plan.id, status=SubscriptionStatus(sub_status))
    db.add(sub)
    db.flush()
    pay = Payment(
        subscription_id=sub.id,
        payment_provider="RAZORPAY",
        payment_method="UPI",
        amount=amount,
        status=pay_status,
        paid_at=datetime.now(UTC) if pay_status == "SUCCESS" else None,
    )
    db.add(pay)
    db.flush()
    return plan, sub, pay


def make_complaint(db, status="OPEN", subject=None):
    from app.models.admin import Complaint, ComplaintStatus

    n = _next_id()
    c = Complaint(
        complainant_user_id=None,
        complaint_type="WRONG_PRICE",
        subject=subject or f"Complaint {n}",
        description="details",
        status=ComplaintStatus(status),
        priority="MEDIUM",
    )
    db.add(c)
    db.flush()
    return c


# -- Dashboard ---------------------------------------------------------------
class TestDashboardMetrics:
    def test_empty_platform_zeros(self, db):
        metrics = admin_service.dashboard_metrics(db)
        assert metrics["total_customers"] == 0
        assert metrics["total_shops"] == 0
        assert metrics["total_products"] == 0
        assert metrics["search_success_rate"] == 0.0

    def test_seeded_metrics(self, db):
        make_user(db, "customer")
        make_user(db, "customer")
        active_shop = make_shop(db, status="ACTIVE")
        make_shop(db, status="PENDING_VERIFICATION")
        cat = make_category(db)
        pm = make_product(db, category=cat)
        make_listing(db, active_shop, pm)

        from app.models.search import SearchEvent

        db.add(SearchEvent(query="milk", event_type="SEARCH", result_count=3))
        db.add(SearchEvent(query="void query", event_type="SEARCH", result_count=0))
        db.flush()

        metrics = admin_service.dashboard_metrics(db)

        assert metrics["total_customers"] == 2  # 2 customers
        assert metrics["total_shops"] == 2
        assert metrics["active_shops"] == 1
        assert metrics["pending_verification"] == 1
        assert metrics["total_products"] == 1
        assert metrics["total_inventory_records"] == 1
        assert metrics["total_searches"] == 2
        assert metrics["search_success_rate"] == 0.5
        assert metrics["popular_categories"][0]["name"].startswith("Cat")

    def test_subscription_metrics(self, db):
        user = make_user(db, "shopkeeper")
        make_subscription_with_payment(db, user, amount=499.0, pay_status="SUCCESS")
        make_subscription_with_payment(db, user, amount=100.0, pay_status="FAILED",
                                       sub_status="CANCELED")
        metrics = admin_service.dashboard_metrics(db)
        assert metrics["active_subscriptions"] == 1
        assert metrics["total_subscription_revenue"] == 499.0

# -- Users / customers management -------------------------------------------
class TestUserManagement:
    def test_list_pagination_exact(self, db):
        for _ in range(6):
            make_user(db, "customer")
        page1, total = admin_service.list_users(db, limit=2, offset=0)
        page2, _ = admin_service.list_users(db, limit=2, offset=2)
        assert total == 6
        assert len(page1) == 2 and len(page2) == 2
        assert page1[0]["id"] != page2[0]["id"]

    def test_search_and_role_filter(self, db):
        make_user(db, "customer", name="Alice Query")
        make_user(db, "shopkeeper", name="Bob")
        items, total = admin_service.list_users(db, search="Alice")
        assert total == 1 and items[0]["name"] == "Alice Query"
        items, total = admin_service.list_users(db, role_name="shopkeeper")
        assert total == 1 and items[0]["name"] == "Bob"

    def test_status_filter_invalid_raises(self, db):
        with pytest.raises(ValidationError):
            admin_service.list_users(db, status="NOT_A_STATUS")

    def test_suspend_requires_reason(self, db):
        admin = make_admin(db)
        target = make_user(db, "customer")
        with pytest.raises(ValidationError):
            admin_service.update_user_status(
                db, admin_user=admin, user_id=target.id, action="SUSPEND"
            )

    def test_cannot_suspend_admin(self, db):
        admin = make_admin(db)
        other_admin = make_user(db, "admin", name="Second Admin")
        with pytest.raises(ValidationError):
            admin_service.update_user_status(
                db, admin_user=admin, user_id=other_admin.id,
                action="SUSPEND", reason="test",
            )

    def test_ban_then_activate_roundtrip_audited(self, db):
        from app.models.admin import AdminAction, AuditLog

        admin = make_admin(db)
        target = make_user(db, "customer")

        updated = admin_service.update_user_status(
            db, admin_user=admin, user_id=target.id, action="BAN", reason="fraud"
        )
        assert updated["status"] == "BANNED"
        assert target.is_active is False

        updated = admin_service.update_user_status(
            db, admin_user=admin, user_id=target.id, action="ACTIVATE"
        )
        assert updated["status"] == "ACTIVE"
        assert target.is_active is True

        logs = (
            db.query(AuditLog).filter(AuditLog.entity_type == "USER").all()
        )
        assert len(logs) == 2
        actions = db.query(AdminAction).filter(AdminAction.target_type == "USER").all()
        assert len(actions) == 2


# -- Admin RBAC ---------------------------------------------------------------
class TestAdminPermissions:
    def test_full_catalog_nonempty_and_unique(self):
        keys = full_admin_keys()
        assert len(keys) >= 40
        assert "verify:shop" in keys
        assert "approve:product" in keys
        assert "update:system_setting" in keys

    def test_subroles_are_strict_subsets(self):
        full = full_admin_keys()
        for role, catalog in ADMIN_SUBROLE_PERMISSIONS.items():
            sub = effective_admin_permissions(role)
            assert sub < full, f"{role} must be a strict subset"
            assert sub == {f"{a}:{r}" for r, a in catalog}

    def test_unknown_role_has_no_permissions(self):
        assert effective_admin_permissions("customer") == set()
        assert effective_admin_permissions(None) == set()
        assert not user_is_admin_family(type("U", (), {"role": None})())

    def test_has_permission_key_format(self):
        perms = effective_admin_permissions("admin_moderator")
        assert has_admin_permission(perms, "shop", "verify")
        assert not has_admin_permission(perms, "system_setting", "update")

    def test_describe_role_levels(self):
        assert describe_admin_role("admin")["level"] == "SUPER"
        assert describe_admin_role("admin_support")["level"] == "SUB"
        assert describe_admin_role("customer")["level"] == "none"

    def test_module_catalog_matches_subrole_unions(self):
        # Every sub-role permission must exist in the master catalog.
        master = {f"{a}:{r}" for r, a in ADMIN_MODULE_PERMISSIONS}
        for catalog in ADMIN_SUBROLE_PERMISSIONS.values():
            for resource, action in catalog:
                assert f"{action}:{resource}" in master

# -- Shop management ----------------------------------------------------------
class TestShopLifecycle:
    def test_verify_pending_shop(self, db):
        admin = make_admin(db)
        shop = make_shop(db, status="PENDING_VERIFICATION")
        result = admin_service.shop_verification_action(
            db, admin_user=admin, shop_id=shop.id, decision="VERIFY"
        )
        assert result["status"] == "VERIFIED"
        assert shop.verified_at is not None

    def test_reject_requires_reason(self, db):
        admin = make_admin(db)
        shop = make_shop(db, status="PENDING_VERIFICATION")
        with pytest.raises(ValidationError):
            admin_service.shop_verification_action(
                db, admin_user=admin, shop_id=shop.id, decision="REJECT"
            )

    def test_reject_sets_reason(self, db):
        admin = make_admin(db)
        shop = make_shop(db, status="DOCUMENTS_SUBMITTED")
        result = admin_service.shop_verification_action(
            db, admin_user=admin, shop_id=shop.id, decision="REJECT", reason="bad docs"
        )
        assert result["status"] == "REJECTED"
        assert shop.rejection_reason == "bad docs"

    def test_suspend_only_from_verified_or_active(self, db):
        admin = make_admin(db)
        pending = make_shop(db, status="PENDING_VERIFICATION")
        with pytest.raises(ConflictError):
            admin_service.shop_verification_action(
                db, admin_user=admin, shop_id=pending.id, decision="SUSPEND", reason="x"
            )
        active = make_shop(db, status="ACTIVE")
        result = admin_service.shop_verification_action(
            db, admin_user=admin, shop_id=active.id, decision="SUSPEND", reason="policy"
        )
        assert result["status"] == "SUSPENDED"
        assert active.is_accepting_orders is False
        assert active.suspension_reason == "policy"

    def test_reactivate_only_from_suspended(self, db):
        admin = make_admin(db)
        active = make_shop(db, status="ACTIVE")
        with pytest.raises(ConflictError):
            admin_service.shop_verification_action(
                db, admin_user=admin, shop_id=active.id, decision="REACTIVATE"
            )
        suspended = make_shop(db, status="SUSPENDED")
        result = admin_service.shop_verification_action(
            db, admin_user=admin, shop_id=suspended.id, decision="REACTIVATE"
        )
        assert result["status"] == "ACTIVE"
        assert suspended.is_accepting_orders is True

    def test_invalid_decision_and_missing_shop(self, db):
        admin = make_admin(db)
        shop = make_shop(db)
        with pytest.raises(ValidationError):
            admin_service.shop_verification_action(
                db, admin_user=admin, shop_id=shop.id, decision="NUKE"
            )
        with pytest.raises(NotFoundError):
            admin_service.shop_verification_action(
                db, admin_user=admin, shop_id=99999, decision="VERIFY"
            )

    def test_list_filter_and_search(self, db):
        make_shop(db, name="Alpha Mart", status="ACTIVE")
        make_shop(db, name="Beta Store", status="SUSPENDED")
        items, total = admin_service.list_shops_admin(db, search="Beta")
        assert total == 1 and items[0]["name"] == "Beta Store"
        items, total = admin_service.list_shops_admin(db, status="ACTIVE")
        assert total == 1
        page, total = admin_service.list_shops_admin(db, limit=1, offset=1)
        assert total == 2 and len(page) == 1

    def test_every_transition_writes_audit_pair(self, db):
        from app.models.admin import AdminAction, AuditLog

        admin = make_admin(db)
        shop = make_shop(db, status="PENDING_VERIFICATION")
        admin_service.shop_verification_action(
            db, admin_user=admin, shop_id=shop.id, decision="VERIFY"
        )
        admin_service.shop_verification_action(
            db, admin_user=admin, shop_id=shop.id, decision="SUSPEND", reason="r"
        )
        logs = db.query(AuditLog).filter(AuditLog.entity_type == "SHOP").all()
        assert [l.action for l in logs] == ["VERIFY", "SUSPEND"]
        actions = db.query(AdminAction).filter(AdminAction.target_type == "SHOP").all()
        assert len(actions) == 2

    def test_bulk_action_mixed_statuses(self, db):
        admin = make_admin(db)
        ok1 = make_shop(db, status="VERIFIED")
        ok2 = make_shop(db, status="ACTIVE")
        skip = make_shop(db, status="PENDING_VERIFICATION")
        result = admin_service.bulk_shop_action(
            db, admin_user=admin, action="SUSPEND", reason="bulk",
            shop_ids=[ok1.id, ok2.id, skip.id, 987654],
        )
        assert sorted(result["updated"]) == sorted([ok1.id, ok2.id])
        assert result["skipped"] == [skip.id]
        assert result["missing"] == [987654]
        # skipped shop untouched by the bulk run
        assert str(skip.status.value) == "PENDING_VERIFICATION"

# -- Products -----------------------------------------------------------------
class TestProductManagement:
    def test_bulk_approve_pending_and_skip_approved(self, db):
        admin = make_admin(db)
        p1 = make_product(db, status="PENDING_REVIEW")
        p2 = make_product(db, status="APPROVED")
        result = admin_service.product_bulk_action(
            db, admin_user=admin, action="APPROVE", product_ids=[p1.id, p2.id, 424242]
        )
        assert result["updated"] == [p1.id]
        assert result["skipped"] == [p2.id]
        assert result["missing"] == [424242]

    def test_archive_then_activate_roundtrip(self, db):
        admin = make_admin(db)
        p = make_product(db, status="APPROVED")
        res = admin_service.product_bulk_action(
            db, admin_user=admin, action="ARCHIVE", product_ids=[p.id]
        )
        assert res["updated"] == [p.id]
        assert str(p.status.value) == "ARCHIVED"
        # REJECT from ARCHIVED is illegal
        res2 = admin_service.product_bulk_action(
            db, admin_user=admin, action="REJECT", product_ids=[p.id]
        )
        assert res2["skipped"] == [p.id]
        res3 = admin_service.product_bulk_action(
            db, admin_user=admin, action="ACTIVATE", product_ids=[p.id]
        )
        assert res3["updated"] == [p.id]
        assert str(p.status.value) == "APPROVED"

    def test_update_authorized_fields_only_audited(self, db):
        from app.models.admin import AuditLog

        admin = make_admin(db)
        cat = make_category(db)
        brand = make_brand(db)
        p = make_product(db)
        old_name = p.name
        updated = admin_service.update_product_admin(
            db,
            admin_user=admin,
            product_id=p.id,
            updates={
                "name": "Renamed Product",
                "description": "new desc",
                "category_id": cat.id,
                "brand_id": brand.id,
                "slug": "hacker-override",  # unauthorized field - ignored
            },
        )
        assert updated["name"] == "Renamed Product"
        assert p.slug != "hacker-override"
        log = db.query(AuditLog).filter(AuditLog.entity_type == "PRODUCT").first()
        assert log.old_values["name"] == old_name
        assert "slug" not in log.new_values

    def test_update_missing_product(self, db):
        admin = make_admin(db)
        with pytest.raises(NotFoundError):
            admin_service.update_product_admin(
                db, admin_user=admin, product_id=555555,
                updates={"name": "ghost"},
            )

    def test_listing_review_flow(self, db):
        from app.models.admin import ProductApproval

        admin = make_admin(db)
        shop = make_shop(db, status="ACTIVE")
        pm = make_product(db, status="PENDING_REVIEW")
        sp, _inv = make_listing(
            db, shop, pm, price="99.00", listing_status="PENDING_REVIEW"
        )

        items, total = admin_service.product_approval_queue(db)
        assert total == 1 and items[0]["id"] == sp.id
        assert items[0]["product_name"] == pm.name
        assert items[0]["shop_name"] == shop.name

        # REJECT requires notes
        with pytest.raises(ValidationError):
            admin_service.review_shop_product(
                db, admin_user=admin, shop_product_id=sp.id, decision="REJECT"
            )

        result = admin_service.review_shop_product(
            db, admin_user=admin, shop_product_id=sp.id,
            decision="APPROVE", review_notes="looks fine",
        )
        assert result["status"] == "APPROVED"
        # master auto-promoted to keep the shared catalog consistent
        assert str(pm.status.value) == "APPROVED"
        approval = db.query(ProductApproval).first()
        assert approval is not None and approval.reviewed_by == admin.id

    def test_double_review_conflict(self, db):
        admin = make_admin(db)
        shop = make_shop(db, status="ACTIVE")
        pm = make_product(db, status="APPROVED")
        sp, _inv = make_listing(db, shop, pm, listing_status="PENDING_REVIEW")
        admin_service.review_shop_product(
            db, admin_user=admin, shop_product_id=sp.id, decision="APPROVE"
        )
        with pytest.raises(ConflictError):
            admin_service.review_shop_product(
                db, admin_user=admin, shop_product_id=sp.id, decision="REJECT",
                review_notes="second try",
            )

# -- Categories & brands ------------------------------------------------------
class TestCategoriesBrands:
    def test_create_and_duplicate_conflicts(self, db):
        admin = make_admin(db)
        cat = admin_service.create_category(
            db, admin_user=admin, data={"name": "Grocery", "slug": "grocery"}
        )
        assert cat["name"] == "Grocery"
        with pytest.raises(ConflictError):
            admin_service.create_category(
                db, admin_user=admin, data={"name": "Grocery", "slug": "other"}
            )
        with pytest.raises(ConflictError):
            admin_service.create_category(
                db, admin_user=admin, data={"name": "Other", "slug": "grocery"}
            )

    def test_update_category(self, db):
        admin = make_admin(db)
        cat = make_category(db, name="Old Name")
        updated = admin_service.update_category(
            db, admin_user=admin, category_id=cat.id,
            updates={"name": "New Name", "sort_order": 5},
        )
        assert updated["name"] == "New Name"
        with pytest.raises(NotFoundError):
            admin_service.update_category(
                db, admin_user=admin, category_id=999999, updates={"name": "X"}
            )

    def test_delete_blocked_while_referenced(self, db):
        admin = make_admin(db)
        cat = make_category(db)
        pm = make_product(db, category=cat)
        with pytest.raises(ConflictError):
            admin_service.delete_category(db, admin_user=admin, category_id=cat.id)
        # remove the product reference (soft-delete it) -> delete succeeds
        pm.is_deleted = True
        db.flush()
        result = admin_service.delete_category(db, admin_user=admin, category_id=cat.id)
        assert result["deleted"] is True
        assert cat.is_deleted is True

    def test_brand_crud(self, db):
        admin = make_admin(db)
        brand = admin_service.create_brand(
            db, admin_user=admin, data={"name": "Acme", "slug": "acme"}
        )
        assert brand["slug"] == "acme"
        with pytest.raises(ConflictError):
            admin_service.create_brand(
                db, admin_user=admin, data={"name": "Acme2", "slug": "acme"}
            )
        updated = admin_service.update_brand(
            db, admin_user=admin, brand_id=brand["id"],
            updates={"description": "updated"},
        )
        assert updated["description"] == "updated"
        items = admin_service.list_brands_admin(db)
        assert any(b["id"] == brand["id"] for b in items)

    def test_identifiers_listing_pagination(self, db):
        from app.models.product import IdentifierType, ProductIdentifier

        pm = make_product(db)
        for i in range(5):
            db.add(ProductIdentifier(
                product_master_id=pm.id,
                identifier_type=IdentifierType.EAN,
                identifier_value=f"890123456789{i}",
            ))
        db.flush()
        page, total = admin_service.list_product_identifiers(db, limit=3, offset=0)
        assert total == 5 and len(page) == 3
        scoped, scoped_total = admin_service.list_product_identifiers(
            db, product_master_id=pm.id
        )
        assert scoped_total == 5

# -- Inventory monitoring -----------------------------------------------------
class TestInventoryMonitoring:
    def test_stale_detection_by_age_and_flag(self, db):
        shop = make_shop(db, status="ACTIVE")
        pm_old = make_product(db)
        sp_old, inv_old = make_listing(db, shop, pm_old)
        old_ts = datetime.now(UTC) - timedelta(hours=96)
        sp_old.last_inventory_update = old_ts
        inv_old.last_synced_at = None
        inv_old.freshness_status = None

        pm_fresh = make_product(db)
        sp_fresh, inv_fresh = make_listing(db, shop, pm_fresh)
        sp_fresh.last_inventory_update = datetime.now(UTC)
        inv_fresh.freshness_status = None

        # explicitly flagged stale even though recently touched
        pm_flagged = make_product(db)
        sp_flag, inv_flag = make_listing(db, shop, pm_flagged)
        sp_flag.last_inventory_update = datetime.now(UTC)
        inv_flag.freshness_status = "STALE"

        db.flush()
        items, total = admin_service.stale_inventory(db, threshold_hours=48)
        ids = {i["shop_product_id"] for i in items}
        assert total == 2
        assert sp_old.id in ids and sp_flag.id in ids
        assert sp_fresh.id not in ids
        stale_row = next(i for i in items if i["shop_product_id"] == sp_old.id)
        assert stale_row["stale_hours"] >= 95

    def test_missing_prices(self, db):
        shop = make_shop(db, status="ACTIVE")
        pm_ok = make_product(db)
        make_listing(db, shop, pm_ok, price="49.00")
        pm_zero = make_product(db)
        sp_zero, _ = make_listing(db, shop, pm_zero, price="0")
        items, total = admin_service.missing_prices(db)
        assert total == 1
        assert items[0]["shop_product_id"] == sp_zero.id
        assert items[0]["anomaly_type"] == "MISSING_PRICE"

    def test_availability_anomalies_both_directions(self, db):
        shop = make_shop(db, status="ACTIVE")
        # available but no stock
        pm_a = make_product(db)
        sp_a, _inv_a = make_listing(db, shop, pm_a, price="10", available=True, qty=0)
        # out-of-stock flag but holding units
        pm_b = make_product(db)
        sp_b, _inv_b = make_listing(
            db, shop, pm_b, price="20", available=False, qty=7,
            stock_status="OUT_OF_STOCK",
        )
        # healthy listing
        pm_c = make_product(db)
        make_listing(db, shop, pm_c, price="30", available=True, qty=4)
        items, total = admin_service.availability_anomalies(db)
        ids = {i["shop_product_id"] for i in items}
        assert total == 2
        assert sp_a.id in ids and sp_b.id in ids

    def test_sync_failures_from_pos_and_import(self, db):
        from app.models.inventory_import import InventoryImportJob
        from app.models.pos import POSSyncJob, POSSyncStatus

        shop = make_shop(db, status="ACTIVE")
        db.add(POSSyncJob(
            shop_id=shop.id, sync_type="FULL",
            status=POSSyncStatus.FAILED, items_failed=3,
            error_summary="provider timeout",
        ))
        db.add(InventoryImportJob(
            shop_id=shop.id, filename="stock.xlsx",
            status="PARTIAL", failed_rows=2, error_message="row errors",
        ))
        db.flush()
        items, total = admin_service.sync_failures(db)
        assert total == 2
        sources = {i["source"] for i in items}
        assert sources == {"POS_SYNC", "EXCEL_IMPORT"}
        pos_item = next(i for i in items if i["source"] == "POS_SYNC")
        assert pos_item["shop_name"] == shop.name
        assert pos_item["items_failed"] == 3

    def test_monitoring_summary_counts(self, db):
        shop = make_shop(db, status="ACTIVE")
        pm = make_product(db)
        make_listing(db, shop, pm, price="0", qty=0)
        summary = admin_service.inventory_monitoring_summary(db)
        assert summary["missing_price_count"] == 1
        assert summary["availability_anomaly_count"] == 1

# -- Offers / subscriptions / payments ---------------------------------------
class TestOffersSubscriptionsPayments:
    def test_offer_transitions(self, db):
        admin = make_admin(db)
        shop = make_shop(db, status="ACTIVE")
        offer = make_offer(db, shop, status="ACTIVE")

        result = admin_service.update_offer_status(
            db, admin_user=admin, offer_id=offer.id, new_status="PAUSED"
        )
        assert result["status"] == "PAUSED"
        result = admin_service.update_offer_status(
            db, admin_user=admin, offer_id=offer.id, new_status="ACTIVE"
        )
        assert result["status"] == "ACTIVE"

    def test_expired_offer_cannot_reactivate(self, db):
        admin = make_admin(db)
        shop = make_shop(db, status="ACTIVE")
        offer = make_offer(db, shop, status="EXPIRED")
        with pytest.raises(ConflictError):
            admin_service.update_offer_status(
                db, admin_user=admin, offer_id=offer.id, new_status="ACTIVE"
            )

    def test_invalid_offer_status(self, db):
        admin = make_admin(db)
        shop = make_shop(db, status="ACTIVE")
        offer = make_offer(db, shop, status="ACTIVE")
        with pytest.raises(ValidationError):
            admin_service.update_offer_status(
                db, admin_user=admin, offer_id=offer.id, new_status="WARP_SPEED"
            )

    def test_subscription_update_audited(self, db):
        from app.models.admin import AuditLog

        admin = make_admin(db)
        user = make_user(db, "shopkeeper")
        plan, sub, _pay = make_subscription_with_payment(db, user)
        result = admin_service.update_subscription_admin(
            db, admin_user=admin, subscription_id=sub.id,
            updates={"status": "CANCELED", "is_auto_renew": False},
        )
        assert result["status"] == "CANCELED"
        assert sub.is_auto_renew is False
        log = (
            db.query(AuditLog).filter(AuditLog.entity_type == "SUBSCRIPTION").first()
        )
        assert log.new_values["status"] == "CANCELED"

    def test_subscription_invalid_status(self, db):
        admin = make_admin(db)
        user = make_user(db, "shopkeeper")
        _plan, sub, _pay = make_subscription_with_payment(db, user)
        with pytest.raises(ValidationError):
            admin_service.update_subscription_admin(
                db, admin_user=admin, subscription_id=sub.id,
                updates={"status": "WARP"},
            )

    def test_payment_filters(self, db):
        user = make_user(db, "shopkeeper")
        make_subscription_with_payment(db, user, amount=100.0, pay_status="SUCCESS")
        make_subscription_with_payment(db, user, amount=200.0, pay_status="REFUNDED")
        items, total = admin_service.list_payments_admin(db, status="success")
        assert total == 1 and float(items[0]["amount"]) == 100.0
        items, total = admin_service.list_payments_admin(db, method="upi")
        assert total == 2
        items, total = admin_service.list_payments_admin(db, provider="STRIPE")
        assert total == 0

    def test_subscription_listing_filters(self, db):
        user = make_user(db, "shopkeeper")
        make_subscription_with_payment(db, user, sub_status="ACTIVE")
        make_subscription_with_payment(
            db, user, amount=99.0, pay_status="PENDING", sub_status="TRIALING"
        )
        items, total = admin_service.list_subscriptions_admin(db, status="ACTIVE")
        assert total == 1

# -- Reports -------------------------------------------------------------------
class TestReports:
    def test_generate_all_report_types(self, db):
        admin = make_admin(db)
        shop = make_shop(db, status="ACTIVE")
        cat = make_category(db)
        pm = make_product(db, category=cat)
        make_listing(db, shop, pm)
        user = make_user(db, "customer")
        make_subscription_with_payment(db, user)

        from app.models.search import SearchEvent

        db.add(SearchEvent(query="milk", event_type="SEARCH", result_count=5))
        db.flush()

        for rtype in ("SEARCH", "INVENTORY", "SHOPS", "PRODUCTS", "USERS", "REVENUE"):
            report = admin_service.generate_report(
                db, admin_user=admin, report_type=rtype,
                report_name=f"{rtype} monthly",
            )
            assert report["status"] == "READY", f"{rtype} should be READY"
            payload = report["parameters_json"]["payload"]
            if rtype == "SEARCH":
                assert payload["total_searches"] == 1
                assert payload["top_queries"][0]["query"] == "milk"
            elif rtype == "INVENTORY":
                assert payload["total_inventory_records"] >= 1
            elif rtype == "SHOPS":
                assert payload["total_shops"] >= 1
            elif rtype == "USERS":
                assert payload["total_users"] >= 2
            elif rtype == "REVENUE":
                assert payload["net_revenue"] >= 499.0

    def test_unknown_report_type_rejected(self, db):
        admin = make_admin(db)
        with pytest.raises(ValidationError):
            admin_service.generate_report(
                db, admin_user=admin, report_type="HOROSCOPES", report_name="bad",
            )

    def test_reports_listing_filter_and_audit(self, db):
        from app.models.admin import AuditLog

        admin = make_admin(db)
        admin_service.generate_report(
            db, admin_user=admin, report_type="REVENUE", report_name="rev-1"
        )
        admin_service.generate_report(
            db, admin_user=admin, report_type="USERS", report_name="usr-1"
        )
        items, total = admin_service.list_reports(db, report_type="REVENUE")
        assert total == 1 and items[0]["report_name"] == "rev-1"
        logs = db.query(AuditLog).filter(AuditLog.entity_type == "REPORT").all()
        assert len(logs) == 2


# -- Analytics ------------------------------------------------------------------
class TestAnalytics:
    def test_analytics_summary(self, db):
        from app.models.analytics import ProductClick, ProductView, ShopView
        from app.models.search import SearchEvent

        db.add(SearchEvent(query="milk", event_type="SEARCH", result_count=4))
        db.add(SearchEvent(query="void", event_type="SEARCH", result_count=0))
        pm = make_product(db)
        shop = make_shop(db)
        db.add(ProductView(product_master_id=pm.id))
        db.add(ShopView(shop_id=shop.id))
        db.add(ProductClick(product_master_id=pm.id, source="SEARCH"))
        db.flush()
        summary = admin_service.analytics_summary(db)
        assert summary["total_searches"] == 2
        assert summary["zero_result_searches"] == 1
        assert summary["total_product_views"] == 1
        assert summary["total_shop_views"] == 1
        assert summary["total_clicks"] == 1

# -- Complaints -----------------------------------------------------------------
class TestComplaints:
    def test_resolution_requires_notes(self, db):
        admin = make_admin(db)
        c = make_complaint(db)
        with pytest.raises(ValidationError):
            admin_service.update_complaint(
                db, admin_user=admin, complaint_id=c.id, updates={"status": "RESOLVED"}
            )

    def test_resolve_sets_timestamp(self, db):
        from app.models.admin import AuditLog

        admin = make_admin(db)
        c = make_complaint(db)
        result = admin_service.update_complaint(
            db, admin_user=admin, complaint_id=c.id,
            updates={"status": "RESOLVED", "resolution_notes": "refunded customer"},
        )
        assert result["status"] == "RESOLVED"
        assert c.resolved_at is not None
        log = (
            db.query(AuditLog).filter(AuditLog.entity_type == "COMPLAINT").first()
        )
        assert log is not None

    def test_assign_to_missing_user_rejected(self, db):
        admin = make_admin(db)
        c = make_complaint(db)
        with pytest.raises(ValidationError):
            admin_service.update_complaint(
                db, admin_user=admin, complaint_id=c.id, updates={"assigned_to": 777777}
            )

    def test_priority_and_assignment_update(self, db):
        admin = make_admin(db)
        staff = make_user(db, "customer")
        c = make_complaint(db)
        result = admin_service.update_complaint(
            db, admin_user=admin, complaint_id=c.id,
            updates={"priority": "urgent", "assigned_to": staff.id},
        )
        assert result["priority"] == "URGENT"
        assert result["assigned_to"] == staff.id

    def test_listing_filters(self, db):
        make_complaint(db, status="OPEN")
        make_complaint(db, status="RESOLVED", subject="done deal")
        items, total = admin_service.list_complaints(db, status="OPEN")
        assert total == 1
        items, total = admin_service.list_complaints(db, priority="medium")
        assert total == 2
        page, total = admin_service.list_complaints(db, limit=1, offset=1)
        assert total == 2 and len(page) == 1


# -- Notifications ---------------------------------------------------------------
class TestNotifications:
    def test_targeted_requires_ids(self, db):
        admin = make_admin(db)
        with pytest.raises(ValidationError):
            admin_service.send_admin_notification(
                db, admin_user=admin, title="t", body="b",
                notification_type="TARGETED",
            )

    def test_broadcast_reaches_active_users_only(self, db):
        from app.models.notification import Notification

        admin = make_admin(db)
        u1 = make_user(db, "customer")
        inactive = make_user(db, "customer", status="INACTIVE")
        result = admin_service.send_admin_notification(
            db, admin_user=admin, title="Maintenance",
            body="tonight", notification_type="ADMIN_BROADCAST",
        )
        assert result["recipient_count"] == 2  # admin + u1
        notes = db.query(Notification).all()
        assert len(notes) == 2

    def test_role_targeting(self, db):
        from app.models.notification import Notification

        admin = make_admin(db)
        keeper1 = make_user(db, "shopkeeper")
        keeper2 = make_user(db, "shopkeeper")
        make_user(db, "customer")
        result = admin_service.send_admin_notification(
            db, admin_user=admin, title="POS update",
            body="new feature", notification_type="ADMIN_BROADCAST",
            target_role="shopkeeper",
        )
        assert result["recipient_count"] == 2
        recipients = {n.user_id for n in db.query(Notification).all()}
        assert recipients == {keeper1.id, keeper2.id}

# -- System settings & feature flags --------------------------------------------
class TestSettingsAndFlags:
    def test_setting_upsert_and_masking(self, db):
        admin = make_admin(db)
        created = admin_service.upsert_system_setting(
            db, admin_user=admin, key="commission_rate",
            value="0.05", value_type="float", description="platform cut",
        )
        assert created["value"] == "0.05"
        updated = admin_service.upsert_system_setting(
            db, admin_user=admin, key="commission_rate", value="0.07"
        )
        assert updated["value"] == "0.07"

        secret = admin_service.upsert_system_setting(
            db, admin_user=admin, key="razorpay_secret",
            value="super-secret-key", is_secret=True,
        )
        assert secret["value"] == "********"

        listed = admin_service.list_system_settings(db)
        by_key = {s["key"]: s for s in listed}
        assert by_key["razorpay_secret"]["value"] == "********"
        assert by_key["commission_rate"]["value"] == "0.07"

    def test_setting_invalid_type(self, db):
        admin = make_admin(db)
        with pytest.raises(ValidationError):
            admin_service.upsert_system_setting(
                db, admin_user=admin, key="x", value="1", value_type="complex"
            )

    def test_setting_delete(self, db):
        admin = make_admin(db)
        admin_service.upsert_system_setting(db, admin_user=admin, key="k1", value="v1")
        result = admin_service.delete_system_setting(db, admin_user=admin, key="k1")
        assert result["deleted"] is True
        with pytest.raises(NotFoundError):
            admin_service.delete_system_setting(db, admin_user=admin, key="missing")

    def test_flag_validation_and_crud(self, db):
        from app.models.admin import AuditLog

        admin = make_admin(db)
        with pytest.raises(ValidationError):
            admin_service.upsert_feature_flag(
                db, admin_user=admin, name="f1",
                rollout_percentage=150,
            )
        with pytest.raises(ValidationError):
            admin_service.upsert_feature_flag(
                db, admin_user=admin, name="f1", scope="GALAXY",
            )
        flag = admin_service.upsert_feature_flag(
            db, admin_user=admin, name="new_search_ui",
            is_enabled=True, rollout_percentage=25, scope="USER",
            description="gradual rollout",
        )
        assert flag["is_enabled"] is True
        assert flag["rollout_percentage"] == 25
        updated = admin_service.upsert_feature_flag(
            db, admin_user=admin, name="new_search_ui",
            is_enabled=False, rollout_percentage=100,
        )
        assert updated["is_enabled"] is False
        logs = (
            db.query(AuditLog).filter(AuditLog.entity_type == "FEATURE_FLAG").all()
        )
        assert len(logs) == 2
        deleted = admin_service.delete_feature_flag(
            db, admin_user=admin, name="new_search_ui"
        )
        assert deleted["deleted"] is True


# -- Admin notes ------------------------------------------------------------------
class TestAdminNotes:
    def test_note_lifecycle_audited(self, db):
        from app.models.admin import AuditLog

        admin = make_admin(db)
        shop = make_shop(db)
        note = admin_service.create_admin_note(
            db, admin_user=admin, entity_type="SHOP",
            entity_id=shop.id, note="Owner documents look forged",
        )
        assert note["is_private"] is True
        items, total = admin_service.list_admin_notes(
            db, entity_type="SHOP", entity_id=shop.id
        )
        assert total == 1
        updated = admin_service.update_admin_note(
            db, admin_user=admin, note_id=note["id"],
            updates={"note": "cleared after review"},
        )
        assert updated["note"] == "cleared after review"
        deleted = admin_service.delete_admin_note(
            db, admin_user=admin, note_id=note["id"]
        )
        assert deleted["deleted"] is True
        _items, total_after = admin_service.list_admin_notes(db)
        assert total_after == 0
        note_logs = (
            db.query(AuditLog).filter(AuditLog.entity_type == "ADMIN_NOTE").all()
        )
        assert {l.action for l in note_logs} == {"CREATE", "UPDATE", "DELETE"}

    def test_missing_note_404(self, db):
        admin = make_admin(db)
        with pytest.raises(NotFoundError):
            admin_service.update_admin_note(
                db, admin_user=admin, note_id=31337, updates={"note": "x"}
            )

# -- Cross-cutting audit trail ---------------------------------------------------
class TestAuditTrail:
    def test_critical_operations_all_audited(self, db):
        from app.models.admin import AdminAction, AuditLog

        admin = make_admin(db)
        target_user = make_user(db, "customer")
        shop = make_shop(db, status="PENDING_VERIFICATION")
        pm = make_product(db, status="APPROVED")

        admin_service.update_user_status(
            db, admin_user=admin, user_id=target_user.id,
            action="SUSPEND", reason="tos",
        )
        admin_service.shop_verification_action(
            db, admin_user=admin, shop_id=shop.id, decision="VERIFY"
        )
        admin_service.product_bulk_action(
            db, admin_user=admin, action="ARCHIVE", product_ids=[pm.id], reason="old"
        )
        admin_service.create_category(
            db, admin_user=admin, data={"name": "AuditCat", "slug": "audit-cat"}
        )
        admin_service.generate_report(
            db, admin_user=admin, report_type="SHOPS", report_name="weekly"
        )

        actions = {a.action for a in db.query(AuditLog).all()}
        assert {"SUSPEND", "VERIFY", "ARCHIVE", "CREATE", "GENERATE"} <= actions

        admin_ops = db.query(AdminAction).all()
        op_types = {a.action_type for a in admin_ops}
        assert {"SUSPEND", "VERIFY", "ARCHIVE", "GENERATE_REPORT"} <= op_types

    def test_audit_listing_filters(self, db):
        admin = make_admin(db)
        shop = make_shop(db, status="PENDING_VERIFICATION")
        user = make_user(db, "customer")
        admin_service.shop_verification_action(
            db, admin_user=admin, shop_id=shop.id, decision="VERIFY"
        )
        admin_service.update_user_status(
            db, admin_user=admin, user_id=user.id, action="SUSPEND", reason="r"
        )
        logs, total = admin_service.list_audit_logs(db, entity_type="SHOP")
        assert total == 1 and logs[0]["action"] == "VERIFY"
        logs, total = admin_service.list_audit_logs(db, action="SUSPEND")
        assert total == 1 and logs[0]["entity_type"] == "USER"
        logs, total = admin_service.list_audit_logs(db, user_id=admin.id)
        assert total == 2

    def test_admin_actions_include_actor_name(self, db):
        admin = make_admin(db)
        shop = make_shop(db, status="ACTIVE")
        admin_service.shop_verification_action(
            db, admin_user=admin, shop_id=shop.id, decision="SUSPEND", reason="x"
        )
        items, total = admin_service.list_admin_actions(
            db, target_type="SHOP", admin_user_id=admin.id
        )
        assert total == 1
        assert items[0]["admin_name"] == "Root Admin"

    def test_audit_pagination(self, db):
        admin = make_admin(db)
        for i in range(5):
            shop = make_shop(db, status="PENDING_VERIFICATION")
            admin_service.shop_verification_action(
                db, admin_user=admin, shop_id=shop.id, decision="VERIFY"
            )
        page1, total = admin_service.list_audit_logs(db, limit=2, offset=0)
        page2, _ = admin_service.list_audit_logs(db, limit=2, offset=2)
        assert total == 5
        assert len(page1) == 2 and len(page2) == 2
        ids1 = {l["id"] for l in page1}
        ids2 = {l["id"] for l in page2}
        assert not (ids1 & ids2)


# -- API-level authorization (HTTP layer) -----------------------------------------
class TestAdminApiAuthorization:
    """Role restrictions enforced at the HTTP boundary."""

    @pytest.fixture()
    def client(self, db):
        from fastapi.testclient import TestClient

        from app.database.session import get_db
        from app.main import app

        app.dependency_overrides[get_db] = lambda: db
        yield TestClient(app)
        app.dependency_overrides.clear()

    @staticmethod
    def _headers(user):
        from app.core.security import create_access_token

        token, _ = create_access_token(subject=str(user.id))
        return {"Authorization": f"Bearer {token}"}

    def _path(self, suffix):
        from app.core.config import settings

        return f"{settings.API_PREFIX}/admin/{suffix}"

    def test_unauthenticated_rejected(self, client):
        resp = client.get(self._path("dashboard/metrics"))
        assert resp.status_code == 401

    def test_customer_forbidden(self, client, db):
        cust = make_user(db, "customer")
        resp = client.get(
            self._path("dashboard/metrics"), headers=self._headers(cust)
        )
        assert resp.status_code == 403

    def test_shopkeeper_forbidden(self, client, db):
        keeper = make_user(db, "shopkeeper")
        resp = client.get(self._path("shops"), headers=self._headers(keeper))
        assert resp.status_code == 403

    def test_admin_reads_dashboard(self, client, db):
        admin = make_admin(db)
        resp = client.get(
            self._path("dashboard/metrics"), headers=self._headers(admin)
        )
        assert resp.status_code == 200
        assert resp.json()["success"] is True

    def test_analyst_cannot_suspend_users(self, client, db):
        analyst = make_user(db, "admin_analyst")
        target = make_user(db, "customer")
        resp = client.post(
            self._path(f"users/{target.id}/status?action=SUSPEND&reason=test"),
            headers=self._headers(analyst),
        )
        assert resp.status_code == 403

    def test_moderator_cannot_update_settings(self, client, db):
        mod = make_user(db, "admin_moderator")
        resp = client.put(
            self._path("settings/some_key?value=x"), headers=self._headers(mod)
        )
        assert resp.status_code == 403

    def test_support_cannot_verify_shops(self, client, db):
        support = make_user(db, "admin_support")
        shop = make_shop(db)
        resp = client.post(
            self._path(f"shops/{shop.id}/verification"),
            json={"decision": "VERIFY"},
            headers=self._headers(support),
        )
        assert resp.status_code == 403

    def test_moderator_can_verify_but_not_suspend_via_endpoint_guard(
        self, client, db
    ):
        mod = make_user(db, "admin_moderator")
        shop = make_shop(db, status="PENDING_VERIFICATION")
        resp = client.post(
            self._path(f"shops/{shop.id}/verification"),
            json={"decision": "VERIFY"},
            headers=self._headers(mod),
        )
        assert resp.status_code == 200
        # Moderator lacks shop.suspend -> endpoint guard blocks the decision.
        resp2 = client.post(
            self._path(f"shops/{shop.id}/verification"),
            json={"decision": "SUSPEND", "reason": "x"},
            headers=self._headers(mod),
        )
        assert resp2.status_code == 403


if __name__ == "__main__":
    import sys

    sys.exit(pytest.main([__file__, "-v"]))

