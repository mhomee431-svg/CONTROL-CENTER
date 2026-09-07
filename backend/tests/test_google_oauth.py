"""Tests for the Google OAuth integration.

Covers the consent URL builder, signed-state CSRF tokens, the token exchange,
real JWKS-based ID token verification (with a locally generated RSA key), and
the two auth routes.
"""
from unittest.mock import MagicMock, patch

import pytest

from app.core.config import settings

# The route is exercised directly (no HTTP layer), so the slowapi decorator
# would reject the call for lacking a starlette Request. Disable the limiter
# instance itself — it captured `enabled` from settings at import time, so
# flipping the setting later has no effect. Mirrors test_admin_moderation_flow.
settings.RATE_LIMIT_ENABLED = False


def _rsa_key_pair():
    """Generate a throwaway RSA key pair as JWK dicts for signing tests."""
    import base64

    from cryptography.hazmat.primitives.asymmetric import rsa

    def _b64n(v: int) -> str:
        raw = v.to_bytes((v.bit_length() + 7) // 8, "big")
        return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()

    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pub = private_key.public_key().public_numbers()
    priv = private_key.private_numbers()
    kid = "test-kid"

    public_jwk = {
        "kty": "RSA",
        "kid": kid,
        "alg": "RS256",  # Google's real JWKS keys include this
        "n": _b64n(pub.n),
        "e": _b64n(pub.e),
    }
    private_jwk = {
        "kty": "RSA",
        "kid": kid,
        "n": _b64n(pub.n),
        "e": _b64n(pub.e),
        "d": _b64n(priv.d),
        "p": _b64n(priv.p),
        "q": _b64n(priv.q),
        "dp": _b64n(priv.dmp1),
        "dq": _b64n(priv.dmq1),
        "qi": _b64n(priv.iqmp),
    }
    return private_jwk, public_jwk


def _sign_id_token(private_jwk, kid, aud, email, email_verified=True):
    import datetime

    from jose import jwt as jose_jwt

    now = datetime.datetime.now(datetime.timezone.utc)
    payload = {
        "iss": "https://accounts.google.com",
        "aud": aud,
        "exp": now + datetime.timedelta(hours=1),
        "iat": now,
        "sub": "google-user-123",
        "email": email,
        "email_verified": email_verified,
        "name": "Test User",
        "picture": "https://example.com/pic.png",
    }
    return jose_jwt.encode(
        payload, private_jwk, algorithm="RS256", headers={"kid": kid, "alg": "RS256"}
    )


# ── URL builder + state tokens ───────────────────────────────────────────────
class TestOAuthState:
    def test_build_authorization_url(self):
        from app.services import google_oauth

        settings.GOOGLE_CLIENT_ID = "client-1"
        url = google_oauth.build_authorization_url("state-abc")
        assert url.startswith(settings.GOOGLE_OAUTH_AUTHORIZE_URL)
        assert "client_id=client-1" in url
        assert "redirect_uri=" in url and "state=state-abc" in url

    def test_state_token_round_trip(self):
        from app.services import google_oauth

        token = google_oauth.create_state_token()
        assert google_oauth.validate_state_token(token) is True

    def test_state_token_rejects_tampering(self):
        from app.services import google_oauth

        token = google_oauth.create_state_token()
        assert google_oauth.validate_state_token(token + "x") is False
        assert google_oauth.validate_state_token("") is False
        assert google_oauth.validate_state_token("garbage") is False


# ── Token exchange ───────────────────────────────────────────────────────────
class TestTokenExchange:
    def test_exchange_posts_form_encoded(self):
        from app.services import google_oauth

        settings.GOOGLE_CLIENT_ID = "client-1"
        settings.GOOGLE_CLIENT_SECRET = "secret-1"
        resp = MagicMock()
        resp.status_code = 200
        resp.json.return_value = {"access_token": "at", "id_token": "it"}
        with patch("httpx.post", return_value=resp) as mock_post:
            tokens = google_oauth.exchange_code_for_tokens("code-1")
        assert tokens["access_token"] == "at"
        call = mock_post.call_args
        assert call.kwargs["data"]["code"] == "code-1"
        assert call.kwargs["data"]["grant_type"] == "authorization_code"
        assert call.kwargs["data"]["client_id"] == "client-1"

    def test_exchange_rejects_http_error(self):
        from app.services import google_oauth

        settings.GOOGLE_CLIENT_ID = "client-1"
        settings.GOOGLE_CLIENT_SECRET = "secret-1"
        resp = MagicMock()
        resp.status_code = 400
        with patch("httpx.post", return_value=resp):
            with pytest.raises(google_oauth.GoogleOAuthError):
                google_oauth.exchange_code_for_tokens("code-bad")

    def test_exchange_missing_credentials(self):
        from app.services import google_oauth

        settings.GOOGLE_CLIENT_ID = ""
        settings.GOOGLE_CLIENT_SECRET = ""
        with pytest.raises(google_oauth.GoogleOAuthError):
            google_oauth.exchange_code_for_tokens("code-x")


# ── ID token verification (real crypto path) ─────────────────────────────────
class TestIdTokenVerification:
    def test_verify_valid_id_token(self):
        from app.services import google_oauth

        settings.GOOGLE_CLIENT_ID = "client-1"
        private_jwk, public_jwk = _rsa_key_pair()
        token = _sign_id_token(private_jwk, public_jwk["kid"], "client-1", "user@example.com")
        with patch.object(google_oauth, "_fetch_jwks", return_value={"keys": [public_jwk]}):
            claims = google_oauth.verify_id_token(token)
        assert claims["email"] == "user@example.com"
        assert claims["sub"] == "google-user-123"

    def test_verify_rejects_wrong_audience(self):
        from app.services import google_oauth

        settings.GOOGLE_CLIENT_ID = "client-1"
        private_jwk, public_jwk = _rsa_key_pair()
        token = _sign_id_token(private_jwk, public_jwk["kid"], "some-other-app", "user@example.com")
        with patch.object(google_oauth, "_fetch_jwks", return_value={"keys": [public_jwk]}):
            with pytest.raises(google_oauth.GoogleOAuthError):
                google_oauth.verify_id_token(token)

    def test_google_user_profile_requires_verified_email(self):
        from app.services import google_oauth

        settings.GOOGLE_CLIENT_ID = "client-1"
        private_jwk, public_jwk = _rsa_key_pair()
        token = _sign_id_token(
            private_jwk, public_jwk["kid"], "client-1", "user@example.com", email_verified=False
        )
        with patch.object(google_oauth, "_fetch_jwks", return_value={"keys": [public_jwk]}):
            with pytest.raises(google_oauth.GoogleOAuthError):
                google_oauth.google_user_profile({"id_token": token})

    def test_google_user_profile_ok(self):
        from app.services import google_oauth

        settings.GOOGLE_CLIENT_ID = "client-1"
        private_jwk, public_jwk = _rsa_key_pair()
        token = _sign_id_token(private_jwk, public_jwk["kid"], "client-1", "user@example.com")
        with patch.object(google_oauth, "_fetch_jwks", return_value={"keys": [public_jwk]}):
            profile = google_oauth.google_user_profile({"id_token": token})
        assert profile["google_id"] == "google-user-123"
        assert profile["email"] == "user@example.com"

    def test_missing_id_token_rejected(self):
        from app.services import google_oauth

        with pytest.raises(google_oauth.GoogleOAuthError):
            google_oauth.google_user_profile({"access_token": "only"})
def run_async(coro):
    import asyncio

    return asyncio.run(coro)


# ── Routes ────────────────────────────────────────────────────────────────────
class TestGoogleAuthRoutes:
    def test_google_login_url_endpoint(self):
        from starlette.requests import Request

        from app.api.routes.google_auth import google_login_url
        from app.core.rate_limit import limiter

        limiter.enabled = False
        # The route is called directly (no FastAPI DI), so hand it a minimal
        # real Request — the rate-limit decorator requires a starlette Request
        # instance and the route signature requires `request`.
        scope = {
            "type": "http",
            "method": "GET",
            "path": "/auth/google/login",
            "headers": [],
            "query_string": b"",
            "client": ("127.0.0.1", 12345),
            "server": ("testserver", 80),
            "scheme": "http",
        }
        response = run_async(google_login_url(Request(scope)))
        assert response.status_code == 200
        body = response.body
        assert b"auth_url" in body
        assert b"accounts.google.com" in body

    def test_callback_rejects_bad_state(self):
        from unittest.mock import MagicMock

        from app.api.routes.google_auth import google_callback

        response = run_async(
            google_callback(
                request=MagicMock(),
                db=MagicMock(),
                code="code-1",
                state="tampered",
            )
        )
        assert response.status_code == 400
        assert b"INVALID_OAUTH_STATE" in response.body

    def test_callback_missing_code(self):
        from unittest.mock import MagicMock

        from app.services import google_oauth

        from app.api.routes.google_auth import google_callback

        state = google_oauth.create_state_token()
        response = run_async(
            google_callback(
                request=MagicMock(),
                db=MagicMock(),
                code="",
                state=state,
            )
        )
        assert response.status_code == 400
        assert b"MISSING_OAUTH_CODE" in response.body

    def test_callback_full_success_new_user(self):
        from unittest.mock import patch

        from app.services import google_oauth

        from app.api.routes.google_auth import google_callback

        state = google_oauth.create_state_token()
        private_jwk, public_jwk = _rsa_key_pair()
        token = _sign_id_token(
            private_jwk, public_jwk["kid"], settings.GOOGLE_CLIENT_ID, "new@example.com"
        )

        db = MagicMock()
        db.query.return_value.filter.return_value.first.return_value = None
        db.flush = MagicMock()
        db.commit = MagicMock()

        mock_token_data = {
            "access_token": "at", "refresh_token": "rt", "token_type": "bearer",
            "expires_in": 3600, "session_id": "sess", "user": {"id": 1, "name": "Test User"},
        }
        with patch.object(google_oauth, "exchange_code_for_tokens") as mock_exchange, \
             patch.object(google_oauth, "verify_id_token") as mock_verify, \
             patch("app.api.routes.google_auth.issue_tokens", return_value=mock_token_data):
            mock_exchange.return_value = {"id_token": token}
            mock_verify.return_value = {
                "sub": "google-user-123", "email": "new@example.com",
                "email_verified": True, "name": "Test User", "picture": None,
            }
            response = run_async(
                google_callback(
                    request=MagicMock(),
                    db=db,
                    code="code-ok",
                    state=state,
                    redirect_to_frontend=0,
                )
            )
        assert response.status_code == 200
        assert b"Google login successful" in response.body
        added = [a for a in db.mock_calls if a[0] == "add"]
        assert added