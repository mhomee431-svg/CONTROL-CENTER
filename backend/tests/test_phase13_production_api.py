"""PHASE 13 — PRODUCTION API VERIFICATION (live stack).

Complete API verification against a live deployment: real HTTPS API, real
PostgreSQL/PostGIS, real Redis, real S3. The suite is designed to be run on
or next to the production stack (see backend/docs/PHASE13_PRODUCTION_API_VERIFICATION.md..
Every module checks: authentication, authorization, validation, success/failure
envelopes, pagination, filtering, sorting, transaction behavior, DB persistence,
error handling. When real infra is not reachable the module auto-skips with
precise reasons(safe to include in any pytest run..

Module coverage: Infrastructure, Authentication, Customer, Shop/Catalog, Product,
Search/Location, Inventory/Pricing/Offers, Favorites, History, Notifications,
Admin, Analytics, Media/S3, Interactions, Shopkeeper/POS/Subscriptions, Cross-cutting.

Environment (all optional, missing value = precise skip:::
  PHASE13_API_BASE_URL (default https://api.hyperlocal.in..
  PHASE13_DATABASE_URL + PHASE13_DATABASE_SSL (default disable; use require for cloud..
  PHASE13_REDIS_URL ..
  PHASE13_S3_BUCKET / PHASE13_S3_KEY_PREFIX / PHASE13_S3_REGION ..
  PHASE13_OTP_CODE, PHASE13_PHONE_PREFIX, PHASE13_CUSTOMER_TOKEN ..
  PHASE13_ADMIN_PHONE/TOKEN, PHASE13_SHOPKEEPER_PHONE/TOKEN ..
  PHASE13_DESTRUCTIVE=1 (write/delete round trips., PHASE13_AUTH_EXTRA=1 ..
  PHASE13_DELAY_MS (pacing between requests; default  ️150..

Quick start:::
  PHASE13_API_BASE_URL=... PHASE13_DATABASE_URL=... PHASE13_REDIS_URL=... \
  PHASE13_DATABASE_SSL=require PHASE13_DESTRUCTIVE=1 \
  python -m pytest tests/test_phase13_production_api.py -v
"""

from __future__ import annotations

import os
import random
import time
import uuid

API_BASE = os.getenv("PHASE13_API_BASE_URL", "https://api.hyperlocal.in").rstrip("/")
DATABASE_URL = os.getenv("PHASE13_DATABASE_URL")
DATABASE_SSL = os.getenv("PHASE13_DATABASE_SSL", "disable").strip() or "disable"
REDIS_URL = os.getenv("PHASE13_REDIS_URL")
S3_BUCKET = os.getenv("PHASE13_S3_BUCKET")
S3_KEY_PREFIX = os.getenv("PHASE13_S3_KEY_PREFIX", "phase13-verify").strip("/")
S3_REGION = os.getenv("PHASE13_S3_REGION", "ap-south-1")
OTP_CODE = os.getenv("PHASE13_OTP_CODE")  # legacy; unused since Firebase OTP migration
FIREBASE_TOKEN = os.getenv("PHASE13_FIREBASE_TOKEN")
_DELAY = int(os.getenv("PHASE13_DELAY_MS", "150"))
DESTRUCTIVE = os.getenv("PHASE13_DESTRUCTIVE", "0") in  ("1", "true", "yes")
AUTH_EXTRA = os.getenv("PHASE13_AUTH_EXTRA", "0") in  ("1", "true", "yes")

CUSTOMER_TOKEN = os.getenv("PHASE13_CUSTOMER_TOKEN")
ADMIN_TOKEN = os.getenv("PHASE13_ADMIN_TOKEN")
ADMIN_PHONE = os.getenv("PHASE13_ADMIN_PHONE")
SHOPKEEPER_TOKEN = os.getenv("PHASE13_SHOPKEEPER_TOKEN")
SHOPKEEPER_PHONE = os.getenv("PHASE13_SHOPKEEPER_PHONE")

_PHONE_BASE = os.getenv("PHASE13_PHONE_PREFIX", "9199900")
_RND = random.Random(20261309)

_OK = [200, 201]
_ERR = [400, 404, 409, 422, 429]

