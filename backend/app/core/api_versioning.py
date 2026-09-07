"""API versioning middleware and utilities.

Supports:
- Header-based versioning (X-API-Version: 1)
- Version validation
- Deprecation warnings
- Sunset headers for deprecated versions
"""
import logging
from datetime import datetime, timezone
from typing import Optional, Set

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware

from app.core.config import settings

logger = logging.getLogger("app.core.api_versioning")


class ApiVersionMiddleware(BaseHTTPMiddleware):
    """Middleware to handle API versioning via headers."""
    
    def __init__(self, app, default_version: str = "1"):
        super().__init__(app)
        self.default_version = default_version
        self.supported_versions = self._parse_versions(settings.API_VERSION_SUPPORTED)
        self.deprecated_versions = self._parse_versions(settings.API_VERSION_DEPRECATED)
    
    @staticmethod
    def _parse_versions(versions_str: str) -> Set[str]:
        """Parse comma-separated version string into a set."""
        if not versions_str:
            return set()
        return {v.strip() for v in versions_str.split(",") if v.strip()}
    
    async def dispatch(self, request: Request, call_next) -> Response:
        # Get requested version from header
        requested_version = request.headers.get(
            settings.API_VERSION_HEADER,
            self.default_version,
        )
        
        # Store version in request state
        request.state.api_version = requested_version
        
        # Validate version
        if requested_version not in self.supported_versions:
            from fastapi.responses import JSONResponse
            return JSONResponse(
                status_code=400,
                content={
                    "success": False,
                    "message": f"Unsupported API version: {requested_version}",
                    "error_code": "UNSUPPORTED_VERSION",
                    "data": {
                        "supported_versions": sorted(self.supported_versions),
                    },
                },
            )
        
        # Process request
        response = await call_next(request)
        
        # Add version headers
        response.headers[settings.API_VERSION_HEADER] = requested_version
        response.headers["X-API-Supported-Versions"] = ",".join(sorted(self.supported_versions))
        
        # Add deprecation warning if version is deprecated
        if requested_version in self.deprecated_versions:
            response.headers["Deprecation"] = "true"
            response.headers["Warning"] = (
                f'299 - "API version {requested_version} is deprecated. '
                f'Please upgrade to version {self.default_version}"'
            )
        
        return response


def get_api_version(request: Request) -> str:
    """Get the API version from the request."""
    return getattr(request.state, "api_version", settings.API_VERSION_DEFAULT)


def is_version_or_later(request: Request, target_version: str) -> bool:
    """Check if the request API version is >= target version."""
    current = get_api_version(request)
    try:
        return int(current) >= int(target_version)
    except (ValueError, TypeError):
        return False


def is_version_or_earlier(request: Request, target_version: str) -> bool:
    """Check if the request API version is <= target version."""
    current = get_api_version(request)
    try:
        return int(current) <= int(target_version)
    except (ValueError, TypeError):
        return False


def version_deprecated(request: Request) -> bool:
    """Check if the request API version is deprecated."""
    current = get_api_version(request)
    deprecated = ApiVersionMiddleware._parse_versions(settings.API_VERSION_DEPRECATED)
    return current in deprecated


def get_version_info() -> dict:
    """Get API version information."""
    middleware = ApiVersionMiddleware(None)
    return {
        "default_version": middleware.default_version,
        "supported_versions": sorted(middleware.supported_versions),
        "deprecated_versions": sorted(middleware.deprecated_versions),
        "current_time": datetime.now(timezone.utc).isoformat(),
    }
