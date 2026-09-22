"""Phase 22 — Shopkeeper Application Foundation tests.

Covers:
  - Registration (shopkeeper account creation, duplicate rejection)
  - Login (OTP flow, unknown account, invalid OTP, success + shops payload)
  - Shop association (owner/manager linkage, multi-shop listing, selection data)
  - Verification status (PENDING default, record propagation, dashboard surfacing)
  - Dashboard (product count, active products, inventory status, recent
    updates, offers, subscription status)
  - Unauthorized shop access (customer/stranger → ForbiddenError; portal
    dependency raises; manager permission restrictions)
  - Logout (session revocation through the shopkeeper logout route)
"""

import asyncio
import json
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import MagicMock

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402

from app.core.config import settings  # noqa: E402

settings.RATE_LIMIT_ENABLED = False
settings.OTP_MAX_ATTEMPTS = 5
settings.OTP_MAX_RESENDS = 5
settings.OTP_RESEND_COOLDOWN_SECONDS = 0
settings.OTP_COOLDOWN_SECONDS = 0


def run_async(coro):
    return asyncio.run(coro)


# ── Mock infrastructure ──────────────────────────────────────────────────


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

    def scalar(self, *args, **kwargs):
        return False


class ShopkeeperMockDB:
    """DB mock tuned for shopkeeper_service call patterns."""

    def __init__(self):
        self.added = []
        self.committed = 0
        self.rolled_back = 0
        self.flushes = 0
        self.first_queues: dict = {}
        self.all_results: dict = {}
        self._next_id = 100

    def queue_first(self, model, items):
        self.first_queues[model] = list(items)

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
        self.rolled_back += 1


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


def make_shop(shop_id=10, name="Kirana Corner", status="REGISTERED", verified=False):
    from app.models.shop import Shop, ShopCategory, ShopStatus

    shop = Shop(
        name=name,
        slug=f"kirana-corner-{shop_id}",
        status=getattr(ShopStatus, status),
        category=ShopCategory.GROCERY,
        is_verified=verified,
        rating=4.2,
        review_count=12,
    )
    shop.id = shop_id
    return shop


def make_owner(shop_id=10, user_id=1):
    from app.models.shop import ShopOwner

    row = ShopOwner(shop_id=shop_id, user_id=user_id, is_primary=True)
    row.is_active = True
    return row


def make_manager(shop_id=20, user_id=1, permissions_json=None):
    from app.models.shop import ShopManager

    row = ShopManager(shop_id=shop_id, user_id=user_id, permissions=permissions_json)
    row.is_active = True
    return row


def make_shop_product(sp_id=100, master_name="Basmati Rice 1kg", price=120.0,
                      quantity=25, threshold=5, active=True, available=True):
    from app.models.product import Inventory, ProductMaster, ShopProduct, StockStatus

    master = ProductMaster(name=master_name, slug=master_name.lower().replace(" ", "-"))
    master.id = sp_id * 7
    sp = ShopProduct(
        product_master_id=master.id,
        shop_id=10,
        price=price,
        mrp=price * 1.2,
        is_active=active,
        is_available=available,
    )
    sp.product_master = master
    sp.id = sp_id
    inv = Inventory(quantity=quantity, low_stock_threshold=threshold, available_quantity=quantity)
    inv.stock_status = StockStatus.IN_STOCK if quantity > threshold else (
        StockStatus.LOW_STOCK if quantity > 0 else StockStatus.OUT_OF_STOCK
    )
    sp.inventory = inv
    sp.last_inventory_update = datetime.now(timezone.utc) - timedelta(hours=2)
    return sp


# ── Permission system ────────────────────────────────────────────────────


class TestShopkeeperPermissions:
    def test_catalog_defined_and_nonempty(self):
        from app.core.shopkeeper_permissions import SHOPKEEPER_PERMISSIONS

        assert len(SHOPKEEPER_PERMISSIONS) >= 8
        assert ("shop", "update") in SHOPKEEPER_PERMISSIONS
        assert ("product", "create") in SHOPKEEPER_PERMISSIONS
        assert ("inventory", "update") in SHOPKEEPER_PERMISSIONS
        assert ("dashboard", "read") in SHOPKEEPER_PERMISSIONS

    def test_catalog_covers_every_route_requirement(self):
        """Regression guard for the "missing permission ⇒ owner gets 403" bug.

        Every ``access.require("<resource>", "<action>")`` call in the backend
        must resolve for an OWNER (the full catalog). When a route required a
        resource that was absent from the catalog (documents, notifications),
        owners were refused with FORBIDDEN on their own shop.
        """
        import re
        from pathlib import Path

        from app.core.shopkeeper_permissions import SHOPKEEPER_PERMISSIONS

        app_dir = Path(__file__).resolve().parents[1] / "app"
        pattern = re.compile(
            r"""\.require\(\s*["']([a-z_]+)["']\s*,\s*["']([a-z_]+)["']\s*\)"""
        )

        required: set[tuple[str, str]] = set()
        for source in app_dir.rglob("*.py"):
            required.update(pattern.findall(source.read_text(encoding="utf-8")))

        # Sanity: the scan must actually see the known call sites.
        assert ("dashboard", "read") in required
        assert ("notifications", "read") in required

        catalog = set(SHOPKEEPER_PERMISSIONS)
        missing = sorted(required - catalog)
        assert not missing, f"routes require permissions absent from catalog: {missing}"

    def test_owner_gets_full_catalog(self):
        from app.core.shopkeeper_permissions import (
            SHOPKEEPER_PERMISSIONS,
            effective_shop_permissions,
        )

        perms = effective_shop_permissions("shopkeeper", True, None)
        assert perms == {f"{a}:{r}" for r, a in SHOPKEEPER_PERMISSIONS}

    def test_manager_subset_excludes_settings(self):
        from app.core.shopkeeper_permissions import effective_shop_permissions

        class UnrestrictedManager:
            permissions = None  # no explicit restriction → full manager catalog

        perms = effective_shop_permissions("shopkeeper", False, UnrestrictedManager())
        assert "update:shop" not in perms
        assert "read:dashboard" in perms
        assert "update:product" in perms

    def test_manager_granted_json_restricts_further(self):
        from app.core.shopkeeper_permissions import effective_shop_permissions

        class Mgr:
            permissions = '["read:product", "update:inventory"]'

        perms = effective_shop_permissions("shopkeeper", False, Mgr())
        assert perms == {"read:product", "update:inventory"}

    def test_stranger_gets_nothing(self):
        from app.core.shopkeeper_permissions import effective_shop_permissions

        assert effective_shop_permissions("customer", False, None) == set()


