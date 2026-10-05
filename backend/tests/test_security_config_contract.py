"""Security contract for backend configuration.

These exist because the failure they guard against is silent: a process starts,
serves traffic, and nothing says the credential was never set.

The rules under test:
  * no hardcoded database password in production;
  * no default/placeholder JWT secret in production;
  * and the check must FAIL CLOSED ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â raising, not warning.

That last point is the whole reason this file exists. The previous
implementation emitted a ``RuntimeWarning`` and returned ``self``, so a
production deploy with `postgres:postgres` as its DSN started normally and the
warning scrolled past in a log nobody reads.
"""
from typing import Any
import pytest
from pydantic import ValidationError

from app.core.config import Settings

# The literal development default, kept here so the test states the fact
# independently of the implementation constant.
DEV_DSN = "postgresql+asyncpg://postgres:postgres@localhost:5432/hyperlocal"


def _settings(**overrides: Any) -> Settings:
    base: dict[str, Any] = {
        "ENVIRONMENT": "production",
        "JWT_SECRET_KEY": "a-real-random-secret-from-the-secret-manager",
        "DATABASE_URL": "postgresql+asyncpg://user:realpass@db.prod.internal:5432/hyperlocal",
    }
    base.update(overrides)
    # model_validate, not Settings(**base): spreading a dict[str, Any] makes a
    # type checker unable to prove every required field is satisfied, so it
    # reports them missing. validate() takes the mapping as data, which is
    # exactly what this helper is producing.
    return Settings.model_validate(base)


class TestProductionFailsClosed:
    def test_real_production_config_is_accepted(self):
        s = _settings()
        assert s.is_production
        assert s.JWT_SECRET_KEY != "change-me-in-production"

    def test_hardcoded_dev_database_url_is_rejected(self):
        with pytest.raises(ValidationError) as exc:
            _settings(DATABASE_URL=DEV_DSN)
        assert "DATABASE_URL" in str(exc.value)

    def test_default_jwt_secret_is_rejected(self):
        with pytest.raises(ValidationError) as exc:
            _settings(JWT_SECRET_KEY="change-me-in-production")
        assert "JWT_SECRET_KEY" in str(exc.value)

    @pytest.mark.parametrize(
        "placeholder", ["changeme", "secret", "secret-key", "your-secret-key"]
    )
    def test_every_known_placeholder_is_rejected(self, placeholder: str):
        with pytest.raises(ValidationError):
            _settings(JWT_SECRET_KEY=placeholder)

    def test_both_problems_are_reported_together(self):
        # One boot failure listing both is more useful than fixing one at a time.
        with pytest.raises(ValidationError) as exc:
            _settings(DATABASE_URL=DEV_DSN, JWT_SECRET_KEY="changeme")
        message = str(exc.value)
        assert "DATABASE_URL" in message and "JWT_SECRET_KEY" in message


class TestNonProductionIsUnaffected:
    @pytest.mark.parametrize("env", ["development", "test", "testing", "staging"])
    def test_dev_defaults_are_fine_outside_production(self, env: str):
        """The local dev experience must keep working ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â a guard that blocks
        `make dev` gets disabled within a week."""
        s = Settings(
            ENVIRONMENT=env,
            JWT_SECRET_KEY="change-me-in-production",
            DATABASE_URL=DEV_DSN,
        )
        assert s.DATABASE_URL == DEV_DSN