"""Background-dispatch contract tests.

Pins the completed email/SMS dispatch tasks and the push test-delivery task to
their contracts, plus the auth fallback that must survive a Firebase outage:

  * ``dispatch_email`` / ``dispatch_sms`` render the template context and
    delegate to the configured (mock by default) provider, reporting
    ``sent`` / ``failed`` — never raising.
  * ``send_test_notification`` pushes to every active device token, deactivates
    permanently-invalid ones, and reports "no_active_devices" instead of
    failing for a user who never registered a device.
  * ``get_current_user`` falls back to the legacy JWT path when Firebase Admin
    is unavailable — a provider outage must not turn every request into a 500.
"""

import os
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402
from fastapi.security import HTTPAuthorizationCredentials  # noqa: E402

import app.core.dependencies as dependencies  # noqa: E402
import app.database.session as db_session  # noqa: E402
import app.services.push_service as push_service  # noqa: E402
from app.core.exceptions import ServiceUnavailableError  # noqa: E402
from app.core.security import create_access_token  # noqa: E402
from app.services.push_service import PushResult  # noqa: E402
from app.services.tasks import (  # noqa: E402
    _render_sms_text,
    _render_template,
    dispatch_email,
    dispatch_sms,
)


# ── Template rendering ───────────────────────────────────────────────────────
class TestTemplateRendering:
    def test_context_flattens_into_html_and_plain_bodies(self):
        html_body, plain = _render_template("welcome_email", {"code": "1234", "shop": "Amul"})
        assert "Welcome Email" in html_body
        assert "code" in html_body and "1234" in html_body
        assert "code: 1234" in plain
        assert "shop: Amul" in plain

    def test_html_output_is_escaped(self):
        html_body, _ = _render_template("alert", {"name": "<script>x</script>"})
        assert "<script>" not in html_body
        assert "&lt;script&gt;" in html_body

    def test_sms_body_is_compact_and_capped(self):
        text = _render_sms_text("otp_sms", {"code": "999999"})
        assert "Otp Sms" in text and "code: 999999" in text
        long_text = _render_sms_text("otp_sms", {f"k{i}": "v" * 20 for i in range(50)})
        assert len(long_text) <= 320

    def test_empty_context_still_renders(self):
        html_body, plain = _render_template("ping", None)
        assert "Ping" in html_body
        assert plain == ""


# ── Celery dispatch tasks (mock providers) ───────────────────────────────────
class TestDispatchTasks:
    def test_dispatch_email_sends_via_the_configured_provider(self):
        outcome = dispatch_email.apply(
            args=("shop@example.com", "Welcome", "welcome_email", {"code": "1234"})
        ).get()
        assert outcome["status"] == "sent"
        assert outcome["to_email"] == "shop@example.com"
        assert outcome["template"] == "welcome_email"

    def test_dispatch_sms_sends_via_the_configured_provider(self):
        outcome = dispatch_sms.apply(
            args=("+919999999999", "otp_sms", {"code": "424242"})
        ).get()
        assert outcome["status"] == "sent"
        assert outcome["phone_number"] == "+919999999999"

    def test_task_names_are_stable_for_external_callers(self):
        assert dispatch_email.name == "app.services.tasks.dispatch_email"
        assert dispatch_sms.name == "app.services.tasks.dispatch_sms"
# ── Test-push delivery ───────────────────────────────────────────────────────
class _FakeQuery:
    def __init__(self, rows):
        self._rows = rows

    def filter(self, *args, **kwargs):
        return self

    def all(self):
        return self._rows

    def first(self):
        return self._rows[0] if self._rows else None


class _FakeSession:
    def __init__(self, rows):
        self._rows = rows
        self.committed = False

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False

    def query(self, model):
        return _FakeQuery(self._rows)

    def commit(self):
        self.committed = True


class _FakeDevice:
    def __init__(self, token, failure_count=0):
        self.token = token
        self.is_active = True
        self.failure_count = failure_count


