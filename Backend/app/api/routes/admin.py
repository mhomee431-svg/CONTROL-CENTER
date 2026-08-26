"""Phase 26 — Admin Platform routes (/admin/*).

Every endpoint requires an admin-family role AND a specific module
permission via ``require_admin_permission(resource, action)``.
Critical operations write both an AuditLog and an AdminAction record
(see ``admin_service.record_audit_log`` / ``record_admin_action``).
"""

import inspect

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.orm import Session

from app.core.admin_permissions import describe_admin_role
from app.core.dependencies import require_admin_permission
from app.core.exceptions import AppError
from app.core.responses import success_response
from app.database.session import get_db
from app.models.user import User
from app.schemas.admin import (
    AdminNoteCreate,
    AdminNotificationCreate,
    BrandAdminCreate,
    BrandAdminUpdate,
    BulkShopAction,
    CategoryAdminCreate,
    CategoryAdminUpdate,
    ComplaintUpdate,
    ProductAdminAction,
    ProductAdminUpdate,
    ReportGenerateRequest,
    ShopVerificationAction,
    SubscriptionAdminUpdate,
)
from app.services import admin_service

router = APIRouter(prefix="/admin", tags=["admin-platform"])


def _client_ip(request: Request) -> str | None:
    return request.client.host if request.client else None


def _admin_keys(user: User) -> set[str]:
    from app.core.admin_permissions import effective_admin_permissions

    role_name = user.role.name if user.role is not None else None
    return effective_admin_permissions(role_name)


def _run(fn, *args, request: Request | None = None, **kwargs):
    """Execute a service call; commit on success, roll back on AppError."""
    db: Session = kwargs.pop("db")
    accepts_ip = "ip_address" in inspect.signature(fn).parameters
    try:
        if accepts_ip:
            result = fn(
                db, *args,
                ip_address=_client_ip(request) if request else None,
                **kwargs,
            )
        else:
            result = fn(db, *args, **kwargs)
        db.commit()
    except AppError:
        db.rollback()
        raise
    return result


# ── Me / role info ────────────────────────────────────────────────────────
@router.get("/me")
async def whoami_admin(
    current_user: User = Depends(require_admin_permission("dashboard", "read")),
):
    """Return the caller's admin role summary and effective permissions."""
    info = describe_admin_role(
        current_user.role.name if current_user.role is not None else None
    )
    return success_response(
        data={"user_id": current_user.id, "name": current_user.name, **info}
    )


# ── Dashboard ────────────────────────────────────────────────────────────
@router.get("/dashboard/metrics")
async def dashboard_metrics(
    _: User = Depends(require_admin_permission("dashboard", "read")),
    db: Session = Depends(get_db),
):
    """Platform-wide dashboard metrics."""
    return success_response(data=admin_service.dashboard_metrics(db))

# ── Customers / Users ────────────────────────────────────────────────────
@router.get("/customers")
async def list_customers(
    role: str | None = Query(None),
    status: str | None = Query(None),
    search: str | None = Query(None, max_length=200),
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    _: User = Depends(require_admin_permission("customer", "read")),
    db: Session = Depends(get_db),
):
    """List customers/shopkeepers with role + status filters and search."""
    items, total = admin_service.list_users(
        db, role_name=role, status=status, search=search, limit=limit, offset=offset
    )
    return success_response(data={"items": items, "total": total, "limit": limit, "offset": offset})


@router.post("/users/{user_id}/status")
async def change_user_status(
    user_id: int,
    action: str = Query(..., pattern="^(SUSPEND|BAN|ACTIVATE)$"),
    reason: str | None = Query(None, max_length=500),
    current_user: User = Depends(require_admin_permission("customer", "update")),
    db: Session = Depends(get_db),
):
    """Suspend / ban / re-activate a user account."""
    result = _run(
        admin_service.update_user_status,
        admin_user=current_user, user_id=user_id, action=action, reason=reason, db=db,
    )
    return success_response(data=result, message=f"User {action.lower()}d")


# ── Shops ────────────────────────────────────────────────────────────────
@router.get("/shops")
async def list_shops(
    status: str | None = Query(None),
    category: str | None = Query(None),
    search: str | None = Query(None, max_length=200),
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    _: User = Depends(require_admin_permission("shop", "read")),
    db: Session = Depends(get_db),
):
    """Admin shop listing with search + filters + pagination."""
    items, total = admin_service.list_shops_admin(
        db, status=status, category=category, search=search, limit=limit, offset=offset
    )
    return success_response(data={"items": items, "total": total, "limit": limit, "offset": offset})


