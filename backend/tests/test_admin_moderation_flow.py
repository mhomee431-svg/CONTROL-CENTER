"""Phase 22 — Admin / Moderation Flow tests.

Verifies against a real in-memory SQLite database + FastAPI TestClient that:

  * Admins can manage every platform module:
      users, shops, shop verification, products, categories, brands,
      inventory issues, reports, complaints, offers, subscriptions,
      audit logs.
  * Role-based authorization is enforced at the HTTP boundary:
      - admin            → full platform control (wildcard permission)
      - admin_support    → users(read) + complaints + notifications
      - admin_moderator  → shop verification + product review
      - admin_analyst    → read-only dashboards / reports / analytics
      - customer / shopkeeper / unauthenticated → denied
  * Every critical admin mutation writes an AuditLog (immutable record)
    and, where applicable, an AdminAction companion row.
  * Unauthorized access is rejected end-to-end (401 / 403).
"""

import os
import sys
from datetime import datetime, timezone
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402
from sqlalchemy import create_engine  # noqa: E402
from sqlalchemy.orm import sessionmaker  # noqa: E402

from app.core.config import settings  # noqa: E402

settings.RATE_LIMIT_ENABLED = False

from app.core.exceptions import (  # noqa: E402
    ConflictError,
    ForbiddenError,
    NotFoundError,
)
from app.models.base import Base  # noqa: E402
from app.services import admin_service  # noqa: E402

UTC = timezone.utc


# Adapt PostGIS Geography columns for plain SQLite (shared, reversible helper).
from tests.geo_compat import strip_geo_columns  # noqa: E402

strip_geo_columns()


def _portable_timestamp_defaults():
    """Replace literal ``now()`` server defaults so SQLite stores timestamps."""
    from sqlalchemy import ColumnDefault

    def _now(ctx=None):
        return datetime.now(timezone.utc)

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
# Tables required by the admin moderation test matrix.
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
    # Re-strip Geography columns: earlier test modules may have called
    # restore_geo_columns(), which puts pristine PostGIS types back into the
    # shared metadata. strip_geo_columns() is idempotent.
    strip_geo_columns()
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
# -- HTTP test harness ------------------------------------------------------
@pytest.fixture()
def client(db):
    from fastapi.testclient import TestClient

    from app.database.session import get_db
    from app.main import app

    app.dependency_overrides[get_db] = lambda: db
    yield TestClient(app)
    app.dependency_overrides.clear()


def _headers(user):
    from app.core.security import create_access_token

    token, _ = create_access_token(subject=str(user.id))
    return {"Authorization": f"Bearer {token}"}


def _admin_path(suffix):
    return f"{settings.API_PREFIX}/admin/{suffix}"


