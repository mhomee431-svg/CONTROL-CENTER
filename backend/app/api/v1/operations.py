"""Notifications, subscriptions, complaints, POS, imports and system settings."""

from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.notification_safety import (
    NOTIFICATION_TYPES,
    SUPPORTED_AUDIENCES,
    validate_explicit_url,
    validate_notification_payload,
)
from app.core.pagination import Pagination, pagination
from app.core.responses import ok, paged
from app.core.serializers import to_dict
from app.core.security import get_current_admin, require_capability
from app.models import (
    AdminUser,
    AuditLog,
    Complaint,
    FeatureFlag,
    ImportError,
    ImportJob,
    NotificationCampaign,
    Payment,
    PosIntegration,
    PosSyncRun,
    Shop,
    Subscription,
    SystemSetting,
)

router = APIRouter(prefix="/admin", tags=["operations"])


def _list(stmt, page: Pagination, db: Session, serialiser):
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    start, end = page.window()
    rows = db.scalars(stmt.offset(start).limit(end - start)).all()
    return ok(paged([serialiser(r) for r in rows], total))


# --- Notifications ---------------------------------------------------------

CAMPAIGN_FIELDS = [
    "id", "title", "body", "notification_type", "audience", "status",
    "deep_link", "entity_id", "recipients_total", "recipients_sent",
    "recipients_failed", "sent_by", "created_at", "sent_at",
    "scheduled_at", "category", "location", "selected_ids", "metadata_json",
    "reason",
]


class CampaignCreate(BaseModel):
    title: str
    body: str
    notification_type: str = "ADMIN_BROADCAST"
    audience: str = "all"
    deep_link: str | None = None
    entity_id: str | None = None
    reason: str | None = None
    # Scheduling: an ISO-8601 timestamp. When supplied the campaign is queued
    # (SCHEDULED) instead of dispatched immediately.
    scheduled_at: datetime | None = None
    # Targeting: only the dimensions the backend resolves are accepted.
    category: str | None = None
    location: str | None = None
    selected_ids: list[int] | None = None
    # Opaque composer metadata; never parsed to build a route.
    metadata: dict[str, Any] | None = None


def _recipient_count(
    db: Session,
    audience: str,
    category: str | None,
    location: str | None,
    selected_ids: list[int] | None,
) -> int:
    """Resolve the number of subjects a campaign would reach.

    Only the targeting the backend actually supports is honoured; anything it
    cannot resolve is reported as zero rather than a fabricated estimate.
    """
    from app.models import User

    if selected_ids:
        # "Selected customers" / "Selected shopkeepers" — an explicit id list.
        if audience == "shopkeeper":
            owner_ids = select(Shop.owner_id).where(
                Shop.owner_id.isnot(None), Shop.owner_id.in_(selected_ids)
            )
            return db.scalar(
                select(func.count()).select_from(User).where(User.id.in_(owner_ids))
            ) or 0
        return db.scalar(
            select(func.count()).select_from(User).where(User.id.in_(selected_ids))
        ) or 0

    stmt = select(func.count()).select_from(User)
    if audience == "shopkeeper":
        owner_ids = select(Shop.owner_id).where(Shop.owner_id.isnot(None)).distinct()
        stmt = stmt.where(User.id.in_(owner_ids))
    elif audience == "customer":
        owner_ids = select(Shop.owner_id).where(Shop.owner_id.isnot(None))
        stmt = stmt.where(User.id.notin_(owner_ids))

    # Location targeting filters on the user's city/state when the column is
    # present; a database without it targets the whole scope instead of guessing.
    if location and hasattr(User, "city"):
        like = f"%{location}%"
        stmt = stmt.where(or_(User.city.ilike(like), User.state.ilike(like)))

    return db.scalar(stmt) or 0


