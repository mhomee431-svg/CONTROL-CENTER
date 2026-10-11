"""Audit Log Center: server-side derivation and filtering helpers.

These exercise the pure functions the endpoint relies on, so the derived
severity/result and the access-control guards are covered without standing up
a database or a full ASGI client — matching the repo's unit-test style.
"""

from datetime import datetime, timezone

import pytest
from fastapi import HTTPException

from app.api.v1.admin_users import (
    _assert_can_touch,
    _assert_not_self,
    _generate_temporary_password,
    _role_default_permissions,
)
from app.api.v1.offers_audit import (
    _parse_day,
    derive_result,
    derive_severity,
)
from app.models import AdminUser


def _admin(admin_id: int, *, is_owner: bool = False, role: str = "SUPPORT_ADMIN") -> AdminUser:
    return AdminUser(
        id=admin_id,
        username=f"admin{admin_id}",
        role_name=role,
        is_owner=is_owner,
        is_active=True,
        hashed_password="x",
        permissions=[],
    )


# --- Severity derivation ---------------------------------------------------


def test_severity_prefers_explicit_details_value():
    assert derive_severity("shop.updated", {"severity": "warning"}) == "WARNING"


@pytest.mark.parametrize(
    "action",
    ["shop.deleted", "admin_user.access_reset", "token.revoked", "data.purged"],
)
def test_severity_marks_destructive_actions_critical(action):
    assert derive_severity(action, None) == "CRITICAL"


@pytest.mark.parametrize(
    "action",
    ["shop.archived", "shop.verification.rejected", "admin_user.deactivated"],
)
def test_severity_marks_high_impact_actions_warning(action):
    assert derive_severity(action, None) == "WARNING"


def test_severity_defaults_to_info():
    assert derive_severity("shop.updated", None) == "INFO"
    assert derive_severity("feature_flag.updated", {}) == "INFO"


# --- Result derivation -----------------------------------------------------


def test_result_reads_explicit_outcome_keys():
    assert derive_result({"status": "failed"}) == "FAILED"
    assert derive_result({"result": "partial"}) == "PARTIAL"
    assert derive_result({"outcome": "success"}) == "SUCCESS"


def test_result_defaults_to_success_when_unrecorded():
    # An audit row is only written for an action the server carried out.
    assert derive_result(None) == "SUCCESS"
    assert derive_result({}) == "SUCCESS"


# --- Date bound parsing ----------------------------------------------------


def test_date_bound_treats_a_bare_date_as_the_whole_day():
    start = _parse_day("2026-10-01", end_of_day=False)
    end = _parse_day("2026-10-01", end_of_day=True)

    assert start == datetime(2026, 10, 1, 0, 0, 0, tzinfo=timezone.utc)
    assert end.hour == 23 and end.minute == 59 and end.second == 59
    assert start.tzinfo is timezone.utc


def test_date_bound_rejects_a_malformed_value():
    with pytest.raises(HTTPException) as excinfo:
        _parse_day("not-a-date", end_of_day=False)
    assert excinfo.value.status_code == 422


# --- Admin-user guards -----------------------------------------------------


def test_admin_cannot_act_on_its_own_account():
    actor = _admin(1)
    with pytest.raises(HTTPException) as excinfo:
        _assert_not_self(actor, actor, "deactivate")
    assert excinfo.value.status_code == 422


def test_a_delegated_admin_cannot_touch_an_owner():
    actor = _admin(1, is_owner=False)
    owner = _admin(2, is_owner=True)
    with pytest.raises(HTTPException) as excinfo:
        _assert_can_touch(actor, owner)
    assert excinfo.value.status_code == 403


def test_the_owner_may_touch_another_owner():
    owner = _admin(1, is_owner=True)
    other_owner = _admin(2, is_owner=True)
    # No exception raised.
    _assert_can_touch(owner, other_owner)


# --- Role -> permission defaults -------------------------------------------


def test_role_defaults_follow_least_privilege():
    assert _role_default_permissions("SUPER_ADMIN") == ["*"]
    assert "admins.manage" not in _role_default_permissions("ANALYST")
    assert "audit.read" in _role_default_permissions("ANALYST")
    # An unknown role receives no grants rather than inheriting anything.
    assert _role_default_permissions("UNKNOWN_ROLE") == []


def test_generated_temporary_password_is_strong_and_unique():
    first = _generate_temporary_password()
    second = _generate_temporary_password()

    assert first != second
    assert len(first) >= 12
    assert any(c.isupper() for c in first)
    assert any(c.islower() for c in first)
    assert any(c.isdigit() for c in first)
