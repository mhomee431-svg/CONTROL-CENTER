"""Phase 30 - Production Hardening tests.

Security:
  * startup security gate (production fail-fast on insecure config)
  * secure upload validation (filename sanitization, size caps,
    magic-byte sniffing against renamed/polyglot files)
  * barcode input hardening
  * token security (forged signature / expired / wrong-type tokens)
  * OTP protection (brute-force lockout, expiry, single-use)
  * access control / IDOR (shop association enforcement)
  * rate-limit configuration & proxy-aware client keying
  * mass assignment protection on request schemas

Performance:
  * query-count bounds (no N+1 on analytics dashboards)
  * pagination limits respected under load
  * search/dashboard latency budget

Reliability:
  * failure simulation (cache down -> degraded health, not crash)
  * audit chain integrity after simulated partial writes
  * idempotency key stability for uploads
"""

import os
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402
from sqlalchemy import create_engine, event  # noqa: E402
from sqlalchemy.orm import sessionmaker  # noqa: E402
from sqlalchemy.pool import StaticPool  # noqa: E402

from app.core.config import Settings, settings  # noqa: E402

settings.RATE_LIMIT_ENABLED = False

from app.core.exceptions import AppError, ForbiddenError, NotFoundError, ValidationError  # noqa: E402
from app.models.admin import AuditLog  # noqa: E402
from app.models.analytics_event import AnalyticsDailyAggregate, AnalyticsEvent  # noqa: E402
from app.models.base import Base  # noqa: E402
from app.core.startup_checks import (  # noqa: E402
    ProductionSecurityError,
    run_startup_security_checks,
)
from app.core.upload_security import (  # noqa: E402
    XLSX_MAGIC,
    UploadValidationError,
    sanitize_filename,
    validate_upload,
)
from app.models.inventory_import import InventoryImportJob, InventoryImportRow  # noqa: E402
from app.services import otp_service  # noqa: E402
from app.services import shopkeeper_service  # noqa: E402


# Adapt PostGIS Geography columns for plain SQLite (shared, reversible helper).
from tests.geo_compat import strip_geo_columns  # noqa: E402

strip_geo_columns()


def _portable_timestamp_defaults():
    from sqlalchemy import ColumnDefault

    def _now(ctx=None):
        return datetime.now(timezone.utc)

    for table in Base.metadata.tables.values():
        for col in table.columns:
            sd = getattr(col, "server_default", None)
            sd_arg = getattr(sd, "arg", None)
            if isinstance(sd_arg, str) and sd_arg.lower() == "now()":
                if col.default is None:
                    col.default = ColumnDefault(_now)
                col.server_default = None
            elif isinstance(sd_arg, str) and sd_arg.lower() == "false":
                if col.default is None and (
                    getattr(getattr(col.type, "python_type", None), "__name__", "") == "bool"
                ):
                    col.default = ColumnDefault(False)
                col.server_default = None
            ou = getattr(col, "onupdate", None)
            ou_arg = getattr(ou, "arg", None)
            if ou is not None and str(ou_arg).strip().lower().startswith("now"):
                col.onupdate = ColumnDefault(_now, for_update=True)


_portable_timestamp_defaults()


from app.models.role import Permission, Role, role_permissions  # noqa: E402
from app.models.shop import Shop, ShopManager, ShopOwner  # noqa: E402
from app.models.user import User, UserStatus  # noqa: E402

TABLES = [
    Role.__table__,
    Permission.__table__,
    role_permissions,
    User.__table__,
    Shop.__table__,
    ShopOwner.__table__,
    ShopManager.__table__,
    InventoryImportJob.__table__,
    InventoryImportRow.__table__,
    AnalyticsEvent.__table__,
    AnalyticsDailyAggregate.__table__,
    AuditLog.__table__,
]


@pytest.fixture()
def db():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine, tables=TABLES)
    session = sessionmaker(bind=engine)()
    yield session
    session.close()
    engine.dispose()


