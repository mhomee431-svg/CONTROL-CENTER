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
from app.api.routes import inventory_intake
from app.api.routes import pos_integration
from app.api.routes import admin as admin_routes
from app.api.routes import interactions
from app.api.routes import google_auth

from app.core.config import settings
from app.core.exceptions import setup_exception_handlers
from app.core.health import router as health_router
from app.core.logging import get_logger, setup_logging
from app.core.middleware import RequestIDMiddleware, SecurityHeadersMiddleware
from app.core.observability.access_log import AccessLogMiddleware, MetricsMiddleware
from app.core.observability.routes import router as observability_router
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

    # Phase 30 — fail-fast production security gate (raises on critical misconfig)
    from app.core.startup_checks import run_startup_security_checks

    run_startup_security_checks(settings)

    await enable_postgis()

    # Phase 24 — observability bootstrap (never fails the app when telemetry breaks)
    try:
        from app.core.observability.alerting import LogNotifier, WebhookNotifier, manager
        from app.core.observability.celery_signals import install_celery_observability
        from app.core.observability.deployment import register_deployment
        from app.core.observability import metrics as obs_metrics

        register_deployment("starting")
        install_celery_observability()
        notifiers = [LogNotifier()]
        if settings.ALERT_WEBHOOK_URL:
            notifiers.append(WebhookNotifier(settings.ALERT_WEBHOOK_URL))
        manager().set_notifiers(notifiers)
        obs_metrics.storage_provider.set(1, provider=settings.STORAGE_PROVIDER.lower())
    except Exception as exc:  # noqa: BLE001
        logger.warning("Observability bootstrap skipped: %s", exc)
    yield
    # Shutdown — close external connections cleanly (graceful shutdown).
    # Redis first (stop accepting cache work), then drain DB engine pools.
    from app.core.cache import cache as redis_cache

    await redis_cache.close()
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
# Phase 24 — observability middlewares (outermost so they time/observe everything,
# but inside request-ID handling so access logs carry the request id).
app.add_middleware(AccessLogMiddleware)
app.add_middleware(MetricsMiddleware)
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

# Phase 24 — Barcode scan + Excel inventory intake
app.include_router(inventory_intake.router, prefix=API_PREFIX)

# Phase 7 — S3 object storage (signed media uploads, authorized reads/deletes)
from app.api.routes import media as media_routes

app.include_router(media_routes.router, prefix=API_PREFIX)

# Phase 25 — Provider-agnostic POS integration platform
app.include_router(pos_integration.router, prefix=API_PREFIX)

# Phase 26 — Complete Admin Platform
app.include_router(admin_routes.router, prefix=API_PREFIX)

# Phase 28 — Shopkeeper subscriptions & payments (monetization)
from app.api.routes import shopkeeper_subscription
app.include_router(shopkeeper_subscription.router, prefix=API_PREFIX)

# Phase 29 — Analytics & audit (event ingestion + admin dashboards/reports)
from app.api.routes import analytics_system as analytics_system_routes
app.include_router(analytics_system_routes.router, prefix=API_PREFIX)
app.include_router(analytics_system_routes.admin_router, prefix=API_PREFIX)

# Interactions / leads — action-triggered verification + immutable actions
app.include_router(interactions.router, prefix=API_PREFIX)

# Google OAuth — mounted at the exact path derived from GOOGLE_CALLBACK_URL
app.include_router(google_auth.router)

# 5. Health / Readiness (no API prefix — infra probes)
app.include_router(health_router, tags=["Health"])

# Phase 24 — Observability: Prometheus metrics + admin overview/alerts.
app.include_router(observability_router)


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