"""Profile response regression coverage for Google-only accounts.

Calls the real route handlers with an ORM user and a mocked persistence layer;
this verifies serialization, not Firebase authentication or database persistence.
"""
import asyncio
import json
from datetime import datetime, timezone
from unittest.mock import MagicMock

import pytest

from app.api.routes.profile import get_profile, patch_profile, update_profile
from app.models.user import User
from app.schemas.profile import ProfileUpdate


@pytest.mark.parametrize("phone_number", [None, "+919999999999"])
@pytest.mark.parametrize("method", ["GET", "PUT", "PATCH"])
def test_profile_response_accepts_optional_phone(method, phone_number):
    user = User(
        id=101,
        name="Test Shopkeeper",
        email="shopkeeper@example.com",
        phone_number=phone_number,
        avatar_url=None,
        created_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
    )
    db = MagicMock()
    if method == "GET":
        response = asyncio.run(get_profile(current_user=user))
    else:
        handler = update_profile if method == "PUT" else patch_profile
        response = asyncio.run(handler(
            payload=ProfileUpdate(name="Updated Name"), current_user=user, db=db,
        ))
        db.add.assert_called_once_with(user)
        db.commit.assert_called_once_with()
        db.refresh.assert_called_once_with(user)

    body = json.loads(response.body)
    assert response.status_code == 200
    assert body["success"] is True
    assert body["data"]["phone_number"] == phone_number
    assert body["data"]["email"] == "shopkeeper@example.com"
    assert body["data"]["id"] == 101
    assert body["data"]["name"] == (
        "Test Shopkeeper" if method == "GET" else "Updated Name"
    )
