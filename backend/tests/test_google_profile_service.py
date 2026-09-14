"""Tests for the minimal Google profile boundary (Phase 19)."""

import pytest

from app.services.google_profile_service import (
    MINIMAL_OAUTH_SCOPES,
    extract_minimal_profile,
)


class TestMinimalGoogleProfile:
    def test_extracts_only_whitelisted_fields(self):
        claims = {
            "sub": "abc123",
            "name": "Home",
            "email": "home91334@gmail.com",
            "picture": "https://lh3.example/pic.jpg",
            "email_verified": True,
            # Non-critical extra claims are allowed to pass through the parse
            # (Firebase always adds iss/aud/exp/iat/auth_time etc.) — the
            # extractor simply ignores them.
            "iss": "https://securetoken.google.com/example",
            "aud": "example-app",
            "exp": 9999999999,
            "firebase": {"sign_in_provider": "google.com"},
        }
        p = extract_minimal_profile(claims)
        assert p.uid == "abc123"
        assert p.name == "Home"
        assert p.email == "home91334@gmail.com"
        assert p.picture == "https://lh3.example/pic.jpg"
        assert p.email_verified is True

        d = p.to_dict()
        # Only app-facing minimal fields, never uid / firebase internal keys.
        assert set(d.keys()) == {"name", "email", "picture", "email_verified"}
        assert "sub" not in d
        assert "iss" not in d

    def test_rejects_forbidden_credential_claims(self):
        claims = {"sub": "abc", "access_token": "not-a-secret-we-keep"}
        with pytest.raises(ValueError, match="Forbidden Google claim key"):
            extract_minimal_profile(claims)

    def test_rejects_refresh_token_claim(self):
        claims = {"sub": "abc", "refresh_token": "super-secret"}
        with pytest.raises(ValueError, match="Forbidden Google claim key"):
            extract_minimal_profile(claims)

    def test_missing_fields_become_none(self):
        p = extract_minimal_profile({"sub": "only-uid"})
        assert p.name is None
        assert p.email is None
        assert p.picture is None
        d = p.to_dict()
        assert d["name"] is None

    def test_minimal_oauth_scopes(self):
        # Exactly the default Google openid/email/profile scopes — nothing more.
        assert MINIMAL_OAUTH_SCOPES == ("openid", "email", "profile")
        assert len(MINIMAL_OAUTH_SCOPES) == 3