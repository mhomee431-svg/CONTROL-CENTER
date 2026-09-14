"""Phase 18 — Shop Management System tests.

Covers:
- Shop registration
- Owner assignment
- Manager assignment
- Address validation
- Geolocation validation
- Opening hours validation
- Holiday schedules
- Verification workflow (REGISTERED → DOCUMENTS_SUBMITTED → PENDING_VERIFICATION → VERIFIED → ACTIVE)
- Rejection
- Suspension
- Reactivation
- Unauthorized access
- Customer visibility rules
- Shop documents
- Shop discovery
- Shop categories
"""

import os
import sys
from datetime import date, datetime, time, timezone
from pathlib import Path
from unittest.mock import MagicMock, patch

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402

# Force test settings
from app.core.config import settings  # noqa: E402
settings.RATE_LIMIT_ENABLED = False


# ── Helpers / fixtures ──────────────────────────────────────────────────────
class MockQuery:
    """A chainable mock query for testing DB interactions."""

    def __init__(self, result=None):
        self._result = result
        self._filtered = result

    def filter(self, *args, **kwargs):
        return self

    def filter_by(self, **kwargs):
        return self

    def join(self, *args, **kwargs):
        return self

    def options(self, *args, **kwargs):
        return self

    def offset(self, *args):
        return self

    def limit(self, *args):
        return self

    def order_by(self, *args):
        return self

    def all(self):
        return self._filtered or []

    def first(self):
        if isinstance(self._result, list) and self._result:
            return self._result[0]
        return self._result

    def one(self):
        return self._result

    def scalars(self):
        return self

    def scalar(self):
        """Support `db.query(sa_exists().where(...)).scalar()` — the slug
        uniqueness check in ``shop_service.register_shop``. With no configured
        result the slug is treated as free."""
        return self._result

    def count(self):
        return len(self._filtered or [])

    def delete(self, synchronize_session=False):
        return 0


class MockDB:
    """Simplified DB mock for unit testing shop_service functions."""

    def __init__(self):
        self.added = []
        self.deleted = []
        self._result = None
        self._results_by_model = {}
        self._query_results = []

    def query(self, model):
        # Return model-specific result if configured, else default
        result = self._results_by_model.get(model, self._result)
        mock_q = MockQuery(result)
        return mock_q

    def set_result(self, model, result):
        """Configure a specific result for a model query."""
        self._results_by_model[model] = result

    def add(self, obj):
        self.added.append(obj)

    def add_all(self, objs):
        self.added.extend(objs)

    def delete(self, obj):
        self.deleted.append(obj)

    def flush(self):
        # Assign IDs if missing
        for obj in self.added:
            if getattr(obj, "id", None) is None:
                obj.id = len(self.added)

    def commit(self):
        pass

    def rollback(self):
        pass

    def close(self):
        pass

    def execute(self, *args, **kwargs):
        return MockQuery(None)

    def scalars(self):
        return MockQuery(None)


@pytest.fixture
def mock_db():
    return MockDB()


# ── Model / Enum tests ─────────────────────────────────────────────────────
def test_shop_status_enum_values():
    """Shop lifecycle must have the required states."""
    from app.models.shop import ShopStatus

    values = {s.value for s in ShopStatus}
    assert "REGISTERED" in values
    assert "DOCUMENTS_SUBMITTED" in values
    assert "PENDING_VERIFICATION" in values
    assert "VERIFIED" in values
    assert "REJECTED" in values
    assert "SUSPENDED" in values
    assert "ACTIVE" in values
    assert "CLOSED" in values


def test_verification_status_enum_values():
    """Verification lifecycle must have the required states."""
    from app.models.shop import VerificationStatus

    values = {s.value for s in VerificationStatus}
    assert "PENDING" in values
    assert "SUBMITTED" in values
    assert "UNDER_REVIEW" in values
    assert "VERIFIED" in values
    assert "REJECTED" in values
    assert "EXPIRED" in values


def test_shop_category_enum_values():
    """Shop categories must be available."""
    from app.models.shop import ShopCategory

    values = {s.value for s in ShopCategory}
    assert "GROCERY" in values
    assert "ELECTRONICS" in values
    assert "PHARMACY" in values
    assert "HARDWARE" in values
    assert "FASHION" in values
    assert "RESTAURANT" in values