class _RecordingPushProvider:
    def __init__(self, delivered=True, permanent=False):
        self.sent = []
        self._delivered = delivered
        self._permanent = permanent

    def send(self, message):
        self.sent.append(message)
        return PushResult(
            delivered=self._delivered,
            provider_message_id="fake-1",
            permanent_failure=self._permanent,
        )


class TestSendTestNotification:
    def test_pushes_to_every_active_device(self, monkeypatch):
        import app.core.tasks as core_tasks

        devices = [_FakeDevice("token-1"), _FakeDevice("token-2")]
        monkeypatch.setattr(db_session, "SessionLocal", lambda: _FakeSession(devices))
        provider = _RecordingPushProvider()
        monkeypatch.setattr(push_service, "get_push_service", lambda: provider)

        outcome = core_tasks.send_test_notification.run(7, "hello shopkeeper")

        assert outcome["delivered"] is True
        assert outcome["sent"] == 2 and outcome["total"] == 2
        assert [m.token for m in provider.sent] == ["token-1", "token-2"]
        assert all(device.is_active for device in devices)

    def test_reports_a_user_without_registered_devices(self, monkeypatch):
        import app.core.tasks as core_tasks

        monkeypatch.setattr(db_session, "SessionLocal", lambda: _FakeSession([]))
        monkeypatch.setattr(push_service, "get_push_service", lambda: None)

        outcome = core_tasks.send_test_notification.run(7, "hello")
        assert outcome == {
            "user_id": 7,
            "delivered": False,
            "reason": "no_active_devices",
        }

    def test_permanent_failures_deactivate_the_token(self, monkeypatch):
        import app.core.tasks as core_tasks

        devices = [_FakeDevice("dead-token")]
        monkeypatch.setattr(db_session, "SessionLocal", lambda: _FakeSession(devices))
        monkeypatch.setattr(
            push_service,
            "get_push_service",
            lambda: _RecordingPushProvider(delivered=False, permanent=True),
        )

        outcome = core_tasks.send_test_notification.run(7, "hello")

        assert outcome["delivered"] is False
        assert devices[0].is_active is False
        assert devices[0].failure_count == 1


# ── Auth fallback must survive a Firebase outage ─────────────────────────────
class _FakeUser:
    def __init__(self, user_id=7):
        self.id = user_id
        self.is_active = True

        class _Status:
            value = "ACTIVE"

        self.status = _Status()


class TestLegacyJwtFallback:
    def _credentials(self):
        token, _ = create_access_token(subject="7")
        return HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)

    def test_firebase_outage_falls_back_to_the_legacy_jwt(self, monkeypatch):
        def _unavailable(token):
            raise RuntimeError("Firebase credentials not configured.")

        monkeypatch.setattr(dependencies, "verify_firebase_id_token", _unavailable)
        monkeypatch.setattr(dependencies, "is_token_blacklisted", lambda db, jti: False)
        monkeypatch.setattr(dependencies, "get_token_claims", lambda token: {})
        monkeypatch.setattr(
            dependencies,
            "get_user_by_firebase_uid",
            lambda db, uid: pytest.fail("firebase path must not be used"),
        )

        class _AlwaysUserQuery:
            def filter(self, *args, **kwargs):
                return self

            def first(self):
                return _FakeUser(7)

        class _FakeDb:
            def query(self, model):
                return _AlwaysUserQuery()

        user = dependencies.get_current_user(self._credentials(), _FakeDb())
        assert user.id == 7

    def test_firebase_only_dependency_surfaces_503_when_unavailable(self, monkeypatch):
        def _unavailable(token):
            raise RuntimeError("Firebase credentials not configured.")

        monkeypatch.setattr(dependencies, "verify_firebase_id_token", _unavailable)

        with pytest.raises(ServiceUnavailableError):
            dependencies.get_current_user_firebase(self._credentials(), db=None)

    def test_malformed_json_credentials_surface_as_503_too(self, monkeypatch):
        def _bad_config(token):
            raise ValueError("Expecting value: line 1 column 1 (char 0)")

        monkeypatch.setattr(dependencies, "verify_firebase_id_token", _bad_config)

        with pytest.raises(ServiceUnavailableError):
            dependencies.get_current_user_firebase(self._credentials(), db=None)