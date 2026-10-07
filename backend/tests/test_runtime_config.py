import pytest
from pydantic import ValidationError

from app.core.config import Settings


def test_production_database_url_uses_tls_and_keeps_password_encoded():
    config = Settings(
        SECRET_KEY="test-production-key-that-is-long-enough",
        ENVIRONMENT="production",
        COOKIE_SECURE=True,
        DB_HOST="database.internal",
        DB_USER="api-user",
        DB_PASSWORD="secret/with@reserved:characters",
    )

    url = config.database_url

    assert url.drivername == "postgresql+psycopg"
    assert url.username == "api-user"
    assert url.password == "secret/with@reserved:characters"
    assert url.host == "database.internal"
    assert url.query["sslmode"] == "require"


@pytest.mark.parametrize(
    "settings",
    [
        {"COOKIE_SECURE": False},
        {"DB_PASSWORD": None},
    ],
)
def test_non_development_requires_secure_cookie_and_postgres_credentials(settings):
    values = {
        "SECRET_KEY": "test-production-key-that-is-long-enough",
        "ENVIRONMENT": "staging",
        "COOKIE_SECURE": True,
        "DB_HOST": "database.internal",
        "DB_USER": "api-user",
        "DB_PASSWORD": "database-password",
    }
    values.update(settings)

    with pytest.raises(ValidationError):
        Settings(**values)