@router.get("/shops/{shop_id}")
async def get_shop(
    shop_id: int,
    _: User = Depends(require_admin_permission("shop", "read")),
    db: Session = Depends(get_db),
):
    return success_response(data=admin_service.get_shop_admin(db, shop_id))


_SHOP_DECISION_PERMS = {
    "VERIFY": ("shop", "verify"),
    "REJECT": ("shop", "reject"),
    "SUSPEND": ("shop", "suspend"),
    "REACTIVATE": ("shop", "reactivate"),
}


@router.post("/shops/{shop_id}/verification")
async def shop_verification(
    shop_id: int,
    payload: ShopVerificationAction,
    request: Request,
    current_user: User = Depends(require_admin_permission("shop", "verify")),
    db: Session = Depends(get_db),
):
    """VERIFY / REJECT / SUSPEND / REACTIVATE a single shop.

    The specific lifecycle permission is re-checked so a moderator who can
    only verify cannot also suspend.
    """
    from app.core.admin_permissions import has_admin_permission

    resource, action = _SHOP_DECISION_PERMS[payload.decision]
    if not has_admin_permission(_admin_keys(current_user), resource, action):
        raise AppError(f"Missing admin permission: {action}:{resource}", "FORBIDDEN", 403)
    result = _run(
        admin_service.shop_verification_action, request=request,
        admin_user=current_user, shop_id=shop_id, decision=payload.decision,
        reason=payload.reason or payload.notes, db=db,
    )
    return success_response(data=result, message=f"Shop {payload.decision.lower()}d")


@router.post("/shops/bulk")
async def bulk_shop_action_route(
    payload: BulkShopAction,
    current_user: User = Depends(require_admin_permission("shop", "verify")),
    db: Session = Depends(get_db),
):
    """Bulk VERIFY / REJECT / SUSPEND / REACTIVATE shops."""
    result = _run(
        admin_service.bulk_shop_action,
        admin_user=current_user, action=payload.action,
        shop_ids=payload.shop_ids, reason=payload.reason, db=db,
    )
    return success_response(data=result, message="Bulk action applied")

# ── Products ─────────────────────────────────────────────────────────────
@router.get("/products")
async def list_products(
    status: str | None = Query(None),
    category_id: int | None = Query(None),
    brand_id: int | None = Query(None),
    search: str | None = Query(None, max_length=200),
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    _: User = Depends(require_admin_permission("product", "read")),
    db: Session = Depends(get_db),
):
    items, total = admin_service.list_products_admin(
        db, status=status, category_id=category_id, brand_id=brand_id,
        search=search, limit=limit, offset=offset,
    )
    return success_response(data={"items": items, "total": total, "limit": limit, "offset": offset})


@router.put("/products/{product_id}")
async def edit_product(
    product_id: int,
    payload: ProductAdminUpdate,
    current_user: User = Depends(require_admin_permission("product", "update")),
    db: Session = Depends(get_db),
):
    """Authorized field edit on a master product (audited)."""
    result = _run(
        admin_service.update_product_admin,
        product_id=product_id, updates=payload.model_dump(exclude_none=True),
        admin_user=current_user, db=db,
    )
    return success_response(data=result, message="Product updated")


@router.post("/products/bulk")
async def bulk_product_action_route(
    payload: ProductAdminAction,
    current_user: User = Depends(require_admin_permission("product", "approve")),
    db: Session = Depends(get_db),
):
    """Bulk APPROVE / REJECT / ARCHIVE / ACTIVATE master products."""
    result = _run(
        admin_service.product_bulk_action,
        admin_user=current_user, action=payload.action,
        product_ids=payload.product_ids, reason=payload.reason, db=db,
    )
    return success_response(data=result, message=f"Bulk {payload.action.lower()} complete")


@router.get("/products/approvals")
async def approval_queue(
    status: str | None = Query(None),
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    _: User = Depends(require_admin_permission("product", "review")),
    db: Session = Depends(get_db),
):
    items, total = admin_service.product_approval_queue(
        db, status=status, limit=limit, offset=offset
    )
    return success_response(data={"items": items, "total": total, "limit": limit, "offset": offset})


