"""SMS service abstraction — providers are swappable via config.

Supported providers:
    mock      → log only (default for development/test)
    twilio    → Twilio API
    aws-sns   → AWS Simple Notification Service
"""

import logging
from abc import ABC, abstractmethod
from typing import Optional

from app.core.config import settings

logger = logging.getLogger("app.services.sms")


class BaseSMSProvider(ABC):
    """Interface for SMS delivery providers."""

    @abstractmethod
    async def send(self, phone_number: str, message: str) -> bool:
        """Send an SMS. Return True on success, raise on failure."""
        raise NotImplementedError


class MockSMSProvider(BaseSMSProvider):
    """Logs SMS instead of sending (development/test)."""

    async def send(self, phone_number: str, message: str) -> bool:
        logger.info("[MOCK SMS] to=%s message=%s", phone_number, message[:200])
        return True


class TwilioSMSProvider(BaseSMSProvider):
    """Send SMS via Twilio."""

    async def send(self, phone_number: str, message: str) -> bool:
        from twilio.rest import Client

        client = Client(settings.TWILIO_ACCOUNT_SID, settings.TWILIO_AUTH_TOKEN)
        result = client.messages.create(
            body=message,
            from_=settings.TWILIO_FROM_NUMBER,
            to=phone_number,
        )
        logger.info("Twilio SMS sent: %s", result.sid)
        return True


class AWSSNSProvider(BaseSMSProvider):
    """Send SMS via AWS SNS."""

    async def send(self, phone_number: str, message: str) -> bool:
        import boto3
        from botocore.exceptions import ClientError

        client = boto3.client(
            "sns",
            region_name=settings.AWS_SNS_REGION,
            aws_access_key_id=settings.AWS_SNS_ACCESS_KEY,
            aws_secret_access_key=settings.AWS_SNS_SECRET_KEY,
        )
        try:
            response = client.publish(
                PhoneNumber=phone_number,
                Message=message,
                MessageAttributes={
                    "AWS.SNS.SMS.SenderID": {
                        "DataType": "String",
                        "StringValue": settings.AWS_SNS_SENDER_ID or "HYPERLOCAL",
                    }
                },
            )
            logger.info("SNS SMS sent: %s", response.get("MessageId"))
            return True
        except ClientError as exc:
            logger.error("SNS SMS failed: %s", exc)
            return False


def get_sms_provider() -> BaseSMSProvider:
    """Factory to return the configured SMS provider."""
    provider = settings.SMS_PROVIDER.lower()
    if provider == "twilio":
        return TwilioSMSProvider()
    if provider == "aws-sns":
        return AWSSNSProvider()
    return MockSMSProvider()


# Singleton
_sms_provider: Optional[BaseSMSProvider] = None


def get_sms_service() -> BaseSMSProvider:
    global _sms_provider
    if _sms_provider is None:
        _sms_provider = get_sms_provider()
    return _sms_provider