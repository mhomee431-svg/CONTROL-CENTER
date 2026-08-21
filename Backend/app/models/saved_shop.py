"""SavedShop model."""
from datetime import datetime
from sqlalchemy import DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.session import Base
from app.models.base import TimestampMixin


class SavedShop(Base, TimestampMixin):
    __tablename__ = "saved_shops"
    __table_args__ = (UniqueConstraint("user_id", "shop_id", name="uq_saved_shop_user_shop"),)

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)
    shop_id: Mapped[int] = mapped_column(ForeignKey("shops.id"), index=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)

    user = relationship("User", back_populates="saved_shops")
    shop = relationship("Shop", back_populates="saved_by_users")