@router.post("/products/listings/{shop_product_id}/review")
async def review_listing(
    shop_product_id: int,
    decision: str = Query(..., pattern="^(APPROVE|REJECT|NEEDS_INFO)$"),
    review_notes: str | None = Query(None, max_length=2000),
    current_user: User = Depends(require_admin_permission("product", "review")),
    db: Session = Depends(get_db),
):
    """Approve / reject / request-info on a shop product listing."""
    result = _run(
        admin_service.review_shop_product,
        shop_product_id=shop_product_id, decision=decision,
        review_notes=review_notes, admin_user=current_user, db=db,
    )
    return success_response(data=result, message=f"Listing {decision.lower()}d")

# ── Categories ───────────────────────────────────────────────────────────
@router.get("/categories")
async def list_categories_route(
    include_inactive: bool = Query(False),
    _: User = Depends(require_admin_permission("category", "read")),
    db: Session = Depends(get_db),
):
    return success_response(
        data={"items": admin_service.list_categories_admin(db, include_inactive=include_inactive)}
    )


@router.post("/categories", status_code=201)
async def create_category_route(
    payload: CategoryAdminCreate,
    current_user: User = Depends(require_admin_permission("category", "create")),
    db: Session = Depends(get_db),
):
    result = _run(
        admin_service.create_category, data=payload.model_dump(),
        admin_user=current_user, db=db,
    )
    return success_response(data=result, message="Category created", status_code=201)


@router.put("/categories/{category_id}")
async def update_category_route(
    category_id: int,
    payload: CategoryAdminUpdate,
    current_user: User = Depends(require_admin_permission("category", "update")),
    db: Session = Depends(get_db),
):
    result = _run(
        admin_service.update_category, category_id=category_id,
        updates=payload.model_dump(exclude_none=True), admin_user=current_user, db=db,
    )
    return success_response(data=result, message="Category updated")


@router.delete("/categories/{category_id}")
async def delete_category_route(
    category_id: int,
    current_user: User = Depends(require_admin_permission("category", "delete")),
    db: Session = Depends(get_db),
):
    result = _run(
        admin_service.delete_category, category_id=category_id,
        admin_user=current_user, db=db,
    )
    return success_response(data=result, message="Category deleted")


# ── Brands ───────────────────────────────────────────────────────────────
@router.get("/brands")
async def list_brands_route(
    include_inactive: bool = Query(False),
    _: User = Depends(require_admin_permission("brand", "read")),
    db: Session = Depends(get_db),
):
    return success_response(
        data={"items": admin_service.list_brands_admin(db, include_inactive=include_inactive)}
    )


@router.post("/brands", status_code=201)
async def create_brand_route(
    payload: BrandAdminCreate,
    current_user: User = Depends(require_admin_permission("brand", "create")),
    db: Session = Depends(get_db),
):
    result = _run(
        admin_service.create_brand, data=payload.model_dump(), admin_user=current_user, db=db,
    )
    return success_response(data=result, message="Brand created", status_code=201)


@router.put("/brands/{brand_id}")
async def update_brand_route(
    brand_id: int,
    payload: BrandAdminUpdate,
    current_user: User = Depends(require_admin_permission("brand", "update")),
    db: Session = Depends(get_db),
):
    result = _run(
        admin_service.update_brand, brand_id=brand_id,
        updates=payload.model_dump(exclude_none=True), admin_user=current_user, db=db,
    )
    return success_response(data=result, message="Brand updated")


# ── Product identifiers ──────────────────────────────────────────────────
@router.get("/identifiers")
async def list_identifiers_route(
    product_master_id: int | None = Query(None),
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    _: User = Depends(require_admin_permission("identifier", "read")),
    db: Session = Depends(get_db),
):
    items, total = admin_service.list_product_identifiers(
        db, product_master_id=product_master_id, limit=limit, offset=offset
    )
    return success_response(data={"items": items, "total": total, "limit": limit, "offset": offset})

# ── Inventory monitoring ─────────────────────────────────────────────────
@router.get("/inventory/summary")
async def inventory_summary_route(
    threshold_hours: int = Query(48, ge=1, le=720),
    _: User = Depends(require_admin_permission("inventory", "read")),
    db: Session = Depends(get_db),
):
    return success_response(
        data=admin_service.inventory_monitoring_summary(db, threshold_hours=threshold_hours)
    )