# -- Brands (full CRUD incl. delete) ----------------------------------------
class TestBrandManagement:
    def test_brand_crud_lifecycle_audited(self, db):
        from app.models.admin import AuditLog

        admin = make_admin(db)
        created = admin_service.create_brand(
            db, admin_user=admin, data={"name": "Amul", "slug": "amul"}
        )
        brand_id = created["id"]
        assert created["name"] == "Amul"

        updated = admin_service.update_brand(
            db, admin_user=admin, brand_id=brand_id, updates={"description": "dairy co-op"}
        )
        assert updated["description"] == "dairy co-op"

        deleted = admin_service.delete_brand(db, admin_user=admin, brand_id=brand_id)
        assert deleted == {"id": brand_id, "deleted": True}

        # Soft-deleted => hidden from the active listing.
        visible = admin_service.list_brands_admin(db)
        assert all(b["id"] != brand_id for b in visible)

        # Every critical stage wrote an immutable AuditLog row.
        audit = (
            db.query(AuditLog)
            .filter(AuditLog.entity_type == "BRAND", AuditLog.user_id == admin.id)
            .order_by(AuditLog.id)
            .all()
        )
        actions = [a.action for a in audit]
        assert actions == ["CREATE", "UPDATE", "DELETE"]
        assert audit[-1].old_values == {"name": "Amul"}

    def test_delete_brand_blocked_while_in_use(self, db):
        admin = make_admin(db)
        brand = make_brand(db)
        shop = make_shop(db, status="ACTIVE")
        product = make_product(db, brand=brand)
        make_listing(db, shop, product)
        with pytest.raises(ConflictError):
            admin_service.delete_brand(db, admin_user=admin, brand_id=brand.id)

    def test_delete_brand_not_found(self, db):
        admin = make_admin(db)
        with pytest.raises(NotFoundError):
            admin_service.delete_brand(db, admin_user=admin, brand_id=99999)

    def test_brand_crud_api_roundtrip(self, db, client):
        admin = make_admin(db)
        resp = client.post(
            _admin_path("brands"),
            json={"name": "Nestle", "slug": "nestle"},
            headers=_headers(admin),
        )
        assert resp.status_code == 201
        brand_id = resp.json()["data"]["id"]

        resp = client.put(
            _admin_path(f"brands/{brand_id}"),
            json={"description": "fmcg"},
            headers=_headers(admin),
        )
        assert resp.status_code == 200
        assert resp.json()["data"]["description"] == "fmcg"

        resp = client.delete(_admin_path(f"brands/{brand_id}"), headers=_headers(admin))
        assert resp.status_code == 200
        assert resp.json()["data"]["deleted"] is True

        # Deleted brand is gone from the active list API too.
        resp = client.get(_admin_path("brands"), headers=_headers(admin))
        assert all(b["id"] != brand_id for b in resp.json()["data"]["items"])

    def test_deleted_brand_delete_returns_404(self, db, client):
        admin = make_admin(db)
        brand = make_brand(db)
        delete = admin_service.delete_brand(db, admin_user=admin, brand_id=brand.id)
        assert delete["deleted"] is True
        resp = client.delete(_admin_path(f"brands/{brand.id}"), headers=_headers(admin))
        assert resp.status_code == 404
# -- Full admin capability walkthrough (all 12 modules) ---------------------
class TestAdminModuleManagement:
    """A single user journey proving an admin can operate every module."""

    def test_admin_manages_every_module(self, db, client):
        admin = make_admin(db)
        headers = _headers(admin)

        # Fixture entities the walkthrough manages.
        target_user = make_user(db, "customer")
        pending_shop = make_shop(db, status="PENDING_VERIFICATION")
        active_shop = make_shop(db, status="ACTIVE")
        pending_product = make_product(db, status="PENDING_REVIEW")
        listing = make_listing(
            db, active_shop, pending_product, listing_status="PENDING_REVIEW"
        )[0]
        other_product = make_product(db, status="APPROVED")
        cat = make_category(db)
        brand = make_brand(db)
        offer = make_offer(db, active_shop)
        sub_owner = make_user(db, "customer")
        _, sub, _ = make_subscription_with_payment(db, sub_owner)
        complaint = make_complaint(db)

        ok = []
        failed = []

        def _checks():
            nonlocal ok, failed
            good = [name for name, passed in ok if passed]
            failed = [name for name, passed in ok if not passed]
            return f"passed={len(good)} failed={failed}"

        # 1. Users
        resp = client.get(_admin_path("customers"), headers=headers)
        ok.append(("customers:list", resp.status_code == 200))
        resp = client.post(
            _admin_path(f"users/{target_user.id}/status?action=SUSPEND&reason=test"),
            headers=headers,
        )
        ok.append(("users:suspend", resp.status_code == 200))

        # 2. Shops + 3. shop verification
        resp = client.get(_admin_path("shops"), headers=headers)
        ok.append(("shops:list", resp.status_code == 200))
        resp = client.get(_admin_path(f"shops/{pending_shop.id}"), headers=headers)
        ok.append(("shops:detail", resp.status_code == 200))
        resp = client.post(
            _admin_path(f"shops/{pending_shop.id}/verification"),
            json={"decision": "VERIFY", "reason": "docs ok"},
            headers=headers,
        )
        ok.append(("shops:verify", resp.status_code == 200))

        # 4. Products (list / edit / bulk approve / review listings)
        resp = client.get(_admin_path("products"), headers=headers)
        ok.append(("products:list", resp.status_code == 200))
        resp = client.put(
            _admin_path(f"products/{other_product.id}"),
            json={"description": "marketplace unit"},
            headers=headers,
        )
        ok.append(("products:update", resp.status_code == 200))
        resp = client.post(
            _admin_path("products/bulk"),
            json={"action": "APPROVE", "product_ids": [pending_product.id]},
            headers=headers,
        )
        ok.append(("products:bulk-approve", resp.status_code == 200))
        resp = client.get(_admin_path("products/approvals"), headers=headers)
        ok.append(("products:approvals", resp.status_code == 200))
        resp = client.post(
            _admin_path(f"products/listings/{listing.id}/review"),
            params={"decision": "APPROVE", "review_notes": "verified"},
            headers=headers,
        )
        ok.append(("products:review-listing", resp.status_code == 200))

        # 5. Categories
        resp = client.post(
            _admin_path("categories"),
            json={"name": "Fruits", "slug": "fruits"},
            headers=headers,
        )
        ok.append(("categories:create", resp.status_code == 201))
        resp = client.put(
            _admin_path(f"categories/{cat.id}"),
            json={"description": "fresh produce"},
            headers=headers,
        )
        ok.append(("categories:update", resp.status_code == 200))
        resp = client.delete(_admin_path(f"categories/{cat.id}"), headers=headers)
        ok.append(("categories:delete", resp.status_code == 200))

        # 6. Brands (incl. the completed delete lifecycle)
        resp = client.post(
            _admin_path("brands"),
            json={"name": "Nestle", "slug": "nestle"},
            headers=headers,
        )
        ok.append(("brands:create", resp.status_code == 201))
        resp = client.put(
            _admin_path(f"brands/{brand.id}"),
            json={"description": "fmcg"},
            headers=headers,
        )
        ok.append(("brands:update", resp.status_code == 200))
        resp = client.delete(_admin_path(f"brands/{brand.id}"), headers=headers)
        ok.append(("brands:delete", resp.status_code == 200))

        assert not failed, _checks()
        assert len(ok) >= 16, "Walkthrough did not cover the admin module surface"