def _persist_campaign(
    db: Session,
    admin: AdminUser,
    payload: CampaignCreate,
    status: str,
) -> NotificationCampaign:
    """Common write path for every campaign status (DRAFT/SCHEDULED/SENT)."""
    recipients = _recipient_count(
        db, payload.audience, payload.category, payload.location, payload.selected_ids
    )
    now = datetime.now(timezone.utc)
    dispatched = status == "SENT"
    campaign = NotificationCampaign(
        title=payload.title.strip(),
        body=payload.body.strip(),
        notification_type=payload.notification_type,
        audience=payload.audience,
        status=status,
        deep_link=payload.deep_link,
        entity_id=payload.entity_id,
        recipients_total=recipients,
        # A campaign that has not gone out yet has no delivery count; null
        # rather than 0 so the UI renders "not sent" instead of a false zero.
        recipients_sent=recipients if dispatched else None,
        recipients_failed=0 if dispatched else None,
        sent_by=admin.name or admin.username if dispatched else None,
        sent_at=now if dispatched else None,
        scheduled_at=payload.scheduled_at,
        category=payload.category,
        location=payload.location,
        selected_ids=payload.selected_ids,
        metadata_json=payload.metadata,
        reason=payload.reason,
    )
    db.add(campaign)
    return campaign


def _validate_or_400(payload: CampaignCreate):
    """Apply the NOTIFICATION SAFETY contract and raise 422 on any violation.

    The client validates too, but this is the authoritative gate: an
    unvalidated or unroutable deep link must never reach a campaign row.
    """
    result = validate_notification_payload(
        notification_type=payload.notification_type,
        audience=payload.audience,
        entity_id=payload.entity_id,
        deep_link=payload.deep_link,
    )
    if not result.valid:
        raise HTTPException(
            status_code=422,
            detail={
                "error": "invalid_notification",
                "code": result.code,
                "message": result.message,
            },
        )
    # Normalise the payload to the canonical, validated deep link.
    payload.deep_link = result.deep_link


@router.get("/notifications/campaigns")
def list_campaigns(
    page: Pagination = Depends(pagination),
    status: str | None = None,
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    stmt = select(NotificationCampaign)
    if status:
        stmt = stmt.where(NotificationCampaign.status == status)
    if page.search:
        stmt = stmt.where(NotificationCampaign.title.ilike(f"%{page.search}%"))
    return _list(
        stmt.order_by(NotificationCampaign.id.desc()), page, db,
        lambda r: to_dict(r, CAMPAIGN_FIELDS),
    )


@router.get("/notifications/campaigns/{campaign_id}")
def campaign_detail(
    campaign_id: int, db: Session = Depends(get_db), _: AdminUser = Depends(get_current_admin)
):
    campaign = db.get(NotificationCampaign, campaign_id)
    if campaign is None:
        raise HTTPException(status_code=404, detail=f"Campaign {campaign_id} not found")
    return ok(to_dict(campaign, CAMPAIGN_FIELDS))


class CampaignDraft(BaseModel):
    """A composer draft. Drafts are exempt from the full safety contract.

    An operator must be able to save partial work, so only the fields that are
    present are validated. Nothing is dispatched from a draft.
    """

    title: str = ""
    body: str = ""
    notification_type: str = "ADMIN_BROADCAST"
    audience: str = "all"
    deep_link: str | None = None
    entity_id: str | None = None
    reason: str | None = None
    scheduled_at: datetime | None = None
    category: str | None = None
    location: str | None = None
    selected_ids: list[int] | None = None
    metadata: dict[str, Any] | None = None


def _validate_draft_or_400(payload: CampaignDraft):
    """A draft may be incomplete, but anything it *does* carry must be safe.

    A type that is not recognised, an audience the API does not serve, or a
    deep link that would fail validation is still rejected — a draft is never a
    way to smuggle an unvalidated link into the database.
    """
    if payload.notification_type not in NOTIFICATION_TYPES:
        raise HTTPException(
            status_code=422,
            detail={
                "error": "invalid_notification",
                "code": "UNKNOWN_NOTIFICATION_TYPE",
                "message": f"Unsupported notification type: {payload.notification_type}",
            },
        )
    if payload.audience not in SUPPORTED_AUDIENCES:
        raise HTTPException(
            status_code=422,
            detail={
                "error": "invalid_notification",
                "code": "UNSUPPORTED_AUDIENCE",
                "message": f"Unsupported audience: {payload.audience}",
            },
        )
    # Only validate the link when one is supplied (a draft may omit it).
    if payload.deep_link:
        link = validate_explicit_url(payload.deep_link)
        if not link.valid:
            raise HTTPException(
                status_code=422,
                detail={"error": "invalid_notification", "code": link.code, "message": link.message},
            )
        payload.deep_link = link.path


@router.post("/notifications/drafts")
def save_draft(
    payload: CampaignDraft,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("notifications.send")),
):
    """Persist a composer draft. Never dispatches anything."""
    _validate_draft_or_400(payload)

    campaign = NotificationCampaign(
        title=payload.title.strip() or "Untitled draft",
        body=payload.body.strip() or None,
        notification_type=payload.notification_type,
        audience=payload.audience,
        status="DRAFT",
        deep_link=payload.deep_link,
        entity_id=payload.entity_id,
        # A draft has reached nobody: delivery counts stay null.
        recipients_total=_recipient_count(
            db, payload.audience, payload.category, payload.location, payload.selected_ids
        ),
        recipients_sent=None,
        recipients_failed=None,
        scheduled_at=payload.scheduled_at,
        category=payload.category,
        location=payload.location,
        selected_ids=payload.selected_ids,
        metadata_json=payload.metadata,
        reason=payload.reason,
    )
    db.add(campaign)
    db.add(
        AuditLog(
            action="notification.draft_saved",
            entity_type="notification",
            user_id=admin.id,
            admin_user=admin.name or admin.username,
            details={"audience": payload.audience, "type": payload.notification_type},
        )
    )
    db.commit()
    db.refresh(campaign)
    return ok(to_dict(campaign, CAMPAIGN_FIELDS), message="Draft saved")


