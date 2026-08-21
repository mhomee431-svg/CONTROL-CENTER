"""Phase 15 foundation tests — config, middleware, errors, tasks, storage, providers."""

import asyncio
import os
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402


# ── Configuration loading ────────────────────────────────────────────────────
def test_settings_loads():
    from app.core.config import settings

    assert settings.APP_NAME == "Hyperlocal Customer API"
    assert settings.ENVIRONMENT in ("development", "test", "staging", "production")
    assert settings.DATABASE_URL
    assert settings.REDIS_URL
    assert settings.CELERY_BROKER_URL
    assert settings.JWT_SECRET_KEY


def test_settings_environment_profiles():
    from app.core.env import VALID_ENVIRONMENTS, is_valid_environment

    assert "development" in VALID_ENVIRONMENTS
    assert "test" in VALID_ENVIRONMENTS
    assert "staging" in VALID_ENVIRONMENTS
    assert "production" in VALID_ENVIRONMENTS
    assert is_valid_environment("test")
    assert not is_valid_environment("invalid")


def test_settings_cors_origin_list():
    from app.core.config import settings

    assert isinstance(settings.cors_origin_list, list)
    assert len(settings.cors_origin_list) > 0


def test_settings_sync_url():
    from app.core.config import settings

    url = settings.sqlalchemy_sync_url
    assert "asyncpg" not in url


# ── Logging ──────────────────────────────────────────────────────────────────
def test_logging_setup():
    from app.core.logging import setup_logging

    setup_logging()
    import logging

    root = logging.getLogger()
    assert root.level > 0


# ── Exception handling ───────────────────────────────────────────────────────
def test_app_error_hierarchy():
    from app.core.exceptions import (
        AppError,
        ConflictError,
        ForbiddenError,
        NotFoundError,
        RateLimitError,
        UnauthorizedError,
        ValidationError,
    )

    assert issubclass(NotFoundError, AppError)
    assert issubclass(UnauthorizedError, AppError)
    assert issubclass(ForbiddenError, AppError)
    assert issubclass(ValidationError, AppError)
    assert issubclass(ConflictError, AppError)
    assert issubclass(RateLimitError, AppError)

    err = NotFoundError("test")
    assert err.status_code == 404
    assert err.error_code == "NOT_FOUND"


# ── Security / JWT ───────────────────────────────────────────────────────────
def test_jwt_token_roundtrip():
    from app.core.security import create_access_token, get_token_subject

    token, _ = create_access_token("42")
    assert get_token_subject(token) == 42


def test_jwt_invalid_token():
    from app.core.security import get_token_subject

    assert get_token_subject("invalid.token.here") is None


# ── Storage abstraction ──────────────────────────────────────────────────────
@pytest.mark.asyncio
async def test_local_storage_upload_delete():
    from app.core.storage import LocalStorageProvider

    provider = LocalStorageProvider(upload_dir="test_uploads")
    url = await provider.upload_file(b"hello", "test.txt", "text/plain")
    assert url.startswith("/static/uploads/")
    assert await provider.delete_file(url) is True


# ── Email / SMS abstractions ─────────────────────────────────────────────────
@pytest.mark.asyncio
async def test_mock_email_provider():
    from app.services.email_service import EmailMessage, MockEmailProvider

    provider = MockEmailProvider()
    result = await provider.send(
        EmailMessage(to_emails=["test@example.com"], subject="Test", html_body="<p>Hi</p>")
    )
    assert result is True


@pytest.mark.asyncio
async def test_mock_sms_provider():
    from app.services.sms_service import MockSMSProvider

    provider = MockSMSProvider()
    result = await provider.send("+919999999999", "Test message")
    assert result is True


# ── Celery / background jobs ─────────────────────────────────────────────────
def test_celery_app_configured():
    from app.core.celery_app import celery_app

    assert celery_app.main == "hyperlocal"
    assert celery_app.conf.timezone == "Asia/Kolkata"
    assert celery_app.conf.task_serializer == "json"


def test_celery_task_registered():
    from app.core.tasks import health_check_task, sample_background_task

    assert sample_background_task.name == "app.core.tasks.sample_background_task"
    assert health_check_task.name == "app.core.tasks.health_check_task"


def test_celery_task_executes():
    from app.core.tasks import sample_background_task

    result = sample_background_task.run("hello")
    assert result["status"] == "success"
    assert result["arg"] == "hello"


# ── Health checks ────────────────────────────────────────────────────────────
def test_health_router_exists():
    from app.core.health import router

    routes = {r.path for r in router.routes}
    assert "/health" in routes
    assert "/ready" in routes


# ── Middleware ───────────────────────────────────────────────────────────────
def test_middleware_classes_exist():
    from app.core.middleware import RequestIDMiddleware, SecurityHeadersMiddleware

    assert RequestIDMiddleware is not None
    assert SecurityHeadersMiddleware is not None


# ── Rate limiting ────────────────────────────────────────────────────────────
def test_rate_limiter_configured():
    from app.core.rate_limit import limiter

    assert limiter is not None
    assert limiter.enabled is False  # disabled in test env


# ── Domain layer ─────────────────────────────────────────────────────────────
def test_domain_entities():
    from app.domain.entities import Product, Shop, User, UserStatus

    user = User(phone_number="+919999999999")
    assert user.status == UserStatus.ACTIVE

    shop = Shop(name="Test Shop")
    assert shop.status.value == "pending"

    product = Product(name="Test Product")
    assert product.status.value == "active"


# ── Repository / Service base ────────────────────────────────────────────────
def test_base_repository_importable():
    from app.repositories.base import BaseRepository

    assert BaseRepository is not None


def test_base_service_importable():
    from app.services.base import BaseService

    assert BaseService is not None