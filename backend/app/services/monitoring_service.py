"""Unified monitoring service.

Provides a comprehensive monitoring dashboard that aggregates:
- System health (DB, Redis, Storage)
- Application metrics (requests, errors, latency)
- Business metrics (users, shops, subscriptions)
- Alert status
"""
import logging
from datetime import datetime, timezone
from typing import Any

from app.core.config import settings

logger = logging.getLogger("app.services.monitoring")


def get_system_health(db: Any = None) -> dict[str, Any]:
    """Get comprehensive system health status."""
    health = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "environment": settings.ENVIRONMENT,
        "version": settings.APP_VERSION,
        "components": {},
        "overall_status": "healthy",
    }
    
    # Database health
    try:
        from app.database.session import check_database_connection
        import asyncio
        db_ok = asyncio.run(check_database_connection())
        health["components"]["database"] = {
            "status": "healthy" if db_ok else "unhealthy",
            "reachable": db_ok,
        }
    except Exception as exc:
        health["components"]["database"] = {"status": "error", "error": str(exc)}
    
    # Redis health
    try:
        from app.core.cache import cache
        redis_ok = cache._connected if hasattr(cache, "_connected") else False
        health["components"]["redis"] = {
            "status": "healthy" if redis_ok else "unhealthy",
            "reachable": redis_ok,
        }
    except Exception as exc:
        health["components"]["redis"] = {"status": "error", "error": str(exc)}
    
    # Storage health
    health["components"]["storage"] = {
        "status": "healthy",
        "provider": getattr(settings, "STORAGE_PROVIDER", "local"),
    }
    
    # Determine overall status
    statuses = [c.get("status", "unknown") for c in health["components"].values()]
    if "error" in statuses:
        health["overall_status"] = "error"
    elif "unhealthy" in statuses:
        health["overall_status"] = "degraded"
    
    return health


def get_application_metrics() -> dict[str, Any]:
    """Get current application metrics from the metrics registry."""
    try:
        from app.core.observability import metrics
        
        return {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "metrics": {
                "http_requests_total": _get_counter_value(metrics.http_requests_total),
                "http_errors_total": _get_counter_value(metrics.http_errors_total),
                "http_5xx_total": _get_counter_value(metrics.http_5xx_total),
                "rate_limit_rejections_total": _get_counter_value(metrics.rate_limit_rejections_total),
                "db_errors_total": _get_counter_value(metrics.db_errors_total),
                "redis_errors_total": _get_counter_value(metrics.redis_errors_total),
                "storage_failures_total": _get_counter_value(metrics.storage_failures_total),
                "auth_attempts_total": _get_counter_value(metrics.auth_attempts_total),
                "auth_failures_total": _get_counter_value(metrics.auth_failures_total),
            },
        }
    except Exception as exc:
        logger.error("Failed to get application metrics: %s", exc)
        return {"error": str(exc)}


def _get_counter_value(counter) -> int:
    """Get total value from a counter metric."""
    try:
        if hasattr(counter, "_value"):
            return int(counter._value.get())
        return 0
    except Exception:
        return 0


def get_business_metrics(db: Any) -> dict[str, Any]:
    """Get business metrics for the dashboard."""
    try:
        from app.models.user import User
        from app.models.shop import Shop
        from app.models.subscription import Subscription, SubscriptionStatus
        from sqlalchemy import func
        
        total_users = db.query(func.count(User.id)).scalar() or 0
        active_users = db.query(func.count(User.id)).filter(
            User.is_active == True, User.is_deleted == False
        ).scalar() or 0
        
        total_shops = db.query(func.count(Shop.id)).filter(
            Shop.is_deleted == False
        ).scalar() or 0
        verified_shops = db.query(func.count(Shop.id)).filter(
            Shop.is_deleted == False,
            Shop.is_verified == True
        ).scalar() or 0
        
        active_subscriptions = db.query(func.count(Subscription.id)).filter(
            Subscription.status == SubscriptionStatus.ACTIVE
        ).scalar() or 0
        
        return {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "metrics": {
                "total_users": total_users,
                "active_users": active_users,
                "total_shops": total_shops,
                "verified_shops": verified_shops,
                "active_subscriptions": active_subscriptions,
            },
        }
    except Exception as exc:
        logger.error("Failed to get business metrics: %s", exc)
        return {"error": str(exc)}


def get_alert_summary() -> dict[str, Any]:
    """Get current alert status summary."""
    try:
        from app.core.observability.alerting import manager
        
        mgr = manager()
        firing = mgr.firing()
        
        return {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "total_rules": len(mgr.rules),
            "firing_count": len(firing),
            "firing_alerts": [r.to_dict() for r in firing],
            "status": "critical" if firing else "healthy",
        }
    except Exception as exc:
        logger.error("Failed to get alert summary: %s", exc)
        return {"error": str(exc)}


def get_monitoring_dashboard(db: Any = None) -> dict[str, Any]:
    """Get complete monitoring dashboard data."""
    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "environment": settings.ENVIRONMENT,
        "version": settings.APP_VERSION,
        "system_health": get_system_health(db),
        "application_metrics": get_application_metrics(),
        "business_metrics": get_business_metrics(db) if db else None,
        "alert_summary": get_alert_summary(),
    }