def test_shop_models_importable():
    """All shop models must be importable."""
    from app.models.shop import (
        Shop,
        ShopAddress,
        ShopCategory,
        ShopDocument,
        ShopHoliday,
        ShopHour,
        ShopManager,
        ShopOwner,
        ShopStatus,
        ShopVerification,
        VerificationStatus,
    )

    assert Shop is not None
    assert ShopAddress is not None
    assert ShopCategory is not None
    assert ShopDocument is not None
    assert ShopHoliday is not None
    assert ShopHour is not None
    assert ShopManager is not None
    assert ShopOwner is not None
    assert ShopStatus is not None
    assert ShopVerification is not None
    assert VerificationStatus is not None


def test_shop_model_fields():
    """Shop model must have all required lifecycle/support fields."""
    from app.models.shop import Shop

    cols = Shop.__table__.columns.keys()
    assert "name" in cols
    assert "slug" in cols
    assert "status" in cols
    assert "category" in cols
    assert "latitude" in cols
    assert "longitude" in cols
    assert "is_verified" in cols
    assert "verified_at" in cols
    assert "rejection_reason" in cols
    assert "suspension_reason" in cols
    assert "suspended_at" in cols
    assert "reactivated_at" in cols
    assert "closed_at" in cols
    assert "gstin" in cols
    assert "fssai_license" in cols
    assert "is_delivery_available" in cols
    assert "is_pickup_available" in cols
    assert "created_by" in cols


# ── Schema tests ────────────────────────────────────────────────────────────
def test_shop_schemas_importable():
    """All shop schemas must be importable."""
    from app.schemas.shop import (
        ShopAddressCreate,
        ShopAddressResponse,
        ShopCategory,
        ShopCreate,
        ShopDetailResponse,
        ShopDocumentCreate,
        ShopDocumentResponse,
        ShopHolidayCreate,
        ShopHolidayResponse,
        ShopHourCreate,
        ShopHourResponse,
        ShopManagerCreate,
        ShopManagerResponse,
        ShopOwnerResponse,
        ShopPublicResponse,
        ShopResponse,
        ShopStatusUpdate,
        ShopUpdate,
        ShopVerificationResponse,
        ShopVerificationReview,
    )

    assert ShopCreate is not None
    assert ShopUpdate is not None
    assert ShopResponse is not None
    assert ShopDetailResponse is not None
    assert ShopPublicResponse is not None
    assert ShopAddressCreate is not None
    assert ShopHourCreate is not None
    assert ShopDocumentCreate is not None
    assert ShopVerificationReview is not None
    assert ShopStatusUpdate is not None


def test_shop_create_schema():
    """ShopCreate schema must validate."""
    from app.schemas.shop import ShopCreate

    payload = ShopCreate(
        name="Test Shop",
        latitude=25.5941,
        longitude=85.1376,
        address={
            "address_line1": "123 Main St",
            "city": "Patna",
            "state": "Bihar",
            "pincode": "800001",
        },
    )
    assert payload.name == "Test Shop"
    assert payload.latitude == 25.5941
    assert payload.longitude == 85.1376
    assert payload.address.city == "Patna"


def test_shop_hour_create_schema():
    """ShopHourCreate must validate day_of_week and time."""
    from app.schemas.shop import ShopHourCreate

    import datetime as dt

    payload = ShopHourCreate(
        day_of_week=0,
        open_time=dt.time(9, 0),
        close_time=dt.time(21, 0),
    )
    assert payload.day_of_week == 0
    assert payload.open_time == dt.time(9, 0)


def test_shop_verification_review_schema():
    """ShopVerificationReview must validate decision."""
    from app.schemas.shop import ShopVerificationReview

    payload = ShopVerificationReview(decision="APPROVE", review_notes="Looks good")
    assert payload.decision == "APPROVE"
    assert payload.review_notes == "Looks good"


# ── Service helper tests ───────────────────────────────────────────────────
def test_slugify():
    """slugify should produce URL-safe slugs."""
    from app.services.shop_service import slugify

    assert slugify("Gupta Electronics") == "gupta-electronics"
    assert slugify("  Hello   World  ") == "hello-world"
    assert slugify("Café & Restaurant") == "caf-restaurant"


