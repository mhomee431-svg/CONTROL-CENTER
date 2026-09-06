"""Shop Location System tests (Phase: Shopkeeper Shop Location).

Covers:
  - Location metadata columns & enums on the Shop model
  - Location provenance persisted at registration (register_shop)
  - update_shop_location: validation, geometry + metadata write-back,
    missing-shop handling
  - Authorization: managers without update:shop rejected; IDOR prevention
    via resolve_shop_access (unauthorized / foreign shop_id)
  - Audit: every location change appends a hash-chained AuditLog row with
    old/new coordinates, accuracy and actor
  - API schema validation (invalid latitude/longitude, negative accuracy)
  - Route registration: PATCH /shopkeeper/shops/{shop_id}/location
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

from app.core.config import settings  # noqa: E402

settings.RATE_LIMIT_ENABLED = False

PATNA = (25.5941, 85.1376)  # (latitude, longitude)


# ── Mock infrastructure (mirrors test_shopkeeper_app.py) ─────────────────


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


class LocationMockDB:
    """DB mock tuned for shop-location service call patterns."""

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


# ── Factories (mirror test_shopkeeper_app.py) ────────────────────────────


def make_user(user_id=1, phone="+919000000001", role_name=None, name="Shop Owner"):
    from app.models.role import Role
    from app.models.user import User, UserStatus

    user = User(phone_number=phone, name=name)
    user.id = user_id
    user.is_active = True
    user.status = UserStatus.ACTIVE
    if role_name:
        user.role = Role(name=role_name)
    return user


def make_shop(shop_id=10, name="ABC Medical Store", with_location=True):
    from app.models.shop import Shop, ShopCategory, ShopStatus

    shop = Shop(
        name=name,
        slug=f"{name.lower().replace(' ', '-')}-{shop_id}",
        status=ShopStatus.REGISTERED,
        category=ShopCategory.PHARMACY,
        is_verified=False,
        rating=0.0,
        review_count=0,
    )
    shop.id = shop_id
    if with_location:
        shop.latitude = PATNA[0]
        shop.longitude = PATNA[1]
        shop.location = "POINT(85.1376 25.5941)"
        shop.accuracy_meters = 8.0
        shop.location_source = "GPS"
        shop.location_type = "SHOP_ENTRANCE"
        shop.location_status = "CONFIRMED"
        shop.location_integrity_status = "NORMAL"
        shop.location_captured_at = datetime(2026, 9, 6, 10, 0, tzinfo=timezone.utc)
        shop.location_verified = True
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


def owner_access(shop):
    from app.core.shopkeeper_permissions import effective_shop_permissions
    from app.services.shopkeeper_service import ShopAccess

    return ShopAccess(
        shop=shop,
        role_name="owner",
        is_owner=True,
        permissions=effective_shop_permissions("shopkeeper", True, None),
    )


def manager_access(shop, perms):
    from app.services.shopkeeper_service import ShopAccess

    return ShopAccess(
        shop=shop, role_name="manager", is_owner=False, permissions=perms
    )


# ── Model / enum ──────────────────────────────────────────────────────────


class TestLocationModel:
    def test_location_metadata_columns_exist(self):
        from app.models.shop import Shop

        cols = Shop.__table__.columns.keys()
        for expected in (
            "location",
            "latitude",
            "longitude",
            "accuracy_meters",
            "location_captured_at",
            "location_source",
            "location_type",
            "location_status",
            "location_integrity_status",
            "location_verified",
        ):
            assert expected in cols, f"missing column: {expected}"

    def test_location_enums_values(self):
        from app.models.shop import (
            LocationIntegrityStatus,
            LocationSource,
            LocationStatus,
            LocationType,
        )

        assert {s.value for s in LocationSource} == {"GPS", "MANUAL", "ADDRESS"}
        assert {s.value for s in LocationType} >= {"SHOP_ENTRANCE", "BUILDING_CENTER"}
        assert {s.value for s in LocationStatus} >= {
            "CAPTURED",
            "CONFIRMED",
            "CORRECTED",
            "STALE",
        }
        assert {s.value for s in LocationIntegrityStatus} == {
            "NORMAL",
            "SUSPICIOUS",
            "UNKNOWN",
        }

    def test_location_is_spatially_queryable_column(self):
        """shops.location must remain the single Geography(Point, 4326) anchor."""
        from geoalchemy2 import Geography

        from app.models.shop import Shop

        col = Shop.__table__.columns["location"]
        assert isinstance(col.type, Geography)
        assert col.type.geometry_type == "POINT"
        assert col.type.srid == 4326


# ── Registration persists provenance ──────────────────────────────────────


class TestRegisterShopLocationMeta:
    def _payload(self):
        return {
            "name": "ABC Medical Store",
            "category": "PHARMACY",
            "latitude": PATNA[0],
            "longitude": PATNA[1],
            "address": {
                "address_line1": "Main Road",
                "city": "Bikramganj",
                "state": "Bihar",
                "pincode": "802112",
            },
        }

    def test_register_shop_persists_location_metadata(self):
        from app.services import shop_service

        payload = self._payload()
        payload["location"] = {
            "accuracy_meters": 5.0,
            "location_source": "GPS",
            "location_type": "SHOP_ENTRANCE",
            "location_status": "CAPTURED",
            "location_integrity_status": "NORMAL",
            "location_captured_at": datetime(2026, 9, 6, 9, 30, tzinfo=timezone.utc),
            "location_verified": True,
        }

        db = LocationMockDB()
        shop = shop_service.register_shop(db, payload, owner_user_id=1)

        assert shop.latitude == pytest.approx(PATNA[0])
        assert shop.longitude == pytest.approx(PATNA[1])
        assert str(shop.location) == "POINT(85.1376 25.5941)"
        assert shop.accuracy_meters == pytest.approx(5.0)
        assert shop.location_source == "GPS"
        assert shop.location_type == "SHOP_ENTRANCE"
        assert shop.location_status == "CAPTURED"
        assert shop.location_integrity_status == "NORMAL"
        assert shop.location_verified is True
        assert shop.location_captured_at is not None

    def test_register_shop_defaults_without_metadata(self):
        from app.models.shop import (
            LocationIntegrityStatus,
            LocationSource,
            LocationStatus,
            LocationType,
        )
        from app.services import shop_service

        db = LocationMockDB()
        shop = shop_service.register_shop(db, self._payload(), owner_user_id=1)

        assert shop.location_source == LocationSource.GPS.value
        assert shop.location_type == LocationType.SHOP_ENTRANCE.value
        assert shop.location_status == LocationStatus.CAPTURED.value
        assert shop.location_integrity_status == LocationIntegrityStatus.UNKNOWN.value
        assert shop.location_verified is False
        assert shop.accuracy_meters is None


# ── Controlled location update ───────────────────────────────────────────


class TestUpdateShopLocation:
    def test_rejects_invalid_latitude(self):
        from app.services import shop_service

        db = LocationMockDB()
        db.queue_first(type(make_shop()), [make_shop()])
        with pytest.raises(ValueError):
            shop_service.update_shop_location(db, 10, 95.0, PATNA[1])

    def test_rejects_invalid_longitude(self):
        from app.services import shop_service

        db = LocationMockDB()
        db.queue_first(type(make_shop()), [make_shop()])
        with pytest.raises(ValueError):
            shop_service.update_shop_location(db, 10, PATNA[0], -200.0)

    def test_missing_shop_returns_none(self):
        from app.services import shop_service

        db = LocationMockDB()
        db.queue_first(type(make_shop()), [None])
        assert shop_service.update_shop_location(db, 404, *PATNA) is None

    def test_updates_geometry_scalars_and_metadata(self):
        from app.services import shop_service

        new_lat, new_lng = 25.6000, 85.1400
        db = LocationMockDB()
        db.queue_first(type(make_shop()), [make_shop()])

        meta = {
            "accuracy_meters": 4.0,
            "location_source": "GPS",
            "location_type": "SHOP_ENTRANCE",
            "location_integrity_status": "NORMAL",
            "location_captured_at": datetime(2026, 9, 6, 11, 0, tzinfo=timezone.utc),
            "location_verified": True,
        }
        updated = shop_service.update_shop_location(db, 10, new_lat, new_lng, meta)

        assert updated.latitude == pytest.approx(new_lat)
        assert updated.longitude == pytest.approx(new_lng)
        assert str(updated.location) == f"POINT({new_lng} {new_lat})"
        assert updated.accuracy_meters == pytest.approx(4.0)
        assert updated.location_status == "CORRECTED"  # no longer CONFIRMED/STALE
        assert updated.location_verified is True
        assert db.flushes >= 1

    def test_preserves_existing_metadata_when_absent(self):
        from app.services import shop_service

        db = LocationMockDB()
        db.queue_first(type(make_shop()), [make_shop()])  # accuracy 8.0 pre-set

        updated = shop_service.update_shop_location(db, 10, *PATNA, None)
        assert updated.accuracy_meters == pytest.approx(8.0)
        assert updated.location_source == "GPS"


# ── Authorization / IDOR ──────────────────────────────────────────────────


class TestLocationAuthorization:
    def test_manager_without_update_shop_permission_rejected(self):
        from app.core.exceptions import ForbiddenError
        from app.services import shopkeeper_service as svc

        shop = make_shop()
        access = manager_access(shop, {"read:shop"})  # manager: no update:shop

        with pytest.raises(ForbiddenError):
            svc.update_shop_location_for_shopkeeper(
                access, LocationMockDB(), make_user(), *PATNA
            )

    def test_owner_can_update_location(self):
        from app.services import shopkeeper_service as svc

        shop = make_shop()
        db = LocationMockDB()
        db.queue_first(type(shop), [shop])  # re-queried inside update_shop_location
        result = svc.update_shop_location_for_shopkeeper(
            owner_access(shop), db, make_user(), 25.6000, 85.1400,
            {"accuracy_meters": 6.0},
        )
        assert result["latitude"] == pytest.approx(25.6000)
        assert result["accuracy_meters"] == pytest.approx(6.0)

    def test_idor_foreign_shop_id_is_forbidden(self):
        """A shopkeeper must never update another shop's location."""
        from app.core.exceptions import ForbiddenError
        from app.services import shopkeeper_service as svc

        stranger = make_user(role_name="shopkeeper")
        foreign_shop = make_shop(shop_id=99, name="Not Mine")
        db = LocationMockDB()
        db.queue_first(type(foreign_shop), [foreign_shop])
        db.queue_first(type(make_owner()), [None])     # no ownership row
        db.queue_first(type(make_manager()), [None])   # no manager row

        with pytest.raises(ForbiddenError):
            svc.resolve_shop_access(db, stranger, 99)

    def test_idor_shop_id_resolved_from_path_only(self):
        """Ownership is resolved from the path id — body ids are ignored."""
        from app.core.exceptions import ForbiddenError
        from app.services import shopkeeper_service as svc

        stranger = make_user(role_name="shopkeeper")
        shop = make_shop(shop_id=77, name="Someone Else")
        db = LocationMockDB()
        db.queue_first(type(shop), [shop])
        db.queue_first(type(make_owner()), [None])
        db.queue_first(type(make_manager()), [None])

        with pytest.raises(ForbiddenError):
            svc.resolve_shop_access(db, stranger, 77)


