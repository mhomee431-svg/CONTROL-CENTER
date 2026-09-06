"""Fraud detection and suspicious activity monitoring."""
import logging
from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.search import SearchEvent
from app.models.session import AuthSession

logger = logging.getLogger("app.services.fraud_detection")


def detect_brute_force_auth(
    db: Session,
    *,
    ip_address: str | None = None,
    user_id: int | None = None,
    minutes: int = 15,
    threshold: int = 20,
) -> dict[str, Any]:
    """Detect brute force authentication attempts."""
    since = datetime.now(timezone.utc) - timedelta(minutes=minutes)
    
    query = db.query(func.count(AuthSession.id)).filter(
        AuthSession.created_at >= since,
        AuthSession.is_revoked == True,  # noqa: E712
    )
    
    if ip_address:
        query = query.filter(AuthSession.ip_address == ip_address)
    if user_id:
        query = query.filter(AuthSession.user_id == user_id)
    
    failed_count = query.scalar() or 0
    
    return {
        "is_suspicious": failed_count >= threshold,
        "failed_attempts": failed_count,
        "threshold": threshold,
        "window_minutes": minutes,
    }


def detect_unusual_api_activity(
    db: Session,
    *,
    user_id: int,
    hours: int = 1,
    threshold: int = 1000,
) -> dict[str, Any]:
    """Detect unusual API activity from a user."""
    since = datetime.now(timezone.utc) - timedelta(hours=hours)
    
    api_calls = (
        db.query(func.count(SearchEvent.id))
        .filter(SearchEvent.user_id == user_id, SearchEvent.event_time >= since)
        .scalar() or 0
    )
    
    return {
        "is_suspicious": api_calls >= threshold,
        "api_calls": api_calls,
        "threshold": threshold,
        "window_hours": hours,
        "user_id": user_id,
    }


def detect_suspicious_shop_creation(
    db: Session,
    *,
    hours: int = 24,
    threshold: int = 5,
) -> list[dict[str, Any]]:
    """Detect suspicious shop creation patterns."""
    since = datetime.now(timezone.utc) - timedelta(hours=hours)
    
    from app.models.shop import ShopOwner
    
    suspicious = (
        db.query(ShopOwner.user_id, func.count(ShopOwner.shop_id).label("shop_count"))
        .filter(ShopOwner.created_at >= since)
        .group_by(ShopOwner.user_id)
        .having(func.count(ShopOwner.shop_id) >= threshold)
        .all()
    )
    
    return [
        {"user_id": uid, "shop_count": count, "threshold": threshold}
        for uid, count in suspicious
    ]


def detect_price_manipulation(
    db: Session,
    *,
    product_master_id: int,
    hours: int = 24,
    threshold: int = 5,
) -> dict[str, Any]:
    """Detect suspicious price changes."""
    since = datetime.now(timezone.utc) - timedelta(hours=hours)
    
    from app.models.product import PriceHistory
    
    change_count = (
        db.query(func.count(PriceHistory.id))
        .filter(PriceHistory.product_master_id == product_master_id, PriceHistory.created_at >= since)
        .scalar() or 0
    )
    
    return {
        "is_suspicious": change_count >= threshold,
        "change_count": change_count,
        "threshold": threshold,
        "product_master_id": product_master_id,
    }


def get_suspicious_activity_report(db: Session, *, hours: int = 24) -> dict[str, Any]:
    """Get a comprehensive suspicious activity report."""
    suspicious_shops = detect_suspicious_shop_creation(db, hours=hours)
    
    since = datetime.now(timezone.utc) - timedelta(hours=hours)
    
    suspicious_ips = (
        db.query(AuthSession.ip_address, func.count(AuthSession.id).label("failed_count"))
        .filter(
            AuthSession.created_at >= since,
            AuthSession.is_revoked == True,  # noqa: E712
            AuthSession.ip_address.isnot(None),
        )
        .group_by(AuthSession.ip_address)
        .having(func.count(AuthSession.id) >= 20)
        .all()
    )
    
    return {
        "period_hours": hours,
        "checked_at": datetime.now(timezone.utc).isoformat(),
        "suspicious_shop_creations": suspicious_shops,
        "suspicious_ips": [{"ip": ip, "failed_attempts": count} for ip, count in suspicious_ips],
        "total_flags": len(suspicious_shops) + len(suspicious_ips),
    }