@router.get("/inventory/stale")
async def stale_inventory_route(
    threshold_hours: int = Query(48, ge=1, le=720),
    shop_id: int | None = Query(None),
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    _: User = Depends(require_admin_permission("inventory", "read")),
    db: Session = Depends(get_db),
):
    items, total = admin_service.stale_inventory(
        db, threshold_hours=threshold_hours, shop_id=shop_id, limit=limit, offset=offset
    )
    return success_response(data={"items": items, "total": total, "limit": limit, "offset": offset})


@router.get("/inventory/missing-prices")
async def missing_prices_route(
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    _: User = Depends(require_admin_permission("inventory", "read")),
    db: Session = Depends(get_db),
):
    items, total = admin_service.missing_prices(db, limit=limit, offset=offset)
    return success_response(data={"items": items, "total": total, "limit": limit, "offset": offset})


@router.get("/inventory/anomalies")
async def availability_anomalies_route(
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    _: User = Depends(require_admin_permission("inventory", "read")),
    db: Session = Depends(get_db),
):
    items, total = admin_service.availability_anomalies(db, limit=limit, offset=offset)
    return success_response(data={"items": items, "total": total, "limit": limit, "offset": offset})


@router.get("/inventory/sync-failures")
async def sync_failures_route(
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    _: User = Depends(require_admin_permission("inventory", "read")),
    db: Session = Depends(get_db),
):
    items, total = admin_service.sync_failures(db, limit=limit, offset=offset)
    return success_response(data={"items": items, "total": total, "limit": limit, "offset": offset})

# ── Offers / Subscriptions / Payments ────────────────────────────────────
@router.get("/offers")
async def list_offers_route(
    status: str | None = Query(None),
    shop_id: int | None = Query(None),
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    _: User = Depends(require_admin_permission("offer", "read")),
    db: Session = Depends(get_db),
):
    items, total = admin_service.list_offers_admin(
        db, status=status, shop_id=shop_id, limit=limit, offset=offset
    )
    return success_response(data={"items": items, "total": total, "limit": limit, "offset": offset})


@router.post("/offers/{offer_id}/status")
async def update_offer_status_route(
    offer_id: int,
    new_status: str = Query(..., pattern="^(ACTIVE|PAUSED|CANCELLED)$"),
    current_user: User = Depends(require_admin_permission("offer", "update")),
    db: Session = Depends(get_db),
):
    result = _run(
        admin_service.update_offer_status, offer_id=offer_id,
        new_status=new_status, admin_user=current_user, db=db,
    )
    return success_response(data=result, message=f"Offer moved to {new_status}")


@router.get("/subscriptions")
async def list_subscriptions_route(
    status: str | None = Query(None),
    plan_id: int | None = Query(None),
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    _: User = Depends(require_admin_permission("subscription", "read")),
    db: Session = Depends(get_db),
):
    items, total = admin_service.list_subscriptions_admin(
        db, status=status, plan_id=plan_id, limit=limit, offset=offset
    )
    return success_response(data={"items": items, "total": total, "limit": limit, "offset": offset})


@router.put("/subscriptions/{subscription_id}")
async def update_subscription_route(
    subscription_id: int,
    payload: SubscriptionAdminUpdate,
    current_user: User = Depends(require_admin_permission("subscription", "update")),
    db: Session = Depends(get_db),
):
    result = _run(
        admin_service.update_subscription_admin, subscription_id=subscription_id,
        updates=payload.model_dump(exclude_none=True), admin_user=current_user, db=db,
    )
    return success_response(data=result, message="Subscription updated")


@router.get("/payments")
async def list_payments_route(
    status: str | None = Query(None),
    provider: str | None = Query(None),
    method: str | None = Query(None),
    subscription_id: int | None = Query(None),
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    _: User = Depends(require_admin_permission("payment", "read")),
    db: Session = Depends(get_db),
):
    items, total = admin_service.list_payments_admin(
        db, status=status, provider=provider, method=method,
        subscription_id=subscription_id, limit=limit, offset=offset,
    )
    return success_response(data={"items": items, "total": total, "limit": limit, "offset": offset})