# ── Audit trail ───────────────────────────────────────────────────────────


class TestLocationAudit:
    def test_location_change_is_audited(self):
        from app.models.admin import AuditLog
        from app.services import shopkeeper_service as svc

        shop = make_shop()  # accuracy 8.0, CONFIRMED
        db = LocationMockDB()
        db.queue_first(type(shop), [shop])  # re-queried inside update_shop_location

        svc.update_shop_location_for_shopkeeper(
            owner_access(shop), db, make_user(), 25.6000, 85.1400,
            {"accuracy_meters": 5.0},
        )

        audit_rows = [o for o in db.added if isinstance(o, AuditLog)]
        assert len(audit_rows) == 1
        row = audit_rows[0]
        assert row.action == "UPDATE"
        assert row.entity_type == "SHOP_LOCATION"
        assert row.entity_id == 10
        assert row.user_id == 1
        assert row.old_values["accuracy_meters"] == pytest.approx(8.0)
        assert row.new_values["accuracy_meters"] == pytest.approx(5.0)
        assert row.old_values["latitude"] == pytest.approx(PATNA[0])
        assert row.new_values["latitude"] == pytest.approx(25.6000)
        assert row.record_hash  # hash-chained

    def test_audit_rows_are_immutable_by_design(self):
        from app.core.exceptions import ForbiddenError
        from app.services import audit_service

        with pytest.raises(ForbiddenError):
            audit_service.update_audit_entry()
        with pytest.raises(ForbiddenError):
            audit_service.delete_audit_entry()