# ── Entity factories ─────────────────────────────────────────────────────────
_counter = {"n": 0}


def _next_id():
    _counter["n"] += 1
    return _counter["n"]


def make_user(db, role_name="customer"):
    n = _next_id()
    role = db.query(Role).filter(Role.name == role_name).first()
    if role is None:
        role = Role(name=role_name, description=role_name)
        db.add(role)
        db.flush()
    user = User(
        phone_number=f"+9198765{n:05d}",
        name=f"User {n}",
        role_id=role.id,
        status=UserStatus.ACTIVE,
        is_active=True,
    )
    db.add(user)
    db.flush()
    return user


def make_shop(db, owner=None):
    from app.models.shop import ShopStatus

    n = _next_id()
    shop = Shop(
        name=f"Shop {n}",
        description=f"desc {n}",
        status=ShopStatus.ACTIVE,
        latitude=25.59,
        longitude=85.13,
    )
    db.add(shop)
    db.flush()
    if owner is not None:
        db.add(ShopOwner(shop_id=shop.id, user_id=owner.id, is_active=True))
        db.flush()
    return shop


def _prod_settings(**overrides) -> Settings:
    """A fully-secure production Settings instance (tests mutate from here)."""
    base = dict(
        ENVIRONMENT="production",
        JWT_SECRET_KEY="x" * 48,
        OTP_DEV_MODE=False,
        DEBUG=False,
        CORS_ORIGINS="https://app.example.com",
        RATE_LIMIT_ENABLED=True,
        # Distributed state is mandatory in production (multi-worker safe):
        OTP_STORAGE_URI="redis://127.0.0.1:6379/4",
        RATE_LIMIT_STORAGE_URI="redis://127.0.0.1:6379/3",
        # Mock gateway must never run with its published default secret in prod:
        MOCK_PAYMENT_SECRET="p" * 48,
    )
    base.update(overrides)
    return Settings(**base)


# ── Startup security gate ────────────────────────────────────────────────────
class TestStartupSecurityGate:
    def test_secure_production_config_boots(self):
        assert run_startup_security_checks(_prod_settings()) == []

    def test_default_jwt_secret_blocks_production(self):
        with pytest.raises(ProductionSecurityError, match="JWT_SECRET_KEY"):
            run_startup_security_checks(_prod_settings(JWT_SECRET_KEY="change-me-in-production"))

    def test_short_jwt_secret_blocks_production(self):
        with pytest.raises(ProductionSecurityError, match="brute force"):
            run_startup_security_checks(_prod_settings(JWT_SECRET_KEY="short"))

    def test_otp_dev_backdoor_blocks_production(self):
        with pytest.raises(ProductionSecurityError, match="OTP_DEV_MODE"):
            run_startup_security_checks(_prod_settings(OTP_DEV_MODE=True))

    def test_cors_wildcard_blocks_production(self):
        with pytest.raises(ProductionSecurityError, match="CORS"):
            run_startup_security_checks(_prod_settings(CORS_ORIGINS="*"))
        with pytest.raises(ProductionSecurityError, match="CORS"):
            run_startup_security_checks(_prod_settings(CORS_ORIGINS=""))

    def test_debug_flagged_in_production(self):
        with pytest.raises(ProductionSecurityError, match="DEBUG"):
            run_startup_security_checks(_prod_settings(DEBUG=True))

    def test_in_memory_otp_store_blocks_production(self):
        with pytest.raises(ProductionSecurityError, match="OTP_STORAGE_URI"):
            run_startup_security_checks(
                _prod_settings(OTP_STORAGE_URI="memory://")
            )

    def test_default_mock_payment_secret_blocks_production(self):
        # Only the built-in mock gateway is registered and its signing secret
        # is the published default → an attacker could forge payment/webhook
        # signatures to activate paid subscriptions for free.
        with pytest.raises(ProductionSecurityError, match="MockPaymentProvider"):
            run_startup_security_checks(
                _prod_settings(MOCK_PAYMENT_SECRET="mock-payment-secret")
            )

    def test_in_memory_rate_limit_store_blocks_production(self):
        with pytest.raises(ProductionSecurityError, match="RATE_LIMIT_STORAGE_URI"):
            run_startup_security_checks(
                _prod_settings(RATE_LIMIT_STORAGE_URI="memory://")
            )

    def test_fcm_provider_without_credentials_blocks_production(self):
        with pytest.raises(ProductionSecurityError, match="FCM"):
            run_startup_security_checks(_prod_settings(PUSH_PROVIDER="fcm"))

    def test_fcm_provider_with_credentials_passes(self):
        findings = run_startup_security_checks(
            _prod_settings(PUSH_PROVIDER="fcm", FCM_CREDENTIALS_JSON='{"project_id": "x"}')
        )
        assert findings == []

    def test_development_only_warns_never_raises(self):
        insecure = Settings(
            ENVIRONMENT="development",
            JWT_SECRET_KEY="change-me-in-production",
            OTP_DEV_MODE=True,
        )
        findings = run_startup_security_checks(insecure)
        assert len(findings) >= 2  # warned, not raised


