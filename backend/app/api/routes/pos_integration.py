"""Phase 25 — Shopkeeper POS integration platform routes.

All endpoints are shop-scoped and association-checked via
``resolve_shop_access`` (same model as the inventory-intake routes).
"""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.core.exceptions import AppError
from app.core.responses import error_response, success_response
from app.database.session import get_db
from app.models.user import User
from app.schemas.pos import (
    POSCredentialUpdateRequest,
    POSDeviceRequest,
    POSScheduleRequest,
    POSSyncConfigRequest,
    POSTriggerSyncRequest,
    POSRegisterRequest,
)
from app.services import pos_sync_service, shopkeeper_service
from app.services.pos_integration.base import list_providers

router = APIRouter(prefix="/shopkeeper/pos", tags=["shopkeeper-pos-integration"])


def _app_error(exc: AppError):
    return error_response(
        message=exc.message,
        error_code=exc.error_code,
        status_code=exc.status_code,
        data=getattr(exc, "data", None),
    )


def _resolve(shop_id: int, current_user: User, db: Session):
    return shopkeeper_service.resolve_shop_access(db, current_user, shop_id)


def _owned_integration(integration_id: int, current_user: User, db: Session):
    """Load an integration and prove the caller belongs to its shop."""
    integration = pos_sync_service._require_integration(db, integration_id)
    _resolve(integration.shop_id, current_user, db)
    return integration


# ── Providers & registration ────────────────────────────────────────────────
@router.get("/providers")
async def get_pos_providers():
    """Registry listing — every pluggable POS vendor adapter."""
    return success_response(data={"providers": list_providers()})


