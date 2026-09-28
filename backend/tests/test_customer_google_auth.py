"""Customer App Google Sign-In route tests.

These tests exercise ``POST /auth/google-login`` at the route-function level
with a mocked Firebase verifier, matching the pattern used by
``test_identity_access.py`` so no Firebase credentials or PostgreSQL instance
are required.

Security invariants asserted here:
  - Only ``google.com`` provider tokens are accepted.
  - Unverified or missing emails are rejected.
  - ``firebase_uid`` is the durable account key and wins on lookup.
  - A verified email links only when exactly one customer owns it.
  - Ambiguous and cross-role email matches are never auto-merged.
"""

import asyncio
from unittest.mock import MagicMock, patch

from app.core.config import settings

settings.RATE_LIMIT_ENABLED = False

from app.api.routes import auth as auth_routes  # noqa: E402
from app.core.rate_limit import limiter  # noqa: E402
from app.schemas.auth import CustomerGoogleAuthRequest  # noqa: E402

# The shared limiter captures ``enabled`` when ``app.core.rate_limit`` is first
# imported; disable it explicitly so route-level unit tests with MagicMock
# requests never trip slowapi's Request type check.
limiter.enabled = False

TOKEN = "test-google-id-token-000000000000000000000"


def run_async(coro):
    """Run an async coroutine synchronously for tests."""
    return asyncio.run(coro)


def _payload() -> CustomerGoogleAuthRequest:
    return CustomerGoogleAuthRequest(
        firebase_id_token=TOKEN,
        device_id="test-device",
        device_name="pytest",
        device_type="web",
    )


def _claims(**overrides) -> dict:
    claims = {
        "uid": "firebase-google-uid-1",
        "email": "Customer@Example.com",
        "email_verified": True,
        "provider": "google.com",
        "google_id": "google-subject-1",
        "name": "Aarav",
        "picture": "https://example.com/avatar.png",
    }
    claims.update(overrides)
    return claims


def _query(first=None, all_rows=None) -> MagicMock:
    """Build a fake ``db.query(...).filter(...)`` chain."""
    query = MagicMock()
    query.filter.return_value.first.return_value = first
    query.filter.return_value.all.return_value = list(all_rows or [])
    return query


def _issue_mock() -> dict:
    return {
        "access_token": "token",
        "refresh_token": "refresh",
        "session_id": "session",
        "expires_in": 3600,
        "user": {"id": 7, "phone_number": None, "role": "customer"},
    }


def _customer_user(uid=None, google_id=None, role_name="customer") -> MagicMock:
    user = MagicMock()
    user.id = 7
    user.firebase_uid = uid
    user.google_id = google_id
    user.email = None
    user.name = None
    user.avatar_url = None
    user.customer_profile = MagicMock()
    user.role = MagicMock()
    user.role.name = role_name
    return user


class TestCustomerGoogleLoginGuards:
    """Rejections that must happen before any account lookup."""

    def test_non_google_provider_is_rejected(self):
        with patch.object(
            auth_routes,
            "verify_firebase_id_token_claims",
            return_value=_claims(provider="phone"),
        ):
            response = run_async(
                auth_routes.google_login(_payload(), MagicMock(), MagicMock())
            )

        assert response.status_code == 403
        assert b"GOOGLE_PROVIDER_REQUIRED" in response.body

    def test_unverified_email_is_rejected(self):
        with patch.object(
            auth_routes,
            "verify_firebase_id_token_claims",
            return_value=_claims(email_verified=False),
        ):
            response = run_async(
                auth_routes.google_login(_payload(), MagicMock(), MagicMock())
            )

        assert response.status_code == 403
        assert b"GOOGLE_EMAIL_NOT_VERIFIED" in response.body



