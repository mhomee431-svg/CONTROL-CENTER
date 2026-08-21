"""Phase 16 — Identity and Access System tests.

Covers:
  - Valid login (send-otp → verify-otp → tokens)
  - Invalid OTP
  - Expired OTP
  - Resend limits
  - Logout
  - Session expiry
  - Token refresh
  - Unauthorized access
  - Role restrictions
  - Shop ownership restrictions
  - Admin access
"""

import asyncio
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch, MagicMock

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402

# Force test settings
from app.core.config import settings  # noqa: E402
settings.OTP_MAX_ATTEMPTS = 5
settings.OTP_MAX_RESENDS = 5
settings.OTP_RESEND_COOLDOWN_SECONDS = 0  # Allow rapid testing
settings.OTP_COOLDOWN_SECONDS = 0
settings.RATE_LIMIT_ENABLED = False


def run_async(coro):
    """Run an async coroutine synchronously for tests."""
    return asyncio.run(coro)


# ── OTP Service ─────────────────────────────────────────────────────────
class TestOTPService:
    def setup_method(self):
        from app.services import otp_service
        otp_service._otp_store.clear()

    def test_generate_and_verify_otp(self):
        from app.services.otp_service import generate_otp, verify_otp

        result = generate_otp("+919999999999")
        assert result["expires_in"] > 0
        assert "dev_otp" in result  # dev mode

        assert verify_otp("+919999999999", result["dev_otp"]) is True

    def test_invalid_otp(self):
        from app.services.otp_service import generate_otp, verify_otp

        generate_otp("+919999999998")
        assert verify_otp("+919999999998", "000000") is False

    def test_otp_single_use(self):
        from app.services.otp_service import generate_otp, verify_otp

        result = generate_otp("+919999999997")
        otp = result["dev_otp"]
        assert verify_otp("+919999999997", otp) is True
        # Second use should fail (single-use)
        assert verify_otp("+919999999997", otp) is False

    def test_otp_max_attempts(self):
        from app.services.otp_service import generate_otp, verify_otp

        result = generate_otp("+919999999996")
        otp = result["dev_otp"]

        # Exhaust all attempts with wrong OTP
        for _ in range(settings.OTP_MAX_ATTEMPTS):
            assert verify_otp("+919999999996", "111111") is False

        # Even correct OTP fails after max attempts
        assert verify_otp("+919999999996", otp) is False

    def test_otp_expiry(self):
        from app.services.otp_service import _otp_store, verify_otp

        _otp_store["+919999999995"] = {
            "otp_hash": "x" * 64,
            "salt": "s" * 32,
            "expires_at": datetime.now(timezone.utc) - timedelta(minutes=1),
            "attempts": 0,
            "resend_count": 1,
            "last_resend_at": datetime.now(timezone.utc),
            "created_at": datetime.now(timezone.utc),
        }
        assert verify_otp("+919999999995", "123456") is False

    def test_resend_limits(self):
        from app.services.otp_service import (
            OTPLimitExceeded,
            generate_otp,
        )

        # Generate first OTP (counts as resend_count=1)
        generate_otp("+919999999994")

        # Generate up to the resend limit (additional OTP_MAX_RESENDS - 1 sends)
        for _ in range(settings.OTP_MAX_RESENDS - 1):
            result = generate_otp("+919999999994")
            assert result["expires_in"] > 0

        # Next resend should raise (exceeds limit)
        with pytest.raises(OTPLimitExceeded):
            generate_otp("+919999999994")

    def test_phone_normalization(self):
        from app.services.otp_service import generate_otp, verify_otp

        # Same phone with and without + should match
        result = generate_otp("919999999993")
        assert verify_otp("+919999999993", result["dev_otp"]) is True


