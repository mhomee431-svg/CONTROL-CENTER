"""Comprehensive tests for Shopkeeper Authentication System."""
import pytest
from datetime import datetime, timezone
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from sqlalchemy import event

from app.main import app
from app.core.security import hash_password, verify_password, create_password_reset_token
from app.database.session import Base, get_db
from app.models.user import User, UserStatus
from app.models.role import Role, Permission
from app.models.session import AuthSession, TokenBlacklist
from app.models.shop import Shop, ShopOwner, ShopManager, ShopStatus
from app.core.shopkeeper_permissions import ensure_shopkeeper_role


def _now() -> datetime:
    """UTC now for tests."""
    return datetime.now(timezone.utc)


# ── Test Database Setup ──────────────────────────────────────────────────────
SQLALCHEMY_DATABASE_URL = "sqlite:///:memory:"

engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)

# Enable foreign keys for SQLite
@event.listens_for(engine, "connect")
def set_sqlite_pragma(dbapi_connection, connection_record):
    cursor = dbapi_connection.cursor()
    cursor.execute("PRAGMA foreign_keys=ON")
    cursor.close()


TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


# ── SQLite-friendly timestamps ────────────────────────────────────────────────
# Models use PostgreSQL `server_default="now()"`, which SQLite can't evaluate.
# This ORM event auto-populates created_at/updated_at in Python for any mapped
# object that declares them, so INSERTs never fall back to the DB default.
from sqlalchemy.orm import Mapper


@event.listens_for(TestingSessionLocal, "before_flush")
def _fill_timestamps(session, flush_context, instances):
    for obj in session.new:
        for col in ("created_at", "updated_at"):
            val = getattr(obj, col, None)
            if val is None and col in obj.__table__.columns:
                setattr(obj, col, _now())
    for obj in session.dirty:
        if hasattr(obj, "updated_at") and "updated_at" in obj.__table__.columns:
            setattr(obj, "updated_at", _now())


def override_get_db():
    try:
        db = TestingSessionLocal()
        yield db
    finally:
        db.close()


app.dependency_overrides[get_db] = override_get_db


def create_test_tables():
    """Create only the tables needed for auth tests (no PostGIS)."""
    # Define the specific tables we need in dependency order
    needed_tables = [
        "roles",
        "permissions", 
        "role_permissions",
        "users",
        "user_roles",
        "auth_sessions",
        "token_blacklist",
        "password_resets",
        "shops",
        "shop_owners",
        "shop_managers",
    ]
    
    # Get tables in dependency order from metadata
    for table in Base.metadata.sorted_tables:
        if table.name in needed_tables:
            try:
                table.create(engine, checkfirst=True)
            except Exception:
                pass  # Skip tables that fail


@pytest.fixture(scope="function")
def client():
    """Create a fresh database for each test."""
    # Drop tables in reverse order
    needed_tables = [
        "token_blacklist",
        "auth_sessions",
        "user_roles",
        "users",
        "password_resets",
        "shop_owners",
        "shop_managers",
        "shops",
        "role_permissions",
        "permissions",
        "roles",
    ]
    for table_name in needed_tables:
        try:
            table = Base.metadata.tables.get(table_name)
            if table is not None:
                table.drop(engine, checkfirst=True)
        except Exception:
            pass
    
    # Create tables
    create_test_tables()
    yield TestClient(app)
    
    # Cleanup
    for table_name in needed_tables:
        try:
            table = Base.metadata.tables.get(table_name)
            if table is not None:
                table.drop(engine, checkfirst=True)
        except Exception:
            pass


@pytest.fixture
def db():
    """Get a database session."""
    session = TestingSessionLocal()
    try:
        yield session
    finally:
        session.close()


@pytest.fixture
def shopkeeper_role(db):
    """Create shopkeeper role."""
    return ensure_shopkeeper_role(db)


