from datetime import datetime
from pydantic import BaseModel


class CategoryResponse(BaseModel):
    id: int
    name: str
    icon_url: str | None
    created_at: datetime

    model_config = {"from_attributes": True}