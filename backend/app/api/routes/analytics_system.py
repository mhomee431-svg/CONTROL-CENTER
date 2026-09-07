"""Phase 29 — Analytics & audit routes.

Ingestion:
    POST /analytics/events          — track a customer/shopkeeper/platform event
                                      (optional auth; PII scrubbed server-side)

Admin dashboards (require ``analytics:read``):
    GET  /admin/analytics/trends            — search trends
    GET  /admin/analytics/popular-products  — popular products
    GET  /admin/analytics/popular-categories— popular categories
    GET  /admin/analytics/popular-shops     — popular shops
    GET  /admin/analytics/conversion        — search-to-shop conversion
    GET  /admin/analytics/inventory-freshness
    GET  /admin/analytics/shop-activity
    GET  /admin/analytics/product-activity
    GET  /admin/analytics/subscriptions     — subscription metrics
    GET  /admin/analytics/health            — API performance / errors

Reports (require ``report:*``) and audit chain integrity (``audit_log:read``).
Audit entries have NO mutation endpoints by design — see services/audit_service.
"""
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.dependencies import get_optional_user, require_admin_permission
from app.core.responses import success_response
from app.database.session import get_db
from app.models.user import User
from app.schemas.analytics import AnalyticsEventIn
from app.services import analytics_system as an
from app.services import audit_service

router = APIRouter(tags=["analytics"])
admin_router = APIRouter(prefix="/admin/analytics", tags=["analytics-admin"])


# ── Ingestion ────────────────────────────────────────────────────────────────
@router.post("/analytics/events")
async def track_analytics_event(
    payload: AnalyticsEventIn,
    user: User | None = Depends(get_optional_user),
    db: Session = Depends(get_db),
):
    """Record one platform event. Anonymous callers allowed (session-scoped)."""
    try:
        event = an.track_event(
            db,
            event_name=payload.event_name,
            actor_type=payload.actor_type,
            actor_id=user.id if user else None,
            session_id=payload.session_id,
            shop_id=payload.shop_id,
            product_master_id=payload.product_master_id,
            category_id=payload.category_id,
            query=payload.query,
            metric_value=payload.metric_value,
            props=payload.props,
            device_type=payload.device_type,
            app_version=payload.app_version,
        )
        db.commit()
    except Exception:
        db.rollback()
        raise
    return success_response(data=an.serialize_event(event), message="Event recorded")


# ── Admin dashboards ─────────────────────────────────────────────────────────
@admin_router.get("/trends")
async def trends_route(
    days: int = Query(30, ge=1, le=365),
    _: User = Depends(require_admin_permission("analytics", "read")),
    db: Session = Depends(get_db),
):
    return success_response(data=an.search_trends(db, days))


@admin_router.get("/popular-products")
async def popular_products_route(
    days: int = Query(30, ge=1, le=365),
    limit: int = Query(10, ge=1, le=100),
    _: User = Depends(require_admin_permission("analytics", "read")),
    db: Session = Depends(get_db),
):
    return success_response(data={"items": an.popular_products(db, days, limit)})


@admin_router.get("/popular-categories")
async def popular_categories_route(
    days: int = Query(30, ge=1, le=365),
    limit: int = Query(10, ge=1, le=100),
    _: User = Depends(require_admin_permission("analytics", "read")),
    db: Session = Depends(get_db),
):
    return success_response(data={"items": an.popular_categories(db, days, limit)})


@admin_router.get("/popular-shops")
async def popular_shops_route(
    days: int = Query(30, ge=1, le=365),
    limit: int = Query(10, ge=1, le=100),
    _: User = Depends(require_admin_permission("analytics", "read")),
    db: Session = Depends(get_db),
):
    return success_response(data={"items": an.popular_shops(db, days, limit)})


@admin_router.get("/conversion")
async def conversion_route(
    days: int = Query(30, ge=1, le=365),
    _: User = Depends(require_admin_permission("analytics", "read")),
    db: Session = Depends(get_db),
):
    return success_response(data=an.search_to_shop_conversion(db, days))


@admin_router.get("/inventory-freshness")
async def freshness_route(
    days: int = Query(30, ge=1, le=365),
    _: User = Depends(require_admin_permission("analytics", "read")),
    db: Session = Depends(get_db),
):
    return success_response(data=an.inventory_freshness(db, days))


@admin_router.get("/shop-activity")
async def shop_activity_route(
    days: int = Query(30, ge=1, le=365),
    limit: int = Query(20, ge=1, le=200),
    _: User = Depends(require_admin_permission("analytics", "read")),
    db: Session = Depends(get_db),
):
    return success_response(data={"items": an.shop_activity(db, days, limit)})


@admin_router.get("/product-activity")
async def product_activity_route(
    days: int = Query(30, ge=1, le=365),
    limit: int = Query(20, ge=1, le=200),
    _: User = Depends(require_admin_permission("analytics", "read")),
    db: Session = Depends(get_db),
):
    return success_response(data={"items": an.product_activity(db, days, limit)})


@admin_router.get("/subscriptions")
async def subscriptions_route(
    days: int = Query(90, ge=1, le=730),
    _: User = Depends(require_admin_permission("analytics", "read")),
    db: Session = Depends(get_db),
):
    return success_response(data=an.subscription_metrics(db, days))


@admin_router.get("/health")
async def platform_health_route(
    hours: int = Query(24, ge=1, le=720),
    _: User = Depends(require_admin_permission("analytics", "read")),
    db: Session = Depends(get_db),
):
    return success_response(data=an.platform_health(db, hours))


# ── Reports ──────────────────────────────────────────────────────────────────
@admin_router.post("/reports/generate", status_code=201)
async def generate_report_route(
    report_type: str = Query(..., max_length=50),
    days: int = Query(30, ge=1, le=365),
    current_user: User = Depends(require_admin_permission("report", "generate")),
    db: Session = Depends(get_db),
):
    try:
        report = an.generate_report(
            db, report_type=report_type, generated_by=current_user.id, params={"days": days}
        )
        db.commit()
    except Exception:
        db.rollback()
        raise
    return success_response(
        data=an.serialize_report(report), message="Report generated", status_code=201
    )


@admin_router.get("/reports")
async def list_reports_route(
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    _: User = Depends(require_admin_permission("report", "read")),
    db: Session = Depends(get_db),
):
    query = (
        db.query(an.Report)
        .filter(an.Report.report_type.like("ANALYTICS_%"))
        .order_by(an.Report.id.desc())
    )
    total = query.count()
    items = query.offset(offset).limit(limit).all()
    return success_response(
        data={
            "items": [an.serialize_report(r) for r in items],
            "total": total,
            "limit": limit,
            "offset": offset,
        }
    )


@admin_router.get("/reports/{report_id}")
async def get_report_route(
    report_id: int,
    _: User = Depends(require_admin_permission("report", "read")),
    db: Session = Depends(get_db),
):
    return success_response(data=an.serialize_report(an.get_report(db, report_id)))


# ── Audit chain integrity ────────────────────────────────────────────────────
@admin_router.get("/audit-chain")
async def audit_chain_route(
    _: User = Depends(require_admin_permission("audit_log", "read")),
    db: Session = Depends(get_db),
):
    """Verify the tamper-evidence hash chain over all audit records."""
    return success_response(data=audit_service.verify_audit_chain(db))