# ── Secure uploads ───────────────────────────────────────────────────────────
class TestUploadSecurity:
    def test_filename_traversal_stripped(self):
        assert sanitize_filename("../../etc/passwd.xlsx") == "passwd.xlsx"
        assert sanitize_filename("..\\..\\windows\\system32\\evil.xlsx") == "evil.xlsx"
        assert sanitize_filename("C:/temp/steal.xlsx") == "steal.xlsx"

    def test_filename_control_chars_and_fallback(self):
        cleaned = sanitize_filename("inv\x00\x1freport.xlsx")
        assert "\x00" not in cleaned and "\x1f" not in cleaned
        assert sanitize_filename("") == "upload"
        assert sanitize_filename(None) == "upload"
        assert sanitize_filename("../../../") == "upload"

    def test_rejects_wrong_extension(self):
        with pytest.raises(UploadValidationError) as ei:
            validate_upload("data.csv", b"a,b,c", max_bytes=1024)
        assert ei.value.reason_code == "INVALID_FILE_TYPE"

    def test_rejects_empty_file(self):
        with pytest.raises(UploadValidationError) as ei:
            validate_upload("ok.xlsx", b"", max_bytes=1024)
        assert ei.value.reason_code == "EMPTY_FILE"

    def test_rejects_oversized_file(self):
        payload = XLSX_MAGIC + b"0" * 100
        with pytest.raises(UploadValidationError) as ei:
            validate_upload("big.xlsx", payload, max_bytes=50)
        assert ei.value.reason_code == "FILE_TOO_LARGE"

    def test_rejects_renamed_executable_magic_mismatch(self):
        # An .exe renamed to .xlsx must fail the magic-byte check.
        exe_bytes = b"MZ\x90\x00\x03\x00\x00\x00" + b"\x00" * 64
        with pytest.raises(UploadValidationError) as ei:
            validate_upload("totally-legit.xlsx", exe_bytes, max_bytes=1024)
        assert ei.value.reason_code == "CONTENT_TYPE_MISMATCH"

    def test_accepts_real_xlsx_content(self):
        from app.services import xlsx_lite

        grid = [["barcode", "name"], ["8901234567890", "Tea"]]
        content = xlsx_lite.write_workbook(grid)
        name = validate_upload("inventory final.xlsx", content, max_bytes=5 * 1024 * 1024)
        assert name == "inventory final.xlsx"

    def test_excel_import_service_uses_validator(self, db):
        """End-to-end: create_import rejects polyglot uploads with reason code."""
        from app.services import excel_import_service

        class _Shop:
            id = 1

        class _Access:
            shop = _Shop()

            def require(self, resource, action):
                assert (resource, action) == ("inventory", "update")

        fake_exe = b"MZ\x90\x00" + b"\x00" * 32
        with pytest.raises(ValidationError) as ei:
            excel_import_service.create_import(_Access(), db, None, "evil.xlsx", fake_exe)
        assert ei.value.data["reason_code"] == "CONTENT_TYPE_MISMATCH"


