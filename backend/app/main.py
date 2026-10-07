"""FastAPI application entrypoint.

Run with:  uvicorn app.main:app --reload --port 8000
The frontend proxies /api/v1/* here.
"""

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
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
    shops,
)
from app.core.config import settings
from app.core.database import Base, engine

app = FastAPI(title=settings.PROJECT_NAME, version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_origin_regex=r"http://(?:localhost|127\.0\.0\.1):\d+",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def on_startup() -> None:
    # create_all is enough for the local console; a shared environment would
    # use Alembic migrations instead.
    Base.metadata.create_all(bind=engine)


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
    )


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    # A 500 still has to be readable JSON, or the client reports a parse error
    # and hides the real failure.
    return JSONResponse(
        status_code=500,
        content={
            "success": False,
            "message": "Internal server error",
            "data": None,
            "error_code": "INTERNAL_ERROR",
        },
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
):
    app.include_router(router, prefix=settings.API_V1_PREFIX)
