"""AWS CloudTrail integration.

CloudTrail logs every API call made in AWS and stores them in S3.
This module provides configuration helpers and security event detection.
"""
import json
import logging
from datetime import datetime, timezone, timedelta
from typing import Any, Optional

from app.core.config import settings

logger = logging.getLogger("app.observability.cloudtrail")


def create_cloudtrail(
    *,
    trail_name: str | None = None,
    bucket_name: str | None = None,
    log_group_arn: str | None = None,
) -> dict[str, Any]:
    """Create a CloudTrail trail configuration."""
    try:
        import boto3
        
        client = boto3.client(
            "cloudtrail",
            region_name=getattr(settings, "AWS_REGION", "ap-south-1"),
        )
        
        trail_name = trail_name or f"hyperlocal-{settings.ENVIRONMENT}-trail"
        
        if not bucket_name:
            raise ValueError("S3 bucket_name is required for CloudTrail")
        
        kwargs = {
            "Name": trail_name,
            "S3BucketName": bucket_name,
            "IsMultiRegionTrail": True,
            "EnableLogFileValidation": True,
            "IncludeGlobalServiceEvents": True,
            "IsOrganizationTrail": False,
        }
        
        if log_group_arn:
            kwargs["CloudWatchLogsLogGroupArn"] = log_group_arn
            kwargs["CloudWatchLogsRoleArn"] = _get_or_create_trail_role()
        
        response = client.create_trail(**kwargs)
        client.start_logging(Name=trail_name)
        
        logger.info("CloudTrail created: %s", trail_name)
        
        return {
            "trail_name": trail_name,
            "trail_arn": response.get("TrailARN"),
            "bucket": bucket_name,
            "status": "created",
        }
        
    except ImportError:
        logger.warning("boto3 not installed, cannot create CloudTrail")
        return {"error": "boto3 not installed"}
    except Exception as exc:
        logger.error("Failed to create CloudTrail: %s", exc)
        return {"error": str(exc)}


def _get_or_create_trail_role() -> str:
    """Get or create IAM role for CloudTrail to write to CloudWatch Logs."""
    try:
        import boto3
        
        iam = boto3.client("iam")
        role_name = "hyperlocal-cloudtrail-role"
        
        try:
            response = iam.get_role(RoleName=role_name)
            return response["Role"]["Arn"]
        except iam.exceptions.NoSuchEntityException:
            pass
        
        trust_policy = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {"Service": "cloudtrail.amazonaws.com"},
                    "Action": "sts:AssumeRole",
                }
            ],
        }
        
        response = iam.create_role(
            RoleName=role_name,
            AssumeRolePolicyDocument=json.dumps(trust_policy),
            Description="Role for CloudTrail to write to CloudWatch Logs",
        )
        
        iam.put_role_policy(
            RoleName=role_name,
            PolicyName="cloudtrail-logs-policy",
            PolicyDocument=json.dumps({
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Action": ["logs:CreateLogStream", "logs:PutLogEvents"],
                        "Resource": "*",
                    }
                ],
            }),
        )
        
        return response["Role"]["Arn"]
        
    except Exception as exc:
        logger.error("Failed to create CloudTrail role: %s", exc)
        raise


def get_trail_status(trail_name: str) -> dict[str, Any]:
    """Get the status of a CloudTrail trail."""
    try:
        import boto3
        
        client = boto3.client(
            "cloudtrail",
            region_name=getattr(settings, "AWS_REGION", "ap-south-1"),
        )
        
        response = client.get_trail_status(Name=trail_name)
        
        return {
            "trail_name": trail_name,
            "is_logging": response.get("IsLogging", False),
            "latest_delivery_time": response.get("LatestDeliveryTime"),
            "latest_delivery_error": response.get("LatestDeliveryError"),
        }
        
    except ImportError:
        return {"error": "boto3 not installed"}
    except Exception as exc:
        logger.error("Failed to get CloudTrail status: %s", exc)
        return {"error": str(exc)}