# ── Reports & Analytics ──────────────────────────────────────────────────
@router.post("/reports/generate")
async def generate_report_route(
    payload: ReportGenerateRequest,
    current_user: User = Depends(require_admin_permission("report", "generate")),
    db: Session = Depends(get_db),
):
    result = _run(
        admin_service.generate_report,
        report_type=payload.report_type, report_name=payload.report_name,
        date_from=payload.date_from, date_to=payload.date_to,
        filters=payload.filters, admin_user=current_user, db=db,
    )
    return success_response(data=result, message="Report generated")


@router.get("/reports")
async def list_reports_route(
    report_type: str | None = Query(None),
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    _: User = Depends(require_admin_permission("report", "read")),
    db: Session = Depends(get_db),
):
    items, total = admin_service.list_reports(
        db, report_type=report_type, limit=limit, offset=offset
    )
    return success_response(data={"items": items, "total": total, "limit": limit, "offset": offset})


@router.get("/analytics/summary")
async def analytics_summary_route(
    days: int = Query(30, ge=1, le=365),
    _: User = Depends(require_admin_permission("analytics", "read")),
    db: Session = Depends(get_db),
):
    return success_response(data=admin_service.analytics_summary(db, days=days))

# ── Complaints ───────────────────────────────────────────────────────────
@router.get("/complaints")
async def list_complaints_route(
    status: str | None = Query(None),
    priority: str | None = Query(None),
    complaint_type: str | None = Query(None),
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    _: User = Depends(require_admin_permission("complaint", "read")),
    db: Session = Depends(get_db),
):
    items, total = admin_service.list_complaints(
        db, status=status, priority=priority, complaint_type=complaint_type,
        limit=limit, offset=offset,
    )
    return success_response(data={"items": items, "total": total, "limit": limit, "offset": offset})


@router.put("/complaints/{complaint_id}")
async def update_complaint_route(
    complaint_id: int,
    payload: ComplaintUpdate,
    current_user: User = Depends(require_admin_permission("complaint", "update")),
    db: Session = Depends(get_db),
):
    result = _run(
        admin_service.update_complaint, complaint_id=complaint_id,
        updates=payload.model_dump(exclude_none=True), admin_user=current_user, db=db,
    )
    return success_response(data=result, message="Complaint updated")


# ── Notifications (admin) ────────────────────────────────────────────────
@router.post("/notifications/send")
async def send_notification_route(
    payload: AdminNotificationCreate,
    current_user: User = Depends(require_admin_permission("notification", "create")),
    db: Session = Depends(get_db),
):
    result = _run(
        admin_service.send_admin_notification,
        title=payload.title, body=payload.body,
        notification_type=payload.notification_type,
        target_user_ids=payload.target_user_ids,
        target_role=payload.target_role,
        admin_user=current_user, db=db,
    )
    return success_response(data=result, message="Notification sent")

# ── System settings ──────────────────────────────────────────────────────
@router.get("/settings")
async def list_settings_route(
    _: User = Depends(require_admin_permission("system_setting", "read")),
    db: Session = Depends(get_db),
):
    return success_response(data={"items": admin_service.list_system_settings(db)})


@router.put("/settings/{key}")
async def upsert_setting_route(
    key: str,
    value: str = Query(..., max_length=5000),
    value_type: str = Query("string", pattern="^(string|int|float|boolean|json)$"),
    description: str | None = Query(None, max_length=2000),
    is_secret: bool = Query(False),
    current_user: User = Depends(require_admin_permission("system_setting", "update")),
    db: Session = Depends(get_db),
):
    result = _run(
        admin_service.upsert_system_setting, key=key, value=value,
        value_type=value_type, description=description, is_secret=is_secret,
        admin_user=current_user, db=db,
    )
    return success_response(data=result, message="Setting saved")


@router.delete("/settings/{key}")
async def delete_setting_route(
    key: str,
    current_user: User = Depends(require_admin_permission("system_setting", "update")),
    db: Session = Depends(get_db),
):
    result = _run(admin_service.delete_system_setting, key=key, admin_user=current_user, db=db)
    return success_response(data=result, message="Setting deleted")


# ── Feature flags ────────────────────────────────────────────────────────
@router.get("/feature-flags")
async def list_flags_route(
    _: User = Depends(require_admin_permission("feature_flag", "read")),
    db: Session = Depends(get_db),
):
    return success_response(data={"items": admin_service.list_feature_flags(db)})


