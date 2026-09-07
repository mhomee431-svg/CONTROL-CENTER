"""Bank Account Verification Provider abstraction.

Bank account verification through penny-drop or API-based verification.
All providers implement a common interface for swappability.

IMPORTANT: Bank verification requires onboarding with payment gateways
(Cashfree, Razorpay, etc.). No free government API exists.
Until configured, all verifications route to PENDING_ADMIN_REVIEW.
"""
from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Optional

from app.core.logging import get_logger

logger = get_logger("app.services.bank_provider")


@dataclass
class BankVerificationResult:
    """Normalized result from bank account verification."""
    status: str  # VERIFIED, PENDING, FAILED, REJECTED
    provider: str
    reference_id: Optional[str] = None
    verified_account_name: Optional[str] = None
    verified_at: Optional[datetime] = None
    failure_reason: Optional[str] = None
    failure_code: Optional[str] = None
    penny_drop_amount: Optional[float] = None
    raw_response_reference: Optional[str] = None
    metadata: Optional[dict] = None


class BankAccountVerificationProvider(ABC):
    """Abstract base for bank account verification providers."""

    name: str = "base"

    @abstractmethod
    async def verify_bank_account(
        self,
        account_holder_name: str,
        account_number: str,
        ifsc_code: str,
    ) -> BankVerificationResult:
        """Verify a bank account via penny-drop or API.

        Args:
            account_holder_name: Name of the account holder
            account_number: Bank account number (never logged)
            ifsc_code: IFSC code of the bank branch

        Returns:
            BankVerificationResult with normalized status
        """

    @staticmethod
    def validate_ifsc_format(ifsc_code: str) -> bool:
        """Basic IFSC format validation.

        IFSC is 11 characters:
        - 4 letters: bank code
        - 1 digit (0): reserved
        - 6 alphanumeric: branch code
        """
        if not ifsc_code:
            return False
        import re
        pattern = r"^[A-Z]{4}0[A-Z0-9]{6}$"
        return bool(re.match(pattern, ifsc_code.upper()))

    @staticmethod
    def mask_account_number(account_number: str) -> str:
        """Mask account number for display/logging (show last 4 digits only)."""
        if not account_number or len(account_number) < 4:
            return "****"
        return "*" * (len(account_number) - 4) + account_number[-4:]

    @staticmethod
    def hash_account_number(account_number: str) -> str:
        """Create a hash of the account number for deduplication."""
        import hashlib
        return hashlib.sha256(account_number.encode()).hexdigest()


class SandboxBankProvider(BankAccountVerificationProvider):
    """Deterministic sandbox bank verification provider for dev/test.

    NEVER enabled in production.
    """

    name = "sandbox"

    # Test account numbers that produce deterministic results
    TEST_VERIFIED_ACCOUNTS = {"1234567890", "9876543210"}
    TEST_PENDING_ACCOUNTS = {"1111111111"}
    TEST_FAILED_ACCOUNTS = {"9999999999"}

    async def verify_bank_account(
        self,
        account_holder_name: str,
        account_number: str,
        ifsc_code: str,
    ) -> BankVerificationResult:
        """Sandbox bank verification with deterministic results."""
        from app.core.config import settings

        if settings.is_production:
            logger.warning(
                "SandboxBankProvider used in production — BLOCKED"
            )
            return BankVerificationResult(
                status="FAILED",
                provider=self.name,
                failure_reason="Sandbox provider not available in production",
                failure_code="SANDBOX_BLOCKED",
            )

        # Never log full account number
        masked = self.mask_account_number(account_number)
        logger.info(
            "Sandbox bank verification for account %s, IFSC %s",
            masked,
            ifsc_code,
        )

        if account_number in self.TEST_VERIFIED_ACCOUNTS:
            return BankVerificationResult(
                status="VERIFIED",
                provider=self.name,
                reference_id=f"SANDBOX-BANK-{account_number[-4:]}",
                verified_account_name=account_holder_name,
                verified_at=datetime.now(timezone.utc),
                metadata={"sandbox": True, "test_data": True},
            )
        elif account_number in self.TEST_PENDING_ACCOUNTS:
            return BankVerificationResult(
                status="PENDING",
                provider=self.name,
                reference_id=f"SANDBOX-BANK-{account_number[-4:]}",
                failure_reason="Penny-drop verification pending",
                failure_code="PENNY_DROP_PENDING",
                penny_drop_amount=1.0,
                metadata={"sandbox": True, "test_data": True},
            )
        elif account_number in self.TEST_FAILED_ACCOUNTS:
            return BankVerificationResult(
                status="FAILED",
                provider=self.name,
                reference_id=f"SANDBOX-BANK-{account_number[-4:]}",
                failure_reason="Account verification failed",
                failure_code="ACCOUNT_MISMATCH",
                metadata={"sandbox": True, "test_data": True},
            )
        else:
            return BankVerificationResult(
                status="FAILED",
                provider=self.name,
                reference_id=f"SANDBOX-BANK-{account_number[-4:]}",
                failure_reason="Unable to verify — requires admin review",
                failure_code="ADMIN_REVIEW_REQUIRED",
                metadata={"sandbox": True, "test_data": True},
            )


class ProductionBankProvider(BankAccountVerificationProvider):
    """Production bank verification provider placeholder.

    IMPORTANT: Requires onboarding with Cashfree/Razorpay or similar.
    Until configured, routes to admin review.
    """

    name = "production"

    async def verify_bank_account(
        self,
        account_holder_name: str,
        account_number: str,
        ifsc_code: str,
    ) -> BankVerificationResult:
        """Production bank verification — routes to admin review."""
        masked = self.mask_account_number(account_number)
        logger.info(
            "Production bank verification for %s at IFSC %s — routing to admin review",
            masked,
            ifsc_code,
        )
        return BankVerificationResult(
            status="FAILED",
            provider=self.name,
            failure_reason="No production bank provider configured — requires admin review",
            failure_code="ADMIN_REVIEW_REQUIRED",
            metadata={"requires_manual_provider_config": True},
        )


# ── Provider Registry ────────────────────────────────────────────────

_providers: dict[str, BankAccountVerificationProvider] = {}


def register_bank_provider(provider: BankAccountVerificationProvider) -> None:
    """Register a bank verification provider."""
    _providers[provider.name] = provider
    logger.info("Bank provider registered: %s", provider.name)


def get_bank_provider(name: str | None = None) -> BankAccountVerificationProvider:
    """Get a bank verification provider by name."""
    from app.core.config import settings

    provider_name = name or getattr(settings, "BANK_PROVIDER", "sandbox")

    if provider_name not in _providers:
        logger.warning(
            "Bank provider \'%s\' not found, falling back to sandbox",
            provider_name,
        )
        provider_name = "sandbox"

    return _providers[provider_name]


# Register built-in providers on import
register_bank_provider(SandboxBankProvider())
register_bank_provider(ProductionBankProvider())

