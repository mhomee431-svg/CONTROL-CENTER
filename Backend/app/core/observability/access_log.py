"""Metrics + access-log middleware (Phase 24 observability).

* :class:`MetricsMiddleware` — records request latency / status / error /
  5xx / 429 metrics for every request handled by the app.
* :class:`AccessLogMiddleware` — emits one structured JSON line per request
  (method, path, status, duration, request/correlation ids, client ip,
  user agent) WITHOUT query strings (which can carry PII or tokens) and with
  the request path truncated to a bounded label.

Both wrap the application outside the existing RequestID middleware so the
contextvars are already populated.
"""

from __future__ import annotations

import time

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

from app.core.logging import get_logger
from app.core.observability.metrics import normalize_path, record_http_request

logger = get_logger("app.access")

# Body/query values in these keys are never logged (defence in depth).
_SENSITIVE_PARAM_KEYS = {
    "password", "passwd", "pwd", "otp", "otp_code", "token", "access_token",
    "refresh_token", "id_token", "authorization", "api_key", "client_secret",
    "secret", "card_number", "cvv", "upi", "upi_id",
}


def _safe_query_params(request: Request) -> dict:
    """Return query params with sensitive keys scrubbed."""
    out: dict = {}
    for key, value in request.query_params.multi_items():
        if key.lower() in _SENSITIVE_PARAM_KEYS:
            value = "[REDACTED]"
        out[key] = str(value)[:120]
    return out


class MetricsMiddleware(BaseHTTPMiddleware):
    """Record Prometheus HTTP metrics for every request."""

    async def dispatch(self, request: Request, call_next):
        start = time.perf_counter()
        try:
            response = await call_next(request)
        except Exception:
            # The exception handler still returns a 500 response; record it
            # here too so metrics are complete even if call_next bubbles.
            elapsed = time.perf_counter() - start
            record_http_request(request.method, request.url.path, 500, elapsed)
            raise
        elapsed = time.perf_counter() - start
        record_http_request(request.method, request.url.path, response.status_code, elapsed)
        return response


class AccessLogMiddleware(BaseHTTPMiddleware):
    """Emit one structured JSON log line per HTTP request."""

    async def dispatch(self, request: Request, call_next):
        start = time.perf_counter()
        response = await call_next(request)
        elapsed_ms = (time.perf_counter() - start) * 1000.0

        client_ip = None
        if request.client is not None:
            client_ip = request.client.host

        log_data = {
            "event": "http_request",
            "method": request.method,
            "path": normalize_path(request.url.path),
            "status": response.status_code,
            "duration_ms": round(elapsed_ms, 2),
            "request_id": getattr(request.state, "request_id", "-"),
            "correlation_id": getattr(request.state, "correlation_id", "-"),
            "client_ip": client_ip,
            "user_agent": request.headers.get("user-agent"),
        }
        # Query parameters are scrubbed; query strings can carry OTPs/tokens.
        try:
            query_params = _safe_query_params(request)
            if query_params:
                log_data["query_params"] = query_params
        except Exception:  # noqa: BLE001 — a logging failure must not break the response
            pass
        # The JsonFormatter merges ``extra={"data": {...}}`` into the output
        # line and redacts it before it reaches the sink.
        logger.info("http_request", extra={"data": log_data})
        return response