# 7. Inventory issues (monitoring)
        for view in ("summary", "stale", "missing-prices", "anomalies", "sync-failures"):
            resp = client.get(_admin_path(f"inventory/{view}"), headers=headers)
            ok.append((f"inventory:{view}", resp.status_code == 200))

        # 8. Offers
        resp = client.get(_admin_path("offers"), headers=headers)
        ok.append(("offers:list", resp.status_code == 200))
        resp = client.post(
            _admin_path(f"offers/{offer.id}/status?new_status=PAUSED"), headers=headers
        )
        ok.append(("offers:update", resp.status_code == 200))

        # 9. Subscriptions + payments
        resp = client.get(_admin_path("subscriptions"), headers=headers)
        ok.append(("subscriptions:list", resp.status_code == 200))
        resp = client.put(
            _admin_path(f"subscriptions/{sub.id}"),
            json={"is_auto_renew": False},
            headers=headers,
        )
        ok.append(("subscriptions:update", resp.status_code == 200))
        resp = client.get(_admin_path("payments"), headers=headers)
        ok.append(("payments:list", resp.status_code == 200))

        # 10. Reports
        resp = client.post(
            _admin_path("reports/generate"),
            json={"report_type": "USERS", "report_name": "users-monthly"},
            headers=headers,
        )
        ok.append(("reports:generate", resp.status_code == 200))
        resp = client.get(_admin_path("reports"), headers=headers)
        ok.append(("reports:list", resp.status_code == 200))

        # 11. Complaints
        resp = client.get(_admin_path("complaints"), headers=headers)
        ok.append(("complaints:list", resp.status_code == 200))
        resp = client.put(
            _admin_path(f"complaints/{complaint.id}"),
            json={"status": "IN_PROGRESS"},
            headers=headers,
        )
        ok.append(("complaints:update", resp.status_code == 200))

        # 12. Audit logs
        resp = client.get(_admin_path("audit-logs"), headers=headers)
        ok.append(("audit-logs:list", resp.status_code == 200))
        resp = client.get(_admin_path("actions"), headers=headers)
        ok.append(("actions:list", resp.status_code == 200))

        good = [name for name, passed in ok if passed]
        failed = [name for name, passed in ok if not passed]
        assert not failed, f"Admin lacks access to: {failed}"
        assert len(good) >= 31, "Walkthrough did not cover the full module surface"

    def test_admin_audit_chain_endpoint_ok(self, db, client):
        admin = make_admin(db)
        resp = client.get(
            _admin_path("analytics/audit-chain"), headers=_headers(admin)
        )
        assert resp.status_code == 200
        assert resp.json()["data"]["valid"] is True