# ── Registration ─────────────────────────────────────────────────────────


class TestShopkeeperRegistration:
    def test_create_account_assigns_shopkeeper_role_and_no_customer_profile(self):
        from app.services import shopkeeper_service as svc

        db = ShopkeeperMockDB()
        user = svc.create_shopkeeper_account(db, "+919000000010", "Ramesh")

        assert user.phone_number == "+919000000010"
        assert user.name == "Ramesh"
        roles = [type(o).__name__ for o in db.added]
        assert "Role" in roles  # shopkeeper role ensured
        customers = [o for o in db.added if type(o).__name__ == "Customer"]
        assert customers == []  # business account: no customer profile

    def test_register_route_full_flow(self, monkeypatch):
        from app.api.routes import shopkeeper_auth
        from app.services import shopkeeper_service

        # Mock Firebase token verification → returns (firebase_uid, phone).
        monkeypatch.setattr(
            shopkeeper_auth,
            "verify_firebase_id_token_claims",
            lambda token: ("fb-uid-0000000001", "+919000000011"),
        )
        # Mock business-ID generation (deterministic) so the test is stable
        # regardless of the mock DB's limited filter() semantics.
        monkeypatch.setattr(
            shopkeeper_service,
            "generate_business_id",
            lambda db, phone: "SHOP_919000000011",
        )

        request = MagicMock()
        request.client.host = "127.0.0.1"
        request.headers.get.return_value = "pytest-agent"

        db = ShopkeeperMockDB()
        payload = shopkeeper_auth.ShopkeeperRegisterRequest(
            phone_number="+919000000011",
            firebase_id_token="fake-firebase-token-0000000000",
            name="Suresh Kirana",
            password="Password123",
            device_id="dev-1",
        )
        response = run_async(shopkeeper_auth.register(payload, request, db))
        body = bytes(response.body).decode()
        assert '"success":true' in body.replace(" ", "")
        assert "access_token" in body
        assert "refresh_token" in body
        assert "Kirana Corner" not in body  # new account, no shops yet
        data = json.loads(body.replace(" ", ""))["data"]
        assert data["shops"] == []
        # Unique Business ID is issued on registration.
        assert data["business_id"] == "SHOP_919000000011"
        assert data["user"]["business_id"] == "SHOP_919000000011"

    def test_register_rejects_existing_account(self, monkeypatch):
        from fastapi.responses import JSONResponse

        from app.api.routes import shopkeeper_auth
        from app.models.user import User

        monkeypatch.setattr(
            shopkeeper_auth,
            "verify_firebase_id_token_claims",
            lambda token: ("fb-uid-0000000002", "+919000000012"),
        )

        request = MagicMock()
        request.client.host = "127.0.0.1"
        request.headers.get.return_value = None

        existing = make_user(user_id=5, phone="+919000000012")
        existing.firebase_uid = "fb-uid-0000000002"
        db = ShopkeeperMockDB()
        db.queue_first(User, [existing])

        payload = shopkeeper_auth.ShopkeeperRegisterRequest(
            phone_number="+919000000012",
            firebase_id_token="fake-firebase-token-0000000000",
            name="Dup",
            password="Password123",
        )
        response = run_async(shopkeeper_auth.register(payload, request, db))
        assert isinstance(response, JSONResponse)
        assert response.status_code == 400
        assert b"already registered" in response.body




# ── Verify-phone (new Firebase phone-auth flow) ─────────────────────────


class TestShopkeeperVerifyPhone:
    def _request(self, authorization=None):
        req = MagicMock()
        req.client.host = "127.0.0.1"
        req.headers.get.side_effect = lambda key, default=None: (
            authorization if key == "authorization" else default
        )
        return req

    def test_verify_phone_invalid_token(self, monkeypatch):
        from fastapi.responses import JSONResponse

        from app.api.routes import shopkeeper_auth
        from app.services.firebase_verification import FirebaseVerificationError

        def _raise(token):
            raise FirebaseVerificationError("Invalid token")

        monkeypatch.setattr(shopkeeper_auth, "verify_firebase_id_token_claims", _raise)

        response = run_async(
            shopkeeper_auth.verify_phone(self._request(), ShopkeeperMockDB())
        )
        assert isinstance(response, JSONResponse)
        assert response.status_code == 401

    def test_verify_phone_missing_token(self):
        from fastapi.responses import JSONResponse

        from app.api.routes import shopkeeper_auth

        response = run_async(
            shopkeeper_auth.verify_phone(self._request(authorization=None), ShopkeeperMockDB())
        )
        assert isinstance(response, JSONResponse)
        assert response.status_code == 401

    def test_verify_phone_new_user(self, monkeypatch):
        from app.api.routes import shopkeeper_auth

        monkeypatch.setattr(
            shopkeeper_auth,
            "verify_firebase_id_token_claims",
            lambda token: ("fb-uid-new", "+919000000020"),
        )

        response = run_async(
            shopkeeper_auth.verify_phone(
                self._request(authorization="Bearer fb-token-new"),
                ShopkeeperMockDB(),
            )
        )
        body = bytes(response.body).decode()
        assert '"success":true' in body.replace(" ", "")
        data = json.loads(body.replace(" ", ""))["data"]
        assert data["is_new_user"] is True
        assert data["firebase_uid"] == "fb-uid-new"
        assert data["phone_number"] == "+919000000020"

    def test_verify_phone_existing_user_returns_login(self, monkeypatch):
        from app.api.routes import shopkeeper_auth
        from app.models.user import User

        monkeypatch.setattr(
            shopkeeper_auth,
            "verify_firebase_id_token_claims",
            lambda token: ("fb-uid-existing", "+919000000021"),
        )
        monkeypatch.setattr(
            shopkeeper_auth,
            "is_account_allowed",
            lambda user: True,
        )
        existing = make_user(user_id=9, phone="+919000000021", role_name="shopkeeper")
        existing.firebase_uid = "fb-uid-existing"
        db = ShopkeeperMockDB()
        db.queue_first(User, [existing])

        response = run_async(
            shopkeeper_auth.verify_phone(
                self._request(authorization="Bearer fb-token-existing"),
                db,
            )
        )
        body = bytes(response.body).decode()
        data = json.loads(body.replace(" ", ""))["data"]
        assert data["is_new_user"] is False
        assert "access_token" in data
        assert "refresh_token" in data
        assert data["user"]["phone_number"] == "+919000000021"


