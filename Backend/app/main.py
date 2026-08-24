from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import (
    auth,
    catalog,
    categories,
    home,
    inventory,
    locations,
    notifications,
    products,
    profile,
    saved_products,
    saved_shops,
    search,
    shops,
    users,
)
from app.api.routes import shopkeeper_auth, shopkeeper_portal
from app.core.config import settings
from app.core.exceptions import setup_exception_handlers
from app.core.health import router as health_router
from app.core.logging import get_logger, setup_logging
from app.core.middleware import RequestIDMiddleware, SecurityHeadersMiddleware
from app.core.rate_limit import limiter
from app.database.session import dispose_database, enable_postgis
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware
from fastapi.responses import JSONResponse

logger = get_logger("app.main")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan — startup/shutdown hooks."""
    # Startup
    logger.info("Starting %s v%s (%s)", settings.APP_NAME, settings.APP_VERSION, settings.ENVIRONMENT)
    await enable_postgis()
    yield
    # Shutdown
    await dispose_database()
    logger.info("Shutdown complete")


# 1. Initialize Structured Logging
setup_logging()

app = FastAPI(
    title=settings.APP_NAME,
    description=settings.APP_DESCRIPTION,
    version=settings.APP_VERSION,
    docs_url="/docs" if settings.docs_enabled else None,
    redoc_url="/redoc" if settings.docs_enabled else None,
    lifespan=lifespan,
)

# 2. Configure Middlewares
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list or ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(SecurityHeadersMiddleware)
app.add_middleware(RequestIDMiddleware)
if settings.RATE_LIMIT_ENABLED:
    app.state.limiter = limiter

    @app.exception_handler(RateLimitExceeded)
    async def rate_limit_handler(request: Request, exc: RateLimitExceeded):
        return JSONResponse(
            status_code=429,
            content={
                "success": False,
                "message": "Rate limit exceeded. Please try again later.",
                "error_code": "RATE_LIMIT_EXCEEDED",
            },
        )

    app.add_middleware(SlowAPIMiddleware)

# 3. Register Exception Handlers
setup_exception_handlers(app)

API_PREFIX = settings.API_PREFIX

# 4. Include All API Routers
app.include_router(auth.router, prefix=API_PREFIX)
app.include_router(users.router, prefix=API_PREFIX)
app.include_router(categories.router, prefix=API_PREFIX)
app.include_router(catalog.router, prefix=API_PREFIX)
app.include_router(products.router, prefix=API_PREFIX)
app.include_router(shops.router, prefix=API_PREFIX)
app.include_router(inventory.router, prefix=API_PREFIX)
app.include_router(search.router, prefix=API_PREFIX)
app.include_router(saved_products.router, prefix=API_PREFIX)
app.include_router(saved_shops.router, prefix=API_PREFIX)
app.include_router(notifications.router, prefix=API_PREFIX)
app.include_router(profile.router, prefix=API_PREFIX)
app.include_router(locations.router, prefix=API_PREFIX)
app.include_router(home.router, prefix=API_PREFIX)

# Phase 22 — Shopkeeper App (isolated module; customer routes untouched)
app.include_router(shopkeeper_auth.router, prefix=API_PREFIX)
app.include_router(shopkeeper_portal.router, prefix=API_PREFIX)

# 5. Health / Readiness (no API prefix — infra probes)
app.include_router(health_router, tags=["Health"])


# 6. Root
@app.get("/", tags=["Root"])
async def root():
    return {
        "app": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "environment": settings.ENVIRONMENT,
        "docs": "/docs",
        "health": "/health",
        "readiness": "/ready",
        "api_prefix": API_PREFIX,
    }