@router.post("/notifications/send")
def send_notification(
    payload: CampaignCreate,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("notifications.send")),
):
    """Dispatch a broadcast, or schedule it for later.

    The payload is validated against the NOTIFICATION SAFETY contract before
    anything is written. The audience size is resolved up front and recorded on
    the campaign, so the reported recipient count is the one that was actually
    targeted rather than a number invented later. When `scheduled_at` is set the
    campaign is queued (SCHEDULED) and no delivery count is reported until it
    actually goes out.
    """
    _validate_or_400(payload)

    now = datetime.now(timezone.utc)
    scheduled = payload.scheduled_at is not None
    if scheduled:
        target = payload.scheduled_at
        if target.tzinfo is None:
            target = target.replace(tzinfo=timezone.utc)
            payload.scheduled_at = target
        if target <= now:
            raise HTTPException(
                status_code=422,
                detail={
                    "error": "invalid_schedule",
                    "code": "SCHEDULE_IN_PAST",
                    "message": "Scheduled time must be in the future.",
                },
            )
        status = "SCHEDULED"
    else:
        status = "SENT"

    campaign = _persist_campaign(db, admin, payload, status)
    db.add(
        AuditLog(
            action="notification.scheduled" if scheduled else "notification.broadcast",
            entity_type="notification",
            user_id=admin.id,
            admin_user=admin.name or admin.username,
            details={
                "audience": payload.audience,
                "recipients": campaign.recipients_total,
                "scheduled_at": payload.scheduled_at.isoformat() if scheduled else None,
                "reason": payload.reason,
            },
        )
    )
    db.commit()
    db.refresh(campaign)
    if scheduled:
        return ok(
            to_dict(campaign, CAMPAIGN_FIELDS),
            message=f"Scheduled for {payload.scheduled_at.isoformat()}",
        )
    return ok(
        to_dict(campaign, CAMPAIGN_FIELDS),
        message=f"Sent to {campaign.recipients_total} recipients",
    )