# -- Role-based authorization boundaries (HTTP layer) ----------------------
class TestRoleBasedAuthorization:
    """Every admin sub-role is limited to exactly its permission catalog."""

    def test_moderator_can_moderate_but_not_admin(self, db, client):
        mod = make_user(db, "admin_moderator", name="Mod")
        headers = _headers(mod)
        shop = make_shop(db, status="PENDING_VERIFICATION")
        target = make_user(db, "customer")
        brand = make_brand(db)
        product = make_product(db, status="PENDING_REVIEW")

        # Allowed: dashboard, shop read/verify, product review/approve, audit log.
        assert client.get(_admin_path("shops"), headers=headers).status_code == 200
        assert (
            client.post(
                _admin_path(f"shops/{shop.id}/verification"),
                json={"decision": "VERIFY"},
                headers=headers,
            ).status_code
            == 200
        )
        assert (
            client.get(_admin_path("products/approvals"), headers=headers).status_code
            == 200
        )
        assert (
            client.post(
                _admin_path("products/bulk"),
                json={"action": "APPROVE", "product_ids": [product.id]},
                headers=headers,
            ).status_code
            == 200
        )
        assert (
            client.get(_admin_path("audit-logs"), headers=headers).status_code == 200
        )

        # Denied: user suspension, shop suspend decision, brand delete, catalog
        # taxonomy writes, complaints, inventory, subscriptions, offers.
        assert (
            client.post(
                _admin_path(f"users/{target.id}/status?action=SUSPEND&reason=x"),
                headers=headers,
            ).status_code
            == 403
        )
        assert (
            client.post(
                _admin_path(f"shops/{shop.id}/verification"),
                json={"decision": "SUSPEND", "reason": "x"},
                headers=headers,
            ).status_code
            == 403
        )
        assert (
            client.delete(_admin_path(f"brands/{brand.id}"), headers=headers).status_code
            == 403
        )
        assert (
            client.post(
                _admin_path("categories"),
                json={"name": "X", "slug": "x"},
                headers=headers,
            ).status_code
            == 403
        )
        assert (
            client.get(_admin_path("complaints"), headers=headers).status_code == 403
        )
        assert (
            client.get(_admin_path("inventory/stale"), headers=headers).status_code
            == 403
        )
        assert (
            client.get(_admin_path("subscriptions"), headers=headers).status_code == 403
        )
    def test_support_handles_users_and_complaints_only(self, db, client):
        support = make_user(db, "admin_support", name="Support")
        headers = _headers(support)
        shop = make_shop(db, status="PENDING_VERIFICATION")
        complaint = make_complaint(db)
        brand = make_brand(db)

        # Allowed: read users + complaints, update complaints.
        assert client.get(_admin_path("customers"), headers=headers).status_code == 200
        assert client.get(_admin_path("complaints"), headers=headers).status_code == 200
        assert (
            client.put(
                _admin_path(f"complaints/{complaint.id}"),
                json={"status": "IN_PROGRESS"},
                headers=headers,
            ).status_code
            == 200
        )

        # Denied: shop verification, audit logs, inventory, taxonomy/brand writes.
        assert (
            client.post(
                _admin_path(f"shops/{shop.id}/verification"),
                json={"decision": "VERIFY"},
                headers=headers,
            ).status_code
            == 403
        )
        assert client.get(_admin_path("audit-logs"), headers=headers).status_code == 403
        assert (
            client.get(_admin_path("inventory/stale"), headers=headers).status_code
            == 403
        )
        assert (
            client.delete(_admin_path(f"brands/{brand.id}"), headers=headers).status_code
            == 403
        )

    def test_analyst_is_read_only(self, db, client):
        analyst = make_user(db, "admin_analyst", name="Analyst")
        headers = _headers(analyst)
        target = make_user(db, "customer")
        complaint = make_complaint(db)
        brand = make_brand(db)

        # Allowed: dashboards, analytics, reports, subscriptions, payments.
        assert (
            client.get(_admin_path("dashboard/metrics"), headers=headers).status_code
            == 200
        )
        assert (
            client.get(_admin_path("analytics/summary"), headers=headers).status_code
            == 200
        )
        assert (
            client.post(
                _admin_path("reports/generate"),
                json={"report_type": "USERS", "report_name": "r"},
                headers=headers,
            ).status_code
            == 200
        )
        assert (
            client.get(_admin_path("subscriptions"), headers=headers).status_code == 200
        )
        assert client.get(_admin_path("payments"), headers=headers).status_code == 200

        # Denied every mutation surface.
        assert (
            client.post(
                _admin_path(f"users/{target.id}/status?action=SUSPEND&reason=x"),
                headers=headers,
            ).status_code
            == 403
        )
        assert (
            client.post(
                _admin_path("categories"),
                json={"name": "X", "slug": "x"},
                headers=headers,
            ).status_code
            == 403
        )
        assert (
            client.delete(_admin_path(f"brands/{brand.id}"), headers=headers).status_code
            == 403
        )
        assert (
            client.put(
                _admin_path(f"complaints/{complaint.id}"),
                json={"status": "IN_PROGRESS"},
                headers=headers,
            ).status_code
            == 403
        )
