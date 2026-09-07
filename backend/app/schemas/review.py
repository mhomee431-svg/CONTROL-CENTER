"""Reviews schemas — Master Spec §§19-20, 49."""
from __future__ import annotations

from datetime import date, datetime
from typing import Optional
from pydantic import BaseModel, Field, ConfigDict


# ── Review Create ──────────────────────────────────────────────────────────
class ReviewCreate(BaseModel):
    shop_id: Optional[int] = Field(None, description="Shop ID (if reviewing a shop)")
    product_master_id: Optional[int] = Field(None, description="Product ID (if reviewing a product)")
    rating: int = Field(..., ge=1, le=5)
    title: Optional[str] = Field(None, max_length=255)
    body: Optional[str] = None


# ── Review Response ────────────────────────────────────────────────────────
class ReviewResponse(BaseModel):
    id: int
    user_id: int
    shop_id: Optional[int] = None
    product_master_id: Optional[int] = None
    rating: int
    title: Optional[str] = None
    body: Optional[str] = None
    is_verified_purchase: bool
    status: str
    moderated_by: Optional[int] = None
    moderated_at: Optional[date] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ── Review Moderation (Admin) ──────────────────────────────────────────────
class ReviewModeration(BaseModel):
    status: str = Field(..., description="APPROVED, REJECTED, HIDDEN")