@router.post("/notifications/campaigns/{campaign_id}/cancel")
def cancel_campaign(
    campaign_id: int,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("notifications.send")),
):
    campaign = db.get(NotificationCampaign, campaign_id)
    if campaign is None:
        raise HTTPException(status_code=404, detail=f"Campaign {campaign_id} not found")
    if campaign.status in {"SENT", "CANCELLED"}:
        raise HTTPException(
            status_code=409, detail=f"Campaign is already {campaign.status} and cannot be cancelled"
        )
    campaign.status = "CANCELLED"
    db.commit()
    return ok(to_dict(campaign, CAMPAIGN_FIELDS), message="Campaign cancelled")


# --- Subscriptions & payments ---------------------------------------------

SUBSCRIPTION_FIELDS = [
    "id", "shop_id", "shop_name", "plan_name", "status", "amount",
    "currency", "started_at", "expires_at", "created_at",
]
PAYMENT_FIELDS = [
    "id", "subscription_id", "shop_name", "amount", "currency",
    "status", "method", "reference", "paid_at", "created_at",
]


@router.get("/subscriptions")
def list_subscriptions(
    page: Pagination = Depends(pagination),
    status: str | None = None,
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    stmt = select(Subscription)
    if status:
        stmt = stmt.where(Subscription.status == status)
    if page.search:
        stmt = stmt.where(
            or_(Subscription.shop_name.ilike(f"%{page.search}%"), Subscription.plan_name.ilike(f"%{page.search}%"))
        )
    return _list(
        stmt.order_by(Subscription.id.desc()), page, db, lambda r: to_dict(r, SUBSCRIPTION_FIELDS)
    )


class SubscriptionUpdate(BaseModel):
    plan_name: str | None = None
    status: str | None = None
    amount: float | None = None
    expires_at: datetime | None = None


@router.patch("/subscriptions/{subscription_id}")
def update_subscription(
    subscription_id: int,
    payload: SubscriptionUpdate,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("subscriptions.update")),
):
    sub = db.get(Subscription, subscription_id)
    if sub is None:
        raise HTTPException(status_code=404, detail=f"Subscription {subscription_id} not found")
    for key, value in payload.model_dump(exclude_unset=True).items():
        setattr(sub, key, value)
    db.commit()
    db.refresh(sub)
    return ok(to_dict(sub, SUBSCRIPTION_FIELDS), message="Subscription updated")