# ── Login ────────────────────────────────────────────────────────────────


class TestShopkeeperLogin:
    def test_login_invalid_token(self, monkeypatch):
        from fastapi.responses import JSONResponse

        from app.api.routes import shopkeeper_auth
        from app.services.firebase_verification import FirebaseVerificationError

        # Mock Firebase verification to reject the token.
        def _raise(token):
            raise FirebaseVerificationError("Invalid token")

        monkeypatch.setattr(shopkeeper_auth, "verify_firebase_id_token_claims", _raise)

        request = MagicMock()
        request.client.host = "127.0.0.1"
        db = ShopkeeperMockDB()
        payload = shopkeeper_auth.ShopkeeperOTPLoginRequest(
            firebase_id_token="bad-token-0000000000000"
        )
        response = run_async(shopkeeper_auth.verify_otp_login(payload, request, db))
        assert isinstance(response, JSONResponse)
        assert response.status_code == 401

    def test_login_unknown_account(self, monkeypatch):
        from fastapi.responses import JSONResponse

        from app.api.routes import shopkeeper_auth

        monkeypatch.setattr(
            shopkeeper_auth,
            "verify_firebase_id_token_claims",
            lambda token: "+919000000014",
        )

        request = MagicMock()
        request.client.host = "127.0.0.1"
        db = ShopkeeperMockDB()  # no user found

        payload = shopkeeper_auth.ShopkeeperOTPLoginRequest(
            firebase_id_token="fake-firebase-token-0000000000"
        )
        response = run_async(shopkeeper_auth.verify_otp_login(payload, request, db))
        assert isinstance(response, JSONResponse)
        assert response.status_code == 404

    def test_login_success_returns_tokens_and_shops(self, monkeypatch):
        from app.api.routes import shopkeeper_auth
        from app.models.user import User

        monkeypatch.setattr(
            shopkeeper_auth,
            "verify_firebase_id_token_claims",
            lambda token: "+919000000015",
        )

        request = MagicMock()
        request.client.host = "127.0.0.1"
        request.headers.get.return_value = "pytest"

        user = make_user(user_id=7, phone="+919000000015", role_name="shopkeeper")
        shop = make_shop()
        owner_row = make_owner(shop_id=10, user_id=7)

        db = ShopkeeperMockDB()
        db.queue_first(User, [user])
        # list_authorized_shops: ShopOwner.all → [row]; Shop.first → shop;
        # ShopManager.all → []
        db.set_all(type(owner_row), [owner_row])
        db.queue_first(type(shop), [shop])
        db.set_all(type(make_manager()), [])

        payload = shopkeeper_auth.ShopkeeperOTPLoginRequest(
            firebase_id_token="fake-firebase-token-0000000000", device_id="dev-2"
        )
        response = run_async(shopkeeper_auth.verify_otp_login(payload, request, db))
        body = bytes(response.body).decode()
        assert '"success":true' in body.replace(" ", "")
        assert "access_token" in body and "refresh_token" in body
        assert '"shops":[' in body.replace(" ", "")
        assert "Kirana Corner" in body


# ── Shop association / selection ─────────────────────────────────────────


class TestShopAssociation:
    def test_owner_can_access_own_shop(self):
        from app.services import shopkeeper_service as svc

        user = make_user(role_name="shopkeeper")
        shop = make_shop()
        db = ShopkeeperMockDB()
        db.queue_first(type(shop), [shop])
        db.queue_first(type(make_owner()), [make_owner(shop_id=10, user_id=1)])

        access = svc.resolve_shop_access(db, user, 10)
        assert access.is_owner is True
        assert access.can("shop", "update") is True
        assert access.can("product", "create") is True

    def test_manager_can_access_with_reduced_permissions(self):
        from app.services import shopkeeper_service as svc

        user = make_user(user_id=2, phone="+919000000002", role_name="shopkeeper")
        shop2 = make_shop(shop_id=20, name="Branch B")
        manager_row = make_manager(shop_id=20, user_id=2)

        db = ShopkeeperMockDB()
        db.queue_first(type(shop2), [shop2])
        db.queue_first(type(make_owner()), [None])  # not an owner here
        db.queue_first(type(manager_row), [manager_row])

        access = svc.resolve_shop_access(db, user, 20)
        assert access.role_name == "manager"
        assert access.can("product", "update") is True
        assert access.can("shop", "update") is False  # settings locked for managers

    def test_multi_shop_listing_enables_shop_selection(self):
        from app.services import shopkeeper_service as svc

        user = make_user(role_name="shopkeeper")
        shop_a = make_shop(shop_id=10, name="Main Store")
        shop_b = make_shop(shop_id=20, name="Branch B")
        owner_row = make_owner(shop_id=10, user_id=1)
        manager_row = make_manager(shop_id=20, user_id=1)

        db = ShopkeeperMockDB()
        db.set_all(type(owner_row), [owner_row])
        db.set_all(type(manager_row), [manager_row])
        db.queue_first(type(shop_a), [shop_a, shop_b])  # one lookup per membership row

        shops = svc.list_authorized_shops(db, user)
        ids = [s["id"] for s in shops]
        assert ids == [10, 20]
        memberships = {s["id"]: s["membership"] for s in shops}
        assert memberships[10] == "owner"
        assert memberships[20] == "manager"
        # Each entry carries its own effective permission set
        by_id = {s["id"]: s for s in shops}
        assert "update:shop" in by_id[10]["permissions"]
        assert "update:shop" not in by_id[20]["permissions"]



