"""PHASE 13 — PRODUCTION API VERIFICATION (live stack).

Complete API verification against a live deployment: real HTTPS API, real
PostgreSQL/PostGIS, real Redis, real S3. The suite is designed to be run on
or next to the production stack (see Backend/docs/PHASE13_PRODUCTION_API_VERIFICATION.md..
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
from typing import Any

import pytest

API_BASE = os.getenv("PHASE13_API_BASE_URL", "https://api.hyperlocal.in").rstrip("/")
DATABASE_URL = os.getenv("PHASE13_DATABASE_URL")
DATABASE_SSL = os.getenv("PHASE13_DATABASE_SSL", "disable").strip() or "disable"
REDIS_URL = os.getenv("PHASE13_REDIS_URL")
S3_BUCKET = os.getenv("PHASE13_S3_BUCKET")
S3_KEY_PREFIX = os.getenv("PHASE13_S3_KEY_PREFIX", "phase13-verify").strip("/")
S3_REGION = os.getenv("PHASE13_S3_REGION", "ap-south-1")
OTP_CODE = os.getenv("PHASE13_OTP_CODE")
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
}
SHOPKEEPER_AUTH_PATHS = {
    "send": "/api/v1/shopkeeper/auth/send-otp",
    "login": "/api/v1/shopkeeper/auth/login",
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


def _send_otp(http, phone, *, shopkeeper=False):
    path = SHOPKEEPER_AUTH_PATHS["send"] if shopkeeper else CUSTOMER_AUTH_PATHS["send"]
    r = _req(http, "POST", path, json_body={"phone_number": phone})
    data = assert_ok(r)
    dev = (data or {}).get("dev_otp") if isinstance(data,dict) else None
    if dev:
        return dev
    return OTP_CODE


def _otp_value(http, phone, *, shopkeeper=False):
    dev = _send_otp(http, phone, shopkeeper=shopkeeper)
    if dev:
        return dev
    raise AuthUnavailable("no dev_otp and PHASE13_OTP_CODE unset — cannot drive live auth flow")


def _login_customer(http, phone, *, register=False):
    otp = _otp_value(http, phone)
    payload = {
        "phone_number": phone,
        "otp": otp,
        "device_id": str(uuid.uuid4()),
        "device_name": "phase13-verifier",
        "device_type": "web",
        "platform": "phase13-verify",
        "app_version": "1.0.0",
    }
    path = CUSTOMER_AUTH_PATHS["register"] if register else CUSTOMER_AUTH_PATHS["verify"]
    r = _req(http, "POST", path, json_body=payload)
    if r.status_code == 409 and register:
        otp = _otp_value(http, phone)
        payload["otp"] = otp
        r = _req(http, "POST", CUSTOMER_AUTH_PATHS["verify"], json_body=payload)
    if r.status_code not in _OK:
        raise AuthUnavailable(f"{path} -> {r.status_code}: {r.text[:250]}")
    data = assert_ok(r)
    token = (data or {}).get("access_token")
    if not token:
        raise AuthUnavailable("login ok but no access_token in response")
    return token


def _login_shopkeeper(http, phone):
    otp = _otp_value(http, phone, shopkeeper=True)
    payload = {
        "phone_number": phone,
        "otp": otp,
        "device_id": str(uuid.uuid4()),
        "device_name": "phase13-verifier",
        "device_type": "web",
        "app_version": "1.0.0",
    }
    r = _req(http, "POST", SHOPKEEPER_AUTH_PATHS["login"], json_body=payload)
    if r.status_code not in _OK:
        raise AuthUnavailable(f"shopkeeper login -> {r.status_code}: {r.text[:250]}")
    data = assert_ok(r)
    token = (data or {}).get("access_token")
    if not token:
        raise AuthUnavailable("shopkeeper login ok but no access_token")
    return token