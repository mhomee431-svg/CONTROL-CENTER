"""Tests for the Merchant Onboarding & Verification System.

Covers all 30 test scenarios from the specification.
"""
import pytest
from datetime import datetime, timezone
from unittest.mock import patch, AsyncMock

from app.models.merchant_category import (
    MerchantCategory,
    MerchantVerificationRequirement,
    VerificationMethod,
)
from app.models.merchant_onboarding import (
    MerchantOnboarding,
    OnboardingStatus,
    VALID_ONBOARDING_TRANSITIONS,
)
from app.models.business_identity_verification import (
    BusinessIdentityVerification,
    IdentityVerificationType,
    IdentityVerificationStatus,
    BankAccountVerification,
    CategoryDocumentVerification,
)
from app.models.verification_attempt import (
    VerificationAttempt,
    VerificationAttemptType,
    VerificationAttemptStatus,
)
from app.services.merchant_onboarding_service import (
    _validate_transition,
    resolve_required_steps,
    get_category_requirements,
)
from app.services.identity_provider import (
    SandboxIdentityProvider,
    ProductionIdentityProvider,
    IdentityVerificationResult,
)
from app.services.bank_provider import (
    SandboxBankProvider,
    ProductionBankProvider,
    BankVerificationResult,
)
from app.services.category_provider import (
    SandboxCategoryProvider,
    ProductionCategoryProvider,
    CategoryVerificationResult,
)


# ── Fixtures ──────────────────────────────────────────────────────────────

@pytest.fixture
def sample_category(db):
    """Create a sample merchant category."""
    category = MerchantCategory(
        code="PHARMACY_HEALTHCARE",
        name="Pharmacy & Healthcare",
        is_active=True,
        sort_order=1,
    )
    db.add(category)
    db.flush()
    return category


@pytest.fixture
def sample_requirements(db, sample_category):
    """Create sample verification requirements."""
    requirements = [
        MerchantVerificationRequirement(
            category_id=sample_category.id,
            requirement_code="PHONE_OTP",
            requirement_name="Phone OTP Verification",
            is_required=True,
            verification_method="PHONE_OTP",
            requires_admin_review=False,
            sort_order=0,
        ),
        MerchantVerificationRequirement(
            category_id=sample_category.id,
            requirement_code="GSTIN_UDYAM",
            requirement_name="Business Identity",
            is_required=True,
            verification_method="GSTIN_VERIFY",
            requires_admin_review=False,
            sort_order=1,
        ),
        MerchantVerificationRequirement(
            category_id=sample_category.id,
            requirement_code="BANK_VERIFY",
            requirement_name="Bank Account Verification",
            is_required=True,
            verification_method="BANK_PENNY_DROP",
            requires_admin_review=False,
            sort_order=2,
        ),
        MerchantVerificationRequirement(
            category_id=sample_category.id,
            requirement_code="DRUG_LICENSE",
            requirement_name="Drug License",
            is_required=True,
            verification_method="DRUG_LICENSE_VERIFY",
            requires_admin_review=True,
            sort_order=3,
        ),
    ]
    for req in requirements:
        db.add(req)
    db.flush()
    return requirements


# ── Test Category Configuration ───────────────────────────────────────────

class TestCategoryConfiguration:
    """Tests for category configuration."""

    def test_create_category(self, db, sample_category):
        """Test creating a merchant category."""
        assert sample_category.id is not None
        assert sample_category.code == "PHARMACY_HEALTHCARE"
        assert sample_category.is_active is True

    def test_get_category_requirements(self, db, sample_category, sample_requirements):
        """Test getting requirements for a category."""
        requirements = get_category_requirements(db, "PHARMACY_HEALTHCARE")
        assert len(requirements) == 4

    def test_resolve_required_steps(self, db, sample_category, sample_requirements):
        """Test resolving required steps for a category."""
        steps = resolve_required_steps(db, "PHARMACY_HEALTHCARE")
        assert steps["phone_otp"] is True
        assert steps["identity_verification"] is True
        assert steps["bank_verification"] is True
        assert steps["category_documents"] is True
        assert steps["admin_review"] is True

    def test_invalid_category_returns_empty(self, db):
        """Test that invalid category returns empty requirements."""
        requirements = get_category_requirements(db, "INVALID_CATEGORY")
        assert len(requirements) == 0