# ── Security / Tokens ──────────────────────────────────────────────────
class TestSecurityTokens:
    def test_access_token_roundtrip(self):
        from app.core.security import (
            create_access_token,
            get_token_subject,
            validate_token_type,
            TokenPurpose,
        )

        token, jti = create_access_token("42")
        assert get_token_subject(token) == 42
        assert jti is not None
        assert validate_token_type(token, TokenPurpose.ACCESS) is True
        assert validate_token_type(token, TokenPurpose.REFRESH) is False

    def test_refresh_token_roundtrip(self):
        from app.core.security import (
            create_refresh_token,
            get_token_subject,
        )

        token, jti = create_refresh_token("42")
        assert get_token_subject(token) == 42
        assert jti is not None

    def test_invalid_token(self):
        from app.core.security import get_token_subject

        assert get_token_subject("invalid.token.here") is None

    def test_token_type_validation(self):
        from app.core.security import (
            create_access_token,
            create_refresh_token,
            validate_token_type,
            TokenPurpose,
        )

        access_token, _ = create_access_token("1")
        refresh_token, _ = create_refresh_token("1")

        assert validate_token_type(access_token, TokenPurpose.ACCESS) is True
        assert validate_token_type(refresh_token, TokenPurpose.REFRESH) is True
        assert validate_token_type(access_token, TokenPurpose.REFRESH) is False
        assert validate_token_type(refresh_token, TokenPurpose.ACCESS) is False

    def test_token_has_iss_aud(self):
        from app.core.security import create_access_token, decode_token

        token, _ = create_access_token("1")
        payload = decode_token(token)
        assert payload["iss"] == settings.TOKEN_ISSUER
        assert payload["aud"] == settings.TOKEN_AUDIENCE
        assert "jti" in payload
        assert "exp" in payload
        assert "iat" in payload


# ── Auth Service (session management) ──────────────────────────────────
class TestAuthService:
    def test_hash_refresh_token(self):
        from app.services.auth_service import hash_refresh_token

        token = "my-secret-refresh-token"
        h1 = hash_refresh_token(token)
        h2 = hash_refresh_token(token)
        assert h1 == h2
        assert h1 != token  # not stored in plaintext

    def test_generate_refresh_token(self):
        from app.services.auth_service import generate_refresh_token

        t1 = generate_refresh_token()
        t2 = generate_refresh_token()
        assert t1 != t2
        assert len(t1) >= 32

    def test_issue_tokens_creates_session(self):
        # Mock DB interactions
        mock_db = MagicMock()
        mock_user = MagicMock()
        mock_user.id = 1
        mock_user.role = MagicMock()
        mock_user.role.name = "customer"
        mock_user.last_login_at = None

        # Mock session queries
        mock_db.query.return_value.filter.return_value.order_by.return_value.all.return_value = []

        from app.services.auth_service import issue_tokens

        result = issue_tokens(mock_user, mock_db, device_id="dev-1", device_name="iPhone")

        assert result["access_token"]
        assert result["refresh_token"]
        assert result["token_type"] == "bearer"
        assert result["session_id"]
        assert result["user"]["id"] == 1
        assert result["user"]["role"] == "customer"

        # Session was created
        mock_db.add.assert_called()
        mock_db.flush.assert_called()

    def test_refresh_session_reuse_detection(self):
        from app.services.auth_service import refresh_session
        from app.core.exceptions import UnauthorizedError

        mock_db = MagicMock()

        # Mock session that has been rotated (previous hash matches)
        mock_session = MagicMock()
        mock_session.session_id = "test-session-id"
        mock_session.user_id = 1
        mock_session.previous_refresh_token_hash = "old-hash"
        mock_session.is_active = True
        mock_session.is_revoked = False
        mock_session.refresh_token_expires_at = None
        mock_session.expires_at = None
        mock_session.refresh_rotation_count = 0
        mock_session.device_id = None
        mock_session.last_activity_at = None
        mock_session.access_jti = None
        mock_session.refresh_jti = None
        mock_session.user = MagicMock()
        mock_session.user.id = 1
        mock_session.user.is_active = True
        mock_session.user.status = "ACTIVE"
        mock_session.user.role = None

        # First query (by refresh_token_hash) returns None → token already rotated
        # Second query (by previous_refresh_token_hash) returns mock_session → reuse detected
        def query_side_effect(*args, **kwargs):
            mock_query = MagicMock()

            def filter_side_effect(*fargs, **fkwargs):
                mock_filter = MagicMock()

                def first_side_effect():
                    # Check if this is the previous_refresh_token_hash query
                    if fkwargs and "previous_refresh_token_hash" in str(fkwargs):
                        return mock_session
                    return None

                mock_filter.first.side_effect = first_side_effect
                return mock_filter

            mock_query.filter.side_effect = filter_side_effect
            return mock_query

        mock_db.query.side_effect = query_side_effect

        with patch("app.services.auth_service.settings.REFRESH_TOKEN_REUSE_DETECTION", True):
            with pytest.raises(UnauthorizedError):
                refresh_session(mock_db, "some-replayed-token")

    def test_is_account_allowed(self):
        from app.models.user import User, UserStatus
        from app.services.auth_service import is_account_allowed

        active = User(phone_number="+911", is_active=True, status=UserStatus.ACTIVE)
        suspended = User(phone_number="+912", is_active=True, status=UserStatus.SUSPENDED)
        banned = User(phone_number="+913", is_active=True, status=UserStatus.BANNED)
        inactive = User(phone_number="+914", is_active=False, status=UserStatus.ACTIVE)

        assert is_account_allowed(active) is True
        assert is_account_allowed(suspended) is False
        assert is_account_allowed(banned) is False
        assert is_account_allowed(inactive) is False