# -- Unauthorized access rejection (HTTP layer) ----------------------------
class TestUnauthorizedAccess:
    """Non-admin actors and anonymous callers are rejected end-to-end."""

    def test_unauthenticated_rejected_on_all_mutating_verbs(self, db, client):
        target = make_user(db, "customer")
        shop = make_shop(db, status="PENDING_VERIFICATION")
        brand = make_brand(db)
        complaint = make_complaint(db)

        probes = [
            ("get", _admin_path("dashboard/metrics"), None, {}),
            ("get", _admin_path("customers"), None, {}),
            ("get", _admin_path("shops"), None, {}),
            ("post", _admin_path("categories"), None, {"json": {"name": "X", "slug": "x"}}),
            ("delete", _admin_path(f"brands/{brand.id}"), None, {}),
            (
                "post",
                _admin_path(f"users/{target.id}/status?action=SUSPEND&reason=x"),
                None,
                {},
            ),
            (
                "post",
                _admin_path(f"shops/{shop.id}/verification"),
                None,
                {"json": {"decision": "VERIFY"}},
            ),
            (
                "put",
                _admin_path(f"complaints/{complaint.id}"),
                None,
                {"json": {"status": "IN_PROGRESS"}},
            ),
        ]
        for method, path, _user, kwargs in probes:
            if method == "get":
                resp = client.get(path)
            elif method == "post":
                resp = client.post(path, **kwargs)
            elif method == "put":
                resp = client.put(path, **kwargs)
            elif method == "delete":
                resp = client.delete(path, **kwargs)
            assert resp.status_code == 401, f"{method.upper()} {path} -> {resp.status_code}"

    def test_customer_role_forbidden(self, db, client):
        cust = make_user(db, "customer")
        headers = _headers(cust)
        assert (
            client.get(_admin_path("dashboard/metrics"), headers=headers).status_code
            == 403
        )
        assert client.get(_admin_path("shops"), headers=headers).status_code == 403
        assert client.get(_admin_path("customers"), headers=headers).status_code == 403
        assert (
            client.get(_admin_path("audit-logs"), headers=headers).status_code == 403
        )
        assert (
            client.get(_admin_path("analytics/summary"), headers=headers).status_code
            == 403
        )

    def test_shopkeeper_role_forbidden(self, db, client):
        keeper = make_user(db, "shopkeeper")
        headers = _headers(keeper)
        assert client.get(_admin_path("shops"), headers=headers).status_code == 403
        assert (
            client.get(_admin_path("inventory/stale"), headers=headers).status_code
            == 403
        )
        assert (
            client.get(_admin_path("subscriptions"), headers=headers).status_code == 403
        )

    def test_suspended_admin_rejected(self, db, client):
        admin = make_user(db, "admin", status="SUSPENDED", name="Blocked Admin")
        headers = _headers(admin)
        assert (
            client.get(_admin_path("dashboard/metrics"), headers=headers).status_code
            == 403
        )

    def test_non_admin_cannot_reach_audit_chain(self, db, client):
        cust = make_user(db, "customer")
        resp = client.get(
            _admin_path("analytics/audit-chain"), headers=_headers(cust)
        )
        assert resp.status_code == 403


