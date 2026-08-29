"""Pydantic schemas for the User Interactions / Leads API."""
from typing import Literal

from pydantic import BaseModel, Field, field_validator

ActionType = Literal["call_view", "message", "rating"]


class InteractionCreateRequest(BaseModel):
    """Create a verified customer action on a shop.

    Create-only by design — there are no update/delete endpoints for these
    records (Immutable Actions Rule).
    """

    action_type: ActionType
    shop_id: int = Field(..., ge=1)
    message_content: str | None = Field(None, max_length=2000)
    rating: int | None = Field(None, ge=1, le=5)

    @field_validator("message_content")
    @classmethod
    def _strip_message(cls, v):
        if v is None:
            return None
        stripped = v.strip()
        return stripped or None


class InteractionOut(BaseModel):
    id: int
    shop_id: int
    action_type: str
    message_content: str | None = None
    rating: int | None = None
    created_at: str | None = None


class ShopReviewOut(BaseModel):
    id: int
    rating: int | None = None
    message_content: str | None = None
    created_at: str | None = None


class ShopReviewsResponse(BaseModel):
    shop_id: int
    average_rating: float | None = None
    rating_count: int
    reviews: list[ShopReviewOut]


class LeadOut(BaseModel):
    id: int
    shop_id: int
    shop_name: str | None = None
    action_type: str
    message_content: str | None = None
    rating: int | None = None
    customer_name: str | None = None
    customer_phone: str | None = None
    created_at: str | None = None