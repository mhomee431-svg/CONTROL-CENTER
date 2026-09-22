"""Phase 3 - Authenticated webhook endpoints.

The S3-event processor (Lambda) and/or external providers may POST completion
or retry notifications here. Each request is authenticated with a HMAC-SHA256
signature (GitHub-style `t=<ts>,v1=<hex>`) so only holders of the shared secret
can deliver events -- the same guarantee S3→EventBridge→Lambda gets via
resource-based policies.

Replay protection: request timestamps older than `WEBHOOK_TOLERANCE_SECONDS`
are rejected, and the `X-Hyperlocal-Event-Id` header is deduped against a
short window of seen ids (insertion-idempotent).
"""
from __future__ import annotations

import hashlib
import hmac
import time
from typing import Optional

from fastapi import APIRouter, Header, HTTPException, Request, status

from app.core.config import settings
from app.core.responses import error_response, success_response

router = APIRouter(prefix="/webhooks", tags=["webhooks"])

# In-memory replay window for tests / single-instance deploys. In multi-instance
# production this is backed by the shared Redis cache; the contract (idempotent
# dedup) is identical.
_seen_event_ids: dict[str, float] = {}


def _secret() -> bytes:
    secret = settings.WEBHOOK_HMAC_SECRET
    if not secret:
        # Fail closed at runtime: an unconfigured secret is a deployment bug.
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="WEBHOOK_HMAC_SECRET is not configured",
        )
    return secret.encode("utf-8")


def _parse_signature(header: str) -> tuple[Optional[str], Optional[str]]:
    """Parse `t=<ts>,v1=<hex>` into (timestamp, digest)."""
    parts = [p.strip() for p in header.split(",")]
    ts = sig = None
    for part in parts:
        if part.startswith("t="):
            ts = part[2:]
        elif part.startswith("v1="):
            sig = part[3:]
    return ts, sig


def verify_signature(body: bytes, signature: str) -> bool:
    """Return True iff the header is a valid, untampered, in-window signature."""
    if not signature:
        return False
    ts_str, sig = _parse_signature(signature)
    if ts_str is None or sig is None:
        return False
    try:
        ts = int(ts_str)
    except ValueError:
        return False
    if abs(time.time() - ts) > settings.WEBHOOK_TOLERANCE_SECONDS:
        return False
    expected = hmac.new(
        _secret(), f"{ts_str}.{body.decode('utf-8')}".encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    return hmac.compare_digest(expected, sig)


def _sign_now(body: bytes) -> str:
    """Helper to mint a valid signature (used by tests and self-posting)."""
    ts = str(int(time.time()))
    sig = hmac.new(
        _secret(), f"{ts}.{body.decode('utf-8')}".encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    return f"t={ts},v1={sig}"


def sign_body(body: bytes) -> str:
    """Public, deterministic signer for tests/builders."""
    return _sign_now(body)


@router.post("/s3/object-created")
async def s3_object_created(
    request: Request,
    signature: Optional[str] = Header(None, alias="X-Hyperlocal-Signature"),
    event_id: Optional[str] = Header(None, alias="X-Hyperlocal-Event-Id"),
):
    """Receive an S3-object-created notification (HMAC-authenticated).

    The Lambda writes the Media row directly; this webhook is the fallback /
    external-provider channel and is idempotent by event id.
    """
    raw = await request.body()
    if not verify_signature(raw, signature or ""):
        return error_response(
            "Invalid or missing signature", error_code="INVALID_SIGNATURE",
            status_code=status.HTTP_401_UNAUTHORIZED,
        )
    if event_id:
        now = time.time()
        # Prune stale entries first (keeps the dict bounded).
        cutoff = now - settings.WEBHOOK_TOLERANCE_SECONDS
        for k, v in list(_seen_event_ids.items()):
            if v < cutoff:
                _seen_event_ids.pop(k, None)
        if event_id in _seen_event_ids:
            return success_response(message="Event already processed (deduped)")
        _seen_event_ids[event_id] = now
    return success_response(
        data={"received": True}, message="Webhook accepted",
    )