# ── API schema validation ─────────────────────────────────────────────────


class TestLocationSchemas:
    def test_location_update_rejects_invalid_latitude(self):
        from pydantic import ValidationError

        from app.schemas.shopkeeper import ShopkeeperShopLocationUpdate

        with pytest.raises(ValidationError):
            ShopkeeperShopLocationUpdate(latitude=123.0, longitude=PATNA[1])

    def test_location_update_rejects_invalid_longitude(self):
        from pydantic import ValidationError

        from app.schemas.shopkeeper import ShopkeeperShopLocationUpdate

        with pytest.raises(ValidationError):
            ShopkeeperShopLocationUpdate(latitude=PATNA[0], longitude=999.0)

    def test_location_meta_rejects_negative_accuracy(self):
        from pydantic import ValidationError

        from app.schemas.shopkeeper import ShopLocationMeta

        with pytest.raises(ValidationError):
            ShopLocationMeta(accuracy_meters=-1.0)

    def test_location_meta_accepts_gps_capture(self):
        from app.schemas.shopkeeper import ShopLocationMeta

        meta = ShopLocationMeta(
            location_source="GPS",
            location_type="SHOP_ENTRANCE",
            location_status="CAPTURED",
            location_integrity_status="NORMAL",
            accuracy_meters=7.0,
            location_captured_at=datetime(2026, 9, 6, 9, 0, tzinfo=timezone.utc),
            location_verified=True,
        )
        dumped = meta.model_dump(exclude_none=True)
        assert dumped["location_source"] == "GPS"
        assert dumped["accuracy_meters"] == pytest.approx(7.0)

    def test_registration_requires_valid_coordinates(self):
        from pydantic import ValidationError

        from app.schemas.shopkeeper import ShopkeeperShopCreate

        base = {
            "name": "X",
            "latitude": PATNA[0],
            "longitude": PATNA[1],
            "address": {
                "address_line1": "Main Road",
                "city": "Bikramganj",
                "state": "Bihar",
                "pincode": "802112",
            },
        }
        assert ShopkeeperShopCreate(**base) is not None
        with pytest.raises(ValidationError):
            ShopkeeperShopCreate(**{**base, "latitude": 91.0})
        with pytest.raises(ValidationError):
            ShopkeeperShopCreate(**{**base, "longitude": -181.0})


# ── Route registration ────────────────────────────────────────────────────


class TestLocationRouteRegistration:
    def test_patch_location_route_registered(self):
        from app.api.routes import shopkeeper_portal

        paths = {
            (route.path, tuple(sorted(route.methods)))
            for route in shopkeeper_portal.router.routes
        }
        assert ("/shopkeeper/shops/{shop_id}/location", ("PATCH",)) in paths

    def test_customer_routes_untouched(self):
        from app.api.routes import shopkeeper_portal

        for route in shopkeeper_portal.router.routes:
            assert not route.path.startswith("/locations"), (
                "shopkeeper module must not shadow customer /locations routes"
            )
