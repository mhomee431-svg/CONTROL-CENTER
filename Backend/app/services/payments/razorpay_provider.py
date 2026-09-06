"""Razorpay payment provider adapter.

Implements the PaymentProvider interface for Razorpay (popular in India).
"""
import hashlib
import hmac
import logging
from typing import Any

from app.services.payments.base import (
    PaymentIntent,
    PaymentProvider,
    PaymentProviderError,
    PaymentVerificationError,
    VerificationResult,
    WebhookSignatureError,
)

logger = logging.getLogger("app.services.payments.razorpay")


class RazorpayProvider(PaymentProvider):
    """Razorpay payment gateway adapter."""
    
    code = "razorpay"
    display_name = "Razorpay"
    supports_refund = True
    supports_subscription = True
    
    def __init__(self, key_id: str, key_secret: str, webhook_secret: str | None = None):
        self.key_id = key_id
        self.key_secret = key_secret
        self.webhook_secret = webhook_secret
    
    def create_order(
        self,
        *,
        amount: float,
        currency: str = "INR",
        receipt: str | None = None,
        notes: dict[str, str] | None = None,
    ) -> PaymentIntent:
        """Create a Razorpay order."""
        try:
            import razorpay
            
            client = razorpay.Client(auth=(self.key_id, self.key_secret))
            amount_in_paise = int(amount * 100)
            
            order_data = {
                "amount": amount_in_paise,
                "currency": currency,
                "receipt": receipt,
                "notes": notes or {},
            }
            
            order = client.order.create(data=order_data)
            
            return PaymentIntent(
                provider_order_id=order["id"],
                amount=amount,
                currency=currency,
                status=order["status"],
                provider_data=order,
            )
            
        except ImportError:
            raise PaymentProviderError("razorpay library not installed")
        except Exception as exc:
            logger.error("Razorpay order creation failed: %s", exc)
            raise PaymentProviderError(f"Failed to create order: {exc}")
    
    def verify_payment(
        self,
        *,
        provider_order_id: str,
        provider_payment_id: str,
        provider_signature: str,
    ) -> VerificationResult:
        """Verify a Razorpay payment using signature."""
        try:
            body = f"{provider_order_id}|{provider_payment_id}"
            
            expected_signature = hmac.new(
                self.key_secret.encode("utf-8"),
                body.encode("utf-8"),
                hashlib.sha256,
            ).hexdigest()
            
            is_valid = hmac.compare_digest(expected_signature, provider_signature)
            
            if not is_valid:
                logger.warning("Razorpay signature mismatch: order=%s", provider_order_id)
                return PaymentVerificationError("Signature verification failed")
            
            return VerificationResult(
                is_valid=True,
                transaction_id=provider_payment_id,
                amount=None,
                currency=None,
                raw_data={
                    "order_id": provider_order_id,
                    "payment_id": provider_payment_id,
                },
            )
            
        except Exception as exc:
            logger.error("Razorpay verification failed: %s", exc)
            raise PaymentVerificationError(f"Verification failed: {exc}")
    
    def verify_webhook(self, payload: bytes, signature: str) -> dict[str, Any]:
        """Verify a Razorpay webhook signature."""
        if not self.webhook_secret:
            raise WebhookSignatureError("Webhook secret not configured")
        
        try:
            expected_signature = hmac.new(
                self.webhook_secret.encode("utf-8"),
                payload,
                hashlib.sha256,
            ).hexdigest()
            
            if not hmac.compare_digest(expected_signature, signature):
                raise WebhookSignatureError("Webhook signature mismatch")
            
            import json
            return json.loads(payload)
            
        except WebhookSignatureError:
            raise
        except Exception as exc:
            logger.error("Razorpay webhook verification failed: %s", exc)
            raise WebhookSignatureError(f"Webhook verification failed: {exc}")
    
    def refund(
        self,
        payment_id: str,
        amount: float | None = None,
        reason: str | None = None,
    ) -> dict[str, Any]:
        """Initiate a refund."""
        try:
            import razorpay
            
            client = razorpay.Client(auth=(self.key_id, self.key_secret))
            
            refund_data = {"payment_id": payment_id}
            if amount is not None:
                refund_data["amount"] = int(amount * 100)
            
            refund = client.payment.refund(payment_id, refund_data)
            
            return {
                "refund_id": refund["id"],
                "status": refund["status"],
                "amount": float(refund["amount"]) / 100,
                "currency": refund["currency"],
            }
            
        except ImportError:
            raise PaymentProviderError("razorpay library not installed")
        except Exception as exc:
            logger.error("Razorpay refund failed: %s", exc)
            raise PaymentProviderError(f"Refund failed: {exc}")
    
    def fetch_payment(self, payment_id: str) -> dict[str, Any]:
        """Fetch payment details from Razorpay."""
        try:
            import razorpay
            
            client = razorpay.Client(auth=(self.key_id, self.key_secret))
            payment = client.payment.fetch(payment_id)
            
            return {
                "id": payment["id"],
                "amount": float(payment["amount"]) / 100,
                "currency": payment["currency"],
                "status": payment["status"],
                "method": payment["method"],
                "email": payment.get("email"),
                "contact": payment.get("contact"),
                "order_id": payment.get("order_id"),
                "created_at": payment.get("created_at"),
            }
            
        except ImportError:
            raise PaymentProviderError("razorpay library not installed")
        except Exception as exc:
            logger.error("Razorpay fetch payment failed: %s", exc)
            raise PaymentProviderError(f"Failed to fetch payment: {exc}")


def create_razorpay_provider() -> RazorpayProvider | None:
    """Create Razorpay provider from settings."""
    from app.core.config import settings
    
    key_id = getattr(settings, "RAZORPAY_KEY_ID", None)
    key_secret = getattr(settings, "RAZORPAY_KEY_SECRET", None)
    
    if not key_id or not key_secret:
        logger.debug("Razorpay not configured, skipping")
        return None
    
    webhook_secret = getattr(settings, "RAZORPAY_WEBHOOK_SECRET", None)
    
    return RazorpayProvider(
        key_id=key_id,
        key_secret=key_secret,
        webhook_secret=webhook_secret,
    )


# Try to register on import
try:
    from app.services.payments.base import register_provider
    
    provider = create_razorpay_provider()
    if provider:
        register_provider(provider)
        logger.info("Razorpay payment provider registered")
except Exception as exc:
    logger.debug("Could not register Razorpay provider: %s", exc)