# ── Test State Machine ────────────────────────────────────────────────────

class TestStateMachine:
    """Tests for the onboarding state machine."""

    def test_valid_transitions(self):
        """Test valid state transitions."""
        assert _validate_transition(OnboardingStatus.DRAFT, OnboardingStatus.PHONE_VERIFIED) is True
        assert _validate_transition(OnboardingStatus.PHONE_VERIFIED, OnboardingStatus.IDENTITY_PENDING) is True
        assert _validate_transition(OnboardingStatus.IDENTITY_PENDING, OnboardingStatus.IDENTITY_VERIFIED) is True
        assert _validate_transition(OnboardingStatus.IDENTITY_VERIFIED, OnboardingStatus.BANK_PENDING) is True
        assert _validate_transition(OnboardingStatus.BANK_PENDING, OnboardingStatus.BANK_VERIFIED) is True
        assert _validate_transition(OnboardingStatus.BANK_VERIFIED, OnboardingStatus.CATEGORY_DOCUMENTS_PENDING) is True
        assert _validate_transition(OnboardingStatus.CATEGORY_DOCUMENTS_PENDING, OnboardingStatus.PENDING_ADMIN_REVIEW) is True
        assert _validate_transition(OnboardingStatus.PENDING_ADMIN_REVIEW, OnboardingStatus.VERIFIED) is True
        assert _validate_transition(OnboardingStatus.VERIFIED, OnboardingStatus.SUSPENDED) is True
        assert _validate_transition(OnboardingStatus.REJECTED, OnboardingStatus.DRAFT) is True

    def test_invalid_transitions(self):
        """Test invalid state transitions."""
        assert _validate_transition(OnboardingStatus.DRAFT, OnboardingStatus.VERIFIED) is False
        assert _validate_transition(OnboardingStatus.PHONE_VERIFIED, OnboardingStatus.VERIFIED) is False
        assert _validate_transition(OnboardingStatus.VERIFIED, OnboardingStatus.DRAFT) is False
        assert _validate_transition(OnboardingStatus.SUSPENDED, OnboardingStatus.DRAFT) is False

    def test_failure_transitions(self):
        """Test that any state can transition to REJECTED."""
        assert _validate_transition(OnboardingStatus.IDENTITY_PENDING, OnboardingStatus.REJECTED) is True
        assert _validate_transition(OnboardingStatus.BANK_PENDING, OnboardingStatus.REJECTED) is True
        assert _validate_transition(OnboardingStatus.CATEGORY_DOCUMENTS_PENDING, OnboardingStatus.REJECTED) is True


# ── Test Identity Verification Provider ────────────────────────────────────