@router.get("/payments")
def list_payments(
    page: Pagination = Depends(pagination),
    status: str | None = None,
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    stmt = select(Payment)
    if status:
        stmt = stmt.where(Payment.status == status)
    if page.search:
        stmt = stmt.where(
            or_(Payment.shop_name.ilike(f"%{page.search}%"), Payment.reference.ilike(f"%{page.search}%"))
        )
    return _list(
        stmt.order_by(Payment.id.desc()), page, db, lambda r: to_dict(r, PAYMENT_FIELDS)
    )


# --- Complaints ------------------------------------------------------------

COMPLAINT_FIELDS = [
    "id", "ticket_number", "reporter_type", "reporter_name", "complaint_type",
    "priority", "status", "description", "resolution", "created_at", "updated_at",
]


@router.get("/complaints")
def list_complaints(
    page: Pagination = Depends(pagination),
    status: str | None = None,
    priority: str | None = None,
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    stmt = select(Complaint)
    if status:
        stmt = stmt.where(Complaint.status == status)
    if priority:
        stmt = stmt.where(Complaint.priority == priority)
    if page.search:
        like = f"%{page.search}%"
        stmt = stmt.where(
            or_(Complaint.ticket_number.ilike(like), Complaint.description.ilike(like))
        )
    return _list(
        stmt.order_by(Complaint.id.desc()), page, db, lambda r: to_dict(r, COMPLAINT_FIELDS)
    )


class ComplaintUpdate(BaseModel):
    status: str | None = None
    priority: str | None = None
    resolution: str | None = None


@router.patch("/complaints/{complaint_id}")
def update_complaint(
    complaint_id: int,
    payload: ComplaintUpdate,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("support.update")),
):
    complaint = db.get(Complaint, complaint_id)
    if complaint is None:
        raise HTTPException(status_code=404, detail=f"Complaint {complaint_id} not found")
    for key, value in payload.model_dump(exclude_unset=True).items():
        setattr(complaint, key, value)
    db.commit()
    db.refresh(complaint)
    return ok(to_dict(complaint, COMPLAINT_FIELDS), message="Complaint updated")


# --- POS -------------------------------------------------------------------

POS_FIELDS = ["id", "shop_id", "shop_name", "provider", "status", "last_sync", "created_at"]


@router.get("/pos/integrations")
def list_pos(
    page: Pagination = Depends(pagination),
    status: str | None = None,
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    stmt = select(PosIntegration)
    if status:
        stmt = stmt.where(PosIntegration.status == status)
    if page.search:
        stmt = stmt.where(
            or_(PosIntegration.shop_name.ilike(f"%{page.search}%"), PosIntegration.provider.ilike(f"%{page.search}%"))
        )
    return _list(stmt.order_by(PosIntegration.id.desc()), page, db, lambda r: to_dict(r, POS_FIELDS))


@router.get("/pos/integrations/{integration_id}")
def pos_detail(
    integration_id: int, db: Session = Depends(get_db), _: AdminUser = Depends(get_current_admin)
):
    row = db.get(PosIntegration, integration_id)
    if row is None:
        raise HTTPException(status_code=404, detail=f"POS integration {integration_id} not found")
    payload = to_dict(row, POS_FIELDS)
    payload["external_ref"] = row.external_ref
    return ok(payload)


@router.get("/pos/integrations/{integration_id}/syncs")
def pos_sync_history(
    integration_id: int,
    page: Pagination = Depends(pagination),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    if db.get(PosIntegration, integration_id) is None:
        raise HTTPException(status_code=404, detail=f"POS integration {integration_id} not found")
    stmt = select(PosSyncRun).where(PosSyncRun.integration_id == integration_id)
    fields = ["id", "integration_id", "status", "rows_synced", "message", "created_at"]
    return _list(stmt.order_by(PosSyncRun.id.desc()), page, db, lambda r: to_dict(r, fields))


def _pos_transition(db: Session, integration_id: int, status: str, action: str, admin: AdminUser):
    row = db.get(PosIntegration, integration_id)
    if row is None:
        raise HTTPException(status_code=404, detail=f"POS integration {integration_id} not found")
    row.status = status
    if status == "CONNECTED":
        row.last_sync = datetime.now(timezone.utc)
    db.add(
        AuditLog(
            action=action,
            entity_type="pos_integration",
            entity_id=integration_id,
            user_id=admin.id,
            admin_user=admin.name or admin.username,
        )
    )
    db.commit()
    db.refresh(row)
    return ok(to_dict(row, POS_FIELDS), message=f"Integration {action.split('.')[-1]}ed")


@router.post("/pos/integrations/{integration_id}/sync")
def pos_sync(
    integration_id: int,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("pos.manage")),
):
    row = db.get(PosIntegration, integration_id)
    if row is None:
        raise HTTPException(status_code=404, detail=f"POS integration {integration_id} not found")
    row.last_sync = datetime.now(timezone.utc)
    run = PosSyncRun(integration_id=integration_id, status="SUCCESS", rows_synced=0, message="Manual sync")
    db.add(run)
    db.add(
        AuditLog(
            action="pos.sync",
            entity_type="pos_integration",
            entity_id=integration_id,
            user_id=admin.id,
            admin_user=admin.name or admin.username,
        )
    )
    db.commit()
    db.refresh(row)
    return ok(to_dict(row, POS_FIELDS), message="Sync triggered")


@router.post("/pos/integrations/{integration_id}/disconnect")
def pos_disconnect(
    integration_id: int,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("pos.manage")),
):
    return _pos_transition(db, integration_id, "DISCONNECTED", "pos.disconnect", admin)


@router.post("/pos/integrations/{integration_id}/reconnect")
def pos_reconnect(
    integration_id: int,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("pos.manage")),
):
    return _pos_transition(db, integration_id, "CONNECTED", "pos.reconnect", admin)


# --- Imports ---------------------------------------------------------------

