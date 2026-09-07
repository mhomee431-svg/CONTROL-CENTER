"""Merchant Category configuration models.

Centralized category configuration for the tiered merchant onboarding system.
Supports 11 merchant categories with configurable verification requirements.
"""
from sqlalchemy import String, Boolean, Integer, Text, ForeignKey, Enum
from sqlalchemy.orm import Mapped, mapped_column, relationship
import enum

from app.database.session import Base
from app.models.base import TimestampMixin


class MerchantCategoryCode(str, enum.Enum):
    """Category codes for all 11 merchant categories."""
    PHARMACY_HEALTHCARE = "PHARMACY_HEALTHCARE"
    BEAUTY_PERSONAL_CARE = "BEAUTY_PERSONAL_CARE"
    FURNITURE_HOME_CARE = "FURNITURE_HOME_CARE"
    HOUSEHOLD_GOODS = "HOUSEHOLD_GOODS"
    SPORTS_FITNESS_OUTDOOR = "SPORTS_FITNESS_OUTDOOR"
    BOOKS_MEDIA_STATIONERY = "BOOKS_MEDIA_STATIONERY"
    AUTOMOTIVE_PARTS_TOOLS = "AUTOMOTIVE_PARTS_TOOLS"
    HARDWARE = "HARDWARE"
    RESTAURANTS = "RESTAURANTS"
    TRANSPORT = "TRANSPORT"
    PERSONAL_TRANSPORT_TRAVEL = "PERSONAL_TRANSPORT_TRAVEL"


class MerchantCategory(Base, TimestampMixin):
    """Centralized merchant category configuration.

    Each category defines what verification requirements apply to merchants
    registering under that category.
    """
    __tablename__ = "merchant_categories"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    code: Mapped[str] = mapped_column(
        String(50), unique=True, nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    is_active: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )
    sort_order: Mapped[int] = mapped_column(Integer, default=0, server_default="0")

    # Relationships
    requirements = relationship(
        "MerchantVerificationRequirement",
        back_populates="category",
        cascade="all, delete-orphan",
    )


class VerificationMethod(str, enum.Enum):
    """How a requirement can be verified."""
    PHONE_OTP = "PHONE_OTP"
    GSTIN_VERIFY = "GSTIN_VERIFY"
    UDYAM_VERIFY = "UDYAM_VERIFY"
    BANK_PENNY_DROP = "BANK_PENNY_DROP"
    DRUG_LICENSE_VERIFY = "DRUG_LICENSE_VERIFY"
    FSSAI_LICENSE_VERIFY = "FSSAI_LICENSE_VERIFY"
    DRIVING_LICENSE_VERIFY = "DRIVING_LICENSE_VERIFY"
    VEHICLE_RC_VERIFY = "VEHICLE_RC_VERIFY"
    ADMIN_REVIEW = "ADMIN_REVIEW"


class MerchantVerificationRequirement(Base, TimestampMixin):
    """Category-specific verification requirement configuration.

    Defines what documents/verifications are required for each category.
    This allows adding new categories/requirements without code changes.
    """
    __tablename__ = "merchant_verification_requirements"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    category_id: Mapped[int] = mapped_column(
        ForeignKey("merchant_categories.id", ondelete="CASCADE"),
        index=True,
        nullable=False,
    )
    requirement_code: Mapped[str] = mapped_column(String(50), nullable=False)
    requirement_name: Mapped[str] = mapped_column(String(100), nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    is_required: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )
    verification_method: Mapped[str] = mapped_column(String(50), nullable=False)
    requires_admin_review: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    is_active: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )
    sort_order: Mapped[int] = mapped_column(Integer, default=0, server_default="0")

    # Relationships
    category = relationship("MerchantCategory", back_populates="requirements")