@pytest.fixture
def active_user(db, shopkeeper_role):
    """Create an active shopkeeper user."""
    user = User(
        phone_number="+919999999999",
        name="Test Shopkeeper",
        email="test@shopkeeper.com",
        password_hash=hash_password("Password123"),
        role_id=shopkeeper_role.id,
        status=UserStatus.ACTIVE,
        is_active=True,
        created_at=_now(),
        updated_at=_now(),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


@pytest.fixture
def suspended_user(db, shopkeeper_role):
    """Create a suspended shopkeeper user."""
    user = User(
        phone_number="+918888888888",
        name="Suspended User",
        email="suspended@shopkeeper.com",
        password_hash=hash_password("Password123"),
        role_id=shopkeeper_role.id,
        status=UserStatus.SUSPENDED,
        is_active=True,
        created_at=_now(),
        updated_at=_now(),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


@pytest.fixture
def inactive_user(db, shopkeeper_role):
    """Create an inactive shopkeeper user."""
    user = User(
        phone_number="+917777777777",
        name="Inactive User",
        email="inactive@shopkeeper.com",
        password_hash=hash_password("Password123"),
        role_id=shopkeeper_role.id,
        status=UserStatus.ACTIVE,
        is_active=False,
        created_at=_now(),
        updated_at=_now(),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


@pytest.fixture
def user_with_shop(db, active_user):
    """Create a user with an associated shop."""
    shop = Shop(
        name="Test Shop",
        status=ShopStatus.ACTIVE,
        location="POINT(77.1025 28.7041)",
        created_at=_now(),
        updated_at=_now(),
    )
    db.add(shop)
    db.flush()
    
    owner = ShopOwner(
        shop_id=shop.id,
        user_id=active_user.id,
        is_active=True,
        created_at=_now(),
        updated_at=_now(),
    )
    db.add(owner)
    db.commit()
    db.refresh(active_user)
    return active_user, shop


# ── Password Hashing Tests ────────────────────────────────────────────────────
class TestPasswordHashing:
    def test_hash_password_produces_different_output(self):
        """Password hash should not equal plain password."""
        password = "Password123"
        hashed = hash_password(password)
        assert hashed != password
        assert len(hashed) > 0

    def test_verify_password_correct(self):
        """Correct password should verify."""
        password = "Password123"
        hashed = hash_password(password)
        assert verify_password(password, hashed) is True

    def test_verify_password_incorrect(self):
        """Incorrect password should not verify."""
        password = "Password123"
        wrong_password = "WrongPassword123"
        hashed = hash_password(password)
        assert verify_password(wrong_password, hashed) is False

    def test_password_reset_token_creation(self):
        """Password reset token should be created with correct type."""
        token, jti = create_password_reset_token("1")
        assert token is not None
        assert jti is not None
        assert len(token) > 0


# ── Password-based Login Tests ────────────────────────────────────────────────
class TestPasswordLogin:
    def test_login_with_valid_email_and_password(self, client, active_user):
        """Valid email + password should return tokens."""
        response = client.post(
            "/api/v1/shopkeeper/auth/login",
            json={
                "identifier": "test@shopkeeper.com",
                "password": "Password123",
            },
        )
        assert response.status_code == 200
        data = response.json()["data"]
        assert "access_token" in data
        assert "refresh_token" in data
        assert data["token_type"] == "bearer"
        assert "user" in data
        assert data["user"]["email"] == "test@shopkeeper.com"

    def test_login_with_valid_phone_and_password(self, client, active_user):
        """Valid phone + password should return tokens."""
        response = client.post(
            "/api/v1/shopkeeper/auth/login",
            json={
                "identifier": "+919999999999",
                "password": "Password123",
            },
        )
        assert response.status_code == 200
        data = response.json()["data"]
        assert "access_token" in data
        assert "refresh_token" in data

    def test_login_with_wrong_password(self, client, active_user):
        """Wrong password should return 401."""
        response = client.post(
            "/api/v1/shopkeeper/auth/login",
            json={
                "identifier": "test@shopkeeper.com",
                "password": "WrongPassword123",
            },
        )
        assert response.status_code == 401
        assert response.json()["error_code"] == "INVALID_CREDENTIALS"

    def test_login_with_nonexistent_email(self, client):
        """Non-existent email should return 401 (don't reveal existence)."""
        response = client.post(
            "/api/v1/shopkeeper/auth/login",
            json={
                "identifier": "nonexistent@test.com",
                "password": "Password123",
            },
        )
        assert response.status_code == 401
        assert response.json()["error_code"] == "INVALID_CREDENTIALS"

    def test_login_suspended_account(self, client, suspended_user):
        """Suspended account should return 403."""
        response = client.post(
            "/api/v1/shopkeeper/auth/login",
            json={
                "identifier": "suspended@shopkeeper.com",
                "password": "Password123",
            },
        )
        assert response.status_code == 403
        assert response.json()["error_code"] == "ACCOUNT_NOT_ACTIVE"

    def test_login_inactive_account(self, client, inactive_user):
        """Inactive account should return 403."""
        response = client.post(
            "/api/v1/shopkeeper/auth/login",
            json={
                "identifier": "inactive@shopkeeper.com",
                "password": "Password123",
            },
        )
        assert response.status_code == 403

    def test_login_without_password(self, client, active_user):
        """Login without password should return 422."""
        response = client.post(
            "/api/v1/shopkeeper/auth/login",
            json={
                "identifier": "test@shopkeeper.com",
            },
        )
        assert response.status_code == 422

    def test_login_with_short_password(self, client, active_user):
        """Login with short password should return 422."""
        response = client.post(
            "/api/v1/shopkeeper/auth/login",
            json={
                "identifier": "test@shopkeeper.com",
                "password": "short",
            },
        )
        assert response.status_code == 422

    def test_login_response_does_not_contain_password(self, client, active_user):
        """Login response should not contain password or hash."""
        response = client.post(
            "/api/v1/shopkeeper/auth/login",
            json={
                "identifier": "test@shopkeeper.com",
                "password": "Password123",
            },
        )
        assert response.status_code == 200
        response_text = response.text
        assert "password" not in response_text.lower()
        assert "password_hash" not in response_text.lower()


# ── Firebase Login Tests (auto-login-or-register) ──────────────────────────
class TestFirebaseLogin:
    """Tests for POST /api/v1/shopkeeper/auth/firebase-login.

    The endpoint verifies a Firebase ID token (mocked here), looks up the
    shopkeeper by phone in PostgreSQL, and either logs in an existing user or
    auto-registers a new one.
    """

    @pytest.fixture(autouse=True)
    def _mock_firebase(self, monkeypatch):
        """Mock Firebase token verification for all tests in this class.

        The ``/auth/firebase-login`` route calls ``verify_firebase_id_token_claims``
        (NOT ``verify_firebase_id_token``) and expects a claim dict — patch the
        real symbol with a fake that maps test tokens back to phone numbers.
        """
        from app.api.routes import shopkeeper_auth

        _PHONE_MAP = {
            "valid-token-000000000000000000000000000000": "+919000000001",
            "existing-token-000000000000000000000000000": "+919999999999",
        }

        def _verify_claims(token):
            phone = _PHONE_MAP.get(token, "+919000000099")
            return {
                "uid": "test-firebase-uid-" + phone.replace("+", ""),
                "phone": phone,
                "email": "",
                "name": "",
                "picture": "",
                "provider": "phone",
                "claims": {},
            }

        monkeypatch.setattr(
            shopkeeper_auth, "verify_firebase_id_token_claims", _verify_claims
        )

    def test_firebase_login_auto_registers_new_user(self, client, db, shopkeeper_role):
        """New phone → auto-register and return tokens + is_new_account=true."""
        from app.models.user import User

        # No user exists for this phone yet
        assert db.query(User).filter(User.phone_number == "+919000000001").first() is None

        response = client.post(
            "/api/v1/shopkeeper/auth/firebase-login",
            json={
                "firebase_id_token": "valid-token-000000000000000000000000000000",
                "name": "New Shopkeeper",
            },
        )

        assert response.status_code == 200
        data = response.json()["data"]
        assert "access_token" in data
        assert "refresh_token" in data
        assert data["is_new_account"] is True
        assert data["user"]["phone_number"] == "+919000000001"

        # User was created in PostgreSQL
        user = db.query(User).filter(User.phone_number == "+919000000001").first()
        assert user is not None
        assert user.name == "New Shopkeeper"
        assert user.role.name == "shopkeeper"

    def test_firebase_login_existing_user(self, client, active_user):
        """Existing phone → login + is_new_account=false."""
        response = client.post(
            "/api/v1/shopkeeper/auth/firebase-login",
            json={
                "firebase_id_token": "existing-token-000000000000000000000000000",
            },
        )

        assert response.status_code == 200
        data = response.json()["data"]
        assert "access_token" in data
        assert "refresh_token" in data
        assert data["is_new_account"] is False
        assert data["user"]["phone_number"] == "+919999999999"

    def test_firebase_login_without_name_for_new_user(self, client):
        """New phone without name → 400 NAME_REQUIRED."""
        response = client.post(
            "/api/v1/shopkeeper/auth/firebase-login",
            json={
                "firebase_id_token": "valid-token-000000000000000000000000000000",
            },
        )

        assert response.status_code == 400
        assert response.json()["error_code"] == "NAME_REQUIRED"

    def test_firebase_login_invalid_token(self, client, monkeypatch):
        """Invalid Firebase token → 401."""
        from app.api.routes import shopkeeper_auth
        from app.services.firebase_verification import FirebaseVerificationError

        def _raise(token):
            raise FirebaseVerificationError("Invalid token")

        monkeypatch.setattr(
            shopkeeper_auth, "verify_firebase_id_token_claims", _raise
        )

        response = client.post(
            "/api/v1/shopkeeper/auth/firebase-login",
            json={
                "firebase_id_token": "any-token-00000000000000000000000000000",
            },
        )
        assert response.status_code == 401
        assert response.json()["error_code"] == "FIREBASE_VERIFICATION_FAILED"

    def test_firebase_login_suspended_account(self, client, suspended_user, monkeypatch):
        """Suspended account → 403."""
        from app.api.routes import shopkeeper_auth

        # Map token to the suspended user's phone number (as a claim dict —
        # the route reads claims["phone"]).
        monkeypatch.setattr(
            shopkeeper_auth,
            "verify_firebase_id_token_claims",
            lambda t: {
                "uid": "test-firebase-uid-918888888888",
                "phone": "+918888888888",
                "email": "",
                "name": "",
                "picture": "",
                "provider": "phone",
                "claims": {},
            },
        )

        response = client.post(
            "/api/v1/shopkeeper/auth/firebase-login",
            json={
                "firebase_id_token": "suspended-token-000000000000000000000",
            },
        )
        assert response.status_code == 403
        assert response.json()["error_code"] == "ACCOUNT_NOT_ACTIVE"
# ── Token Refresh Tests ───────────────────────────────────────────────────────
class TestTokenRefresh:
    """Regression guard: ``/shopkeeper/auth/refresh`` must resolve.

    The route called ``refresh_session`` without importing it, so every real
    refresh attempt raised ``NameError`` → HTTP 500. The mobile app only calls
    refresh once its short-lived access token ages out, which is why the fault
    surfaced as a late "Internal Server Error" rather than at sign-in.
    """

    def test_refresh_rotates_tokens(self, client, db, active_user):
        """A valid refresh token returns a NEW access + refresh token pair."""
        from app.services.auth_service import issue_tokens

        tokens = issue_tokens(active_user, db, device_id="refresh-test-device")
        db.commit()

        response = client.post(
            "/api/v1/shopkeeper/auth/refresh",
            json={
                "refresh_token": tokens["refresh_token"],
                "device_id": "refresh-test-device",
            },
        )

        assert response.status_code == 200, response.text
        data = response.json()["data"]
        assert data["access_token"]
        assert data["token_type"] == "bearer"
        # Rotation: the refresh token must never be replayed verbatim.
        assert data["refresh_token"] != tokens["refresh_token"]

    def test_refresh_rejects_unknown_token(self, client):
        """An unknown refresh token is refused with 401 — never a 500 crash."""
        response = client.post(
            "/api/v1/shopkeeper/auth/refresh",
            json={"refresh_token": "not-a-real-refresh-token"},
        )

        assert response.status_code == 401, response.text
        body = response.json()
        assert body["success"] is False


# ── Logout Revocation Tests ───────────────────────────────────────────────────
class TestLogoutRevokesSession:
    """Regression guard: logout must end the session the token came from.

    The route ignored the bearer token's ``session_id`` claim, so a request
    without an explicit ``session_id`` revoked nothing and the token kept
    working until it expired.
    """

    def test_logout_without_body_revokes_token_session(self, client, active_user):
        from unittest.mock import patch

        from app.services.firebase_verification import FirebaseVerificationError

        login = client.post(
            "/api/v1/shopkeeper/auth/login",
            json={"identifier": "test@shopkeeper.com", "password": "Password123"},
        )
        assert login.status_code == 200, login.text
        access = login.json()["data"]["access_token"]

        headers = {"Authorization": f"Bearer {access}"}

        # Legacy JWT path: Firebase verification is mocked to refuse (as it does
        # for a non-Firebase token), so the JWT session check is exercised.
        with patch(
            "app.core.dependencies.verify_firebase_id_token",
            side_effect=FirebaseVerificationError("not a firebase token"),
        ):
            # Token works before logout.
            before = client.get("/api/v1/shopkeeper/auth/me", headers=headers)
            assert before.status_code == 200, before.text

            logout = client.post(
                "/api/v1/shopkeeper/auth/logout", json={}, headers=headers
            )
            assert logout.status_code == 200, logout.text
            assert logout.json()["data"]["revoked"] == 1

            # …and is refused afterwards.
            after = client.get("/api/v1/shopkeeper/auth/me", headers=headers)
            assert after.status_code == 401, after.text

# ── Logout / Revocation Tests ─────────────────────────────────────────────────
class TestLogoutRevocation:
    """Logout must really revoke the session the bearer token belongs to.

    The app posts no ``session_id``; the route must fall back to the token's own
    ``session_id`` claim, otherwise the session stayed valid until expiry.
    """

    @staticmethod
    def _legacy_jwt_only():
        """Simulate the production Firebase fall-through for custom JWTs.

        With credentials configured, a custom access token makes
        ``verify_firebase_id_token`` raise ``FirebaseVerificationError`` and
        ``get_current_user`` proceeds to legacy JWT validation. Without
        credentials (test/CI) it raises ``RuntimeError`` instead, which would
        mask the behaviour under test.
        """
        from unittest.mock import patch

        from app.services.firebase_verification import FirebaseVerificationError

        return patch(
            "app.core.dependencies.verify_firebase_id_token",
            side_effect=FirebaseVerificationError("not a Firebase token"),
        )

    def test_logout_revokes_token_session(self, client, db, active_user):
        from app.models.session import AuthSession
        from app.services.auth_service import issue_tokens

        tokens = issue_tokens(active_user, db, device_id="logout-test-device")
        db.commit()
        session = (
            db.query(AuthSession)
            .filter(AuthSession.session_id == tokens["session_id"])
            .first()
        )
        assert session is not None and session.is_active is True

        with self._legacy_jwt_only():
            response = client.post(
                "/api/v1/shopkeeper/auth/logout",
                json={},
                headers={"Authorization": f"Bearer {tokens['access_token']}"},
            )

        assert response.status_code == 200, response.text
        db.expire_all()
        revoked = (
            db.query(AuthSession)
            .filter(AuthSession.session_id == tokens["session_id"])
            .first()
        )
        assert revoked.is_active is False
        assert revoked.is_revoked is True

    def test_revoked_token_is_rejected(self, client, db, active_user):
        """After logout the same access token must not authenticate again."""
        from app.services.auth_service import issue_tokens

        tokens = issue_tokens(active_user, db, device_id="logout-reuse-device")
        db.commit()
        headers = {"Authorization": f"Bearer {tokens['access_token']}"}

        with self._legacy_jwt_only():
            assert (
                client.get("/api/v1/shopkeeper/auth/me", headers=headers).status_code
                == 200
            )
            client.post("/api/v1/shopkeeper/auth/logout", json={}, headers=headers)
            after = client.get("/api/v1/shopkeeper/auth/me", headers=headers)

        assert after.status_code == 401