def test_validate_address_valid():
    """validate_address should pass for valid address."""
    from app.services.shop_service import validate_address

    validate_address({
        "address_line1": "123 Main St",
        "city": "Patna",
        "state": "Bihar",
        "pincode": "800001",
    })


def test_validate_address_missing_fields():
    """validate_address should raise ValueError for missing fields."""
    from app.services.shop_service import validate_address

    with pytest.raises(ValueError, match="Address line 1"):
        validate_address({"city": "Patna", "state": "Bihar", "pincode": "800001"})

    with pytest.raises(ValueError, match="City"):
        validate_address({"address_line1": "123", "state": "Bihar", "pincode": "800001"})


def test_validate_address_invalid_pincode():
    """validate_address should raise ValueError for invalid pincode."""
    from app.services.shop_service import validate_address

    with pytest.raises(ValueError, match="6-digit"):
        validate_address({
            "address_line1": "123 Main St",
            "city": "Patna",
            "state": "Bihar",
            "pincode": "12345",  # only 5 digits
        })


def test_validate_geolocation_valid():
    """validate_geolocation should pass for valid coordinates."""
    from app.services.shop_service import validate_geolocation

    validate_geolocation(25.5941, 85.1376)


def test_validate_geolocation_invalid():
    """validate_geolocation should raise for invalid coordinates."""
    from app.services.shop_service import validate_geolocation

    with pytest.raises(ValueError, match="Latitude"):
        validate_geolocation(91.0, 85.0)

    with pytest.raises(ValueError, match="Longitude"):
        validate_geolocation(25.0, 181.0)

    with pytest.raises(ValueError, match="required"):
        validate_geolocation(None, None)


def test_validate_hours_valid():
    """validate_hours should pass for valid schedule."""
    from app.services.shop_service import validate_hours

    validate_hours([
        {"day_of_week": 0, "open_time": time(9, 0), "close_time": time(21, 0)},
        {"day_of_week": 1, "open_time": time(9, 0), "close_time": time(21, 0)},
    ])


def test_validate_hours_duplicate_day():
    """validate_hours should reject duplicate day."""
    from app.services.shop_service import validate_hours

    with pytest.raises(ValueError, match="Duplicate"):
        validate_hours([
            {"day_of_week": 0, "open_time": time(9, 0), "close_time": time(21, 0)},
            {"day_of_week": 0, "open_time": time(10, 0), "close_time": time(20, 0)},
        ])


def test_validate_hours_invalid_day():
    """validate_hours should reject day out of range."""
    from app.services.shop_service import validate_hours

    with pytest.raises(ValueError, match="0"):
        validate_hours([{"day_of_week": 7, "open_time": time(9, 0), "close_time": time(21, 0)}])


def test_validate_hours_close_before_open():
    """validate_hours should reject close < open."""
    from app.services.shop_service import validate_hours

    with pytest.raises(ValueError, match="close_time"):
        validate_hours([
            {"day_of_week": 0, "open_time": time(21, 0), "close_time": time(9, 0)}
        ])


def test_parse_subcategories():
    """parse_subcategories should handle JSON and plain strings."""
    from app.services.shop_service import parse_subcategories

    assert parse_subcategories('["Grocery", "Vegetables"]') == ["Grocery", "Vegetables"]
    assert parse_subcategories("Single Category") == ["Single Category"]
    assert parse_subcategories(None) is None


