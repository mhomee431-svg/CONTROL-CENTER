"""Backup monitoring and health check service.

Monitors:
- RDS automated backup status
- S3 backup file integrity
- Backup age and freshness
- Recovery point objective (RPO) compliance
"""
import logging
from datetime import datetime, timezone, timedelta
from typing import Any, Optional

from app.core.config import settings

logger = logging.getLogger("app.services.backup_monitor")


def check_rds_backup_status(
    db_instance_id: str,
    *,
    max_backup_age_hours: int = 25,
) -> dict[str, Any]:
    """Check RDS automated backup status."""
    try:
        import boto3
        
        client = boto3.client(
            "rds",
            region_name=getattr(settings, "AWS_REGION", "ap-south-1"),
        )
        
        response = client.describe_db_instances(DBInstanceIdentifier=db_instance_id)
        instance = response["DBInstances"][0]
        backup_retention = instance.get("BackupRetentionPeriod", 0)
        
        snapshots = client.describe_db_snapshots(
            DBInstanceIdentifier=db_instance_id,
            SnapshotType="automated",
            MaxRecords=1,
        )
        
        latest_snapshot = None
        if snapshots["DBSnapshots"]:
            snap = snapshots["DBSnapshots"][0]
            latest_snapshot = {
                "id": snap["DBSnapshotIdentifier"],
                "created_at": snap["SnapshotCreateTime"],
                "status": snap["Status"],
                "size_gb": snap.get("AllocatedStorage", 0),
            }
            
            age = datetime.now(timezone.utc) - snap["SnapshotCreateTime"]
            latest_snapshot["age_hours"] = age.total_seconds() / 3600
            latest_snapshot["is_fresh"] = age.total_seconds() < (max_backup_age_hours * 3600)
        
        return {
            "db_instance_id": db_instance_id,
            "backup_retention_days": backup_retention,
            "latest_snapshot": latest_snapshot,
            "status": "healthy" if (latest_snapshot and latest_snapshot["is_fresh"]) else "warning",
        }
        
    except ImportError:
        return {"error": "boto3 not installed"}
    except Exception as exc:
        logger.error("Failed to check RDS backup status: %s", exc)
        return {"error": str(exc)}


def check_s3_backup_freshness(
    bucket_name: str,
    *,
    prefix: str = "daily/",
    max_age_hours: int = 25,
) -> dict[str, Any]:
    """Check if S3 backups are fresh."""
    try:
        import boto3
        
        s3 = boto3.client(
            "s3",
            region_name=getattr(settings, "AWS_REGION", "ap-south-1"),
        )
        
        response = s3.list_objects_v2(
            Bucket=bucket_name,
            Prefix=prefix,
            MaxKeys=10,
        )
        
        if "Contents" not in response:
            return {
                "bucket": bucket_name,
                "status": "warning",
                "message": "No backups found",
            }
        
        latest = max(response["Contents"], key=lambda x: x["LastModified"])
        age = datetime.now(timezone.utc) - latest["LastModified"]
        age_hours = age.total_seconds() / 3600
        
        return {
            "bucket": bucket_name,
            "latest_backup": {
                "key": latest["Key"],
                "size_bytes": latest["Size"],
                "last_modified": latest["LastModified"].isoformat(),
                "age_hours": round(age_hours, 2),
            },
            "is_fresh": age_hours < max_age_hours,
            "status": "healthy" if age_hours < max_age_hours else "warning",
        }
        
    except ImportError:
        return {"error": "boto3 not installed"}
    except Exception as exc:
        logger.error("Failed to check S3 backup freshness: %s", exc)
        return {"error": str(exc)}


def get_backup_summary(
    db_instance_id: str,
    backup_bucket: str,
) -> dict[str, Any]:
    """Get a complete backup health summary."""
    rds_status = check_rds_backup_status(db_instance_id)
    s3_status = check_s3_backup_freshness(backup_bucket)
    
    statuses = [rds_status.get("status", "unknown"), s3_status.get("status", "unknown")]
    
    if "error" in statuses:
        overall = "error"
    elif "warning" in statuses:
        overall = "warning"
    else:
        overall = "healthy"
    
    return {
        "overall_status": overall,
        "checked_at": datetime.now(timezone.utc).isoformat(),
        "rds": rds_status,
        "s3": s3_status,
        "retention_policy": {
            "rds_days": 7,
            "s3_daily_days": 30,
            "s3_monthly_days": 365,
        },
    }


def verify_backup_integrity(
    backup_path: str,
    expected_hash: str | None = None,
) -> dict[str, Any]:
    """Verify backup file integrity."""
    import hashlib
    import os
    
    if not os.path.exists(backup_path):
        return {"valid": False, "error": "Backup file not found"}
    
    try:
        sha256 = hashlib.sha256()
        with open(backup_path, "rb") as f:
            for chunk in iter(lambda: f.read(8192), b""):
                sha256.update(chunk)
        
        actual_hash = sha256.hexdigest()
        
        result = {
            "valid": True,
            "file": backup_path,
            "size_bytes": os.path.getsize(backup_path),
            "sha256": actual_hash,
        }
        
        if expected_hash:
            result["hash_match"] = actual_hash == expected_hash
            result["valid"] = result["hash_match"]
        
        return result
        
    except Exception as exc:
        logger.error("Backup integrity check failed: %s", exc)
        return {"valid": False, "error": str(exc)}