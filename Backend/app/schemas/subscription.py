"""Phase 28 — Subscription & payment request schemas."""

from pydantic import BaseModel, Field


class SubscribeRequest(BaseModel):
    plan_id: int = Field(..., gt=0)
    shop_id: int | None = Field(None, gt=0)
    billing_cycle: str = Field("MONTHLY", pattern="^(WEEKLY|MONTHLY|QUARTERLY|ANNUAL)$")


class CancelSubscriptionRequest(BaseModel):
    subscription_id: int = Field(..., gt=0)
    immediate: bool = False


class RenewRequest(BaseModel):
    subscription_id: int = Field(..., gt=0)
    billing_cycle: str | None = Field(None, pattern="^(WEEKLY|MONTHLY|QUARTERLY|ANNUAL)$")
    payment_method: str = Field("UPI", pattern="^(CARD|UPI|NETBANKING|WALLET)$")
    provider_code: str = "MOCK"


class PaymentInitiateRequest(BaseModel):
    subscription_id: int = Field(..., gt=0)
    payment_method: str = Field(..., pattern="^(CARD|UPI|NETBANKING|WALLET)$")
    provider_code: str = "MOCK"
    billing_cycle: str | None = Field(None, pattern="^(WEEKLY|MONTHLY|QUARTERLY|ANNUAL)$")


class PaymentVerifyRequest(BaseModel):
    payment_id: int = Field(..., gt=0)
    provider_payment_id: str = Field(..., min_length=1)
    provider_signature: str = Field(..., min_length=1)


class RefundRequest(BaseModel):
    reason: str | None = Field(None, max_length=500)
