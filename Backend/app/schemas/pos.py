"""Phase 25 — Pydantic schemas for the POS integration platform."""

from pydantic import BaseModel, Field


class POSRegisterRequest(BaseModel):
    """Register a new POS provider integration for a shop."""

    shop_id: int = Field(..., ge=1)
    provider_code: str = Field(..., min_length=1, max_length=50)
    integration_type: str = Field("API", max_length=50)  # API | FILE_UPLOAD | WEBHOOK
    api_base_url: str | None = Field(None, max_length=500)
    api_key: str | None = None
    api_secret: str | None = None
    config: dict | None = None


class POSCredentialUpdateRequest(BaseModel):
    """Rotate stored credentials."""

    api_key: str | None = None
    api_secret: str | None = None
    api_base_url: str | None = Field(None, max_length=500)


class POSSyncConfigRequest(BaseModel):
    """Merge vendor-neutral sync configuration (authorities, thresholds…)."""

    config: dict


class POSScheduleRequest(BaseModel):
    """Background sync cadence / pause-resume."""

    sync_interval_minutes: int | None = Field(None, ge=5)
    sync_enabled: bool | None = None


class POSDeviceRequest(BaseModel):
    """Register/map a physical POS terminal."""

    device_identifier: str = Field(..., min_length=1, max_length=100)
    device_name: str | None = Field(None, max_length=255)
    device_type: str | None = Field(None, max_length=50)  # POS_TERMINAL | SCANNER | TABLET


class POSTriggerSyncRequest(BaseModel):
    """Manual sync trigger with optional idempotency key."""

    sync_type: str = Field("FULL", max_length=20)  # FULL | INCREMENTAL
    idempotency_key: str | None = Field(None, max_length=64)