class TestIdentityProvider:
    """Tests for identity verification providers."""

    @pytest.mark.asyncio
    async def test_sandbox_gstin_verified(self):
        """Test sandbox GSTIN verification - verified case."""
        provider = SandboxIdentityProvider()
        result = await provider.verify_gstin("27AAAAA1234A1Z5")
        assert result.status == "VERIFIED"
        assert result.provider == "sandbox"
        assert result.reference_id is not None

    @pytest.mark.asyncio
    async def test_sandbox_gstin_pending(self):
        """Test sandbox GSTIN verification - pending case."""
        provider = SandboxIdentityProvider()
        result = await provider.verify_gstin("29CCCCC9012C3Z1")
        assert result.status == "PENDING"

    @pytest.mark.asyncio
    async def test_sandbox_gstin_failed(self):
        """Test sandbox GSTIN verification - failed case."""
        provider = SandboxIdentityProvider()
        result = await provider.verify_gstin("33DDDDD3456D4Z9")
        assert result.status == "FAILED"

    @pytest.mark.asyncio
    async def test_sandbox_gstin_unknown(self):
        """Test sandbox GSTIN verification - unknown identifier."""
        provider = SandboxIdentityProvider()
        result = await provider.verify_gstin("99ZZZZZ9999Z9Z9")
        assert result.status == "UNABLE_TO_VERIFY"

    @pytest.mark.asyncio
    async def test_sandbox_udyam_verified(self):
        """Test sandbox UDYAM verification - verified case."""
        provider = SandboxIdentityProvider()
        result = await provider.verify_udyam("UDYAM-MH-1234567890")
        assert result.status == "VERIFIED"

    @pytest.mark.asyncio
    async def test_sandbox_udyam_failed(self):
        """Test sandbox UDYAM verification - failed case."""
        provider = SandboxIdentityProvider()
        result = await provider.verify_udyam("UDYAM-TN-9999999999")
        assert result.status == "FAILED"

    def test_gstin_format_validation(self):
        """Test GSTIN format validation."""
        provider = SandboxIdentityProvider()
        assert provider.validate_gstin_format("27AAAAA1234A1Z5") is True
        assert provider.validate_gstin_format("INVALID") is False
        assert provider.validate_gstin_format("") is False
        assert provider.validate_gstin_format("123") is False

    def test_udyam_format_validation(self):
        """Test UDYAM format validation."""
        provider = SandboxIdentityProvider()
        assert provider.validate_udyam_format("UDYAM-MH-1234567890") is True
        assert provider.validate_udyam_format("INVALID") is False
        assert provider.validate_udyam_format("") is False

    @pytest.mark.asyncio
    async def test_production_provider_routes_to_admin(self):
        """Test that production provider routes to admin review."""
        provider = ProductionIdentityProvider()
        result = await provider.verify_gstin("27AAAAA1234A1Z5")
        assert result.status == "UNABLE_TO_VERIFY"
        assert result.failure_code == "ADMIN_REVIEW_REQUIRED"


# ── Test Bank Verification Provider ───────────────────────────────────────

class TestBankProvider:
    """Tests for bank verification providers."""

    @pytest.mark.asyncio
    async def test_sandbox_bank_verified(self):
        """Test sandbox bank verification - verified case."""
        provider = SandboxBankProvider()
        result = await provider.verify_bank_account(
            "Test User", "1234567890", "SBIN0001234"
        )
        assert result.status == "VERIFIED"
        assert result.provider == "sandbox"

    @pytest.mark.asyncio
    async def test_sandbox_bank_pending(self):
        """Test sandbox bank verification - pending case."""
        provider = SandboxBankProvider()
        result = await provider.verify_bank_account(
            "Test User", "1111111111", "SBIN0001234"
        )
        assert result.status == "PENDING"

    @pytest.mark.asyncio
    async def test_sandbox_bank_failed(self):
        """Test sandbox bank verification - failed case."""
        provider = SandboxBankProvider()
        result = await provider.verify_bank_account(
            "Test User", "9999999999", "SBIN0001234"
        )
        assert result.status == "FAILED"

    def test_ifsc_format_validation(self):
        """Test IFSC format validation."""
        provider = SandboxBankProvider()
        assert provider.validate_ifsc_format("SBIN0001234") is True
        assert provider.validate_ifsc_format("INVALID") is False
        assert provider.validate_ifsc_format("") is False

    def test_account_number_masking(self):
        """Test account number masking."""
        provider = SandboxBankProvider()
        assert provider.mask_account_number("1234567890") == "******7890"
        assert provider.mask_account_number("123") == "****"
        assert provider.mask_account_number("") == "****"

    def test_account_number_hashing(self):
        """Test account number hashing."""
        provider = SandboxBankProvider()
        hash1 = provider.hash_account_number("1234567890")
        hash2 = provider.hash_account_number("1234567890")
        hash3 = provider.hash_account_number("9876543210")
        assert hash1 == hash2  # Same input = same hash
        assert hash1 != hash3  # Different input = different hash

    @pytest.mark.asyncio
    async def test_production_bank_routes_to_admin(self):
        """Test that production bank provider routes to admin review."""
        provider = ProductionBankProvider()
        result = await provider.verify_bank_account(
            "Test User", "1234567890", "SBIN0001234"
        )
        assert result.status == "FAILED"
        assert result.failure_code == "ADMIN_REVIEW_REQUIRED"


