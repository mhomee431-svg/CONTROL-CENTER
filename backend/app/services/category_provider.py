"""Category-Specific Document Verification Provider abstraction.

Verification for pharmacy (drug_license_no), restaurant (fssai_license_no),
and transport (driving_license_no, vehicle_rc_no) documents.

IMPORTANT: No official government API exists for automated verification
of these documents. All verifications route to PENDING_ADMIN_REVIEW.
Never scrape government portals or bypass CAPTCHA.
"""
from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import datetime
from typing import Optional

from app.core.logging import get_logger

logger = get_logger("app.services.category_provider")


@dataclass
class CategoryVerificationResult:
    """Normalized result from category document verification."""
    status: str  # VERIFIED, PENDING, FAILED, REJECTED, UNABLE_TO_VERIFY
    provider: str
    document_type: str
    reference_id: Optional[str] = None
    verified_name: Optional[str] = None
    verified_at: Optional[datetime] = None
    expiry_date: Optional[datetime] = None
    failure_reason: Optional[str] = None
    failure_code: Optional[str] = None
    requires_admin_review: bool = True
    raw_response_reference: Optional[str] = None
    metadata: Optional[dict] = None


class CategoryVerificationProvider(ABC):
    """Abstract base for category-specific document verification."""

    name: str = "base"

    @abstractmethod
    async def verify_drug_license(
        self,
        license_no: str,
        business_name: Optional[str] = None,
    ) -> CategoryVerificationResult:
        """Verify a drug license number."""

    @abstractmethod
    async def verify_fssai_license(
        self,
        license_no: str,
        business_name: Optional[str] = None,
    ) -> CategoryVerificationResult:
        """Verify an FSSAI license/registration number."""

    @abstractmethod
    async def verify_driving_license(
        self,
        license_no: str,
        holder_name: Optional[str] = None,
    ) -> CategoryVerificationResult:
        """Verify a driving license number."""

    @abstractmethod
    async def verify_vehicle_rc(
        self,
        rc_number: str,
        owner_name: Optional[str] = None,
    ) -> CategoryVerificationResult:
        """Verify a vehicle registration certificate."""

    @staticmethod
    def validate_fssai_format(license_no: str) -> bool:
        """Basic FSSAI format validation.

        FSSAI license numbers are typically 14 digits.
        FSSAI registration numbers may vary.
        This is a basic format check, not a validity check.
        """
        if not license_no:
            return False
        # Remove spaces and hyphens
        cleaned = license_no.replace(" ", "").replace("-", "")
        # FSSAI licenses are typically 14 digits, but registration can vary
        return cleaned.isdigit() and 10 <= len(cleaned) <= 20

    @staticmethod
    def validate_drug_license_format(license_no: str) -> bool:
        """Basic drug license format validation.

        Drug license formats vary by state. Basic check for non-empty alphanumeric.
        """
        if not license_no:
            return False
        cleaned = license_no.replace(" ", "").replace("-", "").replace("/", "")
        return cleaned.isalnum() and 5 <= len(cleaned) <= 30

    @staticmethod
    def validate_driving_license_format(license_no: str) -> bool:
        """Basic driving license format validation.
        DL format: XX00 00000000000 (state code + RTO code + digits)
        """
        if not license_no:
            return False
        import re
        cleaned = license_no.replace(" ", "").replace("-", "").upper()
        pattern = r"^[A-Z]{2}[0-9]{2}[0-9]{11,13}$"
        return bool(re.match(pattern, cleaned))

    @staticmethod
    def validate_vehicle_rc_format(rc_number: str) -> bool:
        """Basic vehicle RC number format validation.
        RC format: XX00XX0000 (state + RTO + series + number)
        """
        if not rc_number:
            return False
        import re
        cleaned = rc_number.replace(" ", "").replace("-", "").upper()
        pattern = r"^[A-Z]{2}[0-9]{2}[A-Z]{1,3}[0-9]{4}$"
        return bool(re.match(pattern, cleaned))