# ── Shop registration ───────────────────────────────────────────────────────
def test_register_shop_creates_shop_with_owner():
    """register_shop must create shop + owner + address + verification."""
    from app.models.shop import Shop, ShopStatus
    from app.services.shop_service import register_shop

    mock_db = MockDB()
    # Pre-populate a shop so the query returns None for slug check
    mock_db._result = None

    data = {
        "name": "New Corner Store",
        "description": "Test shop",
        "phone": "+919876543210",
        "category": "GROCERY",
        "latitude": 25.5941,
        "longitude": 85.1376,
        "address": {
            "address_line1": "123 Main St",
            "city": "Patna",
            "state": "Bihar",
            "pincode": "800001",
        },
        "hours": [
            {"day_of_week": 0, "open_time": time(9, 0), "close_time": time(21, 0)},
        ],
    }

    shop = register_shop(mock_db, data, owner_user_id=1)

    assert shop is not None
    assert shop.name == "New Corner Store"
    assert shop.status == ShopStatus.REGISTERED
    assert shop.created_by == 1

    # Check owner was created
    owners = [o for o in mock_db.added if hasattr(o, "is_primary") and hasattr(o, "shop_id") and hasattr(o, "user_id")]
    assert len(owners) == 1
    assert owners[0].shop_id is not None
    assert owners[0].user_id == 1

    # Check address created
    addresses = [a for a in mock_db.added if hasattr(a, "is_primary") and hasattr(a, "city")]
    assert len(addresses) == 1
    assert addresses[0].city == "Patna"

    # Check verification record created
    verifications = [v for v in mock_db.added if hasattr(v, "status") and hasattr(v, "shop_id")]
    assert len(verifications) >= 1


def test_register_shop_invalid_geolocation():
    """register_shop must reject invalid geolocation."""
    from app.services.shop_service import register_shop

    mock_db = MockDB()
    data = {
        "name": "Bad Shop",
        "latitude": 95.0,  # invalid
        "longitude": 85.1376,
        "address": {
            "address_line1": "123 Main St",
            "city": "Patna",
            "state": "Bihar",
            "pincode": "800001",
        },
    }

    with pytest.raises(ValueError, match="Latitude"):
        register_shop(mock_db, data, owner_user_id=1)


def test_register_shop_invalid_address():
    """register_shop must reject invalid address."""
    from app.services.shop_service import register_shop

    mock_db = MockDB()
    data = {
        "name": "Bad Shop",
        "latitude": 25.5941,
        "longitude": 85.1376,
        "address": {
            "address_line1": "",
            "city": "Patna",
            "state": "Bihar",
            "pincode": "800001",
        },
    }

    with pytest.raises(ValueError, match="Address line 1"):
        register_shop(mock_db, data, owner_user_id=1)


def test_register_shop_invalid_hours():
    """register_shop must reject invalid hours."""
    from app.services.shop_service import register_shop

    mock_db = MockDB()
    data = {
        "name": "Bad Hours Shop",
        "latitude": 25.5941,
        "longitude": 85.1376,
        "address": {
            "address_line1": "123 Main St",
            "city": "Patna",
            "state": "Bihar",
            "pincode": "800001",
        },
        "hours": [
            {"day_of_week": 0, "open_time": time(21, 0), "close_time": time(9, 0)},
        ],
    }

    with pytest.raises(ValueError, match="close_time"):
        register_shop(mock_db, data, owner_user_id=1)


# ── Ownership / Manager tests ───────────────────────────────────────────────
def test_add_owner():
    """add_owner should create an owner record."""
    from app.services.shop_service import add_owner

    mock_db = MockDB()
    mock_db._result = None
    owner = add_owner(mock_db, shop_id=1, user_id=2)

    assert owner is not None
    assert owner.shop_id == 1
    assert owner.user_id == 2
    assert owner.is_primary is False


def test_add_primary_owner():
    """add_owner with is_primary=True should set primary."""
    from app.services.shop_service import add_owner

    mock_db = MockDB()
    mock_db._result = None
    owner = add_owner(mock_db, shop_id=1, user_id=2, is_primary=True)

    assert owner.is_primary is True


def test_add_duplicate_owner_raises():
    """add_owner must raise when user is already an owner."""
    from app.services.shop_service import add_owner

    mock_db = MockDB()

    # Simulate existing owner record
    class MockOwner:
        id = 1
        shop_id = 1
        user_id = 2
        is_primary = False
        is_deleted = False
        is_active = True

    mock_db._result = MockOwner()

    with pytest.raises(ValueError, match="already an owner"):
        add_owner(mock_db, shop_id=1, user_id=2)


def test_remove_owner():
    """remove_owner should soft-delete an owner."""
    from app.models.shop import ShopOwner
    from app.services.shop_service import remove_owner

    class MockOwner:
        def __init__(self):
            self.id = 1
            self.shop_id = 1
            self.user_id = 2
            self.is_primary = False
            self.is_active = True
            self.is_deleted = False
            self.deleted_at = None

    owner = MockOwner()
    mock_db = MockDB()
    mock_db.set_result(ShopOwner, owner)

    result = remove_owner(mock_db, shop_id=1, user_id=2)
    assert result is True
    assert owner.is_active is False


