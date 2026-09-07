"""Identity Verification Provider abstraction.

GSTIN/UDYAM verification through external providers.
All providers implement a common interface for swappability.

IMPORTANT: No official free government API exists for GSTIN/UDYAM verification.
Production providers require onboarding with paid services (ClearTax, Razorpay, etc.)
Until then, all verifications route to PENDING_ADMIN_REVIEW.
"""
from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Optional

from app.core.logging import get_logger

logger = get_logger("app.services.identity_provider")


@dataclass
class IdentityVerificationResult:
    """Normalized result from identity verification."""
    status: str  # VERIFIED, PENDING, FAILED, REJECTED, UNABLE_TO_VERIFY
    provider: str
    reference_id: Optional[str] = None
    verified_name: Optional[str] = None
    verified_identifier: Optional[str] = None
    verified_at: Optional[datetime] = None
    failure_reason: Optional[str] = None
    failure_code: Optional[str] = None
    raw_response_reference: Optional[str] = None
    metadata: Optional[dict] = None


class IdentityVerificationProvider(ABC):
    """Abstract base for GSTIN/UDYAM verification providers."""

    name: str = "base"

    @abstractmethod
    async def verify_gstin(
        self,
        gstin: str,
        business_name: Optional[str] = None,
    ) -> IdentityVerificationResult:
        """Verify a GSTIN number."""

    @abstractmethod
    async def verify_udyam(
        self,
        udyam_number: str,
        business_name: Optional[str] = None,
    ) -> IdentityVerificationResult:
        """Verify a UDYAM MSME number."""

    @staticmethod
    def validate_gstin_format(gstin: str) -> bool:
        """Basic GSTIN format validation."""
        if not gstin or len(gstin) != 15:
            return False
        import re
        pattern = r"^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$"
        return bool(re.match(pattern, gstin.upper()))

    @staticmethod
    def validate_udyam_format(udyam_number: str) -> bool:
        """Basic UDYAM format validation."""
        if not udyam_number:
            return False
        import re
        pattern = r"^UDYAM-[A-Z]{2}-[0-9]{8,12}$"
        return bool(re.match(pattern, udyam_number.upper()))


