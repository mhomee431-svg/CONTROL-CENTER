"""Backend runtime configuration.

Values are read from the environment so the same image runs locally, on
staging and in production without edits. Defaults are the local development
values documented in the repository's WORKFLOW.md.
"""

from typing import Literal

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy.engine import URL


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # API
    API_V1_PREFIX: str = "/api/v1"
    PROJECT_NAME: str = "HyperLocal Admin API"
    ENVIRONMENT: Literal["development", "staging", "production"] = "development"

    # Storage. SQLite by default so the console can run with no external
    # service. Shared environments provide individual PostgreSQL connection
    # values so credentials are never embedded in a URL.
    DATABASE_URL: str | None = None
    DB_HOST: str | None = None
    DB_PORT: int = 5432
    DB_NAME: str = "hyperlocal"
    DB_USER: str | None = None
    DB_PASSWORD: str | None = None

    # Auth
    SECRET_KEY: str = ""
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24
    # Session cookie transport. False for local HTTP; set COOKIE_SECURE=true in
    # any environment served over HTTPS so the admin session never travels
    # plaintext.
    COOKIE_SECURE: bool = False

    @model_validator(mode="after")
    def require_signing_key(self) -> "Settings":
        if len(self.SECRET_KEY) < 32 or self.SECRET_KEY == "change-me-in-production-admin-console-signing-key":
            raise ValueError("Set a unique SECRET_KEY (at least 32 characters) in backend/.env")
        if self.ENVIRONMENT != "development":
            if not self.COOKIE_SECURE:
                raise ValueError("COOKIE_SECURE must be true outside development")
            if not self.DB_HOST or not self.DB_USER or not self.DB_PASSWORD:
                raise ValueError("Configure PostgreSQL connection values outside development")
        return self

    @property
    def database_url(self) -> str | URL:
        if self.DATABASE_URL:
            return self.DATABASE_URL
        if self.DB_HOST and self.DB_USER and self.DB_PASSWORD:
            return URL.create(
                "postgresql+psycopg",
                username=self.DB_USER,
                password=self.DB_PASSWORD,
                host=self.DB_HOST,
                port=self.DB_PORT,
                database=self.DB_NAME,
                query={"sslmode": "require"} if self.ENVIRONMENT != "development" else {},
            )
        return "sqlite:///./hyperlocal.db"

    # CORS: the Next.js dev server. Credentials are allowed because the admin
    # session cookie has to travel with every request.
    CORS_ORIGINS: list[str] = [
        "http://localhost:3000",
        "http://127.0.0.1:3000",
    ]


settings = Settings()