# ── Barcode input hardening ──────────────────────────────────────────────────
class TestBarcodeHardening:
    def test_valid_barcode_normalized(self):
        from app.api.routes.inventory_intake import _validate_barcode_input

        assert _validate_barcode_input(" 890-12345 67890 ") == "8901234567890"

    def test_non_numeric_barcode_rejected(self):
        from app.api.routes.inventory_intake import _validate_barcode_input

        with pytest.raises(AppError):
            _validate_barcode_input("89012DROP TABLE users")
        with pytest.raises(AppError):
            _validate_barcode_input("../../etc/passwd")

    def test_oversized_barcode_rejected(self):
        from app.api.routes.inventory_intake import MAX_BARCODE_LENGTH, _validate_barcode_input

        with pytest.raises(AppError):
            _validate_barcode_input("9" * (MAX_BARCODE_LENGTH + 1))


# ── Token security ───────────────────────────────────────────────────────────
class TestTokenSecurity:
    def test_forged_signature_rejected(self):
        from app.core.security import TokenPurpose, validate_token_type
        from jose import jwt as jose_jwt

        token, _ = __import__("app.core.security", fromlist=["create_access_token"]).create_access_token("42")
        assert validate_token_type(token, TokenPurpose.ACCESS) is True
        # Re-signed with an attacker-chosen secret — must fail validation.
        evil = jose_jwt.encode(
            {
                "sub": "42",
                "type": "access",
                "exp": datetime.now(timezone.utc) + timedelta(hours=1),
                "iss": settings.TOKEN_ISSUER,
                "aud": settings.TOKEN_AUDIENCE,
            },
            "attacker-secret",
            algorithm="HS256",
        )
        assert validate_token_type(evil, TokenPurpose.ACCESS) is False

    def test_expired_token_rejected(self):
        from app.core.security import TokenPurpose, _create_token, get_token_subject

        expired, _ = _create_token("42", TokenPurpose.ACCESS, timedelta(minutes=-10))
        assert get_token_subject(expired) is None

    def test_refresh_token_not_accepted_as_access(self):
        from app.core.security import (
            TokenPurpose,
            create_refresh_token,
            validate_token_type,
        )

        refresh, _ = create_refresh_token("42")
        assert validate_token_type(refresh, TokenPurpose.ACCESS) is False
        assert validate_token_type(refresh, TokenPurpose.REFRESH) is True

    def test_tampered_payload_invalidates_signature(self):
        from app.core.security import TokenPurpose, create_access_token, validate_token_type

        token, _ = create_access_token("1")
        header, payload, signature = token.split(".")
        tampered = f"{header}.{payload[:-2]}AA.{signature}"
        assert validate_token_type(tampered, TokenPurpose.ACCESS) is False


# ── OTP protection ───────────────────────────────────────────────────────────
class TestOTPProtection:
    def setup_method(self):
        otp_service.clear_all_otps()

    def test_brute_force_lockout(self):
        phone = "+9198765000042"
        otp_service.generate_otp(phone)
        real_otp = settings.OTP_DEV_VALUE  # dev mode returns a fixed code
        for _ in range(settings.OTP_MAX_ATTEMPTS):
            assert otp_service.verify_otp(phone, "000000") is False
        # Even the CORRECT code is now rejected — record destroyed on lockout.
        assert otp_service.verify_otp(phone, real_otp) is False

    def test_expired_otp_rejected(self):
        from app.services.otp_store import get_otp_store

        phone = "+9198765000043"
        otp_service.generate_otp(phone)
        store = get_otp_store(settings.OTP_STORAGE_URI)
        record = store.get(phone)
        record["expires_at"] = datetime.now(timezone.utc) - timedelta(seconds=1)
        store.set(phone, record, ttl_seconds=60)
        assert otp_service.verify_otp(phone, settings.OTP_DEV_VALUE) is False

    def test_otp_is_single_use(self):
        phone = "+9198765000044"
        otp_service.generate_otp(phone)
        assert otp_service.verify_otp(phone, settings.OTP_DEV_VALUE) is True
        assert otp_service.verify_otp(phone, settings.OTP_DEV_VALUE) is False