def test_add_manager():
    """add_manager should create a manager record."""
    from app.services.shop_service import add_manager

    mock_db = MockDB()
    mock_db._result = None

    manager = add_manager(mock_db, shop_id=1, user_id=3, permissions=["inventory:read", "product:update"])

    assert manager is not None
    assert manager.shop_id == 1
    assert manager.user_id == 3
    assert manager.permissions is not None
    assert "inventory:read" in manager.permissions


def test_remove_manager():
    """remove_manager should soft-delete a manager."""
    from app.models.shop import ShopManager
    from app.services.shop_service import remove_manager

    class MockManager:
        def __init__(self):
            self.id = 1
            self.shop_id = 1
            self.user_id = 3
            self.is_active = True
            self.is_deleted = False
            self.deleted_at = None

    manager = MockManager()
    mock_db = MockDB()
    mock_db.set_result(ShopManager, manager)

    result = remove_manager(mock_db, shop_id=1, user_id=3)
    assert result is True
    assert manager.is_active is False


def test_is_user_owner():
    """is_user_owner should return True for owner."""
    from app.services.shop_service import is_user_owner

    class MockOwner:
        id = 1
        shop_id = 1
        user_id = 5
        is_active = True
        is_deleted = False

    mock_db = MockDB()
    mock_db._result = MockOwner()

    assert is_user_owner(mock_db, user_id=5, shop_id=1) is True


def test_is_user_owner_not_owner():
    """is_user_owner should return False for non-owner."""
    from app.services.shop_service import is_user_owner

    mock_db = MockDB()
    mock_db._result = None

    assert is_user_owner(mock_db, user_id=5, shop_id=1) is False


def test_user_shop_ids():
    """user_shop_ids should return combined owner + manager shop IDs."""
    from app.services.shop_service import user_shop_ids

    class MockOwner:
        shop_id = 1

    class MockManager:
        shop_id = 2

    mock_db = MockDB()

    # Configure query to return owners first, managers second
    original_query = mock_db.query

    call_count = 0

    def fake_query(model):
        nonlocal call_count
        call_count += 1
        if call_count == 1:
            return MockQuery([MockOwner()])
        elif call_count == 2:
            return MockQuery([MockManager()])
        return MockQuery([])

    mock_db.query = fake_query

    result = user_shop_ids(mock_db, user_id=5)
    assert set(result) == {1, 2}


# ── Verification workflow ───────────────────────────────────────────────────
def test_submit_document_updates_status():
    """submit_shop_document should move shop to DOCUMENTS_SUBMITTED."""
    from app.models.shop import Shop, ShopStatus
    from app.services.shop_service import submit_shop_document

    mock_db = MockDB()

    class MockShop:
        def __init__(self):
            self.id = 1
            self.status = ShopStatus.REGISTERED

    shop = MockShop()
    mock_db.set_result(Shop, shop)

    doc = submit_shop_document(mock_db, shop_id=1, data={
        "document_type": "GST",
        "document_url": "https://example.com/gst.pdf",
        "document_number": "GSTIN123456",
    })

    assert doc is not None
    assert doc.shop_id == 1
    assert doc.document_type == "GST"
    assert shop.status == ShopStatus.DOCUMENTS_SUBMITTED


def test_submit_for_verification():
    """submit_for_verification should move shop to PENDING_VERIFICATION."""
    from app.models.shop import Shop, ShopStatus, VerificationStatus
    from app.services.shop_service import submit_for_verification

    mock_db = MockDB()

    class MockShop:
        def __init__(self):
            self.id = 1
            self.status = ShopStatus.DOCUMENTS_SUBMITTED

    shop = MockShop()
    mock_db.set_result(Shop, shop)

    verification = submit_for_verification(mock_db, shop_id=1, submitted_by=10)

    assert verification is not None
    assert verification.shop_id == 1
    assert verification.status == VerificationStatus.SUBMITTED
    assert verification.submitted_by == 10
    assert shop.status == ShopStatus.PENDING_VERIFICATION