class TestCustomerGoogleLoginResolution:
    """Identity resolution: UID first, verified email only as a safe link."""

    def test_creates_new_customer_when_no_identity_matches(self):
        db = MagicMock()
        db.query.side_effect = [
            _query(first=None),  # firebase_uid lookup
            _query(first=None),  # google_id lookup
            _query(all_rows=[]),  # verified email lookup
        ]
        new_user = _customer_user(
            uid="firebase-google-uid-1", google_id="google-subject-1"
        )

        with patch.object(
            auth_routes,
            "verify_firebase_id_token_claims",
            return_value=_claims(),
        ), patch.object(
            auth_routes, "_create_customer_account", return_value=new_user
        ) as create, patch.object(
            auth_routes, "issue_tokens", return_value=_issue_mock()
        ):
            response = run_async(auth_routes.google_login(_payload(), MagicMock(), db))

        assert response.status_code == 200
        assert b"is_new_account" in response.body
        assert b"true" in response.body
        create.assert_called_once()
        kwargs = create.call_args.kwargs
        assert kwargs["firebase_uid"] == "firebase-google-uid-1"
        assert kwargs["email"] == "customer@example.com"
        assert kwargs["google_id"] == "google-subject-1"
        assert kwargs["avatar_url"] == "https://example.com/avatar.png"

    def test_existing_firebase_uid_logs_in_without_creating_account(self):
        user = _customer_user(
            uid="firebase-google-uid-1", google_id="google-subject-1"
        )
        db = MagicMock()
        db.query.side_effect = [
            _query(first=user),
            _query(first=user),
            _query(all_rows=[user]),
        ]

        with patch.object(
            auth_routes,
            "verify_firebase_id_token_claims",
            return_value=_claims(),
        ), patch.object(
            auth_routes, "is_account_allowed", return_value=True
        ), patch.object(
            auth_routes, "issue_tokens", return_value=_issue_mock()
        ) as issue:
            response = run_async(auth_routes.google_login(_payload(), MagicMock(), db))

        assert response.status_code == 200
        assert b'"is_new_account":false' in response.body
        issue.assert_called_once()
        assert user.firebase_uid == "firebase-google-uid-1"

    def test_verified_email_links_legacy_phone_customer(self):
        legacy = _customer_user(uid=None, google_id=None)
        legacy.email = "customer@example.com"
        db = MagicMock()
        db.query.side_effect = [
            _query(first=None),
            _query(first=None),
            _query(all_rows=[legacy]),
        ]

        with patch.object(
            auth_routes,
            "verify_firebase_id_token_claims",
            return_value=_claims(),
        ), patch.object(
            auth_routes, "is_account_allowed", return_value=True
        ), patch.object(
            auth_routes, "issue_tokens", return_value=_issue_mock()
        ) as issue:
            response = run_async(auth_routes.google_login(_payload(), MagicMock(), db))

        assert response.status_code == 200
        assert b'"is_new_account":false' in response.body
        assert legacy.firebase_uid == "firebase-google-uid-1"
        assert legacy.google_id == "google-subject-1"
        issue.assert_called_once()

    def test_ambiguous_email_match_is_rejected(self):
        first = _customer_user()
        second = _customer_user()
        second.id = 8
        db = MagicMock()
        db.query.side_effect = [
            _query(first=None),
            _query(first=None),
            _query(all_rows=[first, second]),
        ]

        with patch.object(
            auth_routes,
            "verify_firebase_id_token_claims",
            return_value=_claims(),
        ), patch.object(auth_routes, "issue_tokens") as issue:
            response = run_async(auth_routes.google_login(_payload(), MagicMock(), db))

        assert response.status_code == 409
        assert b"ACCOUNT_LINK_CONFLICT" in response.body
        issue.assert_not_called()

    def test_cross_role_email_match_is_rejected(self):
        shopkeeper = _customer_user(uid=None, google_id=None, role_name="shopkeeper")
        shopkeeper.email = "customer@example.com"
        db = MagicMock()
        db.query.side_effect = [
            _query(first=None),
            _query(first=None),
            _query(all_rows=[shopkeeper]),
        ]

        with patch.object(
            auth_routes,
            "verify_firebase_id_token_claims",
            return_value=_claims(),
        ), patch.object(auth_routes, "issue_tokens") as issue:
            response = run_async(auth_routes.google_login(_payload(), MagicMock(), db))

        assert response.status_code == 403
        assert b"ACCOUNT_ROLE_MISMATCH" in response.body
        assert shopkeeper.firebase_uid is None
        issue.assert_not_called()

    def test_uid_login_with_different_email_owner_is_rejected(self):
        user = _customer_user(
            uid="firebase-google-uid-1", google_id="google-subject-1"
        )
        other = _customer_user()
        other.id = 9
        db = MagicMock()
        db.query.side_effect = [
            _query(first=user),
            _query(first=user),
            _query(all_rows=[other]),
        ]

        with patch.object(
            auth_routes,
            "verify_firebase_id_token_claims",
            return_value=_claims(),
        ), patch.object(auth_routes, "issue_tokens") as issue:
            response = run_async(auth_routes.google_login(_payload(), MagicMock(), db))

        assert response.status_code == 409
        assert b"ACCOUNT_LINK_CONFLICT" in response.body
        issue.assert_not_called()

    def test_missing_email_is_rejected(self):
        with patch.object(
            auth_routes,
            "verify_firebase_id_token_claims",
            return_value=_claims(email="", google_id="", name=""),
        ):
            response = run_async(
                auth_routes.google_login(_payload(), MagicMock(), MagicMock())
            )

        assert response.status_code == 403
        assert b"GOOGLE_EMAIL_REQUIRED" in response.body

    def test_missing_firebase_uid_is_rejected(self):
        with patch.object(
            auth_routes,
            "verify_firebase_id_token_claims",
            return_value=_claims(uid=""),
        ):
            response = run_async(
                auth_routes.google_login(_payload(), MagicMock(), MagicMock())
            )

        assert response.status_code == 403
        assert b"GOOGLE_IDENTITY_MISSING" in response.body