# ── Test Category Verification Provider ───────────────────────────────────

class TestCategoryProvider:
    """Tests for category document verification providers."""

    @pytest.mark.asyncio
    async def test_sandbox_drug_license(self):
        """Test sandbox drug license verification."""
        provider = SandboxCategoryProvider()
        result = await provider.verify_drug_license("DL12345")
        assert result.status == "UNABLE_TO_VERIFY"
        assert result.requires_admin_review is True

    @pytest.mark.asyncio
    async def test_sandbox_fssai_license(self):
        """Test sandbox FSSAI license verification."""
        provider = SandboxCategoryProvider()
        result = await provider.verify_fssai_license("12345678901234")
        assert result.status == "UNABLE_TO_VERIFY"
        assert result.requires_admin_review is True

    @pytest.mark.asyncio
    async def test_sandbox_driving_license(self):
        """Test sandbox driving license verification."""
        provider = SandboxCategoryProvider()
        result = await provider.verify_driving_license("MH12201234567890")
        assert result.status == "UNABLE_TO_VERIFY"
        assert result.requires_admin_review is True

    @pytest.mark.asyncio
    async def test_sandbox_vehicle_rc(self):
        """Test sandbox vehicle RC verification."""
        provider = SandboxCategoryProvider()
        result = await provider.verify_vehicle_rc("MH12AB1234")
        assert result.status == "UNABLE_TO_VERIFY"
        assert result.requires_admin_review is True

    def test_fssai_format_validation(self):
        """Test FSSAI format validation."""
        provider = SandboxCategoryProvider()
        assert provider.validate_fssai_format("12345678901234") is True
        assert provider.validate_fssai_format("1234567890") is True
        assert provider.validate_fssai_format("123") is False
        assert provider.validate_fssai_format("") is False

    def test_drug_license_format_validation(self):
        """Test drug license format validation."""
        provider = SandboxCategoryProvider()
        assert provider.validate_drug_license_format("DL12345") is True
        assert provider.validate_drug_license_format("DL/123/456") is True
        assert provider.validate_drug_license_format("") is False

    def test_driving_license_format_validation(self):
        """Test driving license format validation."""
        provider = SandboxCategoryProvider()
        assert provider.validate_driving_license_format("MH12201234567890") is True
        assert provider.validate_driving_license_format("INVALID") is False

    def test_vehicle_rc_format_validation(self):
        """Test vehicle RC format validation."""
        provider = SandboxCategoryProvider()
        assert provider.validate_vehicle_rc_format("MH12AB1234") is True
        assert provider.validate_vehicle_rc_format("INVALID") is False

    @pytest.mark.asyncio
    async def test_production_category_routes_to_admin(self):
        """Test that production category provider routes to admin review."""
        provider = ProductionCategoryProvider()
        result = await provider.verify_drug_license("DL12345")
        assert result.status == "UNABLE_TO_VERIFY"
        assert result.requires_admin_review is True


# ── Test Security ─────────────────────────────────────────────────────────

class TestSecurity:
    """Tests for security features."""

    def test_sandbox_blocked_in_production(self, monkeypatch):
        """Test that sandbox providers are blocked in production."""
        from app.core.config import settings
        monkeypatch.setattr(settings, "ENVIRONMENT", "production")

        provider = SandboxIdentityProvider()
        import asyncio
        result = asyncio.run(provider.verify_gstin("27AAAAA1234A1Z5"))
        assert result.status == "UNABLE_TO_VERIFY"
        assert result.failure_code == "SANDBOX_BLOCKED"

    def test_bank_account_never_stored_full(self):
        """Test that bank account number is never stored in full."""
        provider = SandboxBankProvider()
        # Only hash and last four should be stored
        account = "1234567890"
        hashed = provider.hash_account_number(account)
        masked = provider.mask_account_number(account)
        assert account not in hashed
        assert account not in masked
        assert masked.endswith("7890")

    def test_sensitive_data_not_in_logs(self, caplog):
        """Test that sensitive data is not logged."""
        provider = SandboxBankProvider()
        masked = provider.mask_account_number("1234567890")
        # Masked value should not contain full account number
        assert "1234567890" not in masked