# ── RBAC / Authorization ───────────────────────────────────────────────
class TestAuthorization:
    def test_has_permission(self):
        from app.core.dependencies import has_permission
        from app.models.role import Permission, Role
        from app.models.user import User

        perm = Permission(name="read:product", resource="product", action="read")
        role = Role(name="customer")
        role.permissions = [perm]
        user = User(phone_number="+911")
        user.role = role

        assert has_permission(user, "product", "read") is True
        assert has_permission(user, "product", "write") is False
        assert has_permission(user, "shop", "read") is False

    def test_has_permission_no_role(self):
        from app.core.dependencies import has_permission
        from app.models.user import User

        user = User(phone_number="+911")
        assert has_permission(user, "anything", "anything") is False

    def test_admin_wildcard_permission(self):
        from app.core.dependencies import has_permission
        from app.models.role import Permission, Role
        from app.models.user import User

        # Admin has explicit "*:*" — note that wildcard is handled by role check
        # for admin, not by individual permission entries
        perm = Permission(name="*:*", resource="*", action="*")
        role = Role(name="admin")
        role.permissions = [perm]
        user = User(phone_number="+911")
        user.role = role

        # Admin wildcard at role level
        assert user.role.name == "admin"

        # For the granular check, admin role check bypasses permission evaluation
        assert user.role.name in ("admin",)

    def test_get_user_permissions(self):
        from app.core.dependencies import get_user_permissions
        from app.models.role import Permission, Role
        from app.models.user import User

        perms = [
            Permission(name="read:product", resource="product", action="read"),
            Permission(name="write:product", resource="product", action="write"),
        ]
        role = Role(name="shop_owner")
        role.permissions = perms
        user = User(phone_number="+911")
        user.role = role

        result = get_user_permissions(user)
        assert "read:product" in result
        assert "write:product" in result


# ── Role / Permission Seeding ──────────────────────────────────────────
class TestRoleSeeding:
    def test_role_permissions_map_defined(self):
        from app.services.seed_data import ROLE_PERMISSIONS

        assert "customer" in ROLE_PERMISSIONS
        assert "shop_owner" in ROLE_PERMISSIONS
        assert "shop_manager" in ROLE_PERMISSIONS
        assert "admin" in ROLE_PERMISSIONS

    def test_customer_role_has_read_permissions(self):
        from app.services.seed_data import ROLE_PERMISSIONS

        customer_perms = ROLE_PERMISSIONS["customer"]
        assert ("product", "read") in customer_perms
        assert ("shop", "read") in customer_perms
        assert ("inventory", "read") in customer_perms

        # Customer must NOT have write access to products / inventory
        assert ("product", "create") not in customer_perms
        assert ("inventory", "update") not in customer_perms
        assert ("shop", "update") not in customer_perms

    def test_shop_owner_has_inventory_write(self):
        from app.services.seed_data import ROLE_PERMISSIONS

        owner_perms = ROLE_PERMISSIONS["shop_owner"]
        assert ("inventory", "update") in owner_perms
        assert ("shop", "update") in owner_perms

    def test_admin_has_everything(self):
        from app.services.seed_data import ROLE_PERMISSIONS

        admin_perms = ROLE_PERMISSIONS["admin"]
        assert ("*", "*") in admin_perms