@router.post("/register", status_code=201)
async def register_pos_integration(
    payload: POSRegisterRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        _resolve(payload.shop_id, current_user, db)
        integration = pos_sync_service.register_integration(
            db,
            shop_id=payload.shop_id,
            provider_code=payload.provider_code,
            integration_type=payload.integration_type,
            api_base_url=payload.api_base_url,
            api_key=payload.api_key,
            api_secret=payload.api_secret,
            config=payload.config,
        )
        result = pos_sync_service.integration_payload(db, integration)
        db.commit()
    except AppError as exc:
        db.rollback()
        return _app_error(exc)
    return success_response(data=result, message="POS integration registered", status_code=201)


@router.get("/integrations")
async def list_pos_integrations(
    shop_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    from app.models.pos import POSIntegration

    try:
        _resolve(shop_id, current_user, db)
    except AppError as exc:
        return _app_error(exc)
    rows = (
        db.query(POSIntegration)
        .filter(POSIntegration.shop_id == shop_id, POSIntegration.is_deleted == False)  # noqa: E712
        .all()
    )
    data = {"integrations": [pos_sync_service.integration_payload(db, r) for r in rows]}
    return success_response(data=data)


@router.get("/integrations/{integration_id}")
async def get_pos_integration(
    integration_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        integration = _owned_integration(integration_id, current_user, db)
    except AppError as exc:
        return _app_error(exc)
    return success_response(data=pos_sync_service.integration_payload(db, integration))


@router.put("/integrations/{integration_id}/credentials")
async def update_pos_credentials(
    integration_id: int,
    payload: POSCredentialUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        _owned_integration(integration_id, current_user, db)
        integration = pos_sync_service.update_credentials(
            db, integration_id,
            api_key=payload.api_key, api_secret=payload.api_secret, api_base_url=payload.api_base_url,
        )
        result = pos_sync_service.integration_payload(db, integration)
        db.commit()
    except AppError as exc:
        db.rollback()
        return _app_error(exc)
    return success_response(data=result, message="Credentials updated")


@router.put("/integrations/{integration_id}/config")
async def update_pos_config(
    integration_id: int,
    payload: POSSyncConfigRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        _owned_integration(integration_id, current_user, db)
        integration = pos_sync_service.update_sync_config(db, integration_id, payload.config)
        result = pos_sync_service.integration_payload(db, integration)
        db.commit()
    except AppError as exc:
        db.rollback()
        return _app_error(exc)
    return success_response(data=result, message="Sync configuration updated")


@router.put("/integrations/{integration_id}/schedule")
async def update_pos_schedule(
    integration_id: int,
    payload: POSScheduleRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        _owned_integration(integration_id, current_user, db)
        integration = pos_sync_service.update_schedule(
            db, integration_id,
            sync_interval_minutes=payload.sync_interval_minutes, sync_enabled=payload.sync_enabled,
        )
        result = pos_sync_service.integration_payload(db, integration)
        db.commit()
    except AppError as exc:
        db.rollback()
        return _app_error(exc)
    return success_response(data=result, message="Sync schedule updated")


# ── Connect lifecycle ────────────────────────────────────────────────────────
@router.post("/integrations/{integration_id}/connect")
async def connect_pos(
    integration_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        _owned_integration(integration_id, current_user, db)
        result = pos_sync_service.connect_integration(db, integration_id)
        db.commit()
    except AppError as exc:
        db.rollback()
        return _app_error(exc)
    return success_response(data=result, message="Connected" if result["connected"] else "Connection failed")


@router.post("/integrations/{integration_id}/disconnect")
async def disconnect_pos(
    integration_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        _owned_integration(integration_id, current_user, db)
        integration = pos_sync_service.disconnect_integration(db, integration_id)
        result = pos_sync_service.integration_payload(db, integration)
        db.commit()
    except AppError as exc:
        db.rollback()
        return _app_error(exc)
    return success_response(data=result, message="POS integration disconnected")


@router.post("/integrations/{integration_id}/reconnect")
async def reconnect_pos(
    integration_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        _owned_integration(integration_id, current_user, db)
        result = pos_sync_service.reconnect_integration(db, integration_id)
        db.commit()
    except AppError as exc:
        db.rollback()
        return _app_error(exc)
    return success_response(data=result, message="Reconnected" if result["connected"] else "Reconnection failed")


# ── Device mapping ───────────────────────────────────────────────────────────
@router.post("/integrations/{integration_id}/devices", status_code=201)
async def register_pos_device(
    integration_id: int,
    payload: POSDeviceRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        integration = _owned_integration(integration_id, current_user, db)
        device = pos_sync_service.register_device(
            db,
            shop_id=integration.shop_id,
            integration_id=integration_id,
            device_identifier=payload.device_identifier,
            device_name=payload.device_name,
            device_type=payload.device_type,
        )
        result = {
            "id": device.id,
            "device_identifier": device.device_identifier,
            "device_name": device.device_name,
            "device_type": device.device_type,
            "is_active": device.is_active,
        }
        db.commit()
    except AppError as exc:
        db.rollback()
        return _app_error(exc)
    return success_response(data=result, message="Device registered", status_code=201)


@router.get("/integrations/{integration_id}/devices")
async def list_pos_devices(
    integration_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        integration = _owned_integration(integration_id, current_user, db)
    except AppError as exc:
        return _app_error(exc)
    devices = pos_sync_service.list_devices(db, integration.shop_id)
    data = [
        {
            "id": d.id,
            "device_identifier": d.device_identifier,
            "device_name": d.device_name,
            "device_type": d.device_type,
            "is_active": d.is_active,
            "last_connected_at": d.last_connected_at,
        }
        for d in devices
    ]
    return success_response(data={"devices": data})


# ── Sync operations ──────────────────────────────────────────────────────────
@router.post("/integrations/{integration_id}/sync", status_code=202)
async def trigger_pos_sync(
    integration_id: int,
    payload: POSTriggerSyncRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        integration = _owned_integration(integration_id, current_user, db)
        job, created = pos_sync_service.trigger_manual_sync(
            db,
            integration.id,
            sync_type=payload.sync_type,
            user_id=current_user.id,
            idempotency_key=payload.idempotency_key,
        )
        result = pos_sync_service.job_payload(job)
        result["created"] = created
        db.commit()
    except AppError as exc:
        db.rollback()
        return _app_error(exc)
    return success_response(
        data=result,
        message="Sync queued" if created else "Existing job returned (idempotency key)",
        status_code=202,
    )


@router.get("/integrations/{integration_id}/status")
async def pos_sync_status(
    integration_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        integration = _owned_integration(integration_id, current_user, db)
    except AppError as exc:
        return _app_error(exc)
    return success_response(data=pos_sync_service.sync_status(db, integration))


@router.get("/integrations/{integration_id}/jobs")
async def list_pos_jobs(
    integration_id: int,
    limit: int = 20,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        _owned_integration(integration_id, current_user, db)
    except AppError as exc:
        return _app_error(exc)
    jobs = pos_sync_service.list_jobs(db, integration_id, limit=min(limit, 100))
    return success_response(data={"jobs": [pos_sync_service.job_payload(j) for j in jobs]})


@router.get("/jobs/{job_id}")
async def get_pos_job(
    job_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        job = pos_sync_service._require_job(db, job_id)
        _owned_integration(job.integration_id, current_user, db)
    except AppError as exc:
        return _app_error(exc)
    return success_response(data=pos_sync_service.job_detail(db, job))


@router.post("/jobs/{job_id}/retry")
async def retry_pos_job(
    job_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        job = pos_sync_service._require_job(db, job_id)
        _owned_integration(job.integration_id, current_user, db)
        result = pos_sync_service.retry_failed_job(db, job_id, user_id=current_user.id)
        db.commit()
    except AppError as exc:
        db.rollback()
        return _app_error(exc)
    return success_response(data=result, message="Retry finished")
