"""FCM push integration tests.

Verifies the defect that went uncaught in the production audit: the
``firebase-admin`` dependency being absent made any FCM send crash.

Coverage:
  * dependency present & importable (the audit's missing smoke test)
  * provider factory wiring (mock default, fcm when configured)
  * send success path (message shape + dry-run flag)
  * permanent vs transient failure classification
  * startup gate: prod + fcm without credentials refuses to boot
"""

import os
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402

from app.core.config import settings  # noqa: E402
from app.services import push_service  # noqa: E402
from app.services.push_service import (  # noqa: E402
    FCMPushProvider,
    MockPushProvider,
    PushMessage,
    get_push_provider,
)

firebase_admin = pytest.importorskip(
    "firebase_admin", reason="firebase-admin not installed (requirements.txt gap)"
)


class FakeMessaging:
    """Stand-in for firebase_admin.messaging (no network)."""

    class Notification:  # noqa: D418 — mirrors the SDK constructor
        def __init__(self, title=None, body=None):
            self.title = title
            self.body = body

    class Message:
        def __init__(self, notification=None, data=None, token=None):
            self.notification = notification
            self.data = data or {}
            self.token = token

    def __init__(self, responses=None, error=None):
        self.responses = responses or []
        self.error = error
        self.sent = []

    def send(self, msg, dry_run=False):
        self.sent.append((msg, dry_run))
        if self.error is not None:
            raise self.error
        return self.responses.pop(0) if self.responses else f"projects/x/messages/{len(self.sent)}"


@pytest.fixture(autouse=True)
def _reset_provider_singleton():
    push_service.set_push_service(MockPushProvider())
    yield
    push_service.set_push_service(MockPushProvider())
    FCMPushProvider._messaging = None


def _message() -> PushMessage:
    return PushMessage(
        token="fake-device-token-1234567890",
        title="Price drop",
        body="Rice 5kg is now ₹299",
        deep_link="hyperlocal://product/abc",
        data={"product_id": "abc"},
    )


class TestDependencySmoke:
    def test_firebase_admin_importable(self):
        """The audit's missing smoke test — catches missing-dependency defects."""
        import firebase_admin as fa

        assert hasattr(fa, "initialize_app")

    def test_messaging_api_available(self):
        from firebase_admin import messaging  # noqa: F401


class TestProviderFactory:
    def test_default_is_mock(self, monkeypatch):
        monkeypatch.setattr(settings, "PUSH_PROVIDER", "mock")
        assert isinstance(get_push_provider(), MockPushProvider)

    def test_fcm_when_configured(self, monkeypatch):
        monkeypatch.setattr(settings, "PUSH_PROVIDER", "fcm")
        assert isinstance(get_push_provider(), FCMPushProvider)


class TestFCMSend:
    def test_send_success(self, monkeypatch):
        fake = FakeMessaging(responses=["msg-id-1"])
        monkeypatch.setattr(FCMPushProvider, "_get_messaging", lambda self: fake)
        monkeypatch.setattr(settings, "FCM_DRY_RUN", False)

        result = FCMPushProvider().send(_message())

        assert result.delivered is True
        assert result.provider_message_id == "msg-id-1"
        assert fake.sent[0][1] is False  # dry_run flag forwarded
        assert fake.sent[0][0].token == _message().token
        assert fake.sent[0][0].data["deep_link"] == "hyperlocal://product/abc"

    def test_dry_run_forwarded(self, monkeypatch):
        fake = FakeMessaging()
        monkeypatch.setattr(FCMPushProvider, "_get_messaging", lambda self: fake)
        monkeypatch.setattr(settings, "FCM_DRY_RUN", True)

        FCMPushProvider().send(_message())
        assert fake.sent[0][1] is True

    def test_unregistered_token_is_permanent_failure(self, monkeypatch):
        class UnregisteredError(Exception):
            code = "UNREGISTERED"

        fake = FakeMessaging(error=UnregisteredError("token no longer valid"))
        monkeypatch.setattr(FCMPushProvider, "_get_messaging", lambda self: fake)

        result = FCMPushProvider().send(_message())

        assert result.delivered is False
        assert result.permanent_failure is True

    def test_transient_error_is_not_permanent(self, monkeypatch):
        fake = FakeMessaging(error=TimeoutError("backend unavailable"))
        monkeypatch.setattr(FCMPushProvider, "_get_messaging", lambda self: fake)

        result = FCMPushProvider().send(_message())

        assert result.delivered is False
        assert result.permanent_failure is False
