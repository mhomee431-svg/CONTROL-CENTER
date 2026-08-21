"""Service-layer background tasks — domain-specific job orchestration."""

import logging
from datetime import datetime, timezone

from app.core.celery_app import celery_app

logger = logging.getLogger("app.services.tasks")


@celery_app.task(name="app.services.tasks.dispatch_email")
def dispatch_email(to_email: str, subject: str, template_name: str, context: dict) -> dict:
    """Dispatch an email via the configured email provider.

    The actual delivery is delegated to the email abstraction so the provider
    can be swapped (SMTP / SendGrid / AWS SES) without touching this task.
    """
    logger.info(
        "dispatch_email to=%s subject=%s template=%s",
        to_email,
        subject,
        template_name,
    )
    # TODO: import EmailService and call send here.
    return {
        "status": "queued",
        "to_email": to_email,
        "template": template_name,
        "queued_at": datetime.now(timezone.utc).isoformat(),
    }


@celery_app.task(name="app.services.tasks.dispatch_sms")
def dispatch_sms(phone_number: str, template_name: str, context: dict) -> dict:
    """Dispatch an SMS via the configured SMS provider.

    The actual delivery is delegated to the SMS abstraction so the provider
    can be swapped (Mock / Twilio / MSG91 / AWS SNS) without touching this task.
    """
    logger.info(
        "dispatch_sms to=%s template=%s",
        phone_number,
        template_name,
    )
    # TODO: import SmsService and call send here.
    return {
        "status": "queued",
        "phone_number": phone_number,
        "template": template_name,
        "queued_at": datetime.now(timezone.utc).isoformat(),
    }