class SandboxCategoryProvider(CategoryVerificationProvider):
    """Deterministic sandbox category verification provider for dev/test.

    NEVER enabled in production.
    """

    name = "sandbox"

    async def verify_drug_license(
        self,
        license_no: str,
        business_name: Optional[str] = None,
    ) -> CategoryVerificationResult:
        """Sandbox drug license verification."""
        from app.core.config import settings

        if settings.is_production:
            return self._blocked_result("DRUG_LICENSE")

        return CategoryVerificationResult(
            status="UNABLE_TO_VERIFY",
            provider=self.name,
            document_type="DRUG_LICENSE",
            reference_id=f"SANDBOX-DRUG-{license_no[-4:] if license_no else '0000'}",
            failure_reason="No automated drug license API available — requires admin review",
            failure_code="ADMIN_REVIEW_REQUIRED",
            requires_admin_review=True,
            metadata={"sandbox": True, "test_data": True},
        )

    async def verify_fssai_license(
        self,
        license_no: str,
        business_name: Optional[str] = None,
    ) -> CategoryVerificationResult:
        """Sandbox FSSAI license verification."""
        from app.core.config import settings

        if settings.is_production:
            return self._blocked_result("FSSAI_LICENSE")

        return CategoryVerificationResult(
            status="UNABLE_TO_VERIFY",
            provider=self.name,
            document_type="FSSAI_LICENSE",
            reference_id=f"SANDBOX-FSSAI-{license_no[-4:] if license_no else '0000'}",
            failure_reason="No automated FSSAI API available — requires admin review",
            failure_code="ADMIN_REVIEW_REQUIRED",
            requires_admin_review=True,
            metadata={"sandbox": True, "test_data": True},
        )

    async def verify_driving_license(
        self,
        license_no: str,
        holder_name: Optional[str] = None,
    ) -> CategoryVerificationResult:
        """Sandbox driving license verification."""
        from app.core.config import settings

        if settings.is_production:
            return self._blocked_result("DRIVING_LICENSE")

        return CategoryVerificationResult(
            status="UNABLE_TO_VERIFY",
            provider=self.name,
            document_type="DRIVING_LICENSE",
            reference_id=f"SANDBOX-DL-{license_no[-4:] if license_no else '0000'}",
            failure_reason="No automated VAHAN/Parivahan API available — requires admin review",
            failure_code="ADMIN_REVIEW_REQUIRED",
            requires_admin_review=True,
            metadata={"sandbox": True, "test_data": True},
        )

    async def verify_vehicle_rc(
        self,
        rc_number: str,
        owner_name: Optional[str] = None,
    ) -> CategoryVerificationResult:
        """Sandbox vehicle RC verification."""
        from app.core.config import settings

        if settings.is_production:
            return self._blocked_result("VEHICLE_RC")

        return CategoryVerificationResult(
            status="UNABLE_TO_VERIFY",
            provider=self.name,
            document_type="VEHICLE_RC",
            reference_id=f"SANDBOX-RC-{rc_number[-4:] if rc_number else '0000'}",
            failure_reason="No automated VAHAN/Parivahan API available — requires admin review",
            failure_code="ADMIN_REVIEW_REQUIRED",
            requires_admin_review=True,
            metadata={"sandbox": True, "test_data": True},
        )

    def _blocked_result(self, doc_type: str) -> CategoryVerificationResult:
        """Return a blocked result for production."""
        return CategoryVerificationResult(
            status="UNABLE_TO_VERIFY",
            provider=self.name,
            document_type=doc_type,
            failure_reason="Sandbox provider not available in production",
            failure_code="SANDBOX_BLOCKED",
            requires_admin_review=True,
        )


class ProductionCategoryProvider(CategoryVerificationProvider):
    """Production category verification provider placeholder.

    IMPORTANT: No official government API exists for automated verification.
    All verifications route to PENDING_ADMIN_REVIEW.
    """

    name = "production"

    async def verify_drug_license(
        self,
        license_no: str,
        business_name: Optional[str] = None,
    ) -> CategoryVerificationResult:
        """Production drug license — routes to admin review."""
        return CategoryVerificationResult(
            status="UNABLE_TO_VERIFY",
            provider=self.name,
            document_type="DRUG_LICENSE",
            failure_reason="No automated drug license API available — requires admin review",
            failure_code="ADMIN_REVIEW_REQUIRED",
            requires_admin_review=True,
            metadata={"requires_manual_provider_config": True},
        )

    async def verify_fssai_license(
        self,
        license_no: str,
        business_name: Optional[str] = None,
    ) -> CategoryVerificationResult:
        """Production FSSAI — routes to admin review."""
        return CategoryVerificationResult(
            status="UNABLE_TO_VERIFY",
            provider=self.name,
            document_type="FSSAI_LICENSE",
            failure_reason="No automated FSSAI API available — requires admin review",
            failure_code="ADMIN_REVIEW_REQUIRED",
            requires_admin_review=True,
            metadata={"requires_manual_provider_config": True},
        )

    async def verify_driving_license(
        self,
        license_no: str,
        holder_name: Optional[str] = None,
    ) -> CategoryVerificationResult:
        """Production driving license — routes to admin review."""
        return CategoryVerificationResult(
            status="UNABLE_TO_VERIFY",
            provider=self.name,
            document_type="DRIVING_LICENSE",
            failure_reason="No automated VAHAN/Parivahan API available — requires admin review",
            failure_code="ADMIN_REVIEW_REQUIRED",
            requires_admin_review=True,
            metadata={"requires_manual_provider_config": True},
        )

    async def verify_vehicle_rc(
        self,
        rc_number: str,
        owner_name: Optional[str] = None,
    ) -> CategoryVerificationResult:
        """Production vehicle RC — routes to admin review."""
        return CategoryVerificationResult(
            status="UNABLE_TO_VERIFY",
            provider=self.name,
            document_type="VEHICLE_RC",
            failure_reason="No automated VAHAN/Parivahan API available — requires admin review",
            failure_code="ADMIN_REVIEW_REQUIRED",
            requires_admin_review=True,
            metadata={"requires_manual_provider_config": True},
        )


# ── Provider Registry ────────────────────────────────────────────────

_providers: dict[str, CategoryVerificationProvider] = {}


def register_category_provider(provider: CategoryVerificationProvider) -> None:
    """Register a category verification provider."""
    _providers[provider.name] = provider
    logger.info("Category provider registered: %s", provider.name)


def get_category_provider(name: str | None = None) -> CategoryVerificationProvider:
    """Get a category verification provider by name."""
    from app.core.config import settings

    provider_name = name or getattr(settings, "CATEGORY_PROVIDER", "sandbox")

    if provider_name not in _providers:
        logger.warning(
            "Category provider \'%s\' not found, falling back to sandbox",
            provider_name,
        )
        provider_name = "sandbox"

    return _providers[provider_name]


# Register built-in providers on import
register_category_provider(SandboxCategoryProvider())
register_category_provider(ProductionCategoryProvider())
