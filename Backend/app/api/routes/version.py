"""API version information endpoint.

Provides details about the API version, supported versions, and deprecation status.
"""
from fastapi import APIRouter, Request

from app.core.api_versioning import get_version_info, get_api_version
from app.core.config import settings
from app.core.responses import success_response

router = APIRouter(tags=["version"])


@router.get(
    "/version",
    summary="Get API version information",
    description="Returns the current API version, supported versions, and deprecation status.",
)
async def get_version(request: Request):
    """Get API version information."""
    info = get_version_info()
    info["app_name"] = settings.APP_NAME
    info["app_version"] = settings.APP_VERSION
    info["environment"] = settings.ENVIRONMENT
    info["your_version"] = get_api_version(request)
    return success_response(data=info, message="API version information")


@router.get(
    "/versions",
    summary="List all supported API versions",
    description="Returns a list of all supported API versions.",
)
async def list_versions():
    """List all supported API versions."""
    info = get_version_info()
    return success_response(
        data={
            "supported_versions": info["supported_versions"],
            "default_version": info["default_version"],
            "deprecated_versions": info["deprecated_versions"],
        },
        message="Supported API versions",
    )
