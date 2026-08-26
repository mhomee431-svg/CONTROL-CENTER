"""Phase 26 â€” Admin Platform business logic.

Every critical operation funnels through :func:`record_audit_log` and
:func:`record_admin_action`, so the platform governance trail is complete.

Business rules are enforced here (never bypassed):
  * Shop lifecycle transitions validate the current status first.
  * Product approval transitions validate the approval's current state.
  * Complaint resolution requires resolution notes.
  * Offers cannot be re-activated after expiry.
  * Admins cannot suspend/ban other admins.
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.exceptions import ConflictError, NotFoundError, ValidationError
from app.models.admin import (
    AdminAction,
    AdminNote,
    ApprovalStatus,
    AuditLog,
    Complaint,
    ComplaintStatus,
    Report,
)
from app.models.product import (
    Brand,
    Category,
    Inventory,
    Offer,
    OfferStatus,
    ProductIdentifier,
    ProductMaster,
    ProductStatus,
    ShopProduct,
)
from app.models.search import SearchEvent, SearchHistory
from app.models.shop import Shop, ShopStatus
from app.models.subscription import Payment, Subscription, SubscriptionPlan, SubscriptionStatus
from app.models.system import FeatureFlag, SystemSetting
from app.models.user import User, UserStatus
from app.models.analytics import ProductClick, ProductView, ShopView

logger = logging.getLogger("app.services.admin_service")


# â”€â”€ Serialization helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
def _json_safe(value: Any) -> Any:
    """Convert a value into a JSON-serializable representation."""
    if value is None or isinstance(value, (bool, int, float, str)):
        return value
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, dict):
        return {str(k): _json_safe(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_json_safe(v) for v in value]
    try:
        return str(value.value)  # enums
    except AttributeError:
        return str(value)


def serialize_model(obj: Any) -> dict:
    """Serialize a SQLAlchemy model row into a JSON-safe dict."""
    out: dict[str, Any] = {}
    for column in obj.__table__.columns:
        out[column.name] = _json_safe(getattr(obj, column.name))
    return out


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


# â”€â”€ Governance: audit trail â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
def record_audit_log(
    db: Session,
    *,
    user_id: int | None,
    action: str,
    entity_type: str,
    entity_id: int | None = None,
    old_values: dict | None = None,
    new_values: dict | None = None,
    description: str | None = None,
    ip_address: str | None = None,
    user_agent: str | None = None,
    request_id: str | None = None,
) -> AuditLog:
    """Persist an immutable audit record. Called on EVERY critical operation."""
    entry = AuditLog(
        user_id=user_id,
        action=action,
        entity_type=entity_type,
        entity_id=entity_id,
        old_values=old_values,
        new_values=new_values,
        description=description,
        ip_address=ip_address,
        user_agent=user_agent,
        request_id=request_id,
    )
    db.add(entry)
    db.flush()
    return entry


def record_admin_action(
    db: Session,
    *,
    admin_user_id: int,
    action_type: str,
    target_type: str,
    target_id: int,
    action_data: dict | None = None,
    description: str | None = None,
    ip_address: str | None = None,
) -> AdminAction:
    """Record a discrete admin operation (companion to the audit log)."""
    record = AdminAction(
        admin_user_id=admin_user_id,
        action_type=action_type,
        target_type=target_type,
        target_id=target_id,
        action_data=action_data,
        description=description,
        ip_address=ip_address,
        performed_at=_utcnow(),
    )
    db.add(record)
    db.flush()
    return record


# â”€â”€ Dashboard â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
def dashboard_metrics(db: Session) -> dict:
    """Aggregate platform-wide metrics for the admin dashboard."""
    now = _utcnow()

    total_customers = db.query(func.count(User.id)).filter(User.is_deleted == False).scalar() or 0  # noqa: E712

    total_shops = db.query(func.count(Shop.id)).filter(Shop.is_deleted == False).scalar() or 0  # noqa: E712
    active_shops = (
        db.query(func.count(Shop.id))
        .filter(Shop.is_deleted == False, Shop.status.in_([ShopStatus.ACTIVE, ShopStatus.VERIFIED]))  # noqa: E712
        .scalar() or 0
    )
    pending_verification = (
        db.query(func.count(Shop.id))
        .filter(
            Shop.is_deleted == False,  # noqa: E712
            Shop.status.in_([ShopStatus.PENDING_VERIFICATION, ShopStatus.DOCUMENTS_SUBMITTED]),
        )
        .scalar() or 0
    )

    total_products = (
        db.query(func.count(ProductMaster.id)).filter(ProductMaster.is_deleted == False).scalar() or 0  # noqa: E712
    )
    total_inventory_records = db.query(func.count(Inventory.id)).scalar() or 0

    # Search metrics (SearchEvent preferred; fall back to history rows)
    total_searches = db.query(func.count(SearchEvent.id)).scalar() or 0
    if total_searches:
        successful_searches = (
            db.query(func.count(SearchEvent.id)).filter(SearchEvent.result_count > 0).scalar() or 0
        )
    else:
        total_searches = db.query(func.count(SearchHistory.id)).scalar() or 0
        successful_searches = (
            db.query(func.count(SearchHistory.id))
            .filter(SearchHistory.is_successful == True)  # noqa: E712
            .scalar() or 0
        )
    search_success_rate = round(successful_searches / total_searches, 4) if total_searches else 0.0

    # Popular categories (products per category)
    cat_rows = (
        db.query(Category.name, func.count(ProductMaster.id).label("product_count"))
        .join(ProductMaster, ProductMaster.category_id == Category.id)
        .filter(ProductMaster.is_deleted == False)  # noqa: E712
        .group_by(Category.id, Category.name)
        .order_by(func.count(ProductMaster.id).desc())
        .limit(5)
        .all()
    )
    popular_categories = [
        {"name": name, "product_count": int(count)} for name, count in cat_rows
    ]

    # Subscription metrics
    active_subscriptions = (
        db.query(func.count(Subscription.id))
        .filter(Subscription.status == SubscriptionStatus.ACTIVE)
        .scalar() or 0
    )
    revenue_row = (
        db.query(func.coalesce(func.sum(Payment.amount), 0.0))
        .filter(Payment.status == "SUCCESS")
        .scalar()
    )
    total_revenue = float(revenue_row or 0.0)

    pending_approvals = (
        db.query(func.count(ShopProduct.id))
        .join(Shop, ShopProduct.shop_id == Shop.id)
        .filter(
            ShopProduct.status == "PENDING_REVIEW",
            Shop.is_deleted == False,  # noqa: E712
        )
        .scalar() or 0
    )
    open_complaints = (
        db.query(func.count(Complaint.id))
        .filter(Complaint.status.in_([ComplaintStatus.OPEN, ComplaintStatus.IN_PROGRESS]))
        .scalar() or 0
    )
    stale_count = (
        db.query(func.count(Inventory.id))
        .filter(Inventory.freshness_status == "STALE")
        .scalar() or 0
    )
    missing_price_count = (
        db.query(func.count(ShopProduct.id))
        .filter(ShopProduct.price.is_(None))
        .scalar() or 0
    )

    return {
        "total_customers": total_customers,
        "total_shops": total_shops,
        "active_shops": active_shops,
        "pending_verification": pending_verification,
        "total_products": total_products,
        "total_inventory_records": total_inventory_records,
        "total_searches": total_searches,
        "search_success_rate": search_success_rate,
        "popular_categories": popular_categories,
        "active_subscriptions": active_subscriptions,
        "total_subscription_revenue": round(total_revenue, 2),
        "pending_approvals": pending_approvals,
        "open_complaints": open_complaints,
        "stale_inventory_count": stale_count,
        "products_missing_prices": missing_price_count,
        "generated_at": now.isoformat(),
    }


# â”€â”€ Customers / Shopkeepers / Users â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
def list_users(
    db: Session,
    *,
    role_name: str | None = None,
    status: str | None = None,
    search: str | None = None,
    limit: int = 50,
    offset: int = 0,
) -> tuple[list[dict], int]:
    """List users with role/status filters, search, and pagination."""
    from app.models.role import Role

    query = db.query(User).filter(User.is_deleted == False)  # noqa: E712
    if role_name:
        query = query.join(Role, User.role_id == Role.id).filter(Role.name == role_name)
    if status:
        try:
            query = query.filter(User.status == UserStatus(status))
        except ValueError as exc:
            raise ValidationError(f"Invalid user status: {status}") from exc
    if search:
        like = f"%{search}%"
        query = query.filter(
            (User.name.ilike(like)) | (User.phone_number.ilike(like)) | (User.email.ilike(like))
        )
    total = query.count()
    rows = query.order_by(User.id).offset(offset).limit(limit).all()
    items = []
    for u in rows:
        data = serialize_model(u)
        data["role"] = u.role.name if u.role is not None else None
        # Never leak secrets through admin listings.
        data.pop("password_hash", None)
        items.append(data)
    return items, total


_USER_STATUS_ACTIONS = {
    "SUSPEND": UserStatus.SUSPENDED,
    "BAN": UserStatus.BANNED,
    "ACTIVATE": UserStatus.ACTIVE,
}


def update_user_status(
    db: Session,
    *,
    admin_user: User,
    user_id: int,
    action: str,
    reason: str | None = None,
    ip_address: str | None = None,
) -> dict:
    """Suspend / ban / re-activate a user account.

    Business rules enforced:
      * Target must exist and not be soft-deleted.
      * Admins can never target other admins.
      * SUSPEND/BAN require a reason.
    """
    target = db.query(User).filter(User.id == user_id, User.is_deleted == False).first()  # noqa: E712
    if target is None:
        raise NotFoundError("User not found")
    if action not in _USER_STATUS_ACTIONS:
        raise ValidationError(f"Invalid action: {action}")
    if target.role is not None and target.role.name == "admin":
        raise ValidationError("Admin accounts cannot be suspended via this operation")
    if action in ("SUSPEND", "BAN") and not reason:
        raise ValidationError(f"A reason is required to {action.lower()} a user")

    old_status = serialize_model(target)["status"]
    target.status = _USER_STATUS_ACTIONS[action]
    target.is_active = action == "ACTIVATE"

    record_audit_log(
        db,
        user_id=admin_user.id,
        action=action,
        entity_type="USER",
        entity_id=target.id,
        old_values={"status": old_status},
        new_values={"status": target.status.value, "reason": reason},
        description=f"Admin {action} user {target.id}: {reason or ''}",
    )
    record_admin_action(
        db,
        admin_user_id=admin_user.id,
        action_type=action,
        target_type="USER",
        target_id=target.id,
        action_data={"reason": reason},
        description=reason,
        ip_address=ip_address,
    )
    return serialize_model(target)

# â”€â”€ Shop management â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
def list_shops_admin(
    db: Session,
    *,
    status: str | None = None,
    category: str | None = None,
    search: str | None = None,
    city: str | None = None,
    limit: int = 50,
    offset: int = 0,
) -> tuple[list[dict], int]:
    """Admin shop listing with search + filters + pagination."""
    query = db.query(Shop).filter(Shop.is_deleted == False)  # noqa: E712
    if status:
        try:
            query = query.filter(Shop.status == ShopStatus(status))
        except ValueError as exc:
            raise ValidationError(f"Invalid shop status: {status}") from exc
    if category:
        query = query.filter(Shop.category == category)
    if search:
        like = f"%{search}%"
        query = query.filter((Shop.name.ilike(like)) | (Shop.description.ilike(like)))
    total = query.count()
    rows = query.order_by(Shop.id).offset(offset).limit(limit).all()
    return [serialize_model(s) for s in rows], total


def get_shop_admin(db: Session, shop_id: int) -> dict:
    """Full shop detail for the admin panel."""
    shop = db.query(Shop).filter(Shop.id == shop_id, Shop.is_deleted == False).first()  # noqa: E712
    if shop is None:
        raise NotFoundError("Shop not found")
    return serialize_model(shop)


#: Allowed lifecycle transitions per decision â€” business rules table.
_SHOP_TRANSITIONS = {
    "VERIFY": {
        ShopStatus.REGISTERED, ShopStatus.DOCUMENTS_SUBMITTED,
        ShopStatus.PENDING_VERIFICATION, ShopStatus.REJECTED,
    },
    "REJECT": {
        ShopStatus.REGISTERED, ShopStatus.DOCUMENTS_SUBMITTED,
        ShopStatus.PENDING_VERIFICATION, ShopStatus.VERIFIED, ShopStatus.ACTIVE,
    },
    "SUSPEND": {ShopStatus.VERIFIED, ShopStatus.ACTIVE},
    "REACTIVATE": {ShopStatus.SUSPENDED},
}


def shop_verification_action(
    db: Session,
    *,
    admin_user: User,
    shop_id: int,
    decision: str,
    reason: str | None = None,
    ip_address: str | None = None,
) -> dict:
    """Apply VERIFY / REJECT / SUSPEND / REACTIVATE to a shop.

    Enforces the lifecycle transition table and mandatory reasons for
    REJECT and SUSPEND; every call writes an AuditLog + AdminAction pair.
    """
    shop = db.query(Shop).filter(Shop.id == shop_id, Shop.is_deleted == False).first()  # noqa: E712
    if shop is None:
        raise NotFoundError("Shop not found")
    if decision not in _SHOP_TRANSITIONS:
        raise ValidationError(f"Invalid decision: {decision}")
    current_status = (
        shop.status if isinstance(shop.status, ShopStatus) else ShopStatus(shop.status)
    )
    if current_status not in _SHOP_TRANSITIONS[decision]:
        raise ConflictError(
            f"Cannot {decision.lower()} a shop with status {current_status.value}"
        )
    if decision in ("REJECT", "SUSPEND") and not reason:
        raise ValidationError(f"A reason is required to {decision.lower()} a shop")

    now = _utcnow()
    old_values = {"status": current_status.value}
    new_values: dict[str, Any] = {"status": current_status.value}

    if decision == "VERIFY":
        shop.status = ShopStatus.VERIFIED
        shop.verified_at = now
        new_values["status"] = "VERIFIED"
    elif decision == "REJECT":
        shop.status = ShopStatus.REJECTED
        shop.rejection_reason = reason
        new_values.update({"status": "REJECTED", "rejection_reason": reason})
    elif decision == "SUSPEND":
        shop.status = ShopStatus.SUSPENDED
        shop.suspended_at = now
        shop.suspension_reason = reason
        shop.is_accepting_orders = False
        new_values.update({"status": "SUSPENDED", "suspension_reason": reason})
    else:  # REACTIVATE
        shop.status = ShopStatus.ACTIVE
        shop.reactivated_at = now
        shop.suspension_reason = None
        shop.is_accepting_orders = True
        new_values.update({"status": "ACTIVE", "reactivated_at": now.isoformat()})
    shop.updated_at = now

    record_audit_log(
        db,
        user_id=admin_user.id,
        action=decision,
        entity_type="SHOP",
        entity_id=shop.id,
        old_values=old_values,
        new_values=new_values,
        description=f"Shop {shop_id} {decision}: {reason or ''}",
        ip_address=ip_address,
    )
    record_admin_action(
        db,
        admin_user_id=admin_user.id,
        action_type=decision,
        target_type="SHOP",
        target_id=shop.id,
        action_data=new_values,
        description=reason,
        ip_address=ip_address,
    )

    # Phase 27 — notify every owner of the verification decision.
    try:
        from app.models.shop import ShopOwner
        from app.services import notification_service

        owner_ids = [
            row[0]
            for row in db.query(ShopOwner.user_id).filter(ShopOwner.shop_id == shop.id).all()
        ]
        for owner_id in owner_ids:
            notification_service.notify_shop_verification(
                db,
                shopkeeper_user_id=owner_id,
                shop_id=shop.id,
                decision=decision,
                reason=reason,
            )
    except Exception:  # noqa: BLE001 — notifications must never break governance flows
        logging.getLogger(__name__).warning(
            "Failed to notify owners of shop %s about %s decision", shop.id, decision
        )
    return serialize_model(shop)



def bulk_shop_action(
    db: Session,
    *,
    admin_user: User,
    action: str,
    shop_ids: list[int],
    reason: str | None = None,
    ip_address: str | None = None,
) -> dict:
    """Apply a lifecycle decision to many shops; per-shop results returned.

    Shops whose current status forbids the transition are reported as
    ``skipped`` â€” the batch never aborts, and no partial state is committed
    for skipped shops.
    """
    if action not in _SHOP_TRANSITIONS:
        raise ValidationError(f"Invalid action: {action}")
    results: dict[str, list] = {"updated": [], "skipped": [], "missing": []}
    for sid in shop_ids:
        try:
            shop_verification_action(
                db, admin_user=admin_user, shop_id=sid, decision=action,
                reason=reason, ip_address=ip_address,
            )
            results["updated"].append(sid)
        except ConflictError:
            results["skipped"].append(sid)
        except NotFoundError:
            results["missing"].append(sid)
    return results


# â”€â”€ Product management â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
_PRODUCT_TRANSITIONS = {
    "APPROVE": {ProductStatus.PENDING_REVIEW, ProductStatus.REJECTED},
    "REJECT": {ProductStatus.PENDING_REVIEW},
    "ARCHIVE": {
        ProductStatus.DRAFT, ProductStatus.APPROVED, ProductStatus.REJECTED,
        ProductStatus.INACTIVE,
    },
    "ACTIVATE": {ProductStatus.ARCHIVED, ProductStatus.INACTIVE},
}


def list_products_admin(
    db: Session,
    *,
    status: str | None = None,
    category_id: int | None = None,
    brand_id: int | None = None,
    search: str | None = None,
    limit: int = 50,
    offset: int = 0,
) -> tuple[list[dict], int]:
    """Admin product listing with filters, search and pagination."""
    query = db.query(ProductMaster).filter(ProductMaster.is_deleted == False)  # noqa: E712
    if status:
        try:
            query = query.filter(ProductMaster.status == ProductStatus(status))
        except ValueError as exc:
            raise ValidationError(f"Invalid product status: {status}") from exc
    if category_id is not None:
        query = query.filter(ProductMaster.category_id == category_id)
    if brand_id is not None:
        query = query.filter(ProductMaster.brand_id == brand_id)
    if search:
        like = f"%{search}%"
        query = query.filter(ProductMaster.name.ilike(like))
    total = query.count()
    rows = query.order_by(ProductMaster.id).offset(offset).limit(limit).all()
    return [serialize_model(p) for p in rows], total



def product_bulk_action(
    db: Session,
    *,
    admin_user: User,
    action: str,
    product_ids: list[int],
    reason: str | None = None,
    ip_address: str | None = None,
) -> dict:
    """Bulk APPROVE / REJECT / ARCHIVE / ACTIVATE on master products.

    Enforces :data:`_PRODUCT_TRANSITIONS`; invalid transitions are skipped,
    missing products are reported. Every applied change is audited.
    """
    if action not in _PRODUCT_TRANSITIONS:
        raise ValidationError(f"Invalid action: {action}")
    allowed = _PRODUCT_TRANSITIONS[action]
    new_status = {
        "APPROVE": ProductStatus.APPROVED,
        "REJECT": ProductStatus.REJECTED,
        "ARCHIVE": ProductStatus.ARCHIVED,
        "ACTIVATE": ProductStatus.APPROVED,
    }[action]

    results: dict[str, list] = {"updated": [], "skipped": [], "missing": []}
    for pid in product_ids:
        product = (
            db.query(ProductMaster)
            .filter(ProductMaster.id == pid, ProductMaster.is_deleted == False)  # noqa: E712
            .first()
        )
        if product is None:
            results["missing"].append(pid)
            continue
        current = (
            product.status
            if isinstance(product.status, ProductStatus)
            else ProductStatus(product.status)
        )
        if current not in allowed:
            results["skipped"].append(pid)
            continue
        old_values = {"status": current.value}
        product.status = new_status
        record_audit_log(
            db,
            user_id=admin_user.id,
            action=action,
            entity_type="PRODUCT",
            entity_id=product.id,
            old_values=old_values,
            new_values={"status": new_status.value, "reason": reason},
            description=f"Product {pid} bulk {action}: {reason or ''}",
            ip_address=ip_address,
        )
        record_admin_action(
            db,
            admin_user_id=admin_user.id,
            action_type=action,
            target_type="PRODUCT",
            target_id=product.id,
            action_data={"reason": reason},
            description=reason,
            ip_address=ip_address,
        )
        results["updated"].append(pid)
    return results


def update_product_admin(
    db: Session,
    *,
    admin_user: User,
    product_id: int,
    updates: dict,
    ip_address: str | None = None,
) -> dict:
    """Authorized field edit on a master product with full before/after audit."""
    product = (
        db.query(ProductMaster)
        .filter(ProductMaster.id == product_id, ProductMaster.is_deleted == False)  # noqa: E712
        .first()
    )
    if product is None:
        raise NotFoundError("Product not found")

    allowed_fields = {
        "name", "description", "short_description", "category_id",
        "subcategory_id", "brand_id", "is_active",
    }
    old_values: dict[str, Any] = {}
    new_values: dict[str, Any] = {}
    for field, value in updates.items():
        if field not in allowed_fields or value is None:
            continue
        old_values[field] = _json_safe(getattr(product, field))
        setattr(product, field, value)
        new_values[field] = _json_safe(value)
    if not new_values:
        raise ValidationError("No authorized fields to update")
    product.updated_at = _utcnow()

    record_audit_log(
        db,
        user_id=admin_user.id,
        action="UPDATE",
        entity_type="PRODUCT",
        entity_id=product.id,
        old_values=old_values,
        new_values=new_values,
        description=f"Admin edited product {product_id}",
        ip_address=ip_address,
    )
    record_admin_action(
        db,
        admin_user_id=admin_user.id,
        action_type="EDIT_PRODUCT",
        target_type="PRODUCT",
        target_id=product.id,
        action_data=new_values,
        ip_address=ip_address,
    )
    return serialize_model(product)


def product_approval_queue(
    db: Session,
    *,
    status: str | None = None,
    limit: int = 50,
    offset: int = 0,
) -> tuple[list[dict], int]:
    """ProductApproval records pending (or filtered by status) for review."""
    query = db.query(ShopProduct).filter(
        ShopProduct.status.in_(["PENDING_REVIEW", "NEEDS_INFO"])
        if status in (None, "PENDING")
        else ShopProduct.status == status
    )
    total = query.count()
    rows = query.order_by(ShopProduct.id).offset(offset).limit(limit).all()
    items = []
    for sp in rows:
        item = serialize_model(sp)
        pm = db.query(ProductMaster).filter(ProductMaster.id == sp.product_master_id).first()
        item["product_name"] = pm.name if pm else None
        shop = db.query(Shop).filter(Shop.id == sp.shop_id).first()
        item["shop_name"] = shop.name if shop else None
        items.append(item)
    return items, total



def review_shop_product(
    db: Session,
    *,
    admin_user: User,
    shop_product_id: int,
    decision: str,
    review_notes: str | None = None,
    ip_address: str | None = None,
) -> dict:
    """Approve / reject / request-info on a shop's product listing.

    Business rules:
      * Only PENDING_REVIEW or NEEDS_INFO listings are reviewable.
      * APPROVE auto-promotes a PENDING_REVIEW master product to keep the
        shared catalog consistent with the decision.
      * REJECT requires review notes.
      * Every decision writes a ProductApproval record + audit pair.
    """
    from app.models.admin import ProductApproval

    sp = db.query(ShopProduct).filter(ShopProduct.id == shop_product_id).first()
    if sp is None:
        raise NotFoundError("Shop product listing not found")
    if decision not in ("APPROVE", "REJECT", "NEEDS_INFO"):
        raise ValidationError(f"Invalid decision: {decision}")
    current_status = sp.status if isinstance(sp.status, str) else str(
        getattr(sp.status, "value", sp.status)
    )
    if current_status not in ("PENDING_REVIEW", "NEEDS_INFO"):
        raise ConflictError(f"Listing already reviewed (status {current_status})")
    if decision == "REJECT" and not review_notes:
        raise ValidationError("Rejection requires review notes")

    pm = db.query(ProductMaster).filter(ProductMaster.id == sp.product_master_id).first()
    if decision == "APPROVE" and pm is not None:
        pm_status = (
            pm.status if isinstance(pm.status, ProductStatus) else ProductStatus(pm.status)
        )
        if pm_status == ProductStatus.PENDING_REVIEW:
            pm.status = ProductStatus.APPROVED

    new_status = {"APPROVE": "APPROVED", "REJECT": "REJECTED", "NEEDS_INFO": "NEEDS_INFO"}[decision]
    old_values = {"status": current_status}
    sp.status = new_status

    approval = ProductApproval(
        product_master_id=sp.product_master_id,
        shop_id=sp.shop_id,
        status={
            "APPROVE": ApprovalStatus.APPROVED,
            "REJECT": ApprovalStatus.REJECTED,
            "NEEDS_INFO": ApprovalStatus.NEEDS_INFO,
        }[decision],
        requested_by=None,
        reviewed_by=admin_user.id,
        review_notes=review_notes,
        submitted_at=sp.created_at,
        reviewed_at=_utcnow(),
    )
    db.add(approval)

    record_audit_log(
        db,
        user_id=admin_user.id,
        action=decision,
        entity_type="SHOP_PRODUCT",
        entity_id=sp.id,
        old_values=old_values,
        new_values={"status": new_status, "review_notes": review_notes},
        description=f"Listing {shop_product_id} {decision}: {review_notes or ''}",
        ip_address=ip_address,
    )
    record_admin_action(
        db,
        admin_user_id=admin_user.id,
        action_type=f"{decision}_PRODUCT",
        target_type="SHOP_PRODUCT",
        target_id=sp.id,
        action_data={"review_notes": review_notes, "approval_id": approval.id},
        ip_address=ip_address,
    )
    return serialize_model(sp)

# â”€â”€ Categories â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
def list_categories_admin(db: Session, *, include_inactive: bool = False) -> list[dict]:
    query = db.query(Category).filter(Category.is_deleted == False)  # noqa: E712
    if not include_inactive:
        query = query.filter(Category.is_active == True)  # noqa: E712
    return [serialize_model(c) for c in query.order_by(Category.sort_order).all()]


def create_category(db: Session, *, admin_user: User, data: dict) -> dict:
    """Create a category (unique name + slug enforced)."""
    if db.query(Category).filter(Category.name == data["name"]).first():
        raise ConflictError(f"Category name '{data['name']}' already exists")
    if db.query(Category).filter(Category.slug == data["slug"]).first():
        raise ConflictError(f"Category slug '{data['slug']}' already exists")
    category = Category(**data)
    db.add(category)
    db.flush()
    record_audit_log(
        db, user_id=admin_user.id, action="CREATE", entity_type="CATEGORY",
        entity_id=category.id, new_values=data, description=f"Category created: {data['name']}",
    )
    return serialize_model(category)


def update_category(db: Session, *, admin_user: User, category_id: int, updates: dict) -> dict:
    category = (
        db.query(Category)
        .filter(Category.id == category_id, Category.is_deleted == False)  # noqa: E712
        .first()
    )
    if category is None:
        raise NotFoundError("Category not found")
    old_values: dict[str, Any] = {}
    new_values: dict[str, Any] = {}
    for field, value in updates.items():
        if value is None:
            continue
        if field in ("name", "slug"):
            existing = db.query(Category).filter(getattr(Category, field) == value).first()
            if existing is not None and existing.id != category_id:
                raise ConflictError(f"Category {field} '{value}' already exists")
        old_values[field] = _json_safe(getattr(category, field))
        setattr(category, field, value)
        new_values[field] = _json_safe(value)
    record_audit_log(
        db, user_id=admin_user.id, action="UPDATE", entity_type="CATEGORY",
        entity_id=category.id, old_values=old_values, new_values=new_values,
    )
    return serialize_model(category)


def delete_category(db: Session, *, admin_user: User, category_id: int) -> dict:
    """Soft-delete a category. Blocked while products still reference it."""
    category = (
        db.query(Category)
        .filter(Category.id == category_id, Category.is_deleted == False)  # noqa: E712
        .first()
    )
    if category is None:
        raise NotFoundError("Category not found")
    in_use = (
        db.query(func.count(ProductMaster.id))
        .filter(
            ProductMaster.category_id == category_id,
            ProductMaster.is_deleted == False,  # noqa: E712
        )
        .scalar() or 0
    )
    if in_use:
        raise ConflictError(
            f"Cannot delete category: {in_use} active product(s) still reference it"
        )
    category.is_deleted = True
    category.deleted_at = _utcnow()
    record_audit_log(
        db, user_id=admin_user.id, action="DELETE", entity_type="CATEGORY",
        entity_id=category.id, old_values={"name": category.name},
    )
    return {"id": category_id, "deleted": True}



# â”€â”€ Brands â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
def list_brands_admin(db: Session, *, include_inactive: bool = False) -> list[dict]:
    query = db.query(Brand).filter(Brand.is_deleted == False)  # noqa: E712
    if not include_inactive:
        query = query.filter(Brand.is_active == True)  # noqa: E712
    return [serialize_model(b) for b in query.order_by(Brand.name).all()]


def create_brand(db: Session, *, admin_user: User, data: dict) -> dict:
    if db.query(Brand).filter(Brand.name == data["name"]).first():
        raise ConflictError(f"Brand name '{data['name']}' already exists")
    if db.query(Brand).filter(Brand.slug == data["slug"]).first():
        raise ConflictError(f"Brand slug '{data['slug']}' already exists")
    brand = Brand(**data)
    db.add(brand)
    db.flush()
    record_audit_log(
        db, user_id=admin_user.id, action="CREATE", entity_type="BRAND",
        entity_id=brand.id, new_values=data, description=f"Brand created: {data['name']}",
    )
    return serialize_model(brand)


def update_brand(db: Session, *, admin_user: User, brand_id: int, updates: dict) -> dict:
    brand = (
        db.query(Brand)
        .filter(Brand.id == brand_id, Brand.is_deleted == False)  # noqa: E712
        .first()
    )
    if brand is None:
        raise NotFoundError("Brand not found")
    old_values: dict[str, Any] = {}
    new_values: dict[str, Any] = {}
    for field, value in updates.items():
        if value is None:
            continue
        if field in ("name", "slug"):
            existing = db.query(Brand).filter(getattr(Brand, field) == value).first()
            if existing is not None and existing.id != brand_id:
                raise ConflictError(f"Brand {field} '{value}' already exists")
        old_values[field] = _json_safe(getattr(brand, field))
        setattr(brand, field, value)
        new_values[field] = _json_safe(value)
    record_audit_log(
        db, user_id=admin_user.id, action="UPDATE", entity_type="BRAND",
        entity_id=brand.id, old_values=old_values, new_values=new_values,
    )
    return serialize_model(brand)


# â”€â”€ Product identifiers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
def list_product_identifiers(
    db: Session, *, product_master_id: int | None = None, limit: int = 100, offset: int = 0
) -> tuple[list[dict], int]:
    """List product identifiers (barcodes, GTINs...) with pagination."""
    query = db.query(ProductIdentifier)
    if product_master_id is not None:
        query = query.filter(ProductIdentifier.product_master_id == product_master_id)
    total = query.count()
    rows = query.order_by(ProductIdentifier.id).offset(offset).limit(limit).all()
    return [serialize_model(r) for r in rows], total

# â”€â”€ Inventory monitoring â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
def stale_inventory(
    db: Session,
    *,
    threshold_hours: int = 48,
    shop_id: int | None = None,
    limit: int = 50,
    offset: int = 0,
) -> tuple[list[dict], int]:
    """Inventory rows whose data is older than the freshness threshold."""
    cutoff = _utcnow() - timedelta(hours=threshold_hours)
    query = (
        db.query(ShopProduct, Inventory, ProductMaster, Shop)
        .join(Inventory, Inventory.shop_product_id == ShopProduct.id)
        .join(ProductMaster, ProductMaster.id == ShopProduct.product_master_id)
        .join(Shop, Shop.id == ShopProduct.shop_id)
        .filter(
            Shop.is_deleted == False,  # noqa: E712
            ShopProduct.is_active == True,  # noqa: E712
        )
    )
    if shop_id is not None:
        query = query.filter(ShopProduct.shop_id == shop_id)

    rows = query.all()
    items: list[dict] = []
    for sp, inv, pm, shop in rows:
        last_touched: datetime | None = (
            inv.last_synced_at or sp.last_inventory_update or sp.updated_at
        )
        if last_touched is not None and getattr(last_touched, "tzinfo", None) is None:
            last_touched = last_touched.replace(tzinfo=timezone.utc)
        # Stale if flagged by the freshness engine OR untouched past the cutoff.
        flagged = str(getattr(inv.freshness_status, "value", inv.freshness_status) or "") == "STALE"
        is_old = last_touched is not None and last_touched < cutoff
        if not (flagged or is_old):
            continue
        stale_hours = (
            int((_utcnow() - last_touched).total_seconds() // 3600) if last_touched else None
        )
        items.append({
            "shop_product_id": sp.id,
            "product_name": pm.name,
            "shop_id": shop.id,
            "shop_name": shop.name,
            "quantity": inv.quantity,
            "stock_status": str(getattr(sp.stock_status, "value", sp.stock_status)),
            "freshness_status": str(getattr(inv.freshness_status, "value", inv.freshness_status) or "") or None,
            "last_updated": last_touched.isoformat() if last_touched else None,
            "last_updated_source": str(getattr(inv.last_updated_source, "value", inv.last_updated_source)),
            "stale_hours": stale_hours,
        })
    items.sort(key=lambda x: x["stale_hours"] or 0, reverse=True)
    return items[offset:offset + limit], len(items)



def missing_prices(db: Session, *, limit: int = 50, offset: int = 0) -> tuple[list[dict], int]:
    """Active listings with a NULL or zero price â€” never customer-visible."""
    rows = (
        db.query(ShopProduct, ProductMaster, Shop)
        .join(ProductMaster, ProductMaster.id == ShopProduct.product_master_id)
        .join(Shop, Shop.id == ShopProduct.shop_id)
        .filter(
            ShopProduct.is_active == True,  # noqa: E712
            Shop.is_deleted == False,  # noqa: E712
        )
        .all()
    )
    items: list[dict] = []
    for sp, pm, shop in rows:
        if sp.price is None or float(sp.price) == 0.0:
            items.append({
                "shop_product_id": sp.id,
                "product_name": pm.name,
                "shop_id": shop.id,
                "shop_name": shop.name,
                "price": None if sp.price is None else float(sp.price),
                "anomaly_type": "MISSING_PRICE",
                "detail": "Listing has no sellable price",
            })
    total = len(items)
    return items[offset:offset + limit], total


def availability_anomalies(db: Session, *, limit: int = 50, offset: int = 0) -> tuple[list[dict], int]:
    """Listings marked available but with no stock (or the reverse)."""
    rows = (
        db.query(ShopProduct, Inventory, ProductMaster, Shop)
        .outerjoin(Inventory, Inventory.shop_product_id == ShopProduct.id)
        .join(ProductMaster, ProductMaster.id == ShopProduct.product_master_id)
        .join(Shop, Shop.id == ShopProduct.shop_id)
        .filter(
            ShopProduct.is_active == True,  # noqa: E712
            Shop.is_deleted == False,  # noqa: E712
        )
        .all()
    )
    items: list[dict] = []
    for sp, inv, pm, shop in rows:
        qty = inv.quantity if inv is not None else None
        stock = str(getattr(sp.stock_status, "value", sp.stock_status))
        if sp.is_available and (qty is None or qty <= 0):
            items.append({
                "shop_product_id": sp.id,
                "product_name": pm.name,
                "shop_id": shop.id,
                "shop_name": shop.name,
                "anomaly_type": "AVAILABILITY_ANOMALY",
                "detail": f"Marked available but quantity={qty} ({stock})",
            })
        elif (not sp.is_available) and qty is not None and qty > 0 and stock == "OUT_OF_STOCK":
            items.append({
                "shop_product_id": sp.id,
                "product_name": pm.name,
                "shop_id": shop.id,
                "shop_name": shop.name,
                "anomaly_type": "AVAILABILITY_ANOMALY",
                "detail": f"Holding {qty} units but flagged unavailable/out-of-stock",
            })
    total = len(items)
    return items[offset:offset + limit], total


def sync_failures(db: Session, *, limit: int = 50, offset: int = 0) -> tuple[list[dict], int]:
    """Failed / partially-failed POS sync jobs and Excel import jobs."""
    from app.models.pos import POSSyncJob, POSSyncStatus

    jobs = (
        db.query(POSSyncJob, Shop)
        .join(Shop, Shop.id == POSSyncJob.shop_id)
        .filter(POSSyncJob.status.in_([POSSyncStatus.FAILED, POSSyncStatus.COMPLETED_WITH_ERRORS]))
        .order_by(POSSyncJob.id.desc())
        .all()
    )
    items: list[dict] = []
    for job, shop in jobs:
        items.append({
            "source": "POS_SYNC",
            "reference_id": job.id,
            "shop_id": job.shop_id,
            "shop_name": shop.name,
            "sync_type": job.sync_type,
            "status": str(getattr(job.status, "value", job.status)),
            "items_failed": job.items_failed,
            "error_summary": job.error_summary,
            "anomaly_type": "SYNC_FAILURE",
            "detail": f"POS sync #{job.id} ended {job.status.value}",
        })
    from app.models.inventory_import import ImportJobStatus, InventoryImportJob

    import_jobs = (
        db.query(InventoryImportJob, Shop)
        .join(Shop, Shop.id == InventoryImportJob.shop_id)
        .filter(InventoryImportJob.status.in_([ImportJobStatus.FAILED, ImportJobStatus.PARTIAL]))
        .order_by(InventoryImportJob.id.desc())
        .all()
    )
    for job, shop in import_jobs:
        items.append({
            "source": "EXCEL_IMPORT",
            "reference_id": job.id,
            "shop_id": job.shop_id,
            "shop_name": shop.name,
            "sync_type": "EXCEL_IMPORT",
            "status": str(getattr(job.status, "value", job.status)),
            "items_failed": job.failed_rows,
            "error_summary": job.error_message,
            "anomaly_type": "SYNC_FAILURE",
            "detail": f"Excel import #{job.id} ended {job.status.value}",
        })
    items.sort(key=lambda x: x["reference_id"], reverse=True)
    return items[offset:offset + limit], len(items)


def inventory_monitoring_summary(db: Session, *, threshold_hours: int = 48) -> dict:
    """Counts per anomaly class for the dashboard / inventory module."""
    _, stale_total = stale_inventory(db, threshold_hours=threshold_hours, limit=1)
    _, missing_total = missing_prices(db, limit=1)
    _, anomaly_total = availability_anomalies(db, limit=1)
    _, sync_total = sync_failures(db, limit=1)
    return {
        "stale_count": stale_total,
        "missing_price_count": missing_total,
        "availability_anomaly_count": anomaly_total,
        "sync_failure_count": sync_total,
        "stale_threshold_hours": threshold_hours,
    }


# â”€â”€ Offers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
def list_offers_admin(
    db: Session,
    *,
    status: str | None = None,
    shop_id: int | None = None,
    limit: int = 50,
    offset: int = 0,
) -> tuple[list[dict], int]:
    query = db.query(Offer).filter(Offer.is_deleted == False)  # noqa: E712
    if status:
        try:
            query = query.filter(Offer.status == OfferStatus(status))
        except ValueError as exc:
            raise ValidationError(f"Invalid offer status: {status}") from exc
    if shop_id is not None:
        query = query.filter(Offer.shop_id == shop_id)
    total = query.count()
    rows = query.order_by(Offer.id).offset(offset).limit(limit).all()
    return [serialize_model(o) for o in rows], total


def update_offer_status(
    db: Session,
    *,
    admin_user: User,
    offer_id: int,
    new_status: str,
    ip_address: str | None = None,
) -> dict:
    """Pause / resume / cancel an offer.

    Business rules: expired offers can never be re-activated; only ACTIVE
    offers may be paused or cancelled.
    """
    offer = (
        db.query(Offer).filter(Offer.id == offer_id, Offer.is_deleted == False).first()  # noqa: E712
    )
    if offer is None:
        raise NotFoundError("Offer not found")
    try:
        target_status = OfferStatus(new_status)
    except ValueError as exc:
        raise ValidationError(f"Invalid offer status: {new_status}") from exc
    current = offer.status if isinstance(offer.status, OfferStatus) else OfferStatus(offer.status)

    allowed_transitions = {
        OfferStatus.ACTIVE: {OfferStatus.PAUSED, OfferStatus.CANCELLED},
        OfferStatus.PAUSED: {OfferStatus.ACTIVE, OfferStatus.CANCELLED},
        OfferStatus.DRAFT: {OfferStatus.ACTIVE},
    }
    if current not in allowed_transitions or target_status not in allowed_transitions[current]:
        raise ConflictError(
            f"Cannot move an offer from {current.value} to {target_status.value}"
        )
    old_values = {"status": current.value}
    offer.status = target_status
    record_audit_log(
        db, user_id=admin_user.id, action="UPDATE", entity_type="OFFER",
        entity_id=offer.id, old_values=old_values,
        new_values={"status": target_status.value}, ip_address=ip_address,
    )
    record_admin_action(
        db, admin_user_id=admin_user.id, action_type="UPDATE_OFFER",
        target_type="OFFER", target_id=offer.id,
        action_data={"from": current.value, "to": target_status.value},
        ip_address=ip_address,
    )
    return serialize_model(offer)

# â”€â”€ Subscriptions & Payments â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
def list_subscriptions_admin(
    db: Session,
    *,
    status: str | None = None,
    plan_id: int | None = None,
    limit: int = 50,
    offset: int = 0,
) -> tuple[list[dict], int]:
    query = db.query(Subscription)
    if status:
        try:
            query = query.filter(Subscription.status == SubscriptionStatus(status))
        except ValueError as exc:
            raise ValidationError(f"Invalid subscription status: {status}") from exc
    if plan_id is not None:
        query = query.filter(Subscription.plan_id == plan_id)
    total = query.count()
    rows = query.order_by(Subscription.id).offset(offset).limit(limit).all()
    return [serialize_model(s) for s in rows], total


def update_subscription_admin(
    db: Session,
    *,
    admin_user: User,
    subscription_id: int,
    updates: dict,
    ip_address: str | None = None,
) -> dict:
    """Admin update to a subscription (status / auto-renew / cancel flag)."""
    sub = db.query(Subscription).filter(Subscription.id == subscription_id).first()
    if sub is None:
        raise NotFoundError("Subscription not found")
    old_values: dict[str, Any] = {}
    new_values: dict[str, Any] = {}
    if updates.get("status") is not None:
        try:
            target_status = SubscriptionStatus(updates["status"])
        except ValueError as exc:
            raise ValidationError(f"Invalid subscription status: {updates['status']}") from exc
        old_values["status"] = str(getattr(sub.status, "value", sub.status))
        sub.status = target_status
        new_values["status"] = target_status.value
    if updates.get("is_auto_renew") is not None:
        old_values["is_auto_renew"] = sub.is_auto_renew
        sub.is_auto_renew = bool(updates["is_auto_renew"])
        new_values["is_auto_renew"] = sub.is_auto_renew
    if updates.get("cancel_at_period_end") is not None:
        old_values["cancel_at_period_end"] = sub.cancel_at_period_end
        sub.cancel_at_period_end = bool(updates["cancel_at_period_end"])
        new_values["cancel_at_period_end"] = sub.cancel_at_period_end
    if not new_values:
        raise ValidationError("No subscription fields to update")

    record_audit_log(
        db, user_id=admin_user.id, action="UPDATE", entity_type="SUBSCRIPTION",
        entity_id=sub.id, old_values=old_values, new_values=new_values, ip_address=ip_address,
    )
    record_admin_action(
        db, admin_user_id=admin_user.id, action_type="UPDATE_SUBSCRIPTION",
        target_type="SUBSCRIPTION", target_id=sub.id, action_data=new_values,
        ip_address=ip_address,
    )
    return serialize_model(sub)


def list_payments_admin(
    db: Session,
    *,
    status: str | None = None,
    provider: str | None = None,
    method: str | None = None,
    subscription_id: int | None = None,
    limit: int = 50,
    offset: int = 0,
) -> tuple[list[dict], int]:
    query = db.query(Payment)
    if status:
        query = query.filter(Payment.status == status.upper())
    if provider:
        query = query.filter(Payment.payment_provider == provider.upper())
    if method:
        query = query.filter(Payment.payment_method == method.upper())
    if subscription_id is not None:
        query = query.filter(Payment.subscription_id == subscription_id)
    total = query.count()
    rows = query.order_by(Payment.id.desc()).offset(offset).limit(limit).all()
    return [serialize_model(p) for p in rows], total

# â”€â”€ Reports â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
def _report_payload(db: Session, report_type: str, date_from, date_to) -> dict:
    """Compute the data payload for each report type."""
    now = _utcnow()
    payload: dict = {"generated_at": now.isoformat()}
    if date_from:
        payload["date_from"] = date_from.isoformat()
    if date_to:
        payload["date_to"] = date_to.isoformat()

    if report_type == "SEARCH":
        total = db.query(func.count(SearchEvent.id)).scalar() or 0
        success = (
            db.query(func.count(SearchEvent.id)).filter(SearchEvent.result_count > 0).scalar() or 0
        )
        top = (
            db.query(SearchEvent.query, func.count(SearchEvent.id).label("c"))
            .group_by(SearchEvent.query)
            .order_by(func.count(SearchEvent.id).desc())
            .limit(10)
            .all()
        )
        payload.update({
            "total_searches": total,
            "successful_searches": success,
            "success_rate": round(success / total, 4) if total else 0.0,
            "top_queries": [{"query": q, "count": int(c)} for q, c in top],
        })
    elif report_type == "INVENTORY":
        payload.update(inventory_monitoring_summary(db))
        out_of_stock = (
            db.query(func.count(ShopProduct.id))
            .filter(ShopProduct.stock_status == "OUT_OF_STOCK")
            .scalar() or 0
        )
        total_inv = db.query(func.count(Inventory.id)).scalar() or 0
        payload.update({"total_inventory_records": total_inv, "out_of_stock": out_of_stock})
    elif report_type == "SHOPS":
        by_status_rows = (
            db.query(Shop.status, func.count(Shop.id))
            .filter(Shop.is_deleted == False)  # noqa: E712
            .group_by(Shop.status)
            .all()
        )
        payload["shops_by_status"] = {
            str(getattr(s, "value", s)): int(c) for s, c in by_status_rows
        }
        payload["total_shops"] = sum(payload["shops_by_status"].values())
    elif report_type == "PRODUCTS":
        by_status_rows = (
            db.query(ProductMaster.status, func.count(ProductMaster.id))
            .filter(ProductMaster.is_deleted == False)  # noqa: E712
            .group_by(ProductMaster.status)
            .all()
        )
        payload["products_by_status"] = {
            str(getattr(s, "value", s)): int(c) for s, c in by_status_rows
        }
        pending_listings = (
            db.query(func.count(ShopProduct.id))
            .filter(ShopProduct.status == "PENDING_REVIEW")
            .scalar() or 0
        )
        payload["pending_listing_reviews"] = pending_listings
    elif report_type == "USERS":
        by_status_rows = (
            db.query(User.status, func.count(User.id))
            .filter(User.is_deleted == False)  # noqa: E712
            .group_by(User.status)
            .all()
        )
        payload["users_by_status"] = {
            str(getattr(s, "value", s)): int(c) for s, c in by_status_rows
        }
        payload["total_users"] = sum(payload["users_by_status"].values())
    elif report_type == "REVENUE":
        revenue_row = (
            db.query(func.coalesce(func.sum(Payment.amount), 0.0))
            .filter(Payment.status == "SUCCESS")
            .scalar()
        )
        refunded_row = (
            db.query(func.coalesce(func.sum(Payment.amount), 0.0))
            .filter(Payment.status == "REFUNDED")
            .scalar()
        )
        payments_by_status_rows = (
            db.query(Payment.status, func.count(Payment.id)).group_by(Payment.status).all()
        )
        active_subs = (
            db.query(func.count(Subscription.id))
            .filter(Subscription.status == SubscriptionStatus.ACTIVE)
            .scalar() or 0
        )
        payload.update({
            "successful_payment_total": float(revenue_row or 0.0),
            "refunded_total": float(refunded_row or 0.0),
            "net_revenue": round(float(revenue_row or 0.0) - float(refunded_row or 0.0), 2),
            "payments_by_status": {s: int(c) for s, c in payments_by_status_rows},
            "active_subscriptions": active_subs,
        })
    return payload


def generate_report(
    db: Session,
    *,
    admin_user: User,
    report_type: str,
    report_name: str,
    date_from=None,
    date_to=None,
    filters: dict | None = None,
    ip_address: str | None = None,
) -> dict:
    """Generate an on-demand platform report (READY with inline payload)."""
    if report_type not in ("SEARCH", "INVENTORY", "SHOPS", "PRODUCTS", "USERS", "REVENUE"):
        raise ValidationError(f"Unknown report type: {report_type}")
    now = _utcnow()
    parameters = {"filters": filters or {}}
    try:
        payload = _report_payload(db, report_type, date_from, date_to)
    except Exception as exc:
        logger.exception("Report generation failed")
        report = Report(
            report_type=report_type,
            report_name=report_name,
            parameters_json=parameters,
            generated_by=admin_user.id,
            status="FAILED",
            started_at=now,
            error_message=str(exc),
        )
        db.add(report)
        db.flush()
        return serialize_model(report)

    report = Report(
        report_type=report_type,
        report_name=report_name,
        parameters_json={**parameters, "payload": payload},
        generated_by=admin_user.id,
        status="READY",
        started_at=now,
        completed_at=_utcnow(),
    )
    db.add(report)
    db.flush()
    record_audit_log(
        db, user_id=admin_user.id, action="GENERATE", entity_type="REPORT",
        entity_id=report.id, new_values={"report_type": report_type},
        description=f"Generated {report_type} report '{report_name}'",
        ip_address=ip_address,
    )
    record_admin_action(
        db, admin_user_id=admin_user.id, action_type="GENERATE_REPORT",
        target_type="REPORT", target_id=report.id,
        action_data={"report_type": report_type}, ip_address=ip_address,
    )
    return serialize_model(report)


def list_reports(db: Session, *, report_type: str | None = None, limit: int = 50, offset: int = 0) -> tuple[list[dict], int]:
    query = db.query(Report)
    if report_type:
        query = query.filter(Report.report_type == report_type)
    total = query.count()
    rows = query.order_by(Report.id.desc()).offset(offset).limit(limit).all()
    return [serialize_model(r) for r in rows], total

# â”€â”€ Analytics module â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
def analytics_summary(db: Session, *, days: int = 30) -> dict:
    """Platform analytics: search trends, views, clicks, popular queries."""
    since = _utcnow() - timedelta(days=days)
    total_searches = (
        db.query(func.count(SearchEvent.id))
        .filter(SearchEvent.event_time >= since)
        .scalar() or 0
    )
    total_product_views = db.query(func.count(ProductView.id)).scalar() or 0
    total_shop_views = db.query(func.count(ShopView.id)).scalar() or 0
    total_clicks = db.query(func.count(ProductClick.id)).scalar() or 0
    top_queries = (
        db.query(SearchEvent.query, func.count(SearchEvent.id).label("c"))
        .filter(SearchEvent.event_time >= since)
        .group_by(SearchEvent.query)
        .order_by(func.count(SearchEvent.id).desc())
        .limit(10)
        .all()
    )
    zero_result = (
        db.query(func.count(SearchEvent.id))
        .filter(SearchEvent.result_count == 0, SearchEvent.event_time >= since)
        .scalar() or 0
    )
    return {
        "window_days": days,
        "total_searches": total_searches,
        "zero_result_searches": zero_result,
        "total_product_views": total_product_views,
        "total_shop_views": total_shop_views,
        "total_clicks": total_clicks,
        "top_queries": [{"query": q, "count": int(c)} for q, c in top_queries],
    }

# â”€â”€ Complaints â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
def list_complaints(
    db: Session,
    *,
    status: str | None = None,
    priority: str | None = None,
    complaint_type: str | None = None,
    limit: int = 50,
    offset: int = 0,
) -> tuple[list[dict], int]:
    query = db.query(Complaint)
    if status:
        try:
            query = query.filter(Complaint.status == ComplaintStatus(status))
        except ValueError as exc:
            raise ValidationError(f"Invalid complaint status: {status}") from exc
    if priority:
        query = query.filter(Complaint.priority == priority.upper())
    if complaint_type:
        query = query.filter(Complaint.complaint_type == complaint_type)
    total = query.count()
    rows = query.order_by(Complaint.id).offset(offset).limit(limit).all()
    return [serialize_model(c) for c in rows], total


def update_complaint(
    db: Session,
    *,
    admin_user: User,
    complaint_id: int,
    updates: dict,
    ip_address: str | None = None,
) -> dict:
    """Update a complaint's status/priority/assignment/resolution.

    Business rule: moving to RESOLVED or CLOSED requires resolution notes.
    """
    complaint = db.query(Complaint).filter(Complaint.id == complaint_id).first()
    if complaint is None:
        raise NotFoundError("Complaint not found")

    old_values: dict[str, Any] = {}
    new_values: dict[str, Any] = {}

    if updates.get("status") is not None:
        try:
            target_status = ComplaintStatus(updates["status"])
        except ValueError as exc:
            raise ValidationError(f"Invalid complaint status: {updates['status']}") from exc
        if target_status in (ComplaintStatus.RESOLVED, ComplaintStatus.CLOSED):
            notes = updates.get("resolution_notes") or complaint.resolution_notes
            if not notes:
                raise ValidationError(
                    f"{target_status.value} complaints require resolution notes"
                )
        old_values["status"] = str(getattr(complaint.status, "value", complaint.status))
        complaint.status = target_status
        new_values["status"] = target_status.value
        if (
            target_status in (ComplaintStatus.RESOLVED, ComplaintStatus.CLOSED)
            and complaint.resolved_at is None
        ):
            complaint.resolved_at = _utcnow()
            new_values["resolved_at"] = complaint.resolved_at.isoformat()

    if updates.get("priority") is not None:
        old_values["priority"] = complaint.priority
        complaint.priority = updates["priority"].upper()
        new_values["priority"] = complaint.priority
    if updates.get("assigned_to") is not None:
        assignee = db.query(User).filter(User.id == updates["assigned_to"]).first()
        if assignee is None:
            raise ValidationError(f"Assignee user {updates['assigned_to']} does not exist")
        old_values["assigned_to"] = complaint.assigned_to
        complaint.assigned_to = updates["assigned_to"]
        new_values["assigned_to"] = complaint.assigned_to
    if updates.get("resolution_notes") is not None:
        old_values["resolution_notes"] = complaint.resolution_notes
        complaint.resolution_notes = updates["resolution_notes"]
        new_values["resolution_notes"] = complaint.resolution_notes
    if not new_values:
        raise ValidationError("No complaint fields to update")

    record_audit_log(
        db, user_id=admin_user.id, action="UPDATE", entity_type="COMPLAINT",
        entity_id=complaint.id, old_values=old_values, new_values=new_values,
        ip_address=ip_address,
    )
    record_admin_action(
        db, admin_user_id=admin_user.id, action_type="UPDATE_COMPLAINT",
        target_type="COMPLAINT", target_id=complaint.id, action_data=new_values,
        ip_address=ip_address,
    )
    return serialize_model(complaint)

# â”€â”€ Notifications (admin broadcast) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
def send_admin_notification(
    db: Session,
    *,
    admin_user: User,
    title: str,
    body: str,
    notification_type: str,
    target_user_ids: list[int] | None = None,
    target_role: str | None = None,
) -> dict:
    """Create notifications for targeted users, a role, or everyone."""
    from app.models.notification import Notification
    from app.models.role import Role

    if notification_type == "TARGETED":
        if not target_user_ids:
            raise ValidationError("TARGETED notifications require target_user_ids")
        users = db.query(User).filter(User.id.in_(target_user_ids)).all()
    elif target_role is not None:
        role = db.query(Role).filter(Role.name == target_role).first()
        users = db.query(User).filter(User.role_id == role.id).all() if role else []
    else:  # ADMIN_BROADCAST â€” every active non-deleted user
        users = (
            db.query(User)
            .filter(User.is_active == True, User.is_deleted == False)  # noqa: E712
            .all()
        )

    now = _utcnow()
    created = []
    for u in users:
        n = Notification(user_id=u.id, title=title, body=body, type="admin")
        n.sent_at = now
        db.add(n)
        created.append(u.id)
    db.flush()

    record_audit_log(
        db, user_id=admin_user.id, action="CREATE", entity_type="NOTIFICATION",
        entity_id=None,
        new_values={"title": title, "recipients": len(created), "type": notification_type},
        description=f"Admin notification '{title}' sent to {len(created)} user(s)",
    )
    return {"title": title, "recipient_count": len(created), "recipient_ids": created}


# â”€â”€ System settings & feature flags â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
def list_system_settings(db: Session) -> list[dict]:
    """All settings; secret values are masked."""
    rows = db.query(SystemSetting).order_by(SystemSetting.key).all()
    out = []
    for s in rows:
        item = serialize_model(s)
        if s.is_secret:
            item["value"] = "********"
            item["is_masked"] = True
        else:
            item["is_masked"] = False
        out.append(item)
    return out


def upsert_system_setting(
    db: Session,
    *,
    admin_user: User,
    key: str,
    value: str,
    value_type: str = "string",
    description: str | None = None,
    is_secret: bool = False,
    ip_address: str | None = None,
) -> dict:
    """Create or update a system setting (audited; secrets masked in logs)."""
    if value_type not in ("string", "int", "float", "boolean", "json"):
        raise ValidationError(f"Invalid value_type: {value_type}")
    setting = db.query(SystemSetting).filter(SystemSetting.key == key).first()
    old_values = None
    if setting is None:
        setting = SystemSetting(
            key=key, value=value, value_type=value_type,
            description=description, is_secret=is_secret, updated_by=admin_user.id,
        )
        db.add(setting)
        action_desc = f"System setting created: {key}"
    else:
        old_values = {"value": "********" if setting.is_secret else setting.value}
        setting.value = value
        setting.value_type = value_type
        if description is not None:
            setting.description = description
        setting.is_secret = is_secret
        setting.updated_by = admin_user.id
        action_desc = f"System setting updated: {key}"
    db.flush()

    logged_value = "********" if is_secret else value
    record_audit_log(
        db, user_id=admin_user.id, action="UPDATE", entity_type="SYSTEM_SETTING",
        entity_id=setting.id, old_values=old_values,
        new_values={"key": key, "value": logged_value, "value_type": value_type},
        description=action_desc, ip_address=ip_address,
    )
    record_admin_action(
        db, admin_user_id=admin_user.id, action_type="UPDATE_SYSTEM_SETTING",
        target_type="SYSTEM_SETTING", target_id=setting.id,
        action_data={"key": key, "value": logged_value}, ip_address=ip_address,
    )
    out = serialize_model(setting)
    if is_secret:
        out["value"] = "********"
    return out


def delete_system_setting(db: Session, *, admin_user: User, key: str) -> dict:
    """Delete a system setting (audited)."""
    setting = db.query(SystemSetting).filter(SystemSetting.key == key).first()
    if setting is None:
        raise NotFoundError(f"System setting '{key}' not found")
    db.delete(setting)
    db.flush()
    record_audit_log(
        db, user_id=admin_user.id, action="DELETE", entity_type="SYSTEM_SETTING",
        entity_id=None, old_values={"key": key}, description=f"System setting deleted: {key}",
    )
    return {"key": key, "deleted": True}




# â”€â”€ Feature flags â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
def list_feature_flags(db: Session) -> list[dict]:
    rows = db.query(FeatureFlag).order_by(FeatureFlag.name).all()
    return [serialize_model(f) for f in rows]


def upsert_feature_flag(
    db: Session,
    *,
    admin_user: User,
    name: str,
    description: str | None = None,
    is_enabled: bool = False,
    rollout_percentage: int = 100,
    scope: str = "GLOBAL",
    target_ids_json: dict | None = None,
    conditions_json: dict | None = None,
    ip_address: str | None = None,
) -> dict:
    """Create or update a feature flag with validation of its parameters."""
    if not 0 <= rollout_percentage <= 100:
        raise ValidationError("rollout_percentage must be between 0 and 100")
    if scope not in ("GLOBAL", "SHOP", "USER", "REGION"):
        raise ValidationError(f"Invalid flag scope: {scope}")

    flag = db.query(FeatureFlag).filter(FeatureFlag.name == name).first()
    old_values = None
    if flag is None:
        flag = FeatureFlag(
            name=name,
            description=description,
            is_enabled=is_enabled,
            default_enabled=is_enabled,
            rollout_percentage=rollout_percentage,
            scope=scope,
            target_ids_json=target_ids_json,
            conditions_json=conditions_json,
            updated_by=admin_user.id,
        )
        db.add(flag)
        action_desc = f"Feature flag created: {name}"
    else:
        old_values = {
            "is_enabled": flag.is_enabled,
            "rollout_percentage": flag.rollout_percentage,
            "scope": flag.scope,
        }
        if description is not None:
            flag.description = description
        flag.is_enabled = is_enabled
        flag.rollout_percentage = rollout_percentage
        flag.scope = scope
        flag.target_ids_json = target_ids_json
        flag.conditions_json = conditions_json
        flag.updated_by = admin_user.id
        action_desc = f"Feature flag updated: {name}"
    db.flush()

    record_audit_log(
        db, user_id=admin_user.id, action="UPDATE", entity_type="FEATURE_FLAG",
        entity_id=flag.id, old_values=old_values,
        new_values={
            "name": name, "is_enabled": is_enabled,
            "rollout_percentage": rollout_percentage, "scope": scope,
        },
        description=action_desc, ip_address=ip_address,
    )
    record_admin_action(
        db, admin_user_id=admin_user.id, action_type="UPDATE_FEATURE_FLAG",
        target_type="FEATURE_FLAG", target_id=flag.id,
        action_data={"name": name, "is_enabled": is_enabled}, ip_address=ip_address,
    )
    return serialize_model(flag)


def delete_feature_flag(db: Session, *, admin_user: User, name: str) -> dict:
    flag = db.query(FeatureFlag).filter(FeatureFlag.name == name).first()
    if flag is None:
        raise NotFoundError(f"Feature flag '{name}' not found")
    db.delete(flag)
    db.flush()
    record_audit_log(
        db, user_id=admin_user.id, action="DELETE", entity_type="FEATURE_FLAG",
        entity_id=None, old_values={"name": name}, description=f"Feature flag deleted: {name}",
    )
    return {"name": name, "deleted": True}



# â”€â”€ Audit logs / Admin actions listing â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
def list_audit_logs(
    db: Session,
    *,
    action: str | None = None,
    entity_type: str | None = None,
    entity_id: int | None = None,
    user_id: int | None = None,
    limit: int = 50,
    offset: int = 0,
) -> tuple[list[dict], int]:
    query = db.query(AuditLog)
    if action:
        query = query.filter(AuditLog.action == action.upper())
    if entity_type:
        query = query.filter(AuditLog.entity_type == entity_type.upper())
    if entity_id is not None:
        query = query.filter(AuditLog.entity_id == entity_id)
    if user_id is not None:
        query = query.filter(AuditLog.user_id == user_id)
    total = query.count()
    rows = query.order_by(AuditLog.id.desc()).offset(offset).limit(limit).all()
    return [serialize_model(r) for r in rows], total


def list_admin_actions(
    db: Session,
    *,
    action_type: str | None = None,
    target_type: str | None = None,
    target_id: int | None = None,
    admin_user_id: int | None = None,
    limit: int = 50,
    offset: int = 0,
) -> tuple[list[dict], int]:
    query = db.query(AdminAction)
    if action_type:
        query = query.filter(AdminAction.action_type == action_type.upper())
    if target_type:
        query = query.filter(AdminAction.target_type == target_type.upper())
    if target_id is not None:
        query = query.filter(AdminAction.target_id == target_id)
    if admin_user_id is not None:
        query = query.filter(AdminAction.admin_user_id == admin_user_id)
    total = query.count()
    rows = query.order_by(AdminAction.id.desc()).offset(offset).limit(limit).all()
    items = []
    for r in rows:
        item = serialize_model(r)
        actor = db.query(User).filter(User.id == r.admin_user_id).first()
        item["admin_name"] = actor.name if actor else None
        items.append(item)
    return items, total



# â”€â”€ Admin notes â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
def create_admin_note(
    db: Session,
    *,
    admin_user: User,
    entity_type: str,
    entity_id: int,
    note: str,
    is_private: bool = True,
) -> dict:
    """Attach an internal note to any entity (audited)."""
    record = AdminNote(
        admin_user_id=admin_user.id,
        entity_type=entity_type.upper(),
        entity_id=entity_id,
        note=note,
        is_private=is_private,
        created_by=admin_user.id,
    )
    db.add(record)
    db.flush()
    record_audit_log(
        db, user_id=admin_user.id, action="CREATE", entity_type="ADMIN_NOTE",
        entity_id=record.id,
        new_values={"target": f"{entity_type}:{entity_id}", "is_private": is_private},
        description=f"Admin note added on {entity_type}#{entity_id}",
    )
    return serialize_model(record)


def list_admin_notes(
    db: Session,
    *,
    entity_type: str | None = None,
    entity_id: int | None = None,
    admin_user_id: int | None = None,
    limit: int = 100,
    offset: int = 0,
) -> tuple[list[dict], int]:
    query = db.query(AdminNote)
    if entity_type:
        query = query.filter(AdminNote.entity_type == entity_type.upper())
    if entity_id is not None:
        query = query.filter(AdminNote.entity_id == entity_id)
    if admin_user_id is not None:
        query = query.filter(AdminNote.admin_user_id == admin_user_id)
    total = query.count()
    rows = query.order_by(AdminNote.id.desc()).offset(offset).limit(limit).all()
    return [serialize_model(n) for n in rows], total


def update_admin_note(db: Session, *, admin_user: User, note_id: int, updates: dict) -> dict:
    note_row = db.query(AdminNote).filter(AdminNote.id == note_id).first()
    if note_row is None:
        raise NotFoundError("Admin note not found")
    old_values = serialize_model(note_row)
    if updates.get("note") is not None:
        note_row.note = updates["note"]
    if updates.get("is_private") is not None:
        note_row.is_private = bool(updates["is_private"])
    record_audit_log(
        db, user_id=admin_user.id, action="UPDATE", entity_type="ADMIN_NOTE",
        entity_id=note_row.id,
        old_values={"note": old_values["note"], "is_private": old_values["is_private"]},
        new_values={"note": note_row.note, "is_private": note_row.is_private},
    )
    return serialize_model(note_row)


def delete_admin_note(db: Session, *, admin_user: User, note_id: int) -> dict:
    note_row = db.query(AdminNote).filter(AdminNote.id == note_id).first()
    if note_row is None:
        raise NotFoundError("Admin note not found")
    db.delete(note_row)
    db.flush()
    record_audit_log(
        db, user_id=admin_user.id, action="DELETE", entity_type="ADMIN_NOTE",
        entity_id=None, old_values={"id": note_id}, description=f"Admin note #{note_id} deleted",
    )
    return {"id": note_id, "deleted": True}
