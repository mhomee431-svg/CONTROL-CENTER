"""AWS CloudWatch integration.

Provides:
- CloudWatch Logs integration
- CloudWatch Metrics publishing
- CloudWatch Alarms configuration
- Structured log formatting for CloudWatch
"""
import json
import logging
import os
from datetime import datetime, timezone
from typing import Any, Optional

from app.core.config import settings

logger = logging.getLogger("app.observability.cloudwatch")


class CloudWatchHandler(logging.Handler):
    """Custom log handler that formats logs for CloudWatch."""
    
    def __init__(self, log_group: str | None = None, stream_name: str | None = None):
        super().__init__()
        self.log_group = log_group or f"/hyperlocal/{settings.ENVIRONMENT}"
        self.stream_name = stream_name or os.getenv("HOSTNAME", "api")
        self._client = None
    
    @property
    def client(self):
        """Lazy-initialize CloudWatch Logs client."""
        if self._client is None:
            try:
                import boto3
                self._client = boto3.client(
                    "logs",
                    region_name=getattr(settings, "AWS_REGION", "ap-south-1"),
                )
            except Exception as exc:
                logger.error("Failed to create CloudWatch client: %s", exc)
        return self._client
    
    def emit(self, record: logging.LogRecord) -> None:
        """Format and emit a log record."""
        try:
            log_entry = {
                "timestamp": int(record.created * 1000),
                "message": self.format(record),
            }
            print(json.dumps(log_entry, default=str))
        except Exception:
            self.handleError(record)


def setup_cloudwatch_logging(
    *,
    log_level: str | None = None,
    service_name: str | None = None,
) -> None:
    """Configure structured logging for CloudWatch."""
    root_logger = logging.getLogger()
    level = getattr(logging, (log_level or settings.LOG_LEVEL).upper())
    root_logger.setLevel(level)
    
    handler = CloudWatchHandler()
    handler.setLevel(level)
    
    formatter = CloudWatchFormatter(
        service_name=service_name or settings.LOG_SERVICE_NAME,
        environment=settings.ENVIRONMENT,
    )
    handler.setFormatter(formatter)
    root_logger.addHandler(handler)