CUSTOMER_AUTH_PATHS = {
    "send": "/api/v1/auth/send-otp",
    "register": "/api/v1/auth/register",
    "verify": "/api/v1/auth/verify-otp",
    "firebase": "/api/v1/auth/firebase-login",
}
SHOPKEEPER_AUTH_PATHS = {
    "send": "/api/v1/shopkeeper/auth/send-otp",
    "login": "/api/v1/shopkeeper/auth/login",
    "firebase": "/api/v1/shopkeeper/auth/firebase-login",
}


class AuthUnavailable(Exception):
    """Raised when the live auth flow cannot be driven(skip dependent tests."""


def fresh_phone() -> str:
    return f"{_PHONE_BASE}{_RND.randint(100000, 999999)}"


def _pace() -> None:
    if _DELAY > 0:
        time.sleep(_DELAY / 1000.0)


def _req(http, method, path, *, token=None, json_body=None, params=None):
    headers = {}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if json_body is not None:
        headers["Content-Type"] = "application/json"
    _pace()
    return http.request(method, path, json=json_body, params=params, headers=headers)


def assert_ok(r, *, statuses=None):
    if statuses is None:
        statuses = _OK
    assert r.status_code in   statuses, f"expected {statuses} got {r.status_code}: {r.text[:500]}"
    body = r.json()
    assert isinstance(body,dict)
    assert body.get("success") is True
    assert "message" in   body
    assert "data" in   body
    return body.get("data")


def assert_err(r, *, statuses=None):
    if statuses is None:
        statuses = _ERR
    assert r.status_code in   statuses,f"expected {statuses} got {r.status_code}: {r.text[:500]}"
    body = r.json()
    assert isinstance(body,dict)
    assert body.get("success") is False
    assert body.get("message")
    assert body.get("error_code")
    return body


def _login_customer(http, phone, *, register=False):
    """Drive the customer auth flow (register flag kept for call-site compat).

    Customer auth is Firebase-based: the Flutter app completes the phone-OTP
    flow client-side and sends the resulting Firebase ID token. For live
    verification a real token must be injected with ``PHASE13_FIREBASE_TOKEN``;
    without it the dependent tests are skipped with a precise reason.
    """
    if not FIREBASE_TOKEN:
        raise AuthUnavailable(
            "PHASE13_FIREBASE_TOKEN unset — customer auth now requires a "
            "Firebase ID token (no dev OTP / Fast2SMS backdoor exists)"
        )
    payload = {
        "firebase_id_token": FIREBASE_TOKEN,
        "device_id": str(uuid.uuid4()),
        "device_name": "phase13-verifier",
        "device_type": "web",
        "platform": "phase13-verify",
        "app_version": "1.0.0",
    }
    path = CUSTOMER_AUTH_PATHS["firebase"]
    r = _req(http, "POST", path, json_body=payload)
    if r.status_code not in _OK:
        raise AuthUnavailable(f"{path} -> {r.status_code}: {r.text[:250]}")
    data = assert_ok(r)
    token = (data or {}).get("access_token")
    if not token:
        raise AuthUnavailable("login ok but no access_token in response")
    return token


def _login_shopkeeper(http, phone):
    """Drive the shopkeeper auth flow.

    Shopkeeper auth is Firebase-based, exactly like the customer flow: OTP
    delivery happens client-side in the Flutter app and the backend verifies
    the resulting Firebase ID token, so there is no dev OTP / Fast2SMS backdoor
    to fetch a code from. The phone number is therefore taken from the verified
    token, not from the caller.

    A live verification must inject a real token with ``PHASE13_FIREBASE_TOKEN``;
    without it the dependent tests are skipped with a precise reason.
    """
    if not FIREBASE_TOKEN:
        raise AuthUnavailable(
            "PHASE13_FIREBASE_TOKEN unset - shopkeeper auth now requires a "
            "Firebase ID token (no dev OTP / Fast2SMS backdoor exists)"
        )
    payload = {
        "firebase_id_token": FIREBASE_TOKEN,
        "device_id": str(uuid.uuid4()),
        "device_name": "phase13-verifier",
        "device_type": "web",
        "platform": "phase13-verify",
    }
    path = SHOPKEEPER_AUTH_PATHS["firebase"]
    r = _req(http, "POST", path, json_body=payload)
    if r.status_code not in _OK:
        raise AuthUnavailable(f"{path} -> {r.status_code}: {r.text[:250]}")
    data = assert_ok(r)
    token = (data or {}).get("access_token")
    if not token:
        raise AuthUnavailable("shopkeeper login ok but no access_token")
    return token