# ── Verification status ──────────────────────────────────────────────────


class TestVerificationStatus:
    def test_verification_defaults_to_pending_without_record(self):
        from app.services import shopkeeper_service as svc

        shop = make_shop()
        db = ShopkeeperMockDB()  # no ShopVerification rows
        payload = svc.verification_payload(db, shop)
        assert payload["status"] == "PENDING"
        assert payload["verified_at"] is None

    def test_verification_reflects_latest_record(self):
        from app.models.shop import ShopVerification, VerificationStatus
        from app.services import shopkeeper_service as svc

        record = ShopVerification(shop_id=10, status=VerificationStatus.UNDER_REVIEW)
        verified_at = datetime.now(timezone.utc) - timedelta(days=1)
        record.submitted_at = verified_at
        db = ShopkeeperMockDB()
        db.queue_first(ShopVerification, [record])

        payload = svc.verification_payload(db, make_shop())
        assert payload["status"] == "UNDER_REVIEW"

    def test_verified_shop_flags_is_verified(self):
        from app.services import shopkeeper_service as svc

        user = make_user(role_name="shopkeeper")
        shop = make_shop(status="VERIFIED", verified=True)
        db = ShopkeeperMockDB()
        db.queue_first(type(shop), [shop])
        db.queue_first(type(make_owner()), [make_owner()])

        access = svc.resolve_shop_access(db, user, 10)
        detail = svc.shop_detail_payload(access, db)
        assert detail["is_verified"] is True
        assert detail["verification"]["status"] == "PENDING"  # no record yet

    def test_dashboard_surfaces_verification_and_subscription(self):
        from app.models.product import Offer, OfferStatus, OfferType
        from app.models.subscription import Subscription, SubscriptionStatus
        from app.services import shopkeeper_service as svc

        user = make_user(role_name="shopkeeper")
        shop = make_shop()
        owner_row = make_owner()

        sp1 = make_shop_product(sp_id=101, quantity=30)   # in stock
        sp2 = make_shop_product(sp_id=102, master_name="Sugar 1kg", quantity=3)  # low
        sp3 = make_shop_product(sp_id=103, master_name="Atta 5kg", quantity=0,
                                active=False, available=False)  # out (inactive)

        now = datetime.now(timezone.utc)
        offer = Offer(
            shop_id=10, title="Diwali Sale", offer_type=OfferType.PERCENTAGE_DISCOUNT,
            status=OfferStatus.ACTIVE, start_date=now - timedelta(days=1),
            end_date=now + timedelta(days=7),
        )
        subscription = Subscription(user_id=1, shop_id=10, plan_id=1,
                                    status=SubscriptionStatus.ACTIVE)

        from app.models.product import Inventory, Offer, ShopProduct
        from app.models.shop import ShopVerification
        from app.models.subscription import Subscription as SubModel

        db = ShopkeeperMockDB()
        db.queue_first(type(shop), [shop])
        db.queue_first(type(owner_row), [owner_row])
        db.set_all(ShopProduct, [sp1, sp2, sp3])
        # Inventory lookups per product, FIFO: inv(sp1), inv(sp2), inv(sp3)
        db.queue_first(Inventory, [sp1.inventory, sp2.inventory, sp3.inventory])
        db.set_all(Offer, [offer])
        db.queue_first(ShopVerification, [None])
        db.queue_first(SubModel, [subscription])

        access = svc.resolve_shop_access(db, user, 10)
        dashboard = svc.dashboard_payload(access, db)

        assert dashboard["products"]["total"] == 3
        assert dashboard["products"]["active"] == 2  # sp3 inactive
        assert dashboard["inventory_status"]["in_stock"] == 1
        assert dashboard["inventory_status"]["low_stock"] == 1
        assert dashboard["inventory_status"]["out_of_stock"] == 1
        assert len(dashboard["recent_updates"]) == 3
        assert dashboard["offers"]["active"] == 1
        assert dashboard["subscription"]["status"] == "ACTIVE"
        assert dashboard["verification"]["status"] == "PENDING"



    # ── Business Insights ────────────────────────────────────────────────────
    def test_insights_returns_all_six_cards(self):
        from app.models.product import (
            Inventory, Offer, OfferProduct, OfferStatus, OfferType,
            ProductMaster, ShopProduct, StockStatus,
        )
        from app.models.shop import ShopCategory, ShopStatus
        from app.models.subscription import Subscription, SubscriptionStatus
        from app.services import shopkeeper_service as svc

        user = make_user(role_name="shopkeeper")
        shop = make_shop()
        owner_row = make_owner()

        sp1 = make_shop_product(sp_id=101, master_name="Rice 1kg", price=120.0,
                                 quantity=50, threshold=10, active=True)
        sp1.last_inventory_update = datetime.now(timezone.utc) - timedelta(hours=1)
        sp1.last_price_update = datetime.now(timezone.utc) - timedelta(hours=2)

        sp2 = make_shop_product(sp_id=102, master_name="Sugar 1kg", price=60.0,
                                 quantity=3, threshold=10, active=True)
        sp2.last_inventory_update = datetime.now(timezone.utc) - timedelta(days=5)

        sp3 = make_shop_product(sp_id=103, master_name="Atta 5kg", price=250.0,
                                 quantity=0, threshold=5, active=True)
        sp3.last_inventory_update = datetime.now(timezone.utc) - timedelta(days=15)

        sp4 = make_shop_product(sp_id=104, master_name="Old Product", price=50.0,
                                 quantity=0, threshold=5, active=False)
        sp4.last_inventory_update = datetime.now(timezone.utc) - timedelta(days=60)

        sp5 = make_shop_product(sp_id=105, master_name="Stale Item", price=80.0,
                                 quantity=20, threshold=5, active=True)
        sp5.last_inventory_update = datetime.now(timezone.utc) - timedelta(days=45)
        sp5.last_price_update = datetime.now(timezone.utc) - timedelta(days=45)

        now = datetime.now(timezone.utc)
        offer = Offer(shop_id=10, title="Diwali Sale",
                      offer_type=OfferType.PERCENTAGE_DISCOUNT,
                      status=OfferStatus.ACTIVE, discount_percentage=15.0,
                      start_date=now - timedelta(days=1),
                      end_date=now + timedelta(days=7))
        offer.id = 1
        op1 = OfferProduct(offer_id=1, shop_product_id=101)
        op1.id = 1
        offer.offer_products = [op1]

        draft_offer = Offer(shop_id=10, title="New Year Sale",
                            offer_type=OfferType.FLAT_DISCOUNT,
                            status=OfferStatus.DRAFT, discount_value=500.0,
                            start_date=now, end_date=now + timedelta(days=30))
        draft_offer.id = 2

        subscription = Subscription(user_id=1, shop_id=10, plan_id=1,
                                     status=SubscriptionStatus.ACTIVE)

        db = ShopkeeperMockDB()
        db.queue_first(type(shop), [shop])
        db.queue_first(type(owner_row), [owner_row])
        db.set_all(ShopProduct, [sp1, sp2, sp3, sp4, sp5])
        db.queue_first(Inventory, [sp1.inventory, sp2.inventory, sp3.inventory,
                                    sp4.inventory, sp5.inventory])
        db.set_all(Offer, [offer, draft_offer])
        db.set_all(OfferProduct, [op1])
        db.queue_first(type(subscription), [subscription])

        sp1.product_master.image_url = "https://example.com/rice.jpg"
        sp2.product_master.image_url = "https://example.com/sugar.jpg"
        sp3.product_master.image_url = "https://example.com/atta.jpg"
        sp5.product_master.image_url = "https://example.com/stale.jpg"

        access = svc.resolve_shop_access(db, user, 10)
        insights = svc.business_insights(access, db)

        assert "shop" in insights
        assert insights["shop"]["id"] == 10
        assert insights["shop"]["name"] == "Kirana Corner"
        assert "generated_at" in insights
        assert "insights" in insights
        assert len(insights["insights"]) == 6

        by_id = {card["id"]: card for card in insights["insights"]}

        top = by_id["top_products"]
        assert top["title"] == "Top Products"
        assert top["status"] == "warning"
        assert top["metrics"]["total_products"] == 5
        assert top["metrics"]["active_products"] == 4
        assert top["metrics"]["ranked_count"] == 4
        assert len(top["items"]) == 4
        assert top["items"][0]["shop_product_id"] == 101
        assert top["items"][0]["name"] == "Rice 1kg"
        assert top["items"][0]["stock_value"] == 6000.0
        top_ids = {item["shop_product_id"] for item in top["items"]}
        assert 104 not in top_ids

        low = by_id["low_stock"]
        assert low["title"] == "Low Stock Alert"
        assert low["status"] == "warning"
        assert low["metrics"]["count"] == 1
        assert low["metrics"]["total_products"] == 5
        assert low["metrics"]["percentage"] == 20.0
        assert low["metrics"]["total_gap_units"] == 7
        assert len(low["items"]) == 1
        assert low["items"][0]["shop_product_id"] == 102
        assert low["items"][0]["name"] == "Sugar 1kg"
        assert low["items"][0]["gap"] == 7
        assert low["suggestion"] is not None
        stale = by_id["stale_inventory"]
        assert stale["title"] == "Stale Inventory"
        assert stale["status"] == "warning"
        assert stale["metrics"]["count"] == 1
        assert stale["metrics"]["oldest_stale_days"] >= 44
        assert len(stale["items"]) == 1
        assert stale["items"][0]["shop_product_id"] == 105
        assert stale["items"][0]["name"] == "Stale Item"
        stale_ids = {item["shop_product_id"] for item in stale["items"]}
        assert 104 not in stale_ids
        assert 103 not in stale_ids

        visibility = by_id["search_visibility"]
        assert visibility["title"] == "Product Search Visibility"
        assert visibility["metrics"]["total_products"] == 5
        assert visibility["metrics"]["visible_products"] == 4
        assert visibility["metrics"]["visibility_percentage"] == 80.0
        assert visibility["metrics"]["products_without_images"] == 0
        assert visibility["status"] == "healthy"
        assert "by_status" in visibility["metrics"]

        offers = by_id["offers_performance"]
        assert offers["title"] == "Offers Performance"
        assert offers["metrics"]["total_offers"] == 2
        assert offers["metrics"]["active_offers"] == 1
        assert offers["metrics"]["draft_offers"] == 1
        assert offers["metrics"]["expiring_soon"] == 1
        assert offers["metrics"]["offer_coverage_percentage"] == 25.0
        assert offers["metrics"]["products_with_offers"] == 1
        assert offers["metrics"]["by_type"]["PERCENTAGE_DISCOUNT"] == 1
        assert offers["metrics"]["by_type"]["FLAT_DISCOUNT"] == 1
        assert len(offers["items"]) == 1
        assert offers["items"][0]["offer_id"] == 1
        assert offers["items"][0]["title"] == "Diwali Sale"
        assert offers["items"][0]["offer_type"] == "PERCENTAGE_DISCOUNT"
        assert offers["items"][0]["discount_percentage"] == 15.0
        assert offers["items"][0]["is_expiring_soon"] is True
        assert offers["suggestion"] is None

        profile = by_id["profile_completeness"]
        assert profile["title"] == "Profile Completeness"
        assert profile["metrics"]["total_fields"] == 12
        assert profile["metrics"]["completed_fields"] == 2
        assert profile["metrics"]["completeness_percentage"] == round(2 / 12 * 100, 1)
        assert profile["metrics"]["missing_fields_count"] == 10
        assert len(profile["items"]) == 10
        missing_fields = {item["field"] for item in profile["items"]}
        assert "name" not in missing_fields
        assert "category" not in missing_fields
        assert "description" in missing_fields
        assert "phone" in missing_fields
        assert profile["status"] == "critical"

        assert low["suggestion"] is not None
        assert "restock" in low["suggestion"].lower()
        assert stale["suggestion"] is not None
        assert profile["suggestion"] is not None
        assert "complete" in profile["suggestion"].lower()
        assert top["suggestion"] is None

    def test_insights_empty_shop(self):
        from app.models.product import Offer, ShopProduct
        from app.models.shop import ShopCategory, ShopStatus
        from app.services import shopkeeper_service as svc

        user = make_user(role_name="shopkeeper")
        shop = make_shop(shop_id=20, name="Empty Shop")
        owner_row = make_owner(shop_id=20)

        db = ShopkeeperMockDB()
        db.queue_first(type(shop), [shop])
        db.queue_first(type(owner_row), [owner_row])
        db.set_all(ShopProduct, [])
        db.set_all(Offer, [])

        access = svc.resolve_shop_access(db, user, 20)
        insights = svc.business_insights(access, db)

        assert len(insights["insights"]) == 6

    def test_insights_expired_offer_not_active(self):
        from app.models.product import (
            Inventory, Offer, OfferProduct, OfferStatus, OfferType,
            ProductMaster, ShopProduct, StockStatus,
        )
        from app.models.shop import ShopCategory, ShopStatus
        from app.services import shopkeeper_service as svc

        user = make_user(role_name="shopkeeper")
        shop = make_shop()
        owner_row = make_owner()

        sp1 = make_shop_product(sp_id=301, master_name="Test Product", price=100.0,
                                 quantity=20, threshold=5, active=True)
        sp1.last_inventory_update = datetime.now(timezone.utc) - timedelta(days=1)
        sp1.product_master.image_url = "https://example.com/test.jpg"

        now = datetime.now(timezone.utc)
        expired_offer = Offer(shop_id=10, title="Old Sale",
                              offer_type=OfferType.PERCENTAGE_DISCOUNT,
                              status=OfferStatus.ACTIVE, discount_percentage=10.0,
                              start_date=now - timedelta(days=60),
                              end_date=now - timedelta(days=30))
        expired_offer.id = 1
        op1 = OfferProduct(offer_id=1, shop_product_id=301)
        op1.id = 1
        expired_offer.offer_products = [op1]

        db = ShopkeeperMockDB()
        db.queue_first(type(shop), [shop])
        db.queue_first(type(owner_row), [owner_row])
        db.set_all(ShopProduct, [sp1])
        db.queue_first(Inventory, [sp1.inventory])
        db.set_all(Offer, [expired_offer])
        db.set_all(OfferProduct, [op1])

        access = svc.resolve_shop_access(db, user, 10)
        insights = svc.business_insights(access, db)

        offers = {card["id"]: card for card in insights["insights"]}["offers_performance"]
        assert offers["metrics"]["active_offers"] == 0
        assert offers["metrics"]["expiring_soon"] == 0
        assert offers["items"] == []


