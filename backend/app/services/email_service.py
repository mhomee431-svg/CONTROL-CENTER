"""Email service abstraction — providers are swappable via config.

Supported providers:
    mock      → log only (default for development/test)
    smtp      → SMTP relay
    sendgrid  → SendGrid API
    aws-ses   → AWS Simple Email Service
"""

import logging
import smtplib
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from typing import List, Optional

from app.core.config import settings

logger = logging.getLogger("app.services.email")


@dataclass
class EmailMessage:
    to_emails: List[str]
    subject: str
    html_body: str
    text_body: Optional[str] = None
    cc_emails: List[str] = field(default_factory=list)
    bcc_emails: List[str] = field(default_factory=list)
    attachments: List[dict] = field(default_factory=list)  # [{"filename":..., "content":..., "mimetype":...}]


class BaseEmailProvider(ABC):
    """Interface for email delivery providers."""

    @abstractmethod
    async def send(self, message: EmailMessage) -> bool:
        """Send an email. Return True on success, raise on failure."""
        raise NotImplementedError


class MockEmailProvider(BaseEmailProvider):
    """Logs emails instead of sending (development/test)."""

    async def send(self, message: EmailMessage) -> bool:
        logger.info(
            "[MOCK EMAIL] to=%s subject=%s body=%s",
            message.to_emails,
            message.subject,
            message.html_body[:200],
        )
        return True


class SMTPEmailProvider(BaseEmailProvider):
    """Send emails via SMTP."""

    async def send(self, message: EmailMessage) -> bool:
        import aiosmtplib

        msg = MIMEMultipart("alternative")
        msg["Subject"] = message.subject
        msg["From"] = f"{settings.EMAIL_FROM_NAME} <{settings.EMAIL_FROM_ADDRESS}>"
        msg["To"] = ", ".join(message.to_emails)
        if message.cc_emails:
            msg["Cc"] = ", ".join(message.cc_emails)

        msg.attach(MIMEText(message.html_body, "html"))
        if message.text_body:
            msg.attach(MIMEText(message.text_body, "plain"))

        await aiosmtplib.send(
            msg,
            hostname=settings.SMTP_HOST,
            port=settings.SMTP_PORT,
            username=settings.SMTP_USERNAME,
            password=settings.SMTP_PASSWORD,
            use_tls=settings.SMTP_USE_TLS,
        )
        logger.info("Email sent via SMTP to %s", message.to_emails)
        return True


class SendGridEmailProvider(BaseEmailProvider):
    """Send emails via SendGrid API."""

    async def send(self, message: EmailMessage) -> bool:
        import sendgrid
        from sendgrid.helpers.mail import Content, Email, Mail

        sg = sendgrid.SendGridAPIClient(api_key=settings.SENDGRID_API_KEY)
        mail = Mail(
            from_email=Email(settings.EMAIL_FROM_ADDRESS, settings.EMAIL_FROM_NAME),
            to_emails=message.to_emails,
            subject=message.subject,
            html_content=Content("text/html", message.html_body),
        )
        response = sg.client.mail.send.post(request_body=mail.get())
        if response.status_code >= 400:
            logger.error("SendGrid error: %s", response.body)
            return False
        return True


class SESEmailProvider(BaseEmailProvider):
    """Send emails via AWS SES."""

    async def send(self, message: EmailMessage) -> bool:
        import boto3
        from botocore.exceptions import ClientError

        client = boto3.client(
            "ses",
            region_name=settings.AWS_SES_REGION,
            aws_access_key_id=settings.AWS_SES_ACCESS_KEY,
            aws_secret_access_key=settings.AWS_SES_SECRET_KEY,
        )
        try:
            response = client.send_email(
                Source=f"{settings.EMAIL_FROM_NAME} <{settings.EMAIL_FROM_ADDRESS}>",
                Destination={"ToAddresses": message.to_emails},
                Message={
                    "Subject": {"Data": message.subject},
                    "Body": {"Html": {"Data": message.html_body}},
                },
            )
            logger.info("SES message sent: %s", response.get("MessageId"))
            return True
        except ClientError as exc:
            logger.error("SES send failed: %s", exc)
            return False


def get_email_provider() -> BaseEmailProvider:
    """Factory to return the configured email provider."""
    provider = settings.EMAIL_PROVIDER.lower()
    if provider == "smtp":
        return SMTPEmailProvider()
    if provider == "sendgrid":
        return SendGridEmailProvider()
    if provider == "aws-ses":
        return SESEmailProvider()
    return MockEmailProvider()


# Singleton
_email_provider: Optional[BaseEmailProvider] = None


def get_email_service() -> BaseEmailProvider:
    global _email_provider
    if _email_provider is None:
        _email_provider = get_email_provider()
    return _email_provider