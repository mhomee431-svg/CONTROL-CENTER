"""AWS resource tagging helper.

Provides a consistent tagging scheme for all resources created by the
application (used by the boto3 clients for S3 uploads, CloudWatch metrics,
etc.) as well as metadata for observability.
"""
import logging
import os
from typing import Any

from app.core.config import settings

logger = logging.getLogger("app.core.resource_tags")


def get_resource_tags(**extra: str) -> dict[str, str]:
    """Return the standard tag set for AWS resources created by the app.

    Tags:
        Project      → hyperlocal
        Environment  → development | staging | production
        Owner        → platform-team
        ManagedBy    → Terraform (or Boto3 when created at runtime)
        CostCenter   → hyperlocal-001

    Extra tags passed as keyword arguments are merged on top.
    """
    tags = {
        "Project": settings.APP_NAME.split()[0].lower() or "hyperlocal",
        "Environment": settings.ENVIRONMENT,
        "Owner": "platform-team",
        "ManagedBy": "Terraform",
        "CostCenter": "hyperlocal-001",
    }
    if extra:
        tags.update({k: str(v) for k, v in extra.items() if v})
    return tags


def tag_s3_object(key: str) -> str:
    """Return an S3 object key with a metadata sidecar?  No — S3 objects can't
    be tagged, only buckets.  This helper returns the key unchanged but logs
    the intended tags so audits can correlate.
    """
    logger.info("S3 object key=%s tags=%s", key, get_resource_tags())
    return key


def cloudwatch_namespace() -> str:
    """Return the CloudWatch metrics namespace for this environment."""
    return f"Hyperlocal/{settings.ENVIRONMENT}"


def log_group_name(component: str = "api") -> str:
    """Return CloudWatch log group name for a component."""
    return f"/hyperlocal/{settings.ENVIRONMENT}/{component}"


def alarm_name(name: str) -> str:
    """Prefix an alarm name with the environment."""
    return f"{settings.ENVIRONMENT}-{name}"


def get_cost_summary_metadata() -> dict[str, Any]:
    """Metadata used by the cost guide / dashboards to group spend."""
    return {
        "project": "hyperlocal",
        "environment": settings.ENVIRONMENT,
        "owner": "platform-team",
        "cost_center": "hyperlocal-001",
        "managed_by": "Terraform",
    }