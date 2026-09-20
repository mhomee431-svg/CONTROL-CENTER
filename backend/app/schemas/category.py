from datetime import datetime
from pydantic import BaseModel, field_validator


class CategoryResponse(BaseModel):
    """A product category — flat, with its parent link.

    Deliberately flat rather than nested: the client fetches the whole
    taxonomy ONCE and indexes it, so choosing a category → subcategory is a
    local lookup instead of a second round trip. `parent_id` is what makes
    that cascade possible, and `is_subcategory` lets the UI treat the same
    table as two levels without guessing from `parent_id` alone.
    """

    id: int
    name: str
    slug: str | None = None
    description: str | None = None
    icon_url: str | None = None
    parent_id: int | None = None
    sort_order: int = 0
    is_active: bool = True
    is_subcategory: bool = False
    created_at: datetime

    model_config = {"from_attributes": True}

    @field_validator("sort_order", mode="before")
    @classmethod
    def _default_sort_order(cls, value: object) -> object:
        # The column's `default=0` is applied at INSERT, so a row built
        # outside a session (or legacy data) can still carry NULL. The API
        # contract stays a plain int — the client never sees null.
        return 0 if value is None else value