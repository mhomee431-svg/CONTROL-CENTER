"""Fast2SMS "otp" route delivery helper.

Sends one-time passwords via Fast2SMS' transactional OTP endpoint:

    POST https://www.fast2sms.com/dev/bulkV2

Behaviour is selected by ``OTP_MODE``:

    mock  → prints the OTP to the server console (₹0 cost testing).
    live  → makes a real POST and debits the Fast2SMS balance.

The API key is read from ``FAST2SMS_API_KEY`` and is never logged.
"""
from typing import Any

import httpx

from app.core.config import settings
from app.core.logging import get_logger

logger = get_logger("app.services.fast2sms")

FAST2SMS_URL = "https://www.fast2sms.com/dev/bulkV2"
FAST2SMS_TIMEOUT_SECONDS = 10.0


class Fast2SMSDeliveryError(RuntimeError):
    """Raised when Fast2SMS cannot be reached or rejects the SMS."""


def _to_sms_phone(phone_number: str) -> str:
    """Fast2SMS expects digits only (no '+', no spaces)."""
    return "".join(ch for ch in phone_number if ch.isdigit())


def send_otp_sms(phone_number: str, otp_code: str) -> None:
    """Deliver ``otp_code`` to ``phone_number`` according to ``OTP_MODE``.

    Raises :class:`Fast2SMSDeliveryError` on any live-mode failure so the
    caller can surface a user-facing error. Mock mode never raises.
    """
    mode = (settings.OTP_MODE or "mock").lower()

    if mode == "mock":
        # Console print is deliberate — the requirement for ₹0 testing is that
        # the generated OTP is visible in the server console.
        print(f"[MOCK OTP] Sent to {phone_number}: your OTP is {otp_code}")  # noqa: T201
        logger.info("Mock OTP delivered to %s", phone_number)
        return

    # mode == "live" (validated at config load).
    if not settings.FAST2SMS_API_KEY:
        raise Fast2SMSDeliveryError("FAST2SMS_API_KEY is not configured while OTP_MODE=live.")

    payload: dict[str, Any] = {
        "route": "otp",
        "variables_values": otp_code,
        "numbers": _to_sms_phone(phone_number),
    }
    headers = {
        "authorization": settings.FAST2SMS_API_KEY,
        "Content-Type": "application/json",
    }

    try:
        resp = httpx.post(
            FAST2SMS_URL,
            json=payload,
            headers=headers,
            timeout=FAST2SMS_TIMEOUT_SECONDS,
        )
    except httpx.HTTPError as exc:  # network / timeout
        raise Fast2SMSDeliveryError(f"Fast2SMS request failed: {exc}") from exc

    if resp.status_code >= 400:
        raise Fast2SMSDeliveryError(
            f"Fast2SMS returned HTTP {resp.status_code}: {resp.text[:200]}"
        )

    # Fast2SMS returns HTTP 200 with {"return": false, "message": ...} on
    # business failures (invalid key, low balance, bad number).
    try:
        body: dict[str, Any] = resp.json()
    except ValueError:
        body = {}
    if body.get("return") is False:
        message = str(body.get("message") or "unknown error")[:200]
        raise Fast2SMSDeliveryError(f"Fast2SMS rejected the SMS: {message}")

    logger.info("Fast2SMS OTP delivered to %s", phone_number)