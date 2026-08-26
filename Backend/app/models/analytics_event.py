"""Phase 29 — Unified platform analytics event store.

A single append-only event stream feeds every business metric:
    - CUSTOMER    : search / click / view / directions / save / share
    - SHOPKEEPER  : catalog + inventory + intake + POS activity
    - PLATFORM    : search outcome, freshness, API performance, errors

Privacy: events intentionally avoid personal information. ``actor_id`` is the
surrogate user id only (never contact data), ``session_id`` is an opaque
client-generated identifier, free-form ``props`` are scrubbed of PII keys by
``analytics_system.sanitize_props`` before persistence.
"""
from datetime import datetime, date
from sqlalchemy import (
    String, Integer, DateTime, Date, Float, ForeignKey, JSON, Index,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.database.session import Base
from app.models.base import TimestampMixin


class AnalyticsEvent(Base):
    """Append-only, privacy-preserving platform event."""

    __tablename__ = "analytics_events"
    __table_args__ = (
        Index("ix_analytics_events_name_time", "event_name", "occurred_at"),
        Index("ix_analytics_events_actor_time", "actor_type", "occurred_at"),
        Index("ix_analytics_events_shop_time", "shop_id", "occurred_at"),
        Index("ix_analytics_events_product_time", "product_master_id", "occurred_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    event_name: Mapped[str] = mapped_column(String(60), nullable=False)
    actor_type: Mapped[str] = mapped_column(String(20), nullable=False)  # CUSTOMER | SHOPKEEPER | PLATFORM
    actor_id: Mapped[int | None] = mapped_column(Integer, index=True)  # surrogate user id — no PII
    session_id: Mapped[str | None] = mapped_column(String(64), index=True)  # opaque client session key
    shop_id: Mapped[int | None] = mapped_column(ForeignKey("shops.id"), index=True)
    product_master_id: Mapped[int | None] = mapped_column(ForeignKey("product_masters.id"))
    category_id: Mapped[int | None] = mapped_column(ForeignKey("categories.id"), index=True)

    query: Mapped[str | None] = mapped_column(String(255))          # normalized search text
    metric_value: Mapped[float | None] = mapped_column(Float)       # duration_ms, amount, freshness ratio...
    props: Mapped[dict | None] = mapped_column(JSON)                # sanitized, non-PII context

    device_type: Mapped[str | None] = mapped_column(String(20))     # android | ios | web
    app_version: Mapped[str | None] = mapped_column(String(20))

    occurred_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=datetime.utcnow, index=True
    )

    def __repr__(self) -> str:
        return f"<AnalyticsEvent(id={self.id}, name={self.event_name}, actor={self.actor_type})>"


class AnalyticsDailyAggregate(Base):
    """Pre-aggregated daily rollup (rebuildable at any time from raw events)."""

    __tablename__ = "analytics_daily_aggregates"
    __table_args__ = (
        Index("ix_analytics_agg_date_name", "aggregate_date", "event_name"),
        Index("ix_analytics_agg_date_shop", "aggregate_date", "shop_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    aggregate_date: Mapped[date] = mapped_column(Date, nullable=False)
    event_name: Mapped[str] = mapped_column(String(60), nullable=False)
    actor_type: Mapped[str] = mapped_column(String(20), nullable=False)

    shop_id: Mapped[int | None] = mapped_column(ForeignKey("shops.id"))
    product_master_id: Mapped[int | None] = mapped_column(Integer)
    category_id: Mapped[int | None] = mapped_column(Integer)

    event_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    distinct_sessions: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    distinct_actors: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    metric_sum: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)

    computed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=datetime.utcnow
    )