@router.put("/feature-flags/{name}")
async def upsert_flag_route(
    name: str,
    is_enabled: bool = Query(False),
    rollout_percentage: int = Query(100, ge=0, le=100),
    scope: str = Query("GLOBAL", pattern="^(GLOBAL|SHOP|USER|REGION)$"),
    description: str | None = Query(None, max_length=2000),
    current_user: User = Depends(require_admin_permission("feature_flag", "update")),
    db: Session = Depends(get_db),
):
    result = _run(
        admin_service.upsert_feature_flag, name=name, is_enabled=is_enabled,
        rollout_percentage=rollout_percentage, scope=scope, description=description,
        admin_user=current_user, db=db,
    )
    return success_response(data=result, message="Flag saved")


@router.delete("/feature-flags/{name}")
async def delete_flag_route(
    name: str,
    current_user: User = Depends(require_admin_permission("feature_flag", "update")),
    db: Session = Depends(get_db),
):
    result = _run(admin_service.delete_feature_flag, name=name, admin_user=current_user, db=db)
    return success_response(data=result, message="Flag deleted")

# ── Governance: audit logs / actions / notes ────────────────────────────
@router.get("/audit-logs")
async def audit_logs_route(
    action: str | None = Query(None),
    entity_type: str | None = Query(None),
    entity_id: int | None = Query(None),
    user_id: int | None = Query(None),
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    _: User = Depends(require_admin_permission("audit_log", "read")),
    db: Session = Depends(get_db),
):
    items, total = admin_service.list_audit_logs(
        db, action=action, entity_type=entity_type, entity_id=entity_id,
        user_id=user_id, limit=limit, offset=offset,
    )
    return success_response(data={"items": items, "total": total, "limit": limit, "offset": offset})


@router.get("/actions")
async def admin_actions_route(
    action_type: str | None = Query(None),
    target_type: str | None = Query(None),
    target_id: int | None = Query(None),
    admin_user_id: int | None = Query(None),
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    _: User = Depends(require_admin_permission("admin_action", "read")),
    db: Session = Depends(get_db),
):
    items, total = admin_service.list_admin_actions(
        db, action_type=action_type, target_type=target_type, target_id=target_id,
        admin_user_id=admin_user_id, limit=limit, offset=offset,
    )
    return success_response(data={"items": items, "total": total, "limit": limit, "offset": offset})


# ── Admin notes ──────────────────────────────────────────────────────────
@router.post("/notes", status_code=201)
async def create_note_route(
    payload: AdminNoteCreate,
    current_user: User = Depends(require_admin_permission("admin_note", "create")),
    db: Session = Depends(get_db),
):
    result = _run(
        admin_service.create_admin_note,
        entity_type=payload.entity_type, entity_id=payload.entity_id,
        note=payload.note, is_private=payload.is_private,
        admin_user=current_user, db=db,
    )
    return success_response(data=result, message="Note created", status_code=201)


@router.get("/notes")
async def list_notes_route(
    entity_type: str | None = Query(None),
    entity_id: int | None = Query(None),
    admin_user_id: int | None = Query(None),
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    _: User = Depends(require_admin_permission("admin_note", "read")),
    db: Session = Depends(get_db),
):
    items, total = admin_service.list_admin_notes(
        db, entity_type=entity_type, entity_id=entity_id,
        admin_user_id=admin_user_id, limit=limit, offset=offset,
    )
    return success_response(data={"items": items, "total": total, "limit": limit, "offset": offset})


@router.put("/notes/{note_id}")
async def update_note_route(
    note_id: int,
    note: str | None = Query(None, max_length=5000),
    is_private: bool | None = Query(None),
    current_user: User = Depends(require_admin_permission("admin_note", "update")),
    db: Session = Depends(get_db),
):
    if note is None and is_private is None:
        from app.core.exceptions import ValidationError

        raise ValidationError("Nothing to update")
    result = _run(
        admin_service.update_admin_note, note_id=note_id,
        updates={"note": note, "is_private": is_private}, admin_user=current_user, db=db,
    )
    return success_response(data=result, message="Note updated")


@router.delete("/notes/{note_id}")
async def delete_note_route(
    note_id: int,
    current_user: User = Depends(require_admin_permission("admin_note", "delete")),
    db: Session = Depends(get_db),
):
    result = _run(admin_service.delete_admin_note, note_id=note_id, admin_user=current_user, db=db)
    return success_response(data=result, message="Note deleted")