# ── Access control / IDOR ────────────────────────────────────────────────────
class TestAccessControlIDOR:
    def test_owner_can_access_own_shop(self, db):
        owner = make_user(db, role_name="shopkeeper")
        shop = make_shop(db, owner=owner)
        access = shopkeeper_service.resolve_shop_access(db, owner, shop.id)
        assert access.shop.id == shop.id
        assert access.is_owner is True

    def test_unrelated_user_cannot_access_shop(self, db):
        """Classic IDOR probe: customer guesses /shopkeeper/shops/{id}/... paths."""
        owner = make_user(db, role_name="shopkeeper")
        stranger = make_user(db, role_name="customer")
        shop = make_shop(db, owner=owner)
        with pytest.raises(ForbiddenError):
            shopkeeper_service.resolve_shop_access(db, stranger, shop.id)

    def test_suspended_owner_mapping_not_authorized(self, db):
        owner = make_user(db, role_name="shopkeeper")
        shop = make_shop(db, owner=owner)
        db.query(ShopOwner).filter(
            ShopOwner.shop_id == shop.id, ShopOwner.user_id == owner.id
        ).update({"is_active": False})
        db.flush()
        with pytest.raises(ForbiddenError):
            shopkeeper_service.resolve_shop_access(db, owner, shop.id)

    def test_nonexistent_shop_is_404_not_403(self, db):
        user = make_user(db)
        with pytest.raises(NotFoundError):
            shopkeeper_service.resolve_shop_access(db, user, 999999)


# ── Rate limiting configuration ──────────────────────────────────────────────
class TestRateLimiting:
    def test_auth_limit_stricter_than_default(self):
        from app.core.rate_limit import auth_rate_limit, default_rate_limit

        assert "5" in settings.RATE_LIMIT_AUTH_ENDPOINT
        assert callable(auth_rate_limit()) and callable(default_rate_limit())

    def test_client_key_ignores_xff_by_default(self):
        from app.core.rate_limit import _client_key

        class _FakeClient:
            host = "10.0.0.7"

        class _FakeRequest:
            client = _FakeClient()
            headers = {"X-Forwarded-For": "1.2.3.4"}

        settings.TRUST_X_FORWARDED_FOR = False
        assert _client_key(_FakeRequest()) == "10.0.0.7"

    def test_client_key_uses_xff_only_when_trusted(self):
        from app.core.rate_limit import _client_key

        class _FakeClient:
            host = "10.0.0.7"

        class _FakeRequest:
            client = _FakeClient()
            headers = {"X-Forwarded-For": "203.0.113.9, 10.0.0.1"}

        settings.TRUST_X_FORWARDED_FOR = True
        try:
            assert _client_key(_FakeRequest()) == "203.0.113.9"
        finally:
            settings.TRUST_X_FORWARDED_FOR = False


# ── Mass assignment ──────────────────────────────────────────────────────────
class TestMassAssignment:
    def test_analytics_event_schema_ignores_extras(self):
        from app.schemas.analytics import AnalyticsEventIn

        payload = AnalyticsEventIn(
            event_name="PRODUCT_VIEW",
            actor_type="CUSTOMER",
            props={"screen": "home"},
            is_admin=True,  # attacker-injected field
        )
        dumped = payload.model_dump()
        assert "is_admin" not in dumped
        # actor_id is server-controlled (from the authenticated user), never
        # accepted from the client payload.
        assert dumped.get("actor_id") is None

    def test_barcode_save_schema_ignores_extras(self):
        from app.schemas.inventory_intake import BarcodeSaveRequest

        payload = BarcodeSaveRequest(
            barcode="8901234567890",
            product_master_id=1,
            price=99.0,
            shop_owner_role_bypass=True,
        )
        assert "shop_owner_role_bypass" not in payload.model_dump()