# ── Business insights endpoint (GET /shopkeeper/shops/{id}/insights) ─────────


class TestShopkeeperInsightsRoute:
    """Route-level coverage: envelope shape + shop-scoped authorization."""

    def test_insights_route_returns_all_six_cards(self):
        from app.api.routes import shopkeeper_portal
        from app.models.product import (
            Inventory,
            Offer,
            OfferStatus,
            OfferType,
            ShopProduct,
        )

        user = make_user(role_name="shopkeeper")
        shop = make_shop()
        owner_row = make_owner()

        sp1 = make_shop_product(sp_id=401, master_name="Route Rice",
                                price=100.0, quantity=10, threshold=5, active=True)
        sp1.product_master.image_url = "https://example.com/route-rice.jpg"

        now = datetime.now(timezone.utc)
        offer = Offer(shop_id=10, title="Route Sale",
                      offer_type=OfferType.PERCENTAGE_DISCOUNT,
                      status=OfferStatus.ACTIVE, discount_percentage=5.0,
                      start_date=now - timedelta(days=1),
                      end_date=now + timedelta(days=3))
        offer.id = 9
        offer.offer_products = []

        db = ShopkeeperMockDB()
        db.queue_first(type(shop), [shop])
        db.queue_first(type(owner_row), [owner_row])
        db.set_all(ShopProduct, [sp1])
        db.queue_first(Inventory, [sp1.inventory])
        db.set_all(Offer, [offer])

        response = run_async(shopkeeper_portal.get_insights(10, user, db))
        body = json.loads(bytes(response.body).decode())

        assert response.status_code == 200
        assert body["success"] is True
        assert body["data"]["shop"]["id"] == 10
        assert "generated_at" in body["data"]
        cards = {card["id"] for card in body["data"]["insights"]}
        assert cards == {
            "top_products",
            "low_stock",
            "stale_inventory",
            "search_visibility",
            "offers_performance",
            "profile_completeness",
        }

    def test_insights_route_rejects_unauthorized_shop(self):
        from app.api.routes import shopkeeper_portal
        from app.core.exceptions import ForbiddenError

        customer = make_user(role_name="customer")
        shop = make_shop(shop_id=88, name="Someone Else")
        db = ShopkeeperMockDB()
        db.queue_first(type(shop), [shop])
        db.queue_first(type(make_owner()), [None])
        db.queue_first(type(make_manager()), [None])

        # Direct route invocation surfaces the domain error; FastAPI's exception
        # handlers translate it to an HTTP 403 on the wire.
        with pytest.raises(ForbiddenError):
            run_async(shopkeeper_portal.get_insights(88, customer, db))