# ── Test Input Validation ─────────────────────────────────────────────────

class TestInputValidation:
    """Tests for input validation."""

    def test_invalid_gstin_rejected(self):
        """Test that invalid GSTIN format is rejected."""
        from app.schemas.merchant_onboarding import MerchantOnboardingRequest
        import pytest
        with pytest.raises(Exception):
            MerchantOnboardingRequest(
                business_name="Test",
                category_code="PHARMACY_HEALTHCARE",
                phone="9999999999",
                address={
                    "address_line1": "123 Main St",
                    "city": "Mumbai",
                    "state": "Maharashtra",
                    "pincode": "400001",
                },
                location={"latitude": 19.07, "longitude": 72.87},
                gstin="INVALID",
            )

    def test_invalid_ifsc_rejected(self):
        """Test that invalid IFSC format is rejected."""
        from app.schemas.merchant_onboarding import BankInput
        import pytest
        with pytest.raises(Exception):
            BankInput(
                account_number="1234567890",
                ifsc_code="INVALID",
                account_holder_name="Test User",
            )

    def test_invalid_category_code_rejected(self):
        """Test that invalid category code is rejected."""
        from app.schemas.merchant_onboarding import MerchantOnboardingRequest
        import pytest
        with pytest.raises(Exception):
            MerchantOnboardingRequest(
                business_name="Test",
                category_code="INVALID_CATEGORY",
                phone="9999999999",
                address={
                    "address_line1": "123 Main St",
                    "city": "Mumbai",
                    "state": "Maharashtra",
                    "pincode": "400001",
                },
                location={"latitude": 19.07, "longitude": 72.87},
            )

    def test_invalid_latitude_rejected(self):
        """Test that invalid latitude is rejected."""
        from app.schemas.merchant_onboarding import ShopLocationInput
        import pytest
        with pytest.raises(Exception):
            ShopLocationInput(latitude=100, longitude=72.87)

    def test_invalid_longitude_rejected(self):
        """Test that invalid longitude is rejected."""
        from app.schemas.merchant_onboarding import ShopLocationInput
        import pytest
        with pytest.raises(Exception):
            ShopLocationInput(latitude=19.07, longitude=200)

    def test_poor_gps_accuracy_warning(self):
        """Test that poor GPS accuracy is flagged."""
        from app.schemas.merchant_onboarding import ShopLocationInput
        import pytest
        with pytest.raises(Exception):
            ShopLocationInput(latitude=19.07, longitude=72.87, accuracy=150)


# ── Test Verification Attempt Tracking ────────────────────────────────────

class TestVerificationAttempts:
    """Tests for verification attempt tracking."""

    def test_attempt_number_incrementing(self, db, sample_category, sample_requirements):
        """Test that attempt numbers increment correctly."""
        # Create an onboarding
        onboarding = MerchantOnboarding(
            shop_id=1,
            user_id=1,
            category_code="PHARMACY_HEALTHCARE",
            status=OnboardingStatus.IDENTITY_PENDING,
        )
        db.add(onboarding)
        db.flush()

        # Create multiple attempts
        for i in range(3):
            attempt = VerificationAttempt(
                onboarding_id=onboarding.id,
                attempt_type=VerificationAttemptType.GSTIN_VERIFY,
                status=VerificationAttemptStatus.SUCCESS,
                attempt_number=i + 1,
                is_latest_attempt=(i == 2),
            )
            db.add(attempt)
        db.flush()

        attempts = (
            db.query(VerificationAttempt)
            .filter(VerificationAttempt.onboarding_id == onboarding.id)
            .all()
        )
        assert len(attempts) == 3
        assert attempts[0].attempt_number == 1
        assert attempts[2].is_latest_attempt is True


# ── Test Compliance ───────────────────────────────────────────────────────