class SandboxIdentityProvider(IdentityVerificationProvider):
    """Deterministic sandbox provider for dev/test."""

    name = "sandbox"

    TEST_VERIFIED_GSTINS = {"27AAAAA1234A1Z5", "07BBBBB5678B2Z3"}
    TEST_PENDING_GSTINS = {"29CCCCC9012C3Z1"}
    TEST_FAILED_GSTINS = {"33DDDDD3456D4Z9"}
    TEST_VERIFIED_UDYAMS = {"UDYAM-MH-1234567890", "UDYAM-DL-9876543210"}
    TEST_PENDING_UDYAMS = {"UDYAM-KA-1111111111"}
    TEST_FAILED_UDYAMS = {"UDYAM-TN-9999999999"}

    async def verify_gstin(
        self, gstin: str, business_name: Optional[str] = None
    ) -> IdentityVerificationResult:
        """Sandbox GSTIN verification."""
        from app.core.config import settings

        if settings.is_production:
            return IdentityVerificationResult(
                status="UNABLE_TO_VERIFY",
                provider=self.name,
                failure_reason="Sandbox provider not available in production",
                failure_code="SANDBOX_BLOCKED",
            )

        gstin_upper = gstin.upper().strip()

        if gstin_upper in self.TEST_VERIFIED_GSTINS:
            return IdentityVerificationResult(
                status="VERIFIED",
                provider=self.name,
                reference_id=f"SANDBOX-GSTIN-{gstin_upper}",
                verified_name=business_name or "Test Business Pvt Ltd",
                verified_identifier=gstin_upper,
                verified_at=datetime.now(timezone.utc),
                metadata={"sandbox": True, "test_data": True},
            )
        elif gstin_upper in self.TEST_PENDING_GSTINS:
            return IdentityVerificationResult(
                status="PENDING",
                provider=self.name,
                reference_id=f"SANDBOX-GSTIN-{gstin_upper}",
                failure_reason="Verification pending",
                failure_code="PENDING_ADMIN_REVIEW",
                metadata={"sandbox": True, "test_data": True},
            )
        elif gstin_upper in self.TEST_FAILED_GSTINS:
            return IdentityVerificationResult(
                status="FAILED",
                provider=self.name,
                reference_id=f"SANDBOX-GSTIN-{gstin_upper}",
                failure_reason="GSTIN not found in test database",
                failure_code="NOT_FOUND",
                metadata={"sandbox": True, "test_data": True},
            )
        else:
            return IdentityVerificationResult(
                status="UNABLE_TO_VERIFY",
                provider=self.name,
                reference_id=f"SANDBOX-GSTIN-{gstin_upper}",
                failure_reason="Unable to verify",
                failure_code="ADMIN_REVIEW_REQUIRED",
                metadata={"sandbox": True, "test_data": True},
            )

    async def verify_udyam(
        self, udyam_number: str, business_name: Optional[str] = None
    ) -> IdentityVerificationResult:
        """Sandbox UDYAM verification."""
        from app.core.config import settings

        if settings.is_production:
            return IdentityVerificationResult(
                status="UNABLE_TO_VERIFY",
                provider=self.name,
                failure_reason="Sandbox provider not available in production",
                failure_code="SANDBOX_BLOCKED",
            )

        udyam_upper = udyam_number.upper().strip()

        if udyam_upper in self.TEST_VERIFIED_UDYAMS:
            return IdentityVerificationResult(
                status="VERIFIED",
                provider=self.name,
                reference_id=f"SANDBOX-UDYAM-{udyam_upper}",
                verified_name=business_name or "Test MSME Enterprise",
                verified_identifier=udyam_upper,
                verified_at=datetime.now(timezone.utc),
                metadata={"sandbox": True, "test_data": True},
            )
        elif udyam_upper in self.TEST_PENDING_UDYAMS:
            return IdentityVerificationResult(
                status="PENDING",
                provider=self.name,
                reference_id=f"SANDBOX-UDYAM-{udyam_upper}",
                failure_reason="Verification pending",
                failure_code="PENDING_ADMIN_REVIEW",
                metadata={"sandbox": True, "test_data": True},
            )
        elif udyam_upper in self.TEST_FAILED_UDYAMS:
            return IdentityVerificationResult(
                status="FAILED",
                provider=self.name,
                reference_id=f"SANDBOX-UDYAM-{udyam_upper}",
                failure_reason="UDYAM not found in test database",
                failure_code="NOT_FOUND",
                metadata={"sandbox": True, "test_data": True},
            )
        else:
            return IdentityVerificationResult(
                status="UNABLE_TO_VERIFY",
                provider=self.name,
                reference_id=f"SANDBOX-UDYAM-{udyam_upper}",
                failure_reason="Unable to verify",
                failure_code="ADMIN_REVIEW_REQUIRED",
                metadata={"sandbox": True, "test_data": True},
            )


class ProductionIdentityProvider(IdentityVerificationProvider):
    """Production identity verification provider placeholder."""

    name = "production"

    async def verify_gstin(
        self, gstin: str, business_name: Optional[str] = None
    ) -> IdentityVerificationResult:
        """Production GSTIN verification."""
        logger.info("Production GSTIN verification requested")
        return IdentityVerificationResult(
            status="UNABLE_TO_VERIFY",
            provider=self.name,
            failure_reason="No production GSTIN provider configured",
            failure_code="ADMIN_REVIEW_REQUIRED",
            metadata={"requires_manual_provider_config": True},
        )

    async def verify_udyam(
        self, udyam_number: str, business_name: Optional[str] = None
    ) -> IdentityVerificationResult:
        """Production UDYAM verification."""
        logger.info("Production UDYAM verification requested")
        return IdentityVerificationResult(
            status="UNABLE_TO_VERIFY",
            provider=self.name,
            failure_reason="No production UDYAM provider configured",
            failure_code="ADMIN_REVIEW_REQUIRED",
            metadata={"requires_manual_provider_config": True},
        )


# Registry
_providers: dict[str, IdentityVerificationProvider] = {}


def register_identity_provider(provider: IdentityVerificationProvider) -> None:
    """Register an identity verification provider."""
    _providers[provider.name] = provider
    logger.info("Identity provider registered: %s", provider.name)


def get_identity_provider(name: str | None = None) -> IdentityVerificationProvider:
    """Get an identity verification provider."""
    from app.core.config import settings

    provider_name = name or getattr(settings, "IDENTITY_PROVIDER", "sandbox")

    if provider_name not in _providers:
        provider_name = "sandbox"

    return _providers[provider_name]


register_identity_provider(SandboxIdentityProvider())
register_identity_provider(ProductionIdentityProvider())


