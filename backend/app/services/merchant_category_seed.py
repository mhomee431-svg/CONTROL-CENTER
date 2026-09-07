"""Seed data for merchant categories and verification requirements.

Populates the 11 merchant categories and their verification requirements.
Run this after the migration is applied.
"""
from sqlalchemy.orm import Session

from app.models.merchant_category import (
    MerchantCategory,
    MerchantCategoryCode,
    MerchantVerificationRequirement,
    VerificationMethod,
)


# ── Category Definitions ──────────────────────────────────────────────────
CATEGORIES = [
    {
        "code": "PHARMACY_HEALTHCARE",
        "name": "Pharmacy & Healthcare",
        "description": "Pharmacies, medical stores, clinics, and healthcare providers",
        "sort_order": 1,
        "requirements": [
            {"code": "PHONE_OTP", "name": "Phone OTP Verification", "method": "PHONE_OTP", "required": True, "admin_review": False},
            {"code": "GSTIN_UDYAM", "name": "Business Identity (GSTIN/UDYAM)", "method": "GSTIN_VERIFY", "required": True, "admin_review": False},
            {"code": "BANK_VERIFY", "name": "Bank Account Verification", "method": "BANK_PENNY_DROP", "required": True, "admin_review": False},
            {"code": "DRUG_LICENSE", "name": "Drug License", "method": "DRUG_LICENSE_VERIFY", "required": True, "admin_review": True},
        ],
    },
    {
        "code": "BEAUTY_PERSONAL_CARE",
        "name": "Beauty & Personal Care",
        "description": "Beauty salons, spas, personal care services",
        "sort_order": 2,
        "requirements": [
            {"code": "PHONE_OTP", "name": "Phone OTP Verification", "method": "PHONE_OTP", "required": True, "admin_review": False},
            {"code": "GSTIN_UDYAM", "name": "Business Identity (GSTIN/UDYAM)", "method": "GSTIN_VERIFY", "required": True, "admin_review": False},
            {"code": "BANK_VERIFY", "name": "Bank Account Verification", "method": "BANK_PENNY_DROP", "required": True, "admin_review": False},
        ],
    },
    {
        "code": "FURNITURE_HOME_CARE",
        "name": "Furniture & Home Care",
        "description": "Furniture stores, home decor, interior design",
        "sort_order": 3,
        "requirements": [
            {"code": "PHONE_OTP", "name": "Phone OTP Verification", "method": "PHONE_OTP", "required": True, "admin_review": False},
            {"code": "GSTIN_UDYAM", "name": "Business Identity (GSTIN/UDYAM)", "method": "GSTIN_VERIFY", "required": True, "admin_review": False},
            {"code": "BANK_VERIFY", "name": "Bank Account Verification", "method": "BANK_PENNY_DROP", "required": True, "admin_review": False},
        ],
    },
    {
        "code": "HOUSEHOLD_GOODS",
        "name": "Household Goods",
        "description": "Household items, cleaning supplies, kitchenware",
        "sort_order": 4,
        "requirements": [
            {"code": "PHONE_OTP", "name": "Phone OTP Verification", "method": "PHONE_OTP", "required": True, "admin_review": False},
            {"code": "GSTIN_UDYAM", "name": "Business Identity (GSTIN/UDYAM)", "method": "GSTIN_VERIFY", "required": True, "admin_review": False},
            {"code": "BANK_VERIFY", "name": "Bank Account Verification", "method": "BANK_PENNY_DROP", "required": True, "admin_review": False},
        ],
    },
    {
        "code": "SPORTS_FITNESS_OUTDOOR",
        "name": "Sports, Fitness & Outdoor",
        "description": "Sports equipment, fitness gear, outdoor supplies",
        "sort_order": 5,
        "requirements": [
            {"code": "PHONE_OTP", "name": "Phone OTP Verification", "method": "PHONE_OTP", "required": True, "admin_review": False},
            {"code": "GSTIN_UDYAM", "name": "Business Identity (GSTIN/UDYAM)", "method": "GSTIN_VERIFY", "required": True, "admin_review": False},
            {"code": "BANK_VERIFY", "name": "Bank Account Verification", "method": "BANK_PENNY_DROP", "required": True, "admin_review": False},
        ],
    },
    {
        "code": "BOOKS_MEDIA_STATIONERY",
        "name": "Books, Media & Stationery",
        "description": "Bookstores, media, stationery, office supplies",
        "sort_order": 6,
        "requirements": [
            {"code": "PHONE_OTP", "name": "Phone OTP Verification", "method": "PHONE_OTP", "required": True, "admin_review": False},
            {"code": "GSTIN_UDYAM", "name": "Business Identity (GSTIN/UDYAM)", "method": "GSTIN_VERIFY", "required": True, "admin_review": False},
            {"code": "BANK_VERIFY", "name": "Bank Account Verification", "method": "BANK_PENNY_DROP", "required": True, "admin_review": False},
        ],
    },
    {
        "code": "AUTOMOTIVE_PARTS_TOOLS",
        "name": "Automotive Parts & Tools",
        "description": "Auto parts, accessories, tools, equipment",
        "sort_order": 7,
        "requirements": [
            {"code": "PHONE_OTP", "name": "Phone OTP Verification", "method": "PHONE_OTP", "required": True, "admin_review": False},
            {"code": "GSTIN_UDYAM", "name": "Business Identity (GSTIN/UDYAM)", "method": "GSTIN_VERIFY", "required": True, "admin_review": False},
            {"code": "BANK_VERIFY", "name": "Bank Account Verification", "method": "BANK_PENNY_DROP", "required": True, "admin_review": False},
        ],
    },
    {
        "code": "HARDWARE",
        "name": "Hardware",
        "description": "Hardware stores, building materials, tools",
        "sort_order": 8,
        "requirements": [
            {"code": "PHONE_OTP", "name": "Phone OTP Verification", "method": "PHONE_OTP", "required": True, "admin_review": False},
            {"code": "GSTIN_UDYAM", "name": "Business Identity (GSTIN/UDYAM)", "method": "GSTIN_VERIFY", "required": True, "admin_review": False},
            {"code": "BANK_VERIFY", "name": "Bank Account Verification", "method": "BANK_PENNY_DROP", "required": True, "admin_review": False},
        ],
    },
    {
        "code": "RESTAURANTS",
        "name": "Restaurants",
        "description": "Restaurants, cafes, food outlets",
        "sort_order": 9,
        "requirements": [
            {"code": "PHONE_OTP", "name": "Phone OTP Verification", "method": "PHONE_OTP", "required": True, "admin_review": False},
            {"code": "GSTIN_UDYAM", "name": "Business Identity (GSTIN/UDYAM)", "method": "GSTIN_VERIFY", "required": True, "admin_review": False},
            {"code": "BANK_VERIFY", "name": "Bank Account Verification", "method": "BANK_PENNY_DROP", "required": True, "admin_review": False},
            {"code": "FSSAI_LICENSE", "name": "FSSAI License", "method": "FSSAI_LICENSE_VERIFY", "required": True, "admin_review": True},
        ],
    },
    {
        "code": "TRANSPORT",
        "name": "Transport",
        "description": "Transport services, logistics, freight",
        "sort_order": 10,
        "requirements": [
            {"code": "PHONE_OTP", "name": "Phone OTP Verification", "method": "PHONE_OTP", "required": True, "admin_review": False},
            {"code": "GSTIN_UDYAM", "name": "Business Identity (GSTIN/UDYAM)", "method": "GSTIN_VERIFY", "required": True, "admin_review": False},
            {"code": "BANK_VERIFY", "name": "Bank Account Verification", "method": "BANK_PENNY_DROP", "required": True, "admin_review": False},
            {"code": "DRIVING_LICENSE", "name": "Driving License", "method": "DRIVING_LICENSE_VERIFY", "required": True, "admin_review": True},
            {"code": "VEHICLE_RC", "name": "Vehicle RC", "method": "VEHICLE_RC_VERIFY", "required": True, "admin_review": True},
        ],
    },
    {
        "code": "PERSONAL_TRANSPORT_TRAVEL",
        "name": "Personal Transport / Personal Travel",
        "description": "Personal transport, taxi, travel services",
        "sort_order": 11,
        "requirements": [
            {"code": "PHONE_OTP", "name": "Phone OTP Verification", "method": "PHONE_OTP", "required": True, "admin_review": False},
            {"code": "GSTIN_UDYAM", "name": "Business Identity (GSTIN/UDYAM)", "method": "GSTIN_VERIFY", "required": True, "admin_review": False},
            {"code": "BANK_VERIFY", "name": "Bank Account Verification", "method": "BANK_PENNY_DROP", "required": True, "admin_review": False},
            {"code": "DRIVING_LICENSE", "name": "Driving License", "method": "DRIVING_LICENSE_VERIFY", "required": True, "admin_review": True},
            {"code": "VEHICLE_RC", "name": "Vehicle RC", "method": "VEHICLE_RC_VERIFY", "required": True, "admin_review": True},
        ],
    },
]


def seed_merchant_categories(db: Session) -> None:
    """Seed merchant categories and verification requirements."""
    for cat_data in CATEGORIES:
        # Check if category already exists
        existing = (
            db.query(MerchantCategory)
            .filter(MerchantCategory.code == cat_data["code"])
            .first()
        )
        if existing:
            continue

        category = MerchantCategory(
            code=cat_data["code"],
            name=cat_data["name"],
            description=cat_data["description"],
            sort_order=cat_data["sort_order"],
            is_active=True,
        )
        db.add(category)
        db.flush()

        # Create requirements
        for idx, req_data in enumerate(cat_data["requirements"]):
            requirement = MerchantVerificationRequirement(
                category_id=category.id,
                requirement_code=req_data["code"],
                requirement_name=req_data["name"],
                is_required=req_data["required"],
                verification_method=req_data["method"],
                requires_admin_review=req_data["admin_review"],
                is_active=True,
                sort_order=idx,
            )
            db.add(requirement)

    db.commit()