# ── Unauthorized shop access ─────────────────────────────────────────────


class TestUnauthorizedShopAccess:
    def test_customer_role_cannot_access_someone_elses_shop(self):
        from app.core.exceptions import ForbiddenError
        from app.services import shopkeeper_service as svc

        customer = make_user(role_name="customer")
        shop = make_shop(shop_id=99, name="Not Mine")
        db = ShopkeeperMockDB()
        db.queue_first(type(shop), [shop])
        db.queue_first(type(make_owner()), [None])
        db.queue_first(type(make_manager()), [None])

        with pytest.raises(ForbiddenError):
            svc.resolve_shop_access(db, customer, 99)

    def test_no_role_user_cannot_access(self):
        from app.core.exceptions import ForbiddenError
        from app.services import shopkeeper_service as svc

        user = make_user()  # no role
        shop = make_shop(shop_id=99)
        db = ShopkeeperMockDB()
        db.queue_first(type(shop), [shop])
        db.queue_first(type(make_owner()), [None])
        db.queue_first(type(make_manager()), [None])

        with pytest.raises(ForbiddenError):
            svc.resolve_shop_access(db, user, 99)

    def test_missing_shop_raises_not_found(self):
        from app.core.exceptions import NotFoundError
        from app.services import shopkeeper_service as svc

        db = ShopkeeperMockDB()
        db.queue_first(type(make_shop()), [None])
        with pytest.raises(NotFoundError):
            svc.resolve_shop_access(db, make_user(), 12345)

    def test_portal_dependency_enforces_403(self):
        from app.core.exceptions import ForbiddenError
        from app.api.routes import shopkeeper_portal

        customer = make_user(role_name="customer")
        shop = make_shop(shop_id=77, name="Someone Else")
        db = ShopkeeperMockDB()
        db.queue_first(type(shop), [shop])
        db.queue_first(type(make_owner()), [None])
        db.queue_first(type(make_manager()), [None])

        resolver = shopkeeper_portal.shop_access_dependency(77)
        # Direct dependency invocation surfaces the domain error; FastAPI's
        # exception handlers translate it to an HTTP 403 on the wire.
        with pytest.raises(ForbiddenError):
            resolver(current_user=customer, db=db)

    def test_inactive_owner_row_denies_access(self):
        """Revoked ownership (is_active=False row) is invisible to queries —
        the DB-level filter returns no active row, so access must be denied."""
        from app.core.exceptions import ForbiddenError
        from app.services import shopkeeper_service as svc

        user = make_user()
        shop = make_shop()

        db = ShopkeeperMockDB()
        db.queue_first(type(shop), [shop])
        # The scoped query filters is_active=True, so a revoked row never comes back.
        db.queue_first(type(make_owner()), [None])
        db.queue_first(type(make_manager()), [None])

        with pytest.raises(ForbiddenError):
            svc.resolve_shop_access(db, user, 10)

    def test_products_require_read_permission(self):
        from app.core.exceptions import ForbiddenError
        from app.services.shopkeeper_service import ShopAccess
        from app.services import shopkeeper_service as svc

        shop = make_shop()
        access = ShopAccess(shop=shop, role_name="manager", is_owner=False,
                            permissions=set())
        with pytest.raises(ForbiddenError):
            access.require("product", "read")