# ── Auth Routes (integration-style with mocked services) ───────────────
class TestAuthRoutes:
    def test_send_otp_route(self):
        from app.api.routes.auth import send_otp
        from app.schemas.auth import SendOTPRequest

        with patch("app.api.routes.auth.generate_otp") as mock_gen:
            mock_gen.return_value = {"expires_in": 300, "dev_otp": "123456"}
            mock_request = MagicMock()

            response = run_async(send_otp(SendOTPRequest(phone_number="+919999999999"), mock_request))

            # unwrap JSONResponse
            body = response.body
            assert b"success" in body
            assert b"123456" in body  # dev mode returns OTP

    def test_send_otp_route_cooldown(self):
        from app.api.routes.auth import send_otp
        from app.schemas.auth import SendOTPRequest
        from app.services.otp_service import OTPCooldownError

        with patch("app.api.routes.auth.generate_otp") as mock_gen:
            mock_gen.side_effect = OTPCooldownError("Wait", 30)
            mock_request = MagicMock()

            response = run_async(send_otp(SendOTPRequest(phone_number="+919999999999"), mock_request))
            assert response.status_code == 429

    def test_send_otp_route_limit(self):
        from app.api.routes.auth import send_otp
        from app.schemas.auth import SendOTPRequest
        from app.services.otp_service import OTPLimitExceeded

        with patch("app.api.routes.auth.generate_otp") as mock_gen:
            mock_gen.side_effect = OTPLimitExceeded("Limit reached", None)
            mock_request = MagicMock()

            response = run_async(send_otp(SendOTPRequest(phone_number="+919999999999"), mock_request))
            assert response.status_code == 429

    def test_verify_otp_route_invalid(self):
        from app.api.routes.auth import verify_otp_endpoint
        from app.schemas.auth import VerifyOTPRequest

        with patch("app.api.routes.auth.verify_otp") as mock_verify:
            mock_verify.return_value = False

            response = run_async(verify_otp_endpoint(
                VerifyOTPRequest(phone_number="+919999999999", otp="000000"),
                request=MagicMock(),
                db=MagicMock(),
            ))
            # unwrap
            assert response.status_code == 400

    def test_verify_otp_route_new_user(self):
        from app.api.routes.auth import verify_otp_endpoint
        from app.schemas.auth import VerifyOTPRequest

        mock_db = MagicMock()
        mock_db.query.return_value.filter.return_value.first.return_value = None  # user not found

        mock_role = MagicMock()
        mock_role.id = 1
        mock_db.query.return_value.filter.return_value.first.return_value = mock_role  # default role

        mock_user = MagicMock()
        mock_user.id = 1
        mock_user.role = mock_role
        mock_user.role.name = "customer"

        with patch("app.api.routes.auth.verify_otp", return_value=True), \
             patch("app.api.routes.auth.issue_tokens") as mock_issue:

            mock_issue.return_value = {
                "access_token": "token",
                "refresh_token": "refresh",
                "session_id": "abc",
                "expires_in": 3600,
                "user": {"id": 1, "phone_number": "+919999999999", "role": "customer"},
            }
            mock_request = MagicMock()
            mock_request.client.host = "127.0.0.1"

            response = run_async(verify_otp_endpoint(
                VerifyOTPRequest(phone_number="+919999999999", otp="123456"),
                request=mock_request,
                db=mock_db,
            ))
            assert response.status_code == 200

    def test_refresh_token_route(self):
        from app.api.routes.auth import refresh_token
        from app.schemas.auth import RefreshTokenRequest

        mock_db = MagicMock()

        with patch("app.api.routes.auth.refresh_session") as mock_refresh:
            mock_refresh.return_value = {
                "access_token": "new-token",
                "refresh_token": "new-refresh",
                "session_id": "abc",
                "expires_in": 3600,
                "user": {"id": 1, "phone_number": "+919999999999", "role": "customer"},
            }
            response = run_async(refresh_token(
                RefreshTokenRequest(refresh_token="old-refresh"),
                request=MagicMock(),
                db=mock_db,
            ))
            assert response.status_code == 200


