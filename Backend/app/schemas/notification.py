from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel


class NotificationResponse(BaseModel):
    id: int
    title: str
    body: str
    type: str
    is_read: bool
    payload: Optional[str]
    created_at: datetime

    model_config = {"from_attributes": True}


class NotificationListResponse(BaseModel):
    notifications: List[NotificationResponse] = []
    unread_count: int = 0