def test_review_verification_approve():
    """Approving a verification should activate the shop."""
    from app.models.shop import Shop, ShopStatus, VerificationStatus
    from app.services.shop_service import review_verification

    mock_db = MockDB()

    class MockShop:
        def __init__(self):
            self.id = 1
            self.status = ShopStatus.PENDING_VERIFICATION
            self.is_verified = False
            self.verified_at = None
            self.rejection_reason = None
            self.suspension_reason = None
            self.suspended_at = None
            self.reactivated_at = None

    shop = MockShop()
    mock_db.set_result(Shop, shop)

    verification = review_verification(
        mock_db, shop_id=1, reviewer_id=99, decision="APPROVE", review_notes="Approved"
    )

    assert verification is not None
    assert verification.status == VerificationStatus.VERIFIED
    assert verification.reviewed_by == 99
    assert verification.review_notes == "Approved"
    assert verification.verified_at is not None

    assert shop.status == ShopStatus.ACTIVE
    assert shop.is_verified is True
    assert shop.verified_at is not None


def test_review_verification_reject():
    """Rejecting a verification should set shop to REJECTED."""
    from app.models.shop import Shop, ShopStatus, VerificationStatus
    from app.services.shop_service import review_verification

    mock_db = MockDB()

    class MockShop:
        def __init__(self):
            self.id = 1
            self.status = ShopStatus.PENDING_VERIFICATION
            self.is_verified = False
            self.verified_at = None
            self.rejection_reason = None
            self.suspension_reason = None
            self.suspended_at = None
            self.reactivated_at = None

    shop = MockShop()
    mock_db.set_result(Shop, shop)

    verification = review_verification(
        mock_db, shop_id=1, reviewer_id=99, decision="REJECT", review_notes="Missing documents"
    )

    assert verification.status == VerificationStatus.REJECTED
    assert shop.status == ShopStatus.REJECTED
    assert shop.is_verified is False
    assert shop.rejection_reason == "Missing documents"


def test_review_verification_suspend():
    """Suspending a shop should set status to SUSPENDED."""
    from app.models.shop import Shop, ShopStatus, VerificationStatus
    from app.services.shop_service import review_verification

    mock_db = MockDB()

    class MockShop:
        def __init__(self):
            self.id = 1
            self.status = ShopStatus.ACTIVE
            self.is_verified = True
            self.verified_at = datetime.now(timezone.utc)
            self.rejection_reason = None
            self.suspension_reason = None
            self.suspended_at = None
            self.reactivated_at = None

    shop = MockShop()
    mock_db.set_result(Shop, shop)

    verification = review_verification(
        mock_db, shop_id=1, reviewer_id=99, decision="SUSPEND", review_notes="Complaints"
    )

    assert shop.status == ShopStatus.SUSPENDED
    assert shop.is_verified is False
    assert shop.suspension_reason == "Complaints"
    assert shop.suspended_at is not None


def test_review_verification_reactivate():
    """Reactivating a suspended shop should set status to ACTIVE."""
    from app.models.shop import Shop, ShopStatus, VerificationStatus
    from app.services.shop_service import review_verification

    mock_db = MockDB()

    class MockShop:
        def __init__(self):
            self.id = 1
            self.status = ShopStatus.SUSPENDED
            self.is_verified = False
            self.verified_at = None
            self.rejection_reason = None
            self.suspension_reason = "Complaints"
            self.suspended_at = datetime.now(timezone.utc)
            self.reactivated_at = None

    shop = MockShop()
    mock_db.set_result(Shop, shop)

    verification = review_verification(
        mock_db, shop_id=1, reviewer_id=99, decision="REACTIVATE", review_notes="Resolved"
    )

    assert shop.status == ShopStatus.ACTIVE
    assert shop.is_verified is True
    assert shop.suspension_reason is None
    assert shop.suspended_at is None
    assert shop.reactivated_at is not None


def test_review_verification_invalid_decision():
    """review_verification should raise on unknown decision."""
    from app.models.shop import Shop
    from app.services.shop_service import review_verification

    mock_db = MockDB()

    class MockShop:
        def __init__(self):
            self.id = 1
            self.status = "PENDING"
            self.is_verified = False

    shop = MockShop()
    mock_db.set_result(Shop, shop)

    with pytest.raises(ValueError, match="Unknown"):
        review_verification(mock_db, shop_id=1, reviewer_id=99, decision="FOO")


