"""Platform configuration service.

Provides a unified interface for managing:
- System settings (key-value configuration)
- Feature flags (enable/disable features)
"""
import json
import logging
from typing import Any

from sqlalchemy.orm import Session

from app.models.system import SystemSetting, FeatureFlag

logger = logging.getLogger("app.services.platform_config")


def get_setting(db: Session, key: str, default: Any = None) -> Any:
    """Get a system setting value."""
    setting = db.query(SystemSetting).filter(SystemSetting.key == key).first()
    if setting is None:
        return default
    return _parse_value(setting.value, setting.value_type)


def set_setting(db: Session, key: str, value: Any, *, value_type: str = "string", description: str | None = None, is_secret: bool = False) -> SystemSetting:
    """Set a system setting value."""
    setting = db.query(SystemSetting).filter(SystemSetting.key == key).first()
    if setting is None:
        setting = SystemSetting(key=key, value_type=value_type)
        db.add(setting)
    setting.value = _serialize_value(value, value_type)
    setting.value_type = value_type
    if description:
        setting.description = description
    setting.is_secret = is_secret
    db.flush()
    return setting


def is_feature_enabled(db: Session, name: str, *, user_id: int | None = None, shop_id: int | None = None) -> bool:
    """Check if a feature flag is enabled."""
    flag = db.query(FeatureFlag).filter(FeatureFlag.name == name).first()
    if flag is None or not flag.is_enabled:
        return False
    if flag.rollout_percentage < 100:
        if user_id is not None:
            return (user_id % 100) < flag.rollout_percentage
        if shop_id is not None:
            return (shop_id % 100) < flag.rollout_percentage
        return flag.default_enabled
    return True


def set_feature_flag(db: Session, name: str, is_enabled: bool, *, rollout_percentage: int = 100, scope: str = "GLOBAL", description: str | None = None) -> FeatureFlag:
    """Set a feature flag."""
    flag = db.query(FeatureFlag).filter(FeatureFlag.name == name).first()
    if flag is None:
        flag = FeatureFlag(name=name, scope=scope)
        db.add(flag)
    flag.is_enabled = is_enabled
    flag.rollout_percentage = rollout_percentage
    flag.default_enabled = is_enabled
    if description:
        flag.description = description
    db.flush()
    return flag


def initialize_default_settings(db: Session) -> None:
    """Initialize default system settings."""
    defaults = {
        "platform_name": ("Hyperlocal", "string", "Platform display name"),
        "max_shops_per_user": ("5", "int", "Maximum shops a user can own"),
        "search_radius_km": ("10", "float", "Default search radius in km"),
        "otp_expiry_minutes": ("5", "int", "OTP expiry time in minutes"),
        "maintenance_mode": ("false", "boolean", "Enable maintenance mode"),
    }
    for key, (value, value_type, description) in defaults.items():
        existing = db.query(SystemSetting).filter(SystemSetting.key == key).first()
        if existing is None:
            set_setting(db, key, value, value_type=value_type, description=description)
    db.commit()


def initialize_default_feature_flags(db: Session) -> None:
    """Initialize default feature flags."""
    defaults = [
        {"name": "barcode_scanning", "is_enabled": True, "rollout_percentage": 100},
        {"name": "excel_import", "is_enabled": True, "rollout_percentage": 100},
        {"name": "pos_integration", "is_enabled": False, "rollout_percentage": 0},
    ]
    for flag_data in defaults:
        existing = db.query(FeatureFlag).filter(FeatureFlag.name == flag_data["name"]).first()
        if existing is None:
            flag = FeatureFlag(**flag_data, scope="GLOBAL", default_enabled=flag_data["is_enabled"])
            db.add(flag)
    db.commit()


def _parse_value(value: str | None, value_type: str) -> Any:
    """Parse a stored value based on its type."""
    if value is None:
        return None
    try:
        match value_type:
            case "int": return int(value)
            case "float": return float(value)
            case "boolean": return value.lower() in ("true", "1", "yes")
            case "json": return json.loads(value)
            case _: return value
    except (ValueError, json.JSONDecodeError):
        return value


def _serialize_value(value: Any, value_type: str) -> str:
    """Serialize a value for storage."""
    if value is None:
        return ""
    match value_type:
        case "json": return json.dumps(value)
        case "boolean": return "true" if value else "false"
        case _: return str(value)