IMPORT_FIELDS = [
    "id", "shop_id", "shop_name", "source", "filename", "status",
    "rows_total", "rows_processed", "rows_failed", "created_at", "updated_at",
]


@router.get("/imports")
def list_imports(
    page: Pagination = Depends(pagination),
    status: str | None = None,
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    stmt = select(ImportJob)
    if status:
        stmt = stmt.where(ImportJob.status == status)
    if page.search:
        stmt = stmt.where(
            or_(ImportJob.shop_name.ilike(f"%{page.search}%"), ImportJob.source.ilike(f"%{page.search}%"))
        )
    return _list(stmt.order_by(ImportJob.id.desc()), page, db, lambda r: to_dict(r, IMPORT_FIELDS))


@router.get("/imports/{import_id}")
def import_detail(
    import_id: int, db: Session = Depends(get_db), _: AdminUser = Depends(get_current_admin)
):
    job = db.get(ImportJob, import_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"Import {import_id} not found")
    return ok(to_dict(job, IMPORT_FIELDS))


@router.get("/imports/{import_id}/errors")
def import_errors(
    import_id: int,
    page: Pagination = Depends(pagination),
    db: Session = Depends(get_db),
    _: AdminUser = Depends(get_current_admin),
):
    if db.get(ImportJob, import_id) is None:
        raise HTTPException(status_code=404, detail=f"Import {import_id} not found")
    stmt = select(ImportError).where(ImportError.import_id == import_id)
    fields = ["id", "import_id", "row_number", "column_name", "message", "raw_value", "created_at"]
    return _list(stmt.order_by(ImportError.row_number), page, db, lambda r: to_dict(r, fields))


@router.post("/imports/{import_id}/retry")
def retry_import(
    import_id: int,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("imports.manage")),
):
    job = db.get(ImportJob, import_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"Import {import_id} not found")
    if job.status == "PROCESSING":
        raise HTTPException(status_code=409, detail="Import is already processing")
    job.status = "PROCESSING"
    job.rows_processed = 0
    job.rows_failed = 0
    db.add(
        AuditLog(
            action="import.retried",
            entity_type="import",
            entity_id=import_id,
            user_id=admin.id,
            admin_user=admin.name or admin.username,
        )
    )
    db.commit()
    db.refresh(job)
    return ok(to_dict(job, IMPORT_FIELDS), message="Import queued for retry")


@router.post("/imports/{import_id}/cancel")
def cancel_import(
    import_id: int,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("imports.manage")),
):
    job = db.get(ImportJob, import_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"Import {import_id} not found")
    if job.status in {"COMPLETED", "CANCELLED"}:
        raise HTTPException(status_code=409, detail=f"Import is already {job.status}")
    job.status = "CANCELLED"
    db.commit()
    db.refresh(job)
    return ok(to_dict(job, IMPORT_FIELDS), message="Import cancelled")


# --- System ----------------------------------------------------------------

FLAG_FIELDS = [
    "name", "is_enabled", "rollout_percentage", "scope", "description",
    "environment", "changed_by", "updated_at",
]
SETTING_FIELDS = ["key", "value", "value_type", "description", "is_secret", "updated_at"]

# The example flags named in the spec are seeded when absent so the console has
# something meaningful to show on a fresh deployment. A flag already in the
# database is never overwritten — an operator's decision wins over the seed.
DEFAULT_FLAGS = (
    ("BARCODE_SEARCH", "Barcode-scan product lookup in discovery."),
    ("EXCEL_IMPORT", "Bulk product/inventory import via Excel workbooks."),
    ("POS", "Point-of-sale integrations and inventory sync."),
    ("OFFERS", "Merchant offers and promotions surface."),
    ("AI_SEARCH", "AI-assisted semantic search ranking."),
    ("NEW_SEARCH_UI", "Next-generation search experience."),
)