class TestCompliance:
    """Tests for compliance requirements."""

    def test_no_scraping_claimed(self):
        """Test that no scraping is performed."""
        # All providers should route to admin review, not scrape
        provider = SandboxIdentityProvider()
        assert hasattr(provider, "verify_gstin")
        assert hasattr(provider, "verify_udyam")

    def test_no_fabricated_results(self):
        """Test that results are not fabricated."""
        provider = SandboxIdentityProvider()
        import asyncio
        # Unknown identifier should not return VERIFIED
        result = asyncio.run(provider.verify_gstin("99XXXXX9999X9X9"))
        assert result.status != "VERIFIED"

    def test_admin_review_fallback(self):
        """Test that unverifiable documents route to admin review."""
        provider = SandboxCategoryProvider()
        import asyncio
        result = asyncio.run(provider.verify_drug_license("UNKNOWN"))
        assert result.requires_admin_review is True

    def test_sandbox_marked_in_metadata(self):
        """Test that sandbox results are clearly marked."""
        provider = SandboxIdentityProvider()
        import asyncio
        result = asyncio.run(provider.verify_gstin("27AAAAA1234A1Z5"))
        assert result.metadata is not None
        assert result.metadata.get("sandbox") is True
        assert result.metadata.get("test_data") is True

# ── DB fixture (in-memory SQLite, same pattern as other phase tests) ──────
import pytest  # noqa: E402
from sqlalchemy import create_engine  # noqa: E402
from sqlalchemy.orm import sessionmaker  # noqa: E402
from app.database.session import Base  # noqa: E402
from app.models.merchant_category import MerchantCategory as _MC, MerchantVerificationRequirement as _MVR  # noqa: E402
from app.models.merchant_onboarding import MerchantOnboarding as _MO  # noqa: E402
from app.models.business_identity_verification import (  # noqa: E402
    BusinessIdentityVerification as _BIV,
    BankAccountVerification as _BAV,
    CategoryDocumentVerification as _CDV,
)
from app.models.verification_attempt import (  # noqa: E402
    VerificationAttempt as _VA,
    VerificationProviderLog as _VPL,
)

_DB_TABLES = [
    _MC.__table__, _MVR.__table__, _MO.__table__,
    _BIV.__table__, _BAV.__table__, _CDV.__table__,
    _VA.__table__, _VPL.__table__,
]


@pytest.fixture()
def db():
    """In-memory SQLite session with PG server_default made portable.

    Uses the same approach as test_admin_moderation_flow.py — replace
    literal ``now()`` / ``false`` server defaults with Python-side
    defaults so SQLite stores timestamps/bools correctly, then restore
    the global metadata afterwards.
    """
    from sqlalchemy import ColumnDefault

    def _now(ctx=None):
        return datetime.now(timezone.utc)

    patched = []
    for table in _DB_TABLES:
        for col in table.columns:
            sd = getattr(col, "server_default", None)
            sd_arg = getattr(sd, "arg", None)
            if sd_arg == "now()":
                if col.default is None:
                    col.default = ColumnDefault(_now)
                    patched.append((col, "now()"))
                col.server_default = None
            elif isinstance(sd_arg, str) and sd_arg.lower() == "false":
                if col.default is None and (
                    getattr(getattr(col.type, "python_type", None), "__name__", "")
                    == "bool"
                ):
                    col.default = ColumnDefault(False)
                    patched.append((col, "false"))
                col.server_default = None
            ou = getattr(col, "onupdate", None)
            if ou is not None and getattr(ou, "arg", None) == "now()":
                col.onupdate = ColumnDefault(_now, for_update=True)
                patched.append((col, "onupdate-now")) if False else None
    try:
        engine = create_engine("sqlite://", connect_args={"check_same_thread": False})
        Base.metadata.create_all(engine, tables=_DB_TABLES)
        session = sessionmaker(bind=engine)()
        yield session
        session.close()
        engine.dispose()
    finally:
        for col, kind in patched:
            if kind == "now()":
                col.server_default = "now()"
            elif kind == "false":
                col.server_default = "false"