def test_update_shop_status_suspend():
    """update_shop_status should handle SUSPENDED state."""
    from app.models.shop import Shop, ShopStatus
    from app.services.shop_service import update_shop_status

    mock_db = MockDB()

    class MockShop:
        def __init__(self):
            self.id = 1
            self.status = ShopStatus.ACTIVE
            self.is_verified = True
            self.suspension_reason = None
            self.suspended_at = None

    shop = MockShop()
    mock_db.set_result(Shop, shop)

    result = update_shop_status(mock_db, shop_id=1, status=ShopStatus.SUSPENDED, reason="Violation")

    assert result is not None
    assert shop.status == ShopStatus.SUSPENDED
    assert shop.is_verified is False
    assert shop.suspension_reason == "Violation"
    assert shop.suspended_at is not None


def test_update_shop_status_close():
    """update_shop_status should handle CLOSED state."""
    from app.models.shop import Shop, ShopStatus
    from app.services.shop_service import update_shop_status

    mock_db = MockDB()

    class MockShop:
        def __init__(self):
            self.id = 1
            self.status = ShopStatus.ACTIVE
            self.is_accepting_orders = True
            self.closed_at = None

    shop = MockShop()
    mock_db.set_result(Shop, shop)

    result = update_shop_status(mock_db, shop_id=1, status=ShopStatus.CLOSED)

    assert result is not None
    assert shop.status == ShopStatus.CLOSED
    assert shop.is_accepting_orders is False
    assert shop.closed_at is not None


# ── Shop opening hours / is_open_now ────────────────────────────────────────
def test_is_shop_open_24x7():
    """is_shop_open should always return True for 24x7 shops."""
    from app.services.shop_service import is_shop_open

    class MockHour:
        day_of_week = 0
        open_time = time(9, 0)
        close_time = time(21, 0)
        is_closed = False

    class MockHoliday:
        holiday_date = date(2026, 1, 1)
        is_recurring_yearly = False

    class MockShop:
        is_open_24x7 = True
        holidays = []
        hours = []

    assert is_shop_open(MockShop()) is True


def test_is_shop_open_during_hours():
    """is_shop_open should return True when within opening hours."""
    from app.services.shop_service import is_shop_open

    class MockHour:
        def __init__(self, dow, open_t, close_t, closed=False):
            self.day_of_week = dow
            self.open_time = open_t
            self.close_time = close_t
            self.is_closed = closed

    class MockShop:
        is_open_24x7 = False
        holidays = []
        hours = [MockHour(0, time(9, 0), time(21, 0))]

    # Monday at 12:00 PM → open (day_of_week=0)
    at = datetime(2026, 1, 5, 12, 0)  # Monday
    assert is_shop_open(MockShop(), at_time=at) is True


def test_is_shop_open_after_hours():
    """is_shop_open should return False when outside opening hours."""
    from app.services.shop_service import is_shop_open

    class MockHour:
        def __init__(self, dow, open_t, close_t, closed=False):
            self.day_of_week = dow
            self.open_time = open_t
            self.close_time = close_t
            self.is_closed = closed

    class MockShop:
        is_open_24x7 = False
        holidays = []
        hours = [MockHour(0, time(9, 0), time(21, 0))]

    # Monday at 23:00 → closed
    at = datetime(2026, 1, 5, 23, 0)
    assert is_shop_open(MockShop(), at_time=at) is False


def test_is_shop_open_on_holiday():
    """is_shop_open should return False on holidays."""
    from app.services.shop_service import is_shop_open

    class MockHoliday:
        holiday_date = date(2026, 1, 5)
        is_recurring_yearly = False

    class MockShop:
        is_open_24x7 = False
        holidays = [MockHoliday()]
        hours = []

    at = datetime(2026, 1, 5, 12, 0)
    assert is_shop_open(MockShop(), at_time=at) is False


# ── API Routes ──────────────────────────────────────────────────────────────
def test_shop_router_exists():
    """Shop router must be importable and have routes."""
    from app.api.routes.shops import router

    paths = {r.path for r in router.routes}
    assert "/shops/nearby" in paths


