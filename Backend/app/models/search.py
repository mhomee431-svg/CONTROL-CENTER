"""Search History, Search Events, Popular Searches, Barcode Scans models."""
from datetime import datetime
from sqlalchemy import String, Integer, DateTime, Boolean, Text, ForeignKey, UniqueConstraint, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.session import Base
from app.models.base import TimestampMixin


class SearchHistory(Base, TimestampMixin):
    __tablename__ = "search_history"
    __table_args__ = (
        Index("ix_search_history_user_query", "user_id", "query"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)
    query: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    result_count: Mapped[int | None] = mapped_column(Integer)
    is_successful: Mapped[bool] = mapped_column(Boolean, default=True)
    searched_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)

    user = relationship("User", back_populates="search_history")


class SearchEvent(Base, TimestampMixin):
    __tablename__ = "search_events"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), index=True)
    session_id: Mapped[str | None] = mapped_column(String(100), index=True)
    query: Mapped[str] = mapped_column(String(255), nullable=False)
    event_type: Mapped[str] = mapped_column(String(50), nullable=False)  # SEARCH, SUGGESTION_CLICK, RESULT_CLICK
    result_count: Mapped[int | None] = mapped_column(Integer)
    clicked_product_id: Mapped[int | None] = mapped_column(ForeignKey("product_masters.id"))
    clicked_shop_id: Mapped[int | None] = mapped_column(ForeignKey("shops.id"))
    device_type: Mapped[str | None] = mapped_column(String(20))
    app_version: Mapped[str | None] = mapped_column(String(20))
    event_time: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)


class PopularSearch(Base, TimestampMixin):
    __tablename__ = "popular_searches"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    query: Mapped[str] = mapped_column(String(255), unique=True, nullable=False, index=True)
    search_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    result_count: Mapped[int | None] = mapped_column(Integer)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    last_searched_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class BarcodeScan(Base, TimestampMixin):
    __tablename__ = "barcode_scans"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    barcode: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
    barcode_type: Mapped[str | None] = mapped_column(String(20))  # EAN-13, UPC-A, QR, etc.
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), index=True)
    shop_id: Mapped[int | None] = mapped_column(ForeignKey("shops.id"), index=True)
    product_master_id: Mapped[int | None] = mapped_column(ForeignKey("product_masters.id"), index=True)
    scan_source: Mapped[str] = mapped_column(String(50), default="CUSTOMER_APP")  # CUSTOMER_APP, SHOPKEEPER_APP
    is_match_found: Mapped[bool] = mapped_column(Boolean, default=False)
    scan_time: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)