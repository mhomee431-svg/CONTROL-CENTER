"""FastAPI application entrypoint.

Run with:  uvicorn app.main:app --reload --port 8000
The frontend proxies /api/v1/* here.
"""

import logging
import re
from uuid import uuid4

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.middleware.base import RequestResponseEndpoint
from starlette.responses import Response
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.api.v1 import (
    auth,
    catalog,
    content,
    dashboard,
    inventory,
    offers_audit,
    operations,
    people,
    realtime,
    shops,
)
from app.core.config import settings
from app.core.migrations import upgrade_database
from app.core.operational_events import register_operational_events

app = FastAPI(title=settings.PROJECT_NAME, version="1.0.0")
logger = logging.getLogger(__name__)
_REQUEST_ID_PATTERN = re.compile(r"^[A-Za-z0-9._-]{1,64}$")


def _request_id_headers(request: Request) -> dict[str, str]:
    request_id = getattr(request.state, "request_id", None)
    return {"X-Request-ID": request_id} if request_id else {}


@app.middleware("http")
async def request_id_middleware(
    request: Request, call_next: RequestResponseEndpoint
) -> Response:
    request_id = request.headers.get("X-Request-ID", "")
    if not _REQUEST_ID_PATTERN.fullmatch(request_id):
        request_id = uuid4().hex
    request.state.request_id = request_id
    response = await call_next(request)
    response.headers["X-Request-ID"] = request_id
    return response


app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_origin_regex=(
        r"http://(?:localhost|127\.0\.0\.1):\d+"
        if settings.ENVIRONMENT == "development"
        else None
    ),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["X-Request-ID"],
)


@app.on_event("startup")
def on_startup() -> None:
    register_operational_events()
    upgrade_database()


@app.exception_handler(StarletteHTTPException)
async def http_exception_handler(request: Request, exc: StarletteHTTPException) -> JSONResponse:
    """Errors use the same envelope as successes.

    The frontend reads `message` and `error_code` off the body, so a raised
    HTTPException has to be reshaped rather than returned raw.
    """
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "success": False,
            "message": exc.detail if isinstance(exc.detail, str) else "Request failed",
            "data": exc.detail if not isinstance(exc.detail, str) else None,
            "error_code": f"HTTP_{exc.status_code}",
        },
        headers=_request_id_headers(request),
    )


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(
    request: Request, exc: RequestValidationError
) -> JSONResponse:
    return JSONResponse(
        status_code=422,
        content={
            "success": False,
            "message": "Request validation failed",
            "data": exc.errors(),
            "error_code": "VALIDATION_ERROR",
        },
        headers=_request_id_headers(request),
    )


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    request_id = getattr(request.state, "request_id", "unknown")
    logger.error(
        "Unhandled API exception (request_id=%s, method=%s, path=%s)",
        request_id,
        request.method,
        request.url.path,
        exc_info=(type(exc), exc, exc.__traceback__),
    )
    return JSONResponse(
        status_code=500,
        content={
            "success": False,
            "message": "Internal server error",
            "data": None,
            "error_code": "INTERNAL_ERROR",
        },
        headers=_request_id_headers(request),
    )


@app.get("/health")
def health() -> dict:
    return {"success": True, "message": "OK", "data": {"status": "healthy"}}


for router in (
    auth.router,
    shops.router,
    catalog.router,
    inventory.router,
    offers_audit.router,
    people.router,
    dashboard.router,
    content.router,
    operations.router,
    realtime.router,
):
    app.include_router(router, prefix=settings.API_V1_PREFIX)
