"""
Application configuration management with environment profiles and
provider-safe secrets. No provider secrets are hardcoded -- everything
is loaded from environment files / OS secrets.
"""
import os
from functools import lru_cache
from pathlib import Path
from typing import List, Optional

from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# ── Environment file resolution ─────────────────────────────────────────────
# Order of precedence for the active environment profile:
#   1. HYPERLOCAL_ENV  (explicit override by tooling / CI)
#   2. ENVIRONMENT     (common convention)
#   3. "development"   (safe default)
def _resolve_environment() -> str:
    env = os.getenv("HYPERLOCAL_ENV") or os.getenv("ENVIRONMENT") or "development"
    return env.lower()


def _resolve_env_file(environment: str) -> str:
    """Locate the appropriate .env file for the current environment."""
    backend_dir = Path(__file__).resolve().parents[2]  # Backend/
    candidates = [
        f".env.{environment}",
        ".env",
    ]
    for name in candidates:
        candidate = backend_dir / name
        if candidate.exists():
            return str(candidate)
    return str(backend_dir / ".env")


_ENVIRONMENT = _resolve_environment()
_ENV_FILE = _resolve_env_file(_ENVIRONMENT)


class Settings(BaseSettings):
    # ── Core ────────────────────────────────────────────────────────────────
    ENVIRONMENT: str = Field(_ENVIRONMENT, description="development|test|staging|production")
    APP_NAME: str = "Hyperlocal Customer API"
    APP_VERSION: str = "1.0.0"
    APP_DESCRIPTION: str = (
        "Search any product. Instantly know which nearby shop or mall has it, "
        "at what price, whether it is available, and how far it is."
    )
    DEBUG: bool = False
    API_PREFIX: str = "/api/v1"
    FRONTEND_URL: str = "http://localhost:3000"
    BACKEND_URL: str = "http://localhost:8000"

    # ── PostgreSQL ─────────────────────────────────────────────────────────────
    DATABASE_URL: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/hyperlocal"
    DATABASE_POOL_SIZE: int = Field(20, ge=1, le=100)
    DATABASE_MAX_OVERFLOW: int = Field(40, ge=0, le=200)
    DATABASE_POOL_TIMEOUT: int = Field(30, ge=1)
    DATABASE_POOL_RECYCLE: int = Field(1800, ge=60)
    DATABASE_ECHO: bool = False
    POSTGIS_EXTENSION: str = "postgis"

    # ── Redis / Cache ─────────────────────────────────────────────────────────
    REDIS_URL: str = "redis://localhost:6379/0"
    CACHE_DEFAULT_TTL: int = Field(300, ge=0)

    # ── Celery ─────────────────────────────────────────────────────────────────
    CELERY_BROKER_URL: str = "redis://localhost:6379/1"
    CELERY_RESULT_BACKEND: str = "redis://localhost:6379/2"
    CELERY_TIMEZONE: str = "Asia/Kolkata"
    CELERY_TASK_TIME_LIMIT: int = Field(300, ge=1)
    CELERY_TASK_SOFT_TIME_LIMIT: int = Field(240, ge=1)

    # ── Security / JWT ─────────────────────────────────────────────────────────
    JWT_SECRET_KEY: str = "change-me-in-production"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = Field(1440, ge=1)
    REFRESH_TOKEN_EXPIRE_DAYS: int = Field(30, ge=1)
    PASSWORD_HASHING_ALGO: str = "bcrypt"

    # ── OTP ─────────────────────────────────────────────────────────────────────
    OTP_DEV_MODE: bool = True
    OTP_DEV_VALUE: str = "123456"
    OTP_EXPIRE_MINUTES: int = Field(5, ge=1)
    OTP_MAX_ATTEMPTS: int = Field(5, ge=1)
    OTP_COOLDOWN_SECONDS: int = Field(60, ge=0)
    OTP_MAX_RESENDS: int = Field(5, ge=1)
    OTP_RESEND_COOLDOWN_SECONDS: int = Field(60, ge=0)
    OTP_LENGTH: int = Field(6, ge=4, le=8)
    # Storage backend for OTP records: "memory://" (single process) or
    # "redis://host:port/db" (distributed — REQUIRED for 2+ workers/instances).
    OTP_STORAGE_URI: str = "memory://"

    # ── Session / Tokens ────────────────────────────────────────────────────────
    SESSION_MAX_DEVICES: int = Field(5, ge=1, le=20)
    SESSION_IDLE_TIMEOUT_DAYS: int = Field(30, ge=1)
    TOKEN_ISSUER: str = "hyperlocal-api"
    TOKEN_AUDIENCE: str = "hyperlocal-app"
    REFRESH_TOKEN_ROTATION: bool = True
    REFRESH_TOKEN_REUSE_DETECTION: bool = True

    # ── SMS Provider (replaceable) ─────────────────────────────────────────────
    SMS_PROVIDER: str = "mock"  # mock | twilio | msg91 | aws-sns
    SMS_PROVIDER_API_KEY: Optional[str] = None
    SMS_PROVIDER_SENDER_ID: Optional[str] = None
    SMS_PROVIDER_SECRET: Optional[str] = None
    TWILIO_ACCOUNT_SID: Optional[str] = None
    TWILIO_AUTH_TOKEN: Optional[str] = None
    TWILIO_FROM_NUMBER: Optional[str] = None
    AWS_SNS_ACCESS_KEY: Optional[str] = None
    AWS_SNS_SECRET_KEY: Optional[str] = None
    AWS_SNS_REGION: str = "us-east-1"
    AWS_SNS_SENDER_ID: Optional[str] = None

    # ── Fast2SMS OTP delivery ────────────────────────────────────────────────────
    # Sends OTPs via Fast2SMS' "otp" route (https://www.fast2sms.com/dev/bulkV2).
    #   OTP_MODE=mock → the OTP is printed to the server console (₹0 testing).
    #   OTP_MODE=live → a real SMS is sent and the Fast2SMS balance is debited.
    FAST2SMS_API_KEY: Optional[str] = None
    OTP_MODE: str = "mock"  # mock | live

    # ── Google OAuth (social login) ─────────────────────────────────────────────
    # Credentials from a Google Cloud Console "OAuth 2.0 Client" (Web application).
    # GOOGLE_CALLBACK_URL must be registered as the authorized redirect URI and
    # is used verbatim as the callback route's mount path.
    GOOGLE_CLIENT_ID: Optional[str] = None
    GOOGLE_CLIENT_SECRET: Optional[str] = None
    GOOGLE_CALLBACK_URL: str = "http://localhost:5000/api/auth/google/callback"
    GOOGLE_OAUTH_AUTHORIZE_URL: str = "https://accounts.google.com/o/oauth2/v2/auth"
    GOOGLE_OAUTH_TOKEN_URL: str = "https://oauth2.googleapis.com/token"
    GOOGLE_OAUTH_CERTS_URL: str = "https://www.googleapis.com/oauth2/v3/certs"
    GOOGLE_OAUTH_SCOPES: str = "openid email profile"

    # ── Push Provider (replaceable; Phase 27) ──────────────────────────────────
    PUSH_PROVIDER: str = "mock"  # mock | fcm
    # FCM credentials are NEVER hardcoded — supply via secret manager / env:
    FCM_CREDENTIALS_FILE: Optional[str] = None   # path to service-account JSON
    FCM_CREDENTIALS_JSON: Optional[str] = None   # raw service-account JSON string
    FCM_DRY_RUN: bool = False                    # true → validate without delivering
    # Anti-spam controls (Phase 27)
    NOTIFICATION_DEDUPE_COOLDOWN_SECONDS: int = Field(3600, ge=0)  # same dedupe_key within window → suppressed
    NOTIFICATION_HOURLY_CAP: int = Field(20, ge=1)                 # max non-transactional notifications / user / hour
    NOTIFICATION_MAX_DELIVERY_ATTEMPTS: int = Field(3, ge=1)       # retries per device before giving up

    # ── Email Provider (replaceable) ───────────────────────────────────────────
    EMAIL_PROVIDER: str = "mock"  # mock | smtp | sendgrid | aws-ses
    EMAIL_FROM_ADDRESS: str = "noreply@hyperlocal.app"
    EMAIL_FROM_NAME: str = "Hyperlocal"
    SMTP_HOST: Optional[str] = None
    SMTP_PORT: int = Field(587, ge=1, le=65535)
    SMTP_USERNAME: Optional[str] = None
    SMTP_PASSWORD: Optional[str] = None
    SMTP_USE_TLS: bool = True
    SENDGRID_API_KEY: Optional[str] = None
    SENDGRID_TEMPLATE_PREFIX: Optional[str] = None
    AWS_SES_REGION: str = "us-east-1"
    AWS_SES_ACCESS_KEY: Optional[str] = None
    AWS_SES_SECRET_KEY: Optional[str] = None

    # ── Object Storage (replaceable) ───────────────────────────────────────────
    STORAGE_PROVIDER: str = "local"  # local | s3 | cloudinary
    STORAGE_LOCAL_PATH: str = "./storage/uploads"
    S3_BUCKET_NAME: Optional[str] = None
    S3_REGION: str = "us-east-1"
    S3_ACCESS_KEY_ID: Optional[str] = None
    S3_SECRET_ACCESS_KEY: Optional[str] = None
    S3_ENDPOINT_URL: Optional[str] = None
    S3_ACL: str = "public-read"
    CLOUDINARY_CLOUD_NAME: Optional[str] = None
    CLOUDINARY_API_KEY: Optional[str] = None
    CLOUDINARY_API_SECRET: Optional[str] = None
    CLOUDINARY_FOLDER: str = "hyperlocal"

    # ── AWS (Secrets Manager / IAM) ────────────────────────────────────────────
    # Use IAM roles (default credential chain) in production. These fields only
    # control the optional startup hydration helper (app/core/aws_secrets.py).
    # Secrets themselves are never read from source; they arrive via ECS task
    # Secrets Manager injection AND/OR this hydration helper.
    AWS_REGION: str = "us-east-1"
    AWS_SECRETS_REGION: Optional[str] = None      # optional override
    USE_AWS_SECRETS: bool = False                 # True → entrypoint hydrates env from Secrets Manager
    AWS_SECRETS_SECRET_ID: Optional[str] = None    # exact secret name/ARN (e.g. hyperlocal/production)
    AWS_SECRETS_PREFIX: str = "hyperlocal"          # fallback path: <prefix>/<environment>

    # ── CORS ─────────────────────────────────────────────────────────────────────
    CORS_ORIGINS: str = "http://localhost:3000,http://localhost:5000"

    # ── Rate Limiting ───────────────────────────────────────────────────────────
    RATE_LIMIT_ENABLED: bool = True
    RATE_LIMIT_DEFAULT: str = "100/minute"
    RATE_LIMIT_AUTH_ENDPOINT: str = "5/minute"
    RATE_LIMIT_STORAGE_URI: str = "memory://"

    # Phase 30 — set True ONLY behind a trusted reverse proxy that overwrites
    # X-Forwarded-For; otherwise client keying uses the direct peer address.
    TRUST_X_FORWARDED_FOR: bool = False

    # ── Security Headers ────────────────────────────────────────────────────────
    SECURITY_HEADERS_ENABLED: bool = True
    HSTS_MAX_AGE: int = Field(31536000, ge=0)
    HSTS_INCLUDE_SUBDOMAINS: bool = True
    HSTS_PRELOAD: bool = True
    CSP_DEFAULT_SRC: str = "'self';"
    FRAME_ANCESTORS: str = "'none'"

    # ── Logging ──────────────────────────────────────────────────────────────────
    LOG_LEVEL: str = "INFO"
    LOG_FORMAT: str = "json"  # json | console
    LOG_MAX_BYTES: int = Field(10485760, ge=1024)
    LOG_BACKUP_COUNT: int = Field(5, ge=0)
    LOG_FILE_ENABLED: bool = False
    LOG_FILE_PATH: str = "logs/app.log"

    # ── Request / Correlation IDs ───────────────────────────────────────────────
    REQUEST_ID_HEADER: str = "X-Request-ID"
    CORRELATION_ID_HEADER: str = "X-Correlation-ID"
    DISABLE_DOCS: bool = False

    model_config = SettingsConfigDict(
        env_file=_ENV_FILE,
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    # ── Validators ──────────────────────────────────────────────────────────────
    @field_validator("CORS_ORIGINS", mode="before")
    @classmethod
    def _normalize_cors_origins(cls, v):
        if isinstance(v, (list, tuple)):
            return ",".join(v)
        return v

    @field_validator("LOG_LEVEL", mode="before")
    @classmethod
    def _uppercase_log_level(cls, v):
        return str(v).upper()

    @field_validator("ENVIRONMENT", mode="before")
    @classmethod
    def _normalize_environment(cls, v):
        return str(v).lower()

    @field_validator("OTP_MODE", mode="before")
    @classmethod
    def _normalize_otp_mode(cls, v):
        val = str(v).lower()
        if val not in ("mock", "live"):
            raise ValueError("OTP_MODE must be one of: mock, live")
        return val

    @model_validator(mode="after")
    def _warn_insecure_production(self):
        if (
            self.is_production
            and self.JWT_SECRET_KEY
            in ("change-me-in-production", "changeme", "secret")
        ):
            import warnings

            warnings.warn(
                "JWT_SECRET_KEY is set to an insecure default in production!",
                RuntimeWarning,
            )
        return self

    # ── Derived / computed properties ────────────────────────────────────────────
    @property
    def cors_origin_list(self) -> List[str]:
        return [o.strip() for o in self.CORS_ORIGINS.split(",") if o.strip()]

    @property
    def is_production(self) -> bool:
        return self.ENVIRONMENT == "production"

    @property
    def is_staging(self) -> bool:
        return self.ENVIRONMENT == "staging"

    @property
    def is_test(self) -> bool:
        return self.ENVIRONMENT in ("test", "testing")

    @property
    def is_development(self) -> bool:
        return self.ENVIRONMENT in ("development", "dev")

    @property
    def sqlalchemy_sync_url(self) -> str:
        """Synchronous connection URL for Celery beats / WS."""
        url = self.DATABASE_URL
        for prefix in ("postgresql+asyncpg://", "postgres+asyncpg://"):
            if url.startswith(prefix):
                return url.replace(prefix, "postgresql+psycopg://")
        return url

    @property
    def docs_enabled(self) -> bool:
        return not self.is_production


@lru_cache()
def get_settings() -> Settings:
    return Settings()


settings = get_settings()