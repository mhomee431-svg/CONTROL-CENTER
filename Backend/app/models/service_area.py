"""Service areas — geographic delivery/service zones (PostGIS polygons)."""

from datetime import datetime

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    Index,
    JSON,
    Numeric,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column
from geoalchemy2 import Geography

from app.database.session import Base
from app.models.base import TimestampMixin


class ServiceArea(Base, TimestampMixin):
    """A PostGIS polygon that bounds where the platform operates.

    ``boundary`` is a ``geography(POLYGON, 4326)`` (great-circle semantics;
    ST_Within / ST_Covers answer "is a customer inside a service area?").
    ``center`` is the representative point used for quick radius distance.
    Both geography columns get GiST indexes via the migration chain.
    """

    __tablename__ = "service_areas"
    __table_args__ = (
        UniqueConstraint("name", name="uq_service_areas_name"),
        CheckConstraint(
            "area_type IN ('CITY','ZONE','LOCALITY','PINCODE')",
            name="ck_service_areas_area_type",
        ),
        Index("ix_service_areas_pincode_prefix", "pincode_prefix"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
    area_type: Mapped[str] = mapped_column(String(30), nullable=False)
    pincode_prefix: Mapped[str | None] = mapped_column(String(6))
    boundary: Mapped[object | None] = mapped_column(
        Geography(geometry_type="POLYGON", srid=4326, spatial_index=False),
        nullable=True,
    )
    center: Mapped[object | None] = mapped_column(
        Geography(geometry_type="POINT", srid=4326, spatial_index=False),
        nullable=True,
    )
    delivery_radius_km: Mapped[float | None] = mapped_column(Numeric(6, 2))
    is_active: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )
    geo_json: Mapped[dict | None] = mapped_column(JSON)