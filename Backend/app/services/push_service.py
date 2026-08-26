"""Push notification service abstraction — FCM behind a swappable interface.

Providers:
    mock  → record delivery in-memory / logs only (default for dev & test)
    fcm   → Firebase Cloud Messaging (credentials come exclusively from
            settings/env — a service-account JSON file path or an OAuth
            server key. Never hardcoded.)

Every provider returns a :class:`PushResult` so the delivery engine can
distinguish transient failures (retry) from permanent ones (invalid token →
deactivate).
"""

import json
import logging
import uuid
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Optional

from app.core.config import settings

logger = logging.getLogger("app.services.push")


@dataclass
class PushResult:
    """Outcome of a single provider send attempt for one device token."""

    delivered: bool
    provider_message_id: Optional[str] = None
    error: Optional[str] = None
    permanent_failure: bool = False  # invalid/unregistered token etc.


@dataclass
class PushMessage:
    token: str
    title: str
    body: str
    deep_link: Optional[str] = None
    data: dict = field(default_factory=dict)


class BasePushProvider(ABC):
    """Interface every push provider implements."""

    name: str = "base"

    @abstractmethod
    def send(self, message: PushMessage) -> PushResult:
        """Attempt delivery of ``message`` to its single device token."""
        raise NotImplementedError


class MockPushProvider(BasePushProvider):
    """Logs the payload instead of contacting a provider (dev/test)."""

    name = "mock"

    def __init__(self):
        # In-memory outbox — handy for tests asserting what was "sent".
        self.sent: list[PushMessage] = []

    def send(self, message: PushMessage) -> PushResult:
        self.sent.append(message)
        logger.info(
            "[MOCK PUSH] token=%s... title=%s deep_link=%s",
            message.token[:12],
            message.title,
            message.deep_link,
        )
        return PushResult(delivered=True, provider_message_id=f"mock-{uuid.uuid4().hex[:12]}")


# Tokens that providers report as permanently invalid (uninstalled app,
# rotated token). Delivery engine deactivates these instead of retrying.
PERMANENT_TOKEN_ERRORS = {
    "UNREGISTERED",
    "INVALID_ARGUMENT",
    "SENDER_ID_MISMATCH",
}


class FCMPushProvider(BasePushProvider):
    """Firebase Cloud Messaging via the firebase-admin SDK.

    Credentials resolution order (all sourced from settings/environment):
      1. ``settings.FCM_CREDENTIALS_FILE`` — path to a service-account JSON.
      2. ``settings.FCM_CREDENTIALS_JSON`` — raw service-account JSON string
         injected by the secret manager.
    """

    name = "fcm"

    _messaging = None  # cached messaging instance

    def _get_messaging(self):
        if FCMPushProvider._messaging is not None:
            return FCMPushProvider._messaging

        import firebase_admin
        from firebase_admin import credentials, messaging

        if not firebase_admin._apps:
            cred: credentials.Base = (
                credentials.Certificate(settings.FCM_CREDENTIALS_FILE)
                if settings.FCM_CREDENTIALS_FILE
                else credentials.Certificate(json.loads(settings.FCM_CREDENTIALS_JSON or "{}"))
            )
            firebase_admin.initialize_app(cred)

        FCMPushProvider._messaging = messaging
        return FCMPushProvider._messaging

    def send(self, message: PushMessage) -> PushResult:
        try:
            messaging = self._get_messaging()
            data = {k: str(v) for k, v in message.data.items()}
            if message.deep_link:
                data["deep_link"] = message.deep_link
            msg = messaging.Message(
                notification=messaging.Notification(title=message.title, body=message.body),
                data=data,
                token=message.token,
            )
            response = messaging.send(msg, dry_run=settings.FCM_DRY_RUN)
            return PushResult(delivered=True, provider_message_id=response)
        except Exception as exc:  # noqa: BLE001 — provider SDK raises many types
            reason = getattr(exc, "code", "") or type(exc).__name__
            permanent = any(marker in str(reason).upper() or marker in str(exc).upper() for marker in PERMANENT_TOKEN_ERRORS)
            logger.warning("FCM send failed token=%s... reason=%s permanent=%s", message.token[:12], reason, permanent)
            return PushResult(delivered=False, error=f"{reason}: {exc}", permanent_failure=permanent)


def get_push_provider() -> BasePushProvider:
    """Factory returning the configured push provider."""
    provider = (settings.PUSH_PROVIDER or "mock").lower()
    if provider == "fcm":
        return FCMPushProvider()
    return MockPushProvider()


_push_provider: Optional[BasePushProvider] = None


def get_push_service() -> BasePushProvider:
    global _push_provider
    if _push_provider is None:
        _push_provider = get_push_provider()
    return _push_provider


def set_push_service(provider: BasePushProvider) -> None:
    """Override the singleton (used by tests to inject a mock)."""
    global _push_provider
    _push_provider = provider