"""SavedProduct model."""
from datetime import datetime
from sqlalchemy import DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.session import Base
from app.models.base import TimestampMixin


class SavedProduct(Base, TimestampMixin):
    __tablename__ = "saved_products"
    __table_args__ = (UniqueConstraint("user_id", "product_master_id", name="uq_saved_product_user_product"),)

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)
    product_master_id: Mapped[int] = mapped_column(ForeignKey("product_masters.id"), index=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow)

    user = relationship("User", back_populates="saved_products")
    product = relationship("ProductMaster", back_populates="saved_by_users")