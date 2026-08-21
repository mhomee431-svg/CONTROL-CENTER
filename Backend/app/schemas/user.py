from datetime import datetime
from pydantic import BaseModel, EmailStr, Field


class UserBase(BaseModel):
    name: str | None = Field(None, max_length=120)
    email: EmailStr | None = None
    avatar_url: str | None = None


class UserUpdate(BaseModel):
    name: str | None = Field(None, max_length=120)
    email: EmailStr | None = None
    avatar_url: str | None = None


class UserResponse(UserBase):
    id: int
    phone_number: str
    is_active: bool
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}