# -- Audit trail for critical admin actions --------------------------------
class TestCriticalActionAuditability:
    """Every critical admin mutation is captured in the immutable audit trail."""

    def test_mutations_write_audit_records_with_actor(self, db):
        from app.models.admin import AuditLog

        admin = make_admin(db)
        target = make_user(db, "customer")
        shop = make_shop(db, status="PENDING_VERIFICATION")
        product = make_product(db, status="APPROVED")
        brand = make_brand(db)

        admin_service.update_user_status(
            db, admin_user=admin, user_id=target.id, action="SUSPEND", reason="tos"
        )
        admin_service.shop_verification_action(
            db, admin_user=admin, shop_id=shop.id, decision="VERIFY"
        )
        admin_service.product_bulk_action(
            db, admin_user=admin, action="ARCHIVE", product_ids=[product.id], reason="old"
        )
        admin_service.create_brand(
            db, admin_user=admin, data={"name": "Amul", "slug": "amul"}
        )

        rows = (
            db.query(AuditLog)
            .filter(AuditLog.user_id == admin.id)
            .order_by(AuditLog.id)
            .all()
        )
        actions = [(r.entity_type, r.action) for r in rows]
        assert ("USER", "SUSPEND") in actions
        assert ("SHOP", "VERIFY") in actions
        assert ("PRODUCT", "ARCHIVE") in actions
        assert ("BRAND", "CREATE") in actions
        # Actor identity is preserved on every record.
        assert all(r.user_id == admin.id for r in rows)

    def test_admin_write_trails_are_tamper_evident(self, db):
        """Admin audit rows join the same hash chain used platform-wide."""
        from app.services import audit_service

        admin = make_admin(db)
        shop = make_shop(db, status="PENDING_VERIFICATION")
        admin_service.shop_verification_action(
            db, admin_user=admin, shop_id=shop.id, decision="VERIFY"
        )
        admin_service.shop_verification_action(
            db, admin_user=admin, shop_id=shop.id, decision="SUSPEND", reason="fraud"
        )

        result = audit_service.verify_audit_chain(db)
        assert result["valid"] is True
        assert result["total"] >= 2

        # Tampering with an admin-written record breaks the chain.
        from app.models.admin import AuditLog

        db.query(AuditLog).filter(AuditLog.entity_type == "SHOP").update(
            {"description": "rewritten history"}
        )
        db.expire_all()
        result = audit_service.verify_audit_chain(db)
        assert result["valid"] is False

    def test_admin_mutations_also_write_admin_action_rows(self, db):
        from app.models.admin import AdminAction

        admin = make_admin(db)
        shop = make_shop(db, status="PENDING_VERIFICATION")
        admin_service.shop_verification_action(
            db, admin_user=admin, shop_id=shop.id, decision="VERIFY"
        )
        admin_service.update_user_status(
            db, admin_user=admin, user_id=make_user(db, "customer").id,
            action="BAN", reason="spam",
        )
        ops = db.query(AdminAction).order_by(AdminAction.id).all()
        assert {o.action_type for o in ops} == {"VERIFY", "BAN"}
        assert all(o.admin_user_id == admin.id for o in ops)

    def test_audit_logs_never_have_mutation_endpoints(self, db, client):
        """Audit records are read-only even for the admin role."""
        from app.models.admin import AuditLog

        admin = make_admin(db)
        admin_service.create_brand(
            db, admin_user=admin, data={"name": "Logbrand", "slug": "logbrand"}
        )
        entry = db.query(AuditLog).filter(AuditLog.entity_type == "BRAND").first()
        # No PUT/POST/DELETE route exists for audit entries; even a direct
        # service call is refused by the immutability guard.
        with pytest.raises(ForbiddenError):
            admin_service.record_audit_log(
                db, user_id=admin.id, action="DELETE",
                entity_type="AUDIT_LOG", entity_id=entry.id,
            )
        resp = client.delete(_admin_path(f"audit-logs/{entry.id}"), headers=_headers(admin))
        assert resp.status_code in (404, 405), "Audit entries must never be deletable"

        # The audit-logs path itself has no mutation route — POST is unhandled.
        resp = client.post(_admin_path("audit-logs"), headers=_headers(admin))
        assert resp.status_code == 405, "No audit mutation endpoint may exist"