"""Merchant Onboarding Pydantic schemas.

Request/Response schemas for the tiered merchant onboarding system.
"""
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field, field_validator
import re


# ── Category Configuration ───────────────────────────────────────────────
class MerchantCategoryResponse(BaseModel):
    id: int
    code: str
    name: str
    description: Optional[str] = None
    is_active: bool
    sort_order: int


class MerchantVerificationRequirementResponse(BaseModel):
    id: int
    category_id: int
    requirement_code: str
    requirement_name: str
    description: Optional[str] = None
    is_required: bool
    verification_method: str
    requires_admin_review: bool


# ── Onboarding Request ───────────────────────────────────────────────────
class ShopAddressInput(BaseModel):
    address_line1: str = Field(..., min_length=1, max_length=255)
    address_line2: Optional[str] = Field(None, max_length=255)
    landmark: Optional[str] = Field(None, max_length=255)
    city: str = Field(..., min_length=1, max_length=100)
    state: str = Field(..., min_length=1, max_length=100)
    pincode: str = Field(..., min_length=3, max_length=10)
    country: str = Field("India", max_length=100)


class ShopLocationInput(BaseModel):
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    accuracy: Optional[float] = Field(None, ge=0, le=1000)
    source: Optional[str] = Field(None, description="GPS, MANUAL, ADDRESS")

    @field_validator("accuracy")
    @classmethod
    def validate_accuracy(cls, v):
        if v is not None and v > 100:
            raise ValueError("GPS accuracy is too poor (>100m). Please retake.")
        return v


class BankInput(BaseModel):
    account_number: str = Field(..., min_length=9, max_length=18)
    ifsc_code: str = Field(..., min_length=11, max_length=11)
    account_holder_name: str = Field(..., min_length=1, max_length=255)

    @field_validator("ifsc_code")
    @classmethod
    def validate_ifsc(cls, v):
        pattern = r"^[A-Z]{4}0[A-Z0-9]{6}$"
        if not re.match(pattern, v.upper()):
            raise ValueError("Invalid IFSC format")
        return v.upper()

    @field_validator("account_number")
    @classmethod
    def validate_account_number(cls, v):
        if not v.isdigit():
            raise ValueError("Account number must be numeric")
        return v


class MerchantOnboardingRequest(BaseModel):
    """Start merchant onboarding for a business."""
    business_name: str = Field(..., min_length=1, max_length=255)
    category_code: str = Field(..., description="One of the 11 category codes")
    phone: str = Field(..., min_length=10, max_length=20)
    email: Optional[str] = Field(None, max_length=255)
    address: ShopAddressInput
    location: ShopLocationInput
    gstin: Optional[str] = Field(None, max_length=15)
    udyam_number: Optional[str] = Field(None, max_length=20)
    bank: Optional[BankInput] = None
    category_details: Optional[dict] = Field(
        None, description="Category-specific details (drug_license_no, fssai_license_no, etc.)"
    )
    idempotency_key: Optional[str] = Field(
        None, max_length=100, description="Prevents duplicate onboarding"
    )

    @field_validator("gstin")
    @classmethod
    def validate_gstin(cls, v):
        if v is None:
            return v
        v = v.upper().strip()
        pattern = r"^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$"
        if not re.match(pattern, v):
            raise ValueError("Invalid GSTIN format")
        return v

    @field_validator("udyam_number")
    @classmethod
    def validate_udyam(cls, v):
        if v is None:
            return v
        v = v.upper().strip()
        pattern = r"^UDYAM-[A-Z]{2}-[0-9]{8,12}$"
        if not re.match(pattern, v):
            raise ValueError("Invalid UDYAM format. Expected UDYAM-XX-0000000000 (8-12 digits)")
        return v

    @field_validator("category_code")
    @classmethod
    def validate_category(cls, v):
        valid_codes = {
            "PHARMACY_HEALTHCARE", "BEAUTY_PERSONAL_CARE", "FURNITURE_HOME_CARE",
            "HOUSEHOLD_GOODS", "SPORTS_FITNESS_OUTDOOR", "BOOKS_MEDIA_STATIONERY",
            "AUTOMOTIVE_PARTS_TOOLS", "HARDWARE", "RESTAURANTS",
            "TRANSPORT", "PERSONAL_TRANSPORT_TRAVEL",
        }
        if v.upper() not in valid_codes:
            raise ValueError(f"Invalid category code. Must be one of: {valid_codes}")
        return v.upper()


