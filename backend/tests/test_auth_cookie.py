import pytest
from fastapi import Response

from app.api.v1.auth import SESSION_COOKIE, _set_session
from app.core.config import settings


@pytest.mark.parametrize("secure", [False, True])
def test_set_session_sets_expected_cookie_attributes(monkeypatch, secure):
    monkeypatch.setattr(settings, "COOKIE_SECURE", secure)
    response = Response()

    _set_session(response, "test-session-token")

    cookie = response.headers["set-cookie"]
    assert f"{SESSION_COOKIE}=test-session-token" in cookie
    assert "httponly" in cookie.lower()
    assert "samesite=lax" in cookie.lower()
    assert ("secure" in cookie.lower()) is secure
    assert response.headers["cache-control"] == "no-store"