def lookup_events(
    *,
    start_time: datetime | None = None,
    end_time: datetime | None = None,
    event_name: str | None = None,
    username: str | None = None,
    max_results: int = 50,
) -> list[dict[str, Any]]:
    """Lookup CloudTrail events."""
    try:
        import boto3
        
        client = boto3.client(
            "cloudtrail",
            region_name=getattr(settings, "AWS_REGION", "ap-south-1"),
        )
        
        kwargs = {"MaxResults": min(max_results, 50)}
        
        if start_time:
            kwargs["StartTime"] = start_time
        if end_time:
            kwargs["EndTime"] = end_time
        
        attributes = []
        if event_name:
            attributes.append({"AttributeKey": "EventName", "AttributeValue": event_name})
        if username:
            attributes.append({"AttributeKey": "Username", "AttributeValue": username})
        
        if attributes:
            kwargs["LookupAttributes"] = attributes
        
        response = client.lookup_events(**kwargs)
        
        events = []
        for event in response.get("Events", []):
            events.append({
                "event_id": event.get("EventId"),
                "event_name": event.get("EventName"),
                "event_time": event.get("EventTime"),
                "username": event.get("Username"),
                "resources": event.get("Resources", []),
            })
        
        return events
        
    except ImportError:
        logger.debug("boto3 not installed, cannot lookup CloudTrail events")
        return []
    except Exception as exc:
        logger.error("Failed to lookup CloudTrail events: %s", exc)
        return []


def detect_security_events(*, hours: int = 24) -> list[dict[str, Any]]:
    """Detect potential security events from CloudTrail."""
    try:
        import boto3
        
        client = boto3.client(
            "cloudtrail",
            region_name=getattr(settings, "AWS_REGION", "ap-south-1"),
        )
        
        start_time = datetime.now(timezone.utc) - timedelta(hours=hours)
        security_events = []
        
        monitored_events = {
            "ConsoleLogin": "Console login",
            "CreateUser": "User created",
            "DeleteUser": "User deleted",
            "AttachUserPolicy": "User policy attached",
            "CreateAccessKey": "Access key created",
            "DeleteAccessKey": "Access key deleted",
            "AuthorizeSecurityGroupIngress": "Security group ingress modified",
            "PutBucketPolicy": "S3 bucket policy changed",
            "DeleteBucket": "S3 bucket deleted",
            "DeleteTrail": "CloudTrail deleted",
            "StopLogging": "CloudTrail logging stopped",
        }
        
        for event_name, description in monitored_events.items():
            try:
                response = client.lookup_events(
                    LookupAttributes=[{"AttributeKey": "EventName", "AttributeValue": event_name}],
                    StartTime=start_time,
                    MaxResults=50,
                )
                
                for event in response.get("Events", []):
                    security_events.append({
                        "severity": _get_event_severity(event_name),
                        "event_name": event_name,
                        "description": description,
                        "event_time": event.get("EventTime"),
                        "username": event.get("Username"),
                        "resources": event.get("Resources", []),
                    })
                    
            except Exception as exc:
                logger.debug("Error looking up %s: %s", event_name, exc)
        
        security_events.sort(key=lambda e: e.get("event_time", ""), reverse=True)
        return security_events
        
    except ImportError:
        logger.debug("boto3 not installed, cannot detect security events")
        return []
    except Exception as exc:
        logger.error("Failed to detect security events: %s", exc)
        return []


def _get_event_severity(event_name: str) -> str:
    """Get severity level for an event type."""
    critical_events = {"DeleteUser", "DeleteAccessKey", "DeleteBucket", "DeleteTrail", "StopLogging"}
    warning_events = {"CreateUser", "AttachUserPolicy", "CreateAccessKey", "AuthorizeSecurityGroupIngress", "PutBucketPolicy"}
    
    if event_name in critical_events:
        return "critical"
    if event_name in warning_events:
        return "warning"
    return "info"


def get_trail_config_instructions() -> dict[str, str]:
    """Get instructions for configuring CloudTrail."""
    return {
        "terraform_resource": """
resource "aws_cloudtrail" "hyperlocal" {
  name                       = "hyperlocal-${var.environment}-trail"
  s3_bucket_name             = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail      = true
  enable_log_file_validation = true
}
""",
        "console_steps": [
            "1. Open CloudTrail console",
            "2. Click 'Create trail'",
            f"3. Set trail name: hyperlocal-{settings.ENVIRONMENT}-trail",
            "4. Enable 'Multi-region trail'",
            "5. Select S3 bucket for log storage",
            "6. Enable 'Log file validation'",
            "7. Click 'Create'",
        ],
    }