# ── Identity Verification ────────────────────────────────────────────────
class IdentityVerificationRequest(BaseModel):
    gstin: Optional[str] = Field(None, max_length=15)
    udyam_number: Optional[str] = Field(None, max_length=20)

    @field_validator("gstin")
    @classmethod
    def validate_gstin(cls, v):
        if v is None:
            return v
        v = v.upper().strip()
        pattern = r"^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$"
        if not re.match(pattern, v):
            raise ValueError("Invalid GSTIN format")
        return v

    @field_validator("udyam_number")
    @classmethod
    def validate_udyam(cls, v):
        if v is None:
            return v
        v = v.upper().strip()
        pattern = r"^UDYAM-[A-Z]{2}-[0-9]{8,12}$"
        if not re.match(pattern, v):
            raise ValueError("Invalid UDYAM format")
        return v


# ── Bank Verification ────────────────────────────────────────────────────
class BankVerificationRequest(BaseModel):
    account_number: str = Field(..., min_length=9, max_length=18)
    ifsc_code: str = Field(..., min_length=11, max_length=11)
    account_holder_name: str = Field(..., min_length=1, max_length=255)

    @field_validator("ifsc_code")
    @classmethod
    def validate_ifsc(cls, v):
        pattern = r"^[A-Z]{4}0[A-Z0-9]{6}$"
        if not re.match(pattern, v.upper()):
            raise ValueError("Invalid IFSC format")
        return v.upper()


# ── Category Documents ───────────────────────────────────────────────────
class CategoryDocumentsRequest(BaseModel):
    category_details: dict = Field(
        ...,
        description="Category-specific documents (drug_license_no, fssai_license_no, driving_license_no, vehicle_rc_no)",
    )

    @field_validator("category_details")
    @classmethod
    def validate_category_details(cls, v):
        if not v:
            raise ValueError("Category details cannot be empty")
        valid_keys = {
            "drug_license_no",
            "fssai_license_no",
            "driving_license_no",
            "vehicle_rc_no",
        }
        unknown_keys = set(v.keys()) - valid_keys
        if unknown_keys:
            raise ValueError(f"Unknown category detail fields: {unknown_keys}")
        return v


# ── Onboarding Status Response ───────────────────────────────────────────
class VerificationStatusItem(BaseModel):
    status: str  # VERIFIED, PENDING, NOT_STARTED
    verified_at: Optional[datetime] = None


class OnboardingStatusResponse(BaseModel):
    business_id: int
    onboarding_id: int
    onboarding_status: str
    verification: dict[str, str]
    next_action: Optional[str] = None
    category_code: str
    admin_reviewed: bool
    rejection_reason: Optional[str] = None


# ── Verification Result Responses ────────────────────────────────────────
class IdentityVerificationResponse(BaseModel):
    status: str
    reference_id: Optional[str] = None
    verified_name: Optional[str] = None
    failure_reason: Optional[str] = None
    failure_code: Optional[str] = None


class BankVerificationResponse(BaseModel):
    status: str
    reference_id: Optional[str] = None
    failure_reason: Optional[str] = None
    failure_code: Optional[str] = None


class CategoryDocumentsResponse(BaseModel):
    status: str
    requires_admin_review: bool
    failure_reason: Optional[str] = None


# ── Admin Review ──────────────────────────────────────────────────────────
class AdminOnboardingReviewRequest(BaseModel):
    decision: str = Field(..., pattern="^(APPROVE|REJECT|REQUEST_RESUBMISSION|SUSPEND)$")
    reason: Optional[str] = Field(None, max_length=500)
    notes: Optional[str] = Field(None, max_length=2000)


class AdminOnboardingListItem(BaseModel):
    onboarding_id: int
    business_id: int
    business_name: Optional[str] = None
    category_code: str
    status: str
    phone_verified: bool
    identity_verified: bool
    bank_verified: bool
    category_verified: bool
    submitted_at: Optional[str] = None


# ── Verification Requirements Response ───────────────────────────────────
class VerificationRequirementItem(BaseModel):
    requirement_code: str
    requirement_name: str
    is_required: bool
    verification_method: str
    requires_admin_review: bool


class VerificationRequirementsResponse(BaseModel):
    category_code: str
    requirements: list[VerificationRequirementItem]