def _resolve_flag(row: FeatureFlag, db: Session) -> dict:
    """One flag, enriched with its last-change actor from the audit trail.

    `changed_by` is stored on the row when a change goes through this API, but
    a row seeded or edited out-of-band has none. Rather than render a blank —
    which reads as "nobody changed it" — the actor is resolved from the newest
    matching audit entry. The audit log stays the source of truth.
    """
    payload = to_dict(row, FLAG_FIELDS)
    if not payload.get("changed_by"):
        entry = db.scalar(
            select(AuditLog)
            .where(
                AuditLog.entity_type == "feature_flag",
                AuditLog.details["name"].as_string() == row.name,
            )
            .order_by(AuditLog.created_at.desc(), AuditLog.id.desc())
        )
        payload["changed_by"] = entry.admin_user if entry else None
        if entry is not None and not payload.get("environment"):
            details = entry.details or {}
            payload["environment"] = details.get("environment")
    return payload


@router.get("/feature-flags")
def list_flags(db: Session = Depends(get_db), _: AdminUser = Depends(get_current_admin)):
    """Every feature flag, with status, environment and last-change actor.

    The spec's example flags are ensured present first so a fresh deployment
    shows the standard set rather than an empty grid.
    """
    existing = {row.name for row in db.scalars(select(FeatureFlag)).all()}
    seeded = False
    for name, description in DEFAULT_FLAGS:
        if name not in existing:
            db.add(
                FeatureFlag(
                    name=name,
                    is_enabled=False,
                    rollout_percentage=0,
                    scope="GLOBAL",
                    description=description,
                    environment="PRODUCTION",
                )
            )
            seeded = True
    if seeded:
        db.commit()

    rows = db.scalars(select(FeatureFlag).order_by(FeatureFlag.name)).all()
    return ok({"items": [_resolve_flag(r, db) for r in rows], "total": len(rows)})


class FlagUpdate(BaseModel):
    is_enabled: bool | None = None
    rollout_percentage: int | None = None
    scope: str | None = None
    description: str | None = None
    environment: str | None = None
    reason: str | None = None


@router.patch("/feature-flags/{name}")
def update_flag(
    name: str,
    payload: FlagUpdate,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("system.flags")),
):
    flag = db.get(FeatureFlag, name)
    if flag is None:
        raise HTTPException(status_code=404, detail=f"Feature flag '{name}' not found")

    changes = payload.model_dump(exclude_unset=True)
    # `reason` is part of the request envelope, not the flag record.
    reason = changes.pop("reason", None)
    previous = {key: getattr(flag, key, None) for key in changes}

    for key, value in changes.items():
        setattr(flag, key, value)
    flag.changed_by = admin.name or admin.username

    db.add(
        AuditLog(
            action="feature_flag.updated",
            entity_type="feature_flag",
            user_id=admin.id,
            admin_user=admin.name or admin.username,
            details={
                "name": name,
                **changes,
                "reason": reason,
                "before": previous,
                "after": {key: getattr(flag, key, None) for key in changes},
            },
        )
    )
    db.commit()
    db.refresh(flag)
    return ok(_resolve_flag(flag, db), message="Feature flag updated")


@router.get("/settings")
def list_settings(db: Session = Depends(get_db), _: AdminUser = Depends(get_current_admin)):
    rows = db.scalars(select(SystemSetting).order_by(SystemSetting.key)).all()
    items = []
    for r in rows:
        row = to_dict(r, SETTING_FIELDS)
        # A secret's value is never returned, only the fact that one is set.
        if r.is_secret:
            row["value"] = "••••••••"
        items.append(row)
    return ok({"items": items, "total": len(items)})


class SettingUpdate(BaseModel):
    value: str


@router.patch("/settings/{key}")
def update_setting(
    key: str,
    payload: SettingUpdate,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("system.settings")),
):
    setting = db.get(SystemSetting, key)
    if setting is None:
        raise HTTPException(status_code=404, detail=f"Setting '{key}' not found")
    setting.value = payload.value
    db.add(
        AuditLog(
            action="setting.updated",
            entity_type="setting",
            user_id=admin.id,
            admin_user=admin.name or admin.username,
            details={"key": key},
        )
    )
    db.commit()
    db.refresh(setting)
    return ok(to_dict(setting, SETTING_FIELDS), message="Setting updated")
