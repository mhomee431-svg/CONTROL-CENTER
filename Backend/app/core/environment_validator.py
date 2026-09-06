"""Environment configuration validator."""
import logging
from dataclasses import dataclass, field
from typing import Any

from app.core.config import settings

logger = logging.getLogger("app.core.environment_validator")


@dataclass
class ValidationResult:
    check: str
    passed: bool
    message: str
    severity: str = "error"


@dataclass
class EnvironmentReport:
    environment: str
    results: list[ValidationResult] = field(default_factory=list)
    
    def append(self, result):
        if isinstance(result, list):
            self.results.extend(result)
        else:
            self.results.append(result)
    
    @property
    def is_valid(self):
        return all(r.passed for r in self.results if r.severity == "error")
    
    @property
    def errors(self):
        return [r for r in self.results if not r.passed and r.severity == "error"]
    
    def to_dict(self):
        return {
            "environment": self.environment,
            "is_valid": self.is_valid,
            "total_checks": len(self.results),
            "passed": sum(1 for r in self.results if r.passed),
            "failed": sum(1 for r in self.results if not r.passed),
            "errors": [{"check": r.check, "message": r.message} for r in self.errors],
        }


def validate_environment() -> EnvironmentReport:
    """Validate the current environment configuration."""
    report = EnvironmentReport(environment=settings.ENVIRONMENT)
    report.append(_check_core_settings())
    report.append(_check_database())
    report.append(_check_redis())
    report.append(_check_security())
    report.append(_check_storage())
    if settings.is_production:
        report.append(_check_production_requirements())
    return report


def _check_core_settings():
    valid_envs = ("development", "test", "staging", "production")
    return [
        ValidationResult("app_name", bool(settings.APP_NAME), f"App: {settings.APP_NAME}"),
        ValidationResult("environment", settings.ENVIRONMENT in valid_envs, f"Env: {settings.ENVIRONMENT}"),
    ]


def _check_database():
    return [ValidationResult("database_url", bool(settings.DATABASE_URL), "Database URL configured")]


def _check_redis():
    return [ValidationResult("redis_url", bool(settings.REDIS_URL), f"Redis: {settings.REDIS_URL}")]


def _check_security():
    jwt_ok = bool(settings.JWT_SECRET_KEY) and settings.JWT_SECRET_KEY not in ("change-me-in-production", "changeme", "secret")
    return [ValidationResult("jwt_secret", jwt_ok, "JWT secret configured")]


def _check_storage():
    return [ValidationResult("storage_provider", settings.STORAGE_PROVIDER in ("local", "s3", "cloudinary"), f"Storage: {settings.STORAGE_PROVIDER}")]


def _check_production_requirements():
    return [
        ValidationResult("debug_off", not settings.DEBUG, "Debug OFF"),
        ValidationResult("security_headers", settings.SECURITY_HEADERS_ENABLED, "Security headers ON"),
        ValidationResult("rate_limiting", settings.RATE_LIMIT_ENABLED, "Rate limiting ON"),
    ]


def get_environment_config_guide() -> dict[str, Any]:
    """Get configuration guide for all environments."""
    return {
        "development": {"ENVIRONMENT": "development", "DEBUG": True, "STORAGE_PROVIDER": "local"},
        "test": {"ENVIRONMENT": "test", "DEBUG": False, "STORAGE_PROVIDER": "local"},
        "staging": {"ENVIRONMENT": "staging", "DEBUG": False, "STORAGE_PROVIDER": "s3"},
        "production": {"ENVIRONMENT": "production", "DEBUG": False, "STORAGE_PROVIDER": "s3"},
    }