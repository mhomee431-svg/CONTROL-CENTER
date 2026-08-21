"""Request ID / correlation ID middleware + security headers middleware."""

import uuid

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

from app.core.config import settings
from app.core.logging import set_context


class RequestIDMiddleware(BaseHTTPMiddleware):
    """Attach request/correlation IDs to every request and response."""

    async def dispatch(self, request: Request, call_next):
        request_id = request.headers.get(settings.REQUEST_ID_HEADER) or str(
            uuid.uuid4()
        )
        correlation_id = request.headers.get(settings.CORRELATION_ID_HEADER) or str(
            uuid.uuid4()
        )

        request.state.request_id = request_id
        request.state.correlation_id = correlation_id

        # Enrich structured logging context
        set_context(request_id, correlation_id)

        response = await call_next(request)
        response.headers[settings.REQUEST_ID_HEADER] = request_id
        response.headers[settings.CORRELATION_ID_HEADER] = correlation_id
        return response


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Apply security headers to all responses when enabled."""

    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)

        if settings.SECURITY_HEADERS_ENABLED:
            response.headers["X-Content-Type-Options"] = "nosniff"
            response.headers["X-Frame-Options"] = "DENY"
            response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
            response.headers["Permissions-Policy"] = (
                "geolocation=(self), camera=(), microphone=(), payment=()"
            )
            response.headers["X-XSS-Protection"] = "1; mode=block"
            response.headers["Content-Security-Policy"] = (
                f"default-src {settings.CSP_DEFAULT_SRC} "
                f"frame-ancestors {settings.FRAME_ANCESTORS}"
            )
            if request.url.scheme == "https":
                hsts = f"max-age={settings.HSTS_MAX_AGE}"
                if settings.HSTS_INCLUDE_SUBDOMAINS:
                    hsts += "; includeSubDomains"
                if settings.HSTS_PRELOAD:
                    hsts += "; preload"
                response.headers["Strict-Transport-Security"] = hsts

        return response