"""Customer and CustomerAddress models."""
from datetime import datetime
from sqlalchemy import String, DateTime, ForeignKey, Boolean, Text, Integer
from sqlalchemy.orm import Mapped, mapped_column, relationship
from geoalchemy2 import Geography

from app.database.session import Base
from app.models.base import TimestampMixin, SoftDeleteMixin


class Customer(Base, TimestampMixin, SoftDeleteMixin):
    __tablename__ = "customers"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), unique=True, index=True, nullable=False)
    date_of_birth: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    gender: Mapped[str | None] = mapped_column(String(20))
    preferred_language: Mapped[str | None] = mapped_column(String(10), default="en")
    default_address_id: Mapped[int | None] = mapped_column(ForeignKey("customer_addresses.id", use_alter=True), nullable=True)

    user = relationship("User", back_populates="customer_profile")
    addresses = relationship("CustomerAddress", back_populates="customer", foreign_keys="CustomerAddress.customer_id")
    favorites = relationship("CustomerFavorite", back_populates="customer", cascade="all, delete-orphan")
    recent_products = relationship("CustomerRecentProduct", back_populates="customer", cascade="all, delete-orphan")


class CustomerAddress(Base, TimestampMixin, SoftDeleteMixin):
    __tablename__ = "customer_addresses"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True, nullable=False)
    customer_id: Mapped[int | None] = mapped_column(ForeignKey("customers.id"), index=True, nullable=True)
    label: Mapped[str | None] = mapped_column(String(50))  # Home, Work, Other
    address_line1: Mapped[str] = mapped_column(String(255), nullable=False)
    address_line2: Mapped[str | None] = mapped_column(String(255))
    city: Mapped[str] = mapped_column(String(100), nullable=False)
    state: Mapped[str] = mapped_column(String(100), nullable=False)
    pincode: Mapped[str] = mapped_column(String(10), nullable=False, index=True)
    country: Mapped[str] = mapped_column(String(100), default="India")
    location: Mapped[object | None] = mapped_column(
        Geography(geometry_type="POINT", srid=4326, spatial_index=True), nullable=True
    )
    is_default: Mapped[bool] = mapped_column(Boolean, default=False)
    is_verified: Mapped[bool] = mapped_column(Boolean, default=False)

    user = relationship("User", back_populates="addresses")
    customer = relationship("Customer", back_populates="addresses", foreign_keys=[customer_id])