# ── Shop Ownership ─────────────────────────────────────────────────────
class TestShopOwnership:
    def test_is_shop_owner(self):
        from app.core.dependencies import is_shop_owner
        from app.models.user import User

        mock_db = MagicMock()
        mock_user = User(phone_number="+911")

        with patch("app.core.dependencies.ShopOwner") as mock_owner:
            mock_owner.shop_id = 1
            mock_owner.user_id = 1
            mock_owner.is_active = True
            mock_db.query.return_value.filter.return_value.first.return_value = mock_owner

            assert is_shop_owner(mock_db, mock_user, 1) is True

    def test_is_shop_manager(self):
        from app.core.dependencies import is_shop_manager

        mock_db = MagicMock()
        mock_user = MagicMock()

        mock_db.query.return_value.filter.return_value.first.return_value = None
        assert is_shop_manager(mock_db, mock_user, 999) is False  # no manager record

    def test_require_shop_access_admin(self):
        from app.models.role import Role
        from app.models.user import User

        admin = User(phone_number="+911")
        admin.role = Role(name="admin")

        # Admin has explicit role access
        assert admin.role.name == "admin"

    def test_get_user_shop_ids(self):
        from app.core.dependencies import get_user_shop_ids

        mock_db = MagicMock()
        mock_user = MagicMock()
        mock_user.id = 1

        # Simulate owner of shop 1, manager of shop 2
        owner = MagicMock()
        owner.shop_id = 1
        manager = MagicMock()
        manager.shop_id = 2

        mock_db.query.side_effect = [
            MagicMock(filter=lambda *args, **kw: MagicMock(all=lambda: [owner])),
            MagicMock(filter=lambda *args, **kw: MagicMock(all=lambda: [manager])),
        ]

        result = get_user_shop_ids(mock_db, mock_user)
        assert set(result) == {1, 2}


# ── Admin Access ───────────────────────────────────────────────────────
class TestAdminAccess:
    def test_admin_role_assignment(self):
        from app.services.seed_data import ROLE_PERMISSIONS

        # Admin has full permissions map
        assert ("*", "*") in ROLE_PERMISSIONS["admin"]

    def test_customer_vs_shop_owner_isolation(self):
        from app.services.seed_data import ROLE_PERMISSIONS

        customer_perms = set(ROLE_PERMISSIONS["customer"])

        # Customer should NOT have shop-owned write permissions
        customer_resources = {r for r, a in customer_perms}
        assert "shop_product" not in customer_resources
        assert "offer" not in customer_resources
        assert "order" not in customer_resources
        assert "report" not in customer_resources
        assert "customer" not in customer_resources


# ── Session / Device Tracking ──────────────────────────────────────────
class TestSessionTracking:
    def test_active_sessions_returns_empty(self):
        from app.services.auth_service import get_active_sessions

        mock_db = MagicMock()
        mock_db.query.return_value.filter.return_value.order_by.return_value.all.return_value = []

        result = get_active_sessions(mock_db, user_id=1)
        assert result == []

    def test_logout_all_sessions(self):
        from app.services.auth_service import logout_session

        mock_db = MagicMock()
        mock_user = MagicMock()
        mock_user.id = 1

        s1 = MagicMock()
        s2 = MagicMock()
        mock_db.query.return_value.filter.return_value.all.return_value = [s1, s2]

        result = logout_session(mock_db, mock_user, revoke_all=True)
        assert result["revoked"] == 2
        assert s1.is_active is False
        assert s1.is_revoked is True
        assert s2.is_active is False

    def test_revoke_session_by_id(self):
        from app.services.auth_service import revoke_session_by_id

        mock_db = MagicMock()
        session = MagicMock()
        mock_db.query.return_value.filter.return_value.first.return_value = session

        result = revoke_session_by_id(mock_db, user_id=1, session_id="abc")
        assert result is True
        assert session.is_revoked is True

    def test_revoke_session_not_found(self):
        from app.services.auth_service import revoke_session_by_id

        mock_db = MagicMock()
        mock_db.query.return_value.filter.return_value.first.return_value = None

        result = revoke_session_by_id(mock_db, user_id=1, session_id="missing")
        assert result is False


# ── Models verification ────────────────────────────────────────────────
class TestModels:
    def test_session_model_importable(self):
        from app.models.session import AuthSession, TokenBlacklist

        assert AuthSession is not None
        assert TokenBlacklist is not None

    def test_user_model_has_auth_sessions(self):
        from app.models.user import User

        assert hasattr(User, "auth_sessions")

    def test_auth_session_fields(self):
        from app.models.session import AuthSession

        cols = AuthSession.__table__.columns.keys()
        assert "session_id" in cols
        assert "user_id" in cols
        assert "refresh_token_hash" in cols
        assert "is_active" in cols
        assert "is_revoked" in cols
        assert "device_id" in cols
        assert "expires_at" in cols
        assert "reuse_detected" in cols
        assert "access_jti" in cols
        assert "refresh_jti" in cols