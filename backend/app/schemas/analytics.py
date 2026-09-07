"""Phase 29 — Analytics event ingestion schemas."""
from pydantic import BaseModel, Field


class AnalyticsEventIn(BaseModel):
    """Client-submitted analytics event (PII-scrubbed server-side)."""

    event_name: str = Field(..., max_length=60)
    actor_type: str = Field("CUSTOMER", max_length=20)
    session_id: str | None = Field(None, max_length=64)
    shop_id: int | None = None
    product_master_id: int | None = None
    category_id: int | None = None
    query: str | None = Field(None, max_length=255)
    metric_value: float | None = None
    props: dict | None = None
    device_type: str | None = Field(None, max_length=20)
    app_version: str | None = Field(None, max_length=20)