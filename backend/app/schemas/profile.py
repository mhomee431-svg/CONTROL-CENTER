from datetime import datetime
from pydantic import BaseModel, EmailStr, Field


class ProfileResponse(BaseModel):
    id: int
    name: str | None
    email: EmailStr | None
    phone_number: str
    avatar_url: str | None
    created_at: datetime

    model_config = {"from_attributes": True}


class ProfileUpdate(BaseModel):
    name: str | None = Field(None, max_length=120)
    email: EmailStr | None = None
    avatar_url: str | None = None