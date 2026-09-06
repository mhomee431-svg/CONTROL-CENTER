"""API middleware for standardized request/response handling.

Provides:
- Request ID generation and tracking
- Response time logging
- Standardized error formatting
- API versioning headers
"""
import logging
import time
import uuid
from typing import Callable

from fastapi import FastAPI, Request, Response
from starlette.middleware.base import BaseHTTPMiddleware

from app.core.config import settings

logger = logging.getLogger("app.core.api_middleware")


class RequestContextMiddleware(BaseHTTPMiddleware):
    """Middleware to add request context (ID, timing) to all requests."""
    
    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        # Generate request ID if not present
        request_id = request.headers.get(
            settings.REQUEST_ID_HEADER,
            str(uuid.uuid4()),
        )
        request.state.request_id = request_id
        
        # Get correlation ID if present
        correlation_id = request.headers.get(
            settings.CORRELATION_ID_HEADER,
        )
        if correlation_id:
            request.state.correlation_id = correlation_id
        
        # Track request start time
        start_time = time.time()
        
        # Process request
        response = await call_next(request)
        
        # Calculate duration
        duration_ms = round((time.time() - start_time) * 1000, 2)
        
        # Add standard headers
        response.headers[settings.REQUEST_ID_HEADER] = request_id
        response.headers["X-Response-Time-Ms"] = str(duration_ms)
        response.headers["X-Api-Version"] = settings.APP_VERSION
        
        # Log slow requests
        if duration_ms > 1000:
            logger.warning(
                "Slow request: %s %s took %s ms (request_id=%s)",
                request.method,
                request.url.path,
                duration_ms,
                request_id,
            )
        
        return response


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Middleware to add security headers to all responses."""
    
    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        response = await call_next(request)
        
        # Security headers
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-XSS-Protection"] = "1; mode=block"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        response.headers["Permissions-Policy"] = "geolocation=(self), camera=()"
        
        # HSTS (only in production)
        if settings.is_production:
            response.headers["Strict-Transport-Security"] = (
                f"max-age={settings.HSTS_MAX_AGE}; includeSubDomains; preload"
            )
        
        return response


def setup_api_middleware(app: FastAPI) -> None:
    """Register all API middleware with the FastAPI app."""
    app.add_middleware(RequestContextMiddleware)
    app.add_middleware(SecurityHeadersMiddleware)
