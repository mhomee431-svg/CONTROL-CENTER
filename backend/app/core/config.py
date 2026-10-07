"""Backend runtime configuration.

Values are read from the environment so the same image runs locally, on
staging and in production without edits. Defaults are the local development
values documented in the repository's WORKFLOW.md.
"""

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # API
    API_V1_PREFIX: str = "/api/v1"
    PROJECT_NAME: str = "HyperLocal Admin API"

    # Storage. SQLite by default so the console can run with no external
    # service; point DATABASE_URL at Postgres for a shared environment.
    DATABASE_URL: str = "sqlite:///./hyperlocal.db"

    # Auth
    SECRET_KEY: str = ""
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24
    @model_validator(mode="after")
    def require_signing_key(self):
        if len(self.SECRET_KEY) < 32 or self.SECRET_KEY == "change-me-in-production-admin-console-signing-key":
            raise ValueError("Set a unique SECRET_KEY (at least 32 characters) in backend/.env")
        return self

    # CORS: the Next.js dev server. Credentials are allowed because the admin
    # session cookie has to travel with every request.
    CORS_ORIGINS: list[str] = [
        "http://localhost:3000",
        "http://127.0.0.1:3000",
    ]


settings = Settings()
