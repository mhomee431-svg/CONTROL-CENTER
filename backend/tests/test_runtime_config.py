import pytest
from pydantic import ValidationError

from app.core.config import Settings


# Build Settings with no environment file. A developer's local backend/.env
# (gitignored) must never change what these assertions measure — without this a
# local DATABASE_URL makes `database_url` return a plain string and the test
# fails for a reason that has nothing to do with the code under test.
Settings.__pydantic_settings_config__ = None


def _settings(**overrides) -> Settings:
    return Settings(_env_file=None, **overrides)  # type: ignore[call-arg]


def test_production_database_url_uses_tls_and_keeps_password_encoded():
    config = _settings(
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
        _settings(**values)
