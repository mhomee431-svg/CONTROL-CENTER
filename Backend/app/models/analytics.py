"""Product Views, Shop Views, Product Clicks, Inventory Events, System Metrics models."""
from datetime import datetime
from sqlalchemy import String, Integer, DateTime, Boolean, Text, ForeignKey, Float, Index, Enum
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.session import Base
from app.models.base import TimestampMixin
from app.models.product import InventorySource


class ProductView(Base, TimestampMixin):
    __tablename__ = "product_views"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    product_master_id: Mapped[int] = mapped_column(ForeignKey("product_masters.id"), index=True, nullable=False)
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), index=True)
    session_id: Mapped[str | None] = mapped_column(String(100), index=True)
    device_type: Mapped[str | None] = mapped_column(String(20))  # android, ios, web
    app_version: Mapped[str | None] = mapped_column(String(20))
    viewed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)

    product = relationship("ProductMaster", back_populates="views")


class ShopView(Base, TimestampMixin):
    __tablename__ = "shop_views"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    shop_id: Mapped[int] = mapped_column(ForeignKey("shops.id"), index=True, nullable=False)
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), index=True)
    session_id: Mapped[str | None] = mapped_column(String(100), index=True)
    device_type: Mapped[str | None] = mapped_column(String(20))
    app_version: Mapped[str | None] = mapped_column(String(20))
    viewed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)


class ProductClick(Base, TimestampMixin):
    __tablename__ = "product_clicks"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    product_master_id: Mapped[int] = mapped_column(ForeignKey("product_masters.id"), index=True, nullable=False)
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), index=True)
    session_id: Mapped[str | None] = mapped_column(String(100), index=True)
    source: Mapped[str] = mapped_column(String(50), nullable=False, default="SEARCH")  # SEARCH, BARCODE_SCAN, RECENT
    clicked_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)
    query: Mapped[str | None] = mapped_column(String(255))
    shop_id: Mapped[int | None] = mapped_column(ForeignKey("shops.id"), index=True)
    shop_product_id: Mapped[int | None] = mapped_column(ForeignKey("shop_products.id"))

    product = relationship("ProductMaster", back_populates="clicks")


class InventoryEvent(Base, TimestampMixin):
    __tablename__ = "inventory_events"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    shop_product_id: Mapped[int] = mapped_column(ForeignKey("shop_products.id"), index=True, nullable=False)
    event_type: Mapped[str] = mapped_column(String(50), nullable=False)  # STOCK_RECEIVED, STOCK, DAMAGED, EXPIRED
    quantity_change: Mapped[int] = mapped_column(Integer, nullable=False)  # +ve or -ve
    source: Mapped[InventorySource] = mapped_column(
        Enum(InventorySource, name="inventory_source"), nullable=False, default=InventorySource.MANUAL
    )
    reference_type: Mapped[str | None] = mapped_column(String(50))  # POS_SYNC, BARCODE_SCAN, EXCEL_UPLOAD
    reference_id: Mapped[int | None] = mapped_column(Integer)
    notes: Mapped[str | None] = mapped_column(Text)
    created_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)

    shop_product = relationship("ShopProduct", back_populates="inventory_events")


class SystemMetric(Base, TimestampMixin):
    __tablename__ = "system_metrics"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    metric_name: Mapped[str] = mapped_column(String(100), nullable=False, index=True)  # cpu_usage, memory_usage, api_latency_p95, error_rate
    metric_value: Mapped[float] = mapped_column(Float, nullable=False)
    unit: Mapped[str] = mapped_column(String(20), default="percent")  # "percent", "ms", "count", "bytes"
    shop_id: Mapped[int | None] = mapped_column(ForeignKey("shops.id"), index=True)  # null if global metric
    source: Mapped[str] = mapped_column(String(50), default="PROMETHEUS")  # PROMETHEUS, DB_QUERY, MANUAL
    recorded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)