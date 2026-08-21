"""System Settings and Feature Flags models."""
from datetime import datetime
from sqlalchemy import String, Integer, DateTime, Boolean, Text, JSON
from sqlalchemy.orm import Mapped, mapped_column

from app.database.session import Base
from app.models.base import TimestampMixin


class SystemSetting(Base, TimestampMixin):
    __tablename__ = "system_settings"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    key: Mapped[str] = mapped_column(String(100), unique=True, nullable=False, index=True)
    value: Mapped[str] = mapped_column(Text, nullable=False)
    value_type: Mapped[str] = mapped_column(String(20), default="string")  # string, int, float, boolean, json
    description: Mapped[str | None] = mapped_column(Text)
    is_secret: Mapped[bool] = mapped_column(Boolean, default=False)
    updated_by: Mapped[int | None] = mapped_column(Integer)


class FeatureFlag(Base, TimestampMixin):
    __tablename__ = "feature_flags"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(100), unique=True, nullable=False, index=True)
    description: Mapped[str | None] = mapped_column(Text)
    is_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    default_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    rollout_percentage: Mapped[int] = mapped_column(Integer, default=100)
    scope: Mapped[str] = mapped_column(String(20), default="GLOBAL")  # GLOBAL, SHOP, USER, REGION
    target_ids_json: Mapped[dict | None] = mapped_column(JSON)  # {"shop_ids": [1, 2]}
    conditions_json: Mapped[dict | None] = mapped_column(JSON)  # deployment conditions
    updated_by: Mapped[int | None] = mapped_column(Integer)