class CloudWatchFormatter(logging.Formatter):
    """JSON log formatter optimized for CloudWatch Insights."""
    
    def __init__(self, service_name: str, environment: str):
        super().__init__()
        self.service_name = service_name
        self.environment = environment
    
    def format(self, record: logging.LogRecord) -> str:
        """Format log record as JSON."""
        log_entry = {
            "timestamp": datetime.fromtimestamp(record.created, tz=timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "service": self.service_name,
            "environment": self.environment,
            "module": record.module,
            "function": record.funcName,
            "line": record.lineno,
        }
        
        if hasattr(record, "request_id"):
            log_entry["request_id"] = record.request_id
        if hasattr(record, "correlation_id"):
            log_entry["correlation_id"] = record.correlation_id
        
        if record.exc_info and record.exc_info[0] is not None:
            log_entry["exception"] = {
                "type": record.exc_info[0].__name__,
                "message": str(record.exc_info[1]),
                "traceback": self.formatException(record.exc_info),
            }
        
        return json.dumps(log_entry, default=str)


def publish_metric(
    namespace: str,
    metric_name: str,
    value: float,
    unit: str = "Count",
    dimensions: dict[str, str] | None = None,
) -> bool:
    """Publish a custom metric to CloudWatch."""
    try:
        import boto3
        
        client = boto3.client(
            "cloudwatch",
            region_name=getattr(settings, "AWS_REGION", "ap-south-1"),
        )
        
        metric_data = {
            "MetricName": metric_name,
            "Value": value,
            "Unit": unit,
            "Timestamp": datetime.now(timezone.utc),
        }
        
        if dimensions:
            metric_data["Dimensions"] = [
                {"Name": k, "Value": v}
                for k, v in dimensions.items()
            ]
        
        client.put_metric_data(
            Namespace=namespace,
            MetricData=[metric_data],
        )
        
        return True
        
    except ImportError:
        logger.debug("boto3 not installed, skipping CloudWatch metric publish")
        return False
    except Exception as exc:
        logger.error("Failed to publish CloudWatch metric: %s", exc)
        return False


def publish_api_metrics(
    *,
    request_count: int = 0,
    error_count: int = 0,
    avg_latency_ms: float = 0,
) -> bool:
    """Publish API metrics to CloudWatch."""
    namespace = f"Hyperlocal/{settings.ENVIRONMENT}"
    
    if request_count:
        publish_metric(namespace, "APIRequests", request_count, "Count", {"Service": "api"})
    
    if error_count:
        publish_metric(namespace, "APIErrors", error_count, "Count", {"Service": "api"})
    
    if avg_latency_ms:
        publish_metric(namespace, "APILatency", avg_latency_ms, "Milliseconds", {"Service": "api"})
    
    return True


def create_cloudwatch_alarms(
    *,
    topic_arn: str,
    rds_instance_id: str | None = None,
) -> list[str]:
    """Create CloudWatch alarms for the application."""
    try:
        import boto3
        
        client = boto3.client(
            "cloudwatch",
            region_name=getattr(settings, "AWS_REGION", "ap-south-1"),
        )
        
        alarms = []
        
        # API 5xx error rate alarm
        client.put_metric_alarm(
            AlarmName=f"{settings.ENVIRONMENT}-api-5xx-rate",
            AlarmDescription="API 5xx error rate > 1% for 5 minutes",
            MetricName="APIErrors",
            Namespace=f"Hyperlocal/{settings.ENVIRONMENT}",
            Statistic="Sum",
            Period=300,
            EvaluationPeriods=1,
            Threshold=10,
            ComparisonOperator="GreaterThanThreshold",
            Dimensions=[{"Name": "Service", "Value": "api"}],
            AlarmActions=[topic_arn],
            OKActions=[topic_arn],
        )
        alarms.append(f"{settings.ENVIRONMENT}-api-5xx-rate")
        
        # API latency alarm
        client.put_metric_alarm(
            AlarmName=f"{settings.ENVIRONMENT}-api-latency",
            AlarmDescription="API average latency > 2 seconds",
            MetricName="APILatency",
            Namespace=f"Hyperlocal/{settings.ENVIRONMENT}",
            Statistic="Average",
            Period=300,
            EvaluationPeriods=2,
            Threshold=2000,
            ComparisonOperator="GreaterThanThreshold",
            Dimensions=[{"Name": "Service", "Value": "api"}],
            AlarmActions=[topic_arn],
            OKActions=[topic_arn],
        )
        alarms.append(f"{settings.ENVIRONMENT}-api-latency")
        
        # RDS CPU alarm
        if rds_instance_id:
            client.put_metric_alarm(
                AlarmName=f"{settings.ENVIRONMENT}-rds-cpu",
                AlarmDescription="RDS CPU utilization > 80%",
                MetricName="CPUUtilization",
                Namespace="AWS/RDS",
                Statistic="Average",
                Period=300,
                EvaluationPeriods=2,
                Threshold=80,
                ComparisonOperator="GreaterThanThreshold",
                Dimensions=[{"Name": "DBInstanceIdentifier", "Value": rds_instance_id}],
                AlarmActions=[topic_arn],
                OKActions=[topic_arn],
            )
            alarms.append(f"{settings.ENVIRONMENT}-rds-cpu")
        
        logger.info("Created %d CloudWatch alarms", len(alarms))
        return alarms
        
    except ImportError:
        logger.warning("boto3 not installed, cannot create CloudWatch alarms")
        return []
    except Exception as exc:
        logger.error("Failed to create CloudWatch alarms: %s", exc)
        return []


def create_log_group(log_group: str, retention_days: int = 14) -> bool:
    """Create a CloudWatch log group with retention policy."""
    try:
        import boto3
        
        client = boto3.client(
            "logs",
            region_name=getattr(settings, "AWS_REGION", "ap-south-1"),
        )
        
        try:
            client.create_log_group(logGroupName=log_group)
            logger.info("Created CloudWatch log group: %s", log_group)
        except client.exceptions.ResourceAlreadyExistsException:
            logger.debug("CloudWatch log group already exists: %s", log_group)
        
        client.put_retention_policy(
            logGroupName=log_group,
            retentionInDays=retention_days,
        )
        
        return True
        
    except ImportError:
        logger.debug("boto3 not installed, skipping log group creation")
        return False
    except Exception as exc:
        logger.error("Failed to create CloudWatch log group: %s", exc)
        return False