# ── Logout ───────────────────────────────────────────────────────────────


class TestShopkeeperLogout:
    def test_logout_route_revokes_session_and_commits(self):
        from app.api.routes import shopkeeper_auth

        user = make_user(user_id=9)
        db = ShopkeeperMockDB()
        captured = {}

        def fake_logout(db_arg, user_arg, session_id=None, revoke_all=False):
            captured["session_id"] = session_id
            captured["revoke_all"] = revoke_all
            return {"revoked": True}

        with pytest.MonkeyPatch.context() as mp:
            # Patch where the route actually looks it up (module namespace).
            mp.setattr(shopkeeper_auth, "logout_session", fake_logout)

            payload = shopkeeper_auth.ShopkeeperLogoutRequest(session_id="sess-1")
            response = run_async(
                shopkeeper_auth.logout(payload, current_user=user, db=db)
            )

        assert captured["session_id"] == "sess-1"
        assert db.committed == 1
        body = bytes(response.body).decode()
        assert '"success":true' in body.replace(" ", "")



# ── Shop registration & product management foundation ───────────────────


class TestShopAndProductFoundation:
    def test_register_shop_assigns_primary_owner_and_verification(self):
        from app.models.shop import ShopOwner, ShopVerification
        from app.services import shopkeeper_service as svc

        user = make_user(role_name="shopkeeper")
        db = ShopkeeperMockDB()

        shop = svc.register_shop_for_shopkeeper(
            db,
            user,
            {
                "name": "New Corner Store",
                "category": "grocery",
                "latitude": 12.9716,
                "longitude": 77.5946,
                "address": {
                    "address_line1": "12 MG Road",
                    "city": "Bengaluru",
                    "state": "Karnataka",
                    "pincode": "560001",
                },
            },
        )

        owners = [o for o in db.added if isinstance(o, ShopOwner)]
        assert len(owners) == 1
        assert owners[0].user_id == user.id and owners[0].is_primary
        verifications = [v for v in db.added if isinstance(v, ShopVerification)]
        assert len(verifications) == 1  # initial PENDING verification record

    def test_register_shop_rejects_bad_category(self):
        from app.core.exceptions import ValidationError
        from app.services import shopkeeper_service as svc

        db = ShopkeeperMockDB()
        with pytest.raises(ValidationError):
            svc.register_shop_for_shopkeeper(
                db,
                make_user(role_name="shopkeeper"),
                {
                    "name": "X",
                    "category": "SPACESHIPS",
                    "latitude": 12.0,
                    "longitude": 77.0,
                    "address": {"address_line1": "a", "city": "c",
                                "state": "s", "pincode": "1"},
                },
            )

    def test_create_product_builds_master_shopproduct_inventory(self):
        from app.models.product import Inventory, ProductMaster, ShopProduct
        from app.services import shopkeeper_service as svc
        from app.services.shopkeeper_service import ShopAccess

        user = make_user()
        shop = make_shop()
        access = ShopAccess(shop=shop, role_name="owner", is_owner=True)
        db = ShopkeeperMockDB()

        product = svc.create_product(
            access,
            db,
            user,
            {"name": "Basmati Rice 5kg", "price": 480.0, "mrp": 550.0,
             "quantity": 40, "publish": True},
        )

        assert product["name"] == "Basmati Rice 5kg"
        assert product["quantity"] == 40
        assert product["stock_status"] == "IN_STOCK"
        masters = [o for o in db.added if isinstance(o, ProductMaster)]
        sps = [o for o in db.added if isinstance(o, ShopProduct)]
        invs = [o for o in db.added if isinstance(o, Inventory)]
        assert len(masters) == len(sps) == len(invs) == 1

    def test_create_product_rejects_mrp_below_price(self):
        from app.core.exceptions import ValidationError
        from app.services import shopkeeper_service as svc
        from app.services.shopkeeper_service import ShopAccess

        db = ShopkeeperMockDB()
        access = ShopAccess(shop=make_shop(), role_name="owner", is_owner=True)
        with pytest.raises(ValidationError):
            svc.create_product(
                access, db, make_user(),
                {"name": "Bad Pricing", "price": 500.0, "mrp": 400.0},
            )


    def test_update_product_stock_updates_status_and_timestamp(self):
        from datetime import datetime as dt

        from app.services import shopkeeper_service as svc
        from app.services.shopkeeper_service import ShopAccess

        sp = make_shop_product(sp_id=200, quantity=50)
        old_stamp = dt.now(timezone.utc) - timedelta(days=1)
        sp.last_inventory_update = old_stamp

        inv = sp.inventory

        db = ShopkeeperMockDB()
        db.queue_first(type(sp), [sp])
        db.queue_first(type(inv), [inv])

        access = ShopAccess(shop=make_shop(), role_name="owner", is_owner=True)
        result = svc.update_product(access, db, make_user(), 200, {"quantity": 2})

        assert result["stock_status"] == "LOW_STOCK"
        assert result["quantity"] == 2
        assert result["is_available"] is True
        assert sp.last_inventory_update > old_stamp

    def test_update_product_zero_quantity_marks_unavailable(self):
        from app.services import shopkeeper_service as svc
        from app.services.shopkeeper_service import ShopAccess

        sp = make_shop_product(sp_id=201, quantity=10)
        inv = sp.inventory
        db = ShopkeeperMockDB()
        db.queue_first(type(sp), [sp])
        db.queue_first(type(inv), [inv])

        access = ShopAccess(shop=make_shop(), role_name="owner", is_owner=True)
        result = svc.update_product(access, db, make_user(), 201, {"quantity": 0})
        assert result["is_available"] is False
        assert result["stock_status"] == "OUT_OF_STOCK"

    def test_update_product_cannot_touch_other_shops_inventory(self):
        from app.core.exceptions import NotFoundError
        from app.services import shopkeeper_service as svc
        from app.services.shopkeeper_service import ShopAccess

        # Product belongs to shop 10; accessor's shop is 99 → scoped query misses.
        sp = make_shop_product(sp_id=202)
        sp.shop_id = 10
        db = ShopkeeperMockDB()
        db.queue_first(type(sp), [None])

        other_shop = make_shop(shop_id=99)
        access = ShopAccess(shop=other_shop, role_name="owner", is_owner=True)
        with pytest.raises(NotFoundError):
            svc.update_product(access, db, make_user(), 202, {"price": 9.0})


