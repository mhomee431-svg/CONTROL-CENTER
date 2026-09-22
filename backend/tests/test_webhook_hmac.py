"""Phase 3 - HMAC webhook verification tests.

Verifies signature validation, replay-tolerance rejection, and event-id
dedup on the FastAPI webhook router -- no external provider required.
"""
from __future__ import annotations

import hashlib
import hmac
import os
import sys
import time
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402
from fastapi import FastAPI  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import app.core.config as cfg  # noqa: E402
from app.api.routes import webhooks  # noqa: E402


def _app():
    app = FastAPI()
    app.include_router(webhooks.router, prefix="/api/v1")
    return app


@pytest.fixture
def secret(monkeypatch):
    monkeypatch.setattr(cfg.settings, "WEBHOOK_HMAC_SECRET", "test-secret")
    monkeypatch.setattr(webhooks, "_seen_event_ids", {})
    return "test-secret"


def test_valid_signature_accepted(secret):
    client = TestClient(_app())
    body = b'{"key":"products/12/2026/08/ab12_photo.png"}'
    sig = webhooks.sign_body(body)
    r = client.post(
        "/api/v1/webhooks/s3/object-created",
        content=body,
        headers={
            "X-Hyperlocal-Signature": sig,
            "X-Hyperlocal-Event-Id": "evt-1",
        },
    )
    assert r.status_code == 200
    assert r.json()["success"] is True


def test_invalid_signature_rejected(secret):
    client = TestClient(_app())
    body = b'{"x":1}'
    r = client.post(
        "/api/v1/webhooks/s3/object-created",
        content=body,
        headers={"X-Hyperlocal-Signature": "t=1,v1=deadbeef"},
    )
    assert r.status_code == 401


def test_missing_signature_rejected(secret):
    client = TestClient(_app())
    r = client.post("/api/v1/webhooks/s3/object-created", content=b'{"x":1}')
    assert r.status_code == 401


def test_replay_timestamp_rejected(secret):
    client = TestClient(_app())
    body = b'{"x":1}'
    past_ts = str(int(time.time()) - (cfg.settings.WEBHOOK_TOLERANCE_SECONDS + 60))
    sig = hmac.new(
        b"test-secret", f"{past_ts}.{body.decode()}".encode(), hashlib.sha256
    ).hexdigest()
    r = client.post(
        "/api/v1/webhooks/s3/object-created",
        content=body,
        headers={"X-Hyperlocal-Signature": f"t={past_ts},v1={sig}"},
    )
    assert r.status_code == 401


def test_event_id_dedup(secret):
    client = TestClient(_app())
    body = b'{"x":1}'
    sig = webhooks.sign_body(body)
    headers = {
        "X-Hyperlocal-Signature": sig,
        "X-Hyperlocal-Event-Id": "dup-evt",
    }
    first = client.post("/api/v1/webhooks/s3/object-created", content=body, headers=headers)
    second = client.post("/api/v1/webhooks/s3/object-created", content=body, headers=headers)
    assert first.status_code == 200
    assert second.status_code == 200
    assert "already" in second.json()["message"].lower()


def test_unconfigured_secret_fails_closed(monkeypatch):
    # No secret configured -> any well-formed signature still fails 500 (fail
    # closed). We must NOT call sign_body() (it would raise here too); instead
    # send a valid-shaped signature to prove the route itself fails closed.
    monkeypatch.setattr(cfg.settings, "WEBHOOK_HMAC_SECRET", None)
    client = TestClient(_app())
    body = b'{"x":1}'
    sig = f"t={int(time.time())},v1=deadbeef"
    r = client.post(
        "/api/v1/webhooks/s3/object-created", content=body,
        headers={"X-Hyperlocal-Signature": sig, "X-Hyperlocal-Event-Id": "e"},
    )
    assert r.status_code == 500