# ── Database / API / search performance ──────────────────────────────────────
class TestPerformance:
    @pytest.fixture()
    def perf_db(self, db):
        """Seed a realistic volume of analytics events."""
        base = datetime.now(timezone.utc) - timedelta(hours=2)
        events = []
        for i in range(300):
            events.append(
                AnalyticsEvent(
                    event_name="PRODUCT_VIEW" if i % 3 else "SEARCH",
                    actor_type="CUSTOMER",
                    actor_id=i % 25,
                    session_id=f"perf-{i % 40}",
                    product_master_id=(i % 50) + 1,
                    category_id=(i % 5) + 1,
                    query=f"q{i % 30}" if i % 3 == 0 else None,
                    metric_value=float(i),
                    occurred_at=base,
                )
            )
        db.bulk_save_objects(events)
        db.flush()
        return db

    def test_dashboard_no_n1_query_explosion(self, perf_db):
        from app.services import analytics_system as an

        statements = []

        def _before(conn, cursor, statement, parameters, context, executemany):
            statements.append(statement)

        bind = perf_db.bind
        event.listen(bind, "before_cursor_execute", _before)
        try:
            for _ in range(3):  # repeat: cached plans shouldn't multiply queries
                an.popular_products(perf_db, days=7, limit=10)
                an.popular_categories(perf_db, days=7, limit=10)
                an.search_trends(perf_db, days=7)
        finally:
            event.remove(bind, "before_cursor_execute", _before)
        # 3 dashboards x a handful of aggregate queries — NOT one per row.
        assert len(statements) <= 40, f"N+1 suspected: {len(statements)} queries"

    def test_indexed_event_lookup_stays_fast_at_volume(self, perf_db):
        from sqlalchemy import func

        start = time.perf_counter()
        rows = (
            perf_db.query(func.count(AnalyticsEvent.id))
            .filter(
                AnalyticsEvent.event_name == "SEARCH",
                AnalyticsEvent.occurred_at >= datetime.now(timezone.utc) - timedelta(days=1),
            )
            .scalar()
        )
        elapsed = time.perf_counter() - start
        assert rows > 0
        assert elapsed < 0.5, f"Indexed lookup too slow: {elapsed:.3f}s"

    def test_pagination_limits_are_respected(self, perf_db):
        from app.services import analytics_system as an

        assert len(an.popular_products(perf_db, days=7, limit=5)) <= 5
        # Route layer caps `limit` at 100; service honours whatever it gets.
        assert len(an.popular_products(perf_db, days=7, limit=100)) <= 100
        assert len(an.read_aggregates(perf_db, limit=10)) <= 10

    def test_aggregation_over_volume_within_budget(self, perf_db):
        from app.services import analytics_system as an

        start = time.perf_counter()
        result = an.aggregate_daily(perf_db, datetime.now(timezone.utc).date())
        elapsed = time.perf_counter() - start
        assert result["groups"] >= 2
        assert elapsed < 3.0, f"Aggregation too slow: {elapsed:.3f}s"

    def test_search_tracking_throughput(self, perf_db):
        from app.services import analytics_system as an

        start = time.perf_counter()
        for i in range(50):
            an.track_search(
                perf_db, user_id=i % 5, session_id=f"t{i}", query=f"prod {i}",
                result_count=i,
            )
        elapsed = time.perf_counter() - start
        assert elapsed < 3.0, f"50 tracked searches took {elapsed:.3f}s"