# ── Route registration ───────────────────────────────────────────────────


class TestRouteRegistration:
    def test_shopkeeper_routers_registered_in_main(self):
        from app.main import app

        paths = set(app.openapi()["paths"].keys())
        expected = [
            "/api/v1/shopkeeper/auth/send-otp",
            "/api/v1/shopkeeper/auth/register",
            "/api/v1/shopkeeper/auth/login",
            "/api/v1/shopkeeper/auth/refresh",
            "/api/v1/shopkeeper/auth/logout",
            "/api/v1/shopkeeper/auth/me",
            "/api/v1/shopkeeper/shops",
            "/api/v1/shopkeeper/shops/{shop_id}",
            "/api/v1/shopkeeper/shops/{shop_id}/dashboard",
            "/api/v1/shopkeeper/shops/{shop_id}/insights",
            "/api/v1/shopkeeper/shops/{shop_id}/inventory",
            "/api/v1/shopkeeper/shops/{shop_id}/products",
            "/api/v1/shopkeeper/shops/{shop_id}/profile",
            "/api/v1/shopkeeper/shops/{shop_id}/settings",
        ]
        for path in expected:
            assert path in paths, f"missing route: {path}"

    def test_customer_routes_untouched_by_shopkeeper_module(self):
        """Shopkeeper logic must NOT leak into customer endpoints."""
        from app.main import app

        paths = set(app.openapi()["paths"].keys())
        # Customer auth still lives at /auth/*
        assert "/api/v1/auth/send-otp" in paths
        assert "/api/v1/auth/verify-otp" in paths