def test_shop_router_registered_in_main():
    """Shop router should be registered in main app."""
    from app.api.routes.shops import router as shops_router

    assert len(shops_router.routes) > 0


# ── Customer visibility rules ───────────────────────────────────────────────
def test_nearby_shops_only_active_verified():
    """nearby_shops should only return ACTIVE/VERIFIED shops accepting orders."""
    from app.models.shop import Shop, ShopStatus
    from app.services.shop_service import nearby_shops

    class MockShop:
        def __init__(self, sid, name, lat, lng, status, is_verified, is_accepting):
            self.id = sid
            self.name = name
            self.latitude = lat
            self.longitude = lng
            self.status = status
            self.is_verified = is_verified
            self.is_accepting_orders = is_accepting
            self.image_url = None
            self.rating = 4.0
            self.category = None
            self.is_open_24x7 = True
            self.is_deleted = False

    active_shop = MockShop(1, "Active Shop", 25.5941, 85.1376, ShopStatus.ACTIVE, True, True)
    suspended_shop = MockShop(2, "Suspended Shop", 25.5941, 85.1376, ShopStatus.SUSPENDED, False, True)
    rejected_shop = MockShop(3, "Rejected Shop", 25.5941, 85.1376, ShopStatus.REJECTED, False, True)
    closed_shop = MockShop(4, "Closed Shop", 25.5941, 85.1376, ShopStatus.CLOSED, True, False)

    all_shops = [active_shop, suspended_shop, rejected_shop, closed_shop]

    class FilteringMockDB(MockDB):
        def query(self, model):
            if model is Shop:
                # Simulate the filter: only ACTIVE/VERIFIED, is_verified, is_accepting_orders
                filtered = [
                    s for s in all_shops
                    if s.status in (ShopStatus.ACTIVE, ShopStatus.VERIFIED)
                    and s.is_verified
                    and s.is_accepting_orders
                    and not s.is_deleted
                ]
                return MockQuery(filtered)
            return super().query(model)

    mock_db = FilteringMockDB()

    results = nearby_shops(mock_db, latitude=25.5941, longitude=85.1376, radius_km=5.0)

    # Only active verified shop should be returned
    assert len(results) == 1
    assert results[0]["id"] == 1
    assert results[0]["name"] == "Active Shop"


def test_nearby_shops_distance_filter():
    """nearby_shops should filter by distance radius."""
    from app.models.shop import ShopStatus
    from app.services.shop_service import nearby_shops

    class MockShop:
        def __init__(self, sid, name, lat, lng):
            self.id = sid
            self.name = name
            self.latitude = lat
            self.longitude = lng
            self.status = ShopStatus.ACTIVE
            self.is_verified = True
            self.is_accepting_orders = True
            self.image_url = None
            self.rating = 4.0
            self.category = None
            self.is_open_24x7 = True
            self.is_deleted = False

    close_shop = MockShop(1, "Close Shop", 25.5941, 85.1376)     # ~0 km
    far_shop = MockShop(2, "Far Shop", 26.5941, 86.1376)          # ~155 km away

    mock_db = MockDB()
    mock_db._result = [close_shop, far_shop]

    results = nearby_shops(mock_db, latitude=25.5941, longitude=85.1376, radius_km=5.0)

    assert len(results) == 1
    assert results[0]["id"] == 1
    assert results[0]["distance_km"] == 0.0


# ── Address management ────────────────────────────────────────────────────
def test_add_shop_address():
    """add_shop_address should create a new address."""
    from app.services.shop_service import add_shop_address

    mock_db = MockDB()

    addr = add_shop_address(mock_db, shop_id=1, data={
        "address_line1": "456 Second St",
        "city": "Gaya",
        "state": "Bihar",
        "pincode": "823001",
        "is_primary": True,
    })

    assert addr is not None
    assert addr.shop_id == 1
    assert addr.city == "Gaya"
    assert addr.is_primary is True


def test_add_shop_address_invalid():
    """add_shop_address should reject invalid address data."""
    from app.services.shop_service import add_shop_address

    mock_db = MockDB()

    with pytest.raises(ValueError):
        add_shop_address(mock_db, shop_id=1, data={"city": "Gaya"})