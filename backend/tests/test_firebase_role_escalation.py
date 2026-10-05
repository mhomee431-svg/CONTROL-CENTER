"""Regression: a client cannot choose its own privilege level at sign-up.

Vulnerability
-------------
``POST /auth/firebase`` accepts a ``requested_role`` field. It is client-supplied
by definition, and it was used verbatim when creating a new account::

    role_name = requested_role or "customer"

Anyone with a valid Firebase phone token could therefore POST::

    {"firebase_id_token": "<valid>", "requested_role": "admin"}

and be issued a brand-new **admin** account â€” full privilege escalation from an
otherwise unauthenticated sign-up, with no approval step anywhere.

Fix
---
``sanitise_requested_role`` reduces the value to an allowlisted self-service
tier and downgrades everything else to ``customer``. Elevated roles remain an
admin-granted action.
"""
import pytest

from app.services.firebase_auth_service import (
    DEFAULT_ROLE,
    SELF_SERVICE_ROLES,
    sanitise_requested_role,
)


class TestNoPrivilegeEscalation:
    @pytest.mark.parametrize(
        "hostile",
        [
            "admin",
            "administrator",
            "superadmin",
            "super_admin",
            "super-admin",
            "staff",
            "ADMIN",  # case must not smuggle it through
            " Admin ",
            "root",
            "owner",
        ],
    )
    def test_elevated_roles_are_downgraded(self, hostile: str):
        assert sanitise_requested_role(hostile) == DEFAULT_ROLE

    def test_none_and_empty_default_to_customer(self):
        assert sanitise_requested_role(None) == DEFAULT_ROLE
        assert sanitise_requested_role("") == DEFAULT_ROLE
        assert sanitise_requested_role("   ") == DEFAULT_ROLE

    def test_unknown_but_benign_role_is_also_downgraded(self):
        # Not a security hole, but an allowlist must be a closed set.
        assert sanitise_requested_role("wizard") == DEFAULT_ROLE


class TestLegitimateSignUpStillWorks:
    @pytest.mark.parametrize("role", sorted(SELF_SERVICE_ROLES))
    def test_self_service_roles_pass_through(self, role: str):
        assert sanitise_requested_role(role) == role

    def test_normalised_for_case_and_whitespace(self):
        assert sanitise_requested_role("  Shopkeeper ") == "shopkeeper"


class TestTheAllowlistItself:
    def test_privileged_roles_are_absent(self):
        for banned in ("admin", "superadmin", "staff", "root"):
            assert banned not in SELF_SERVICE_ROLES

    def test_default_is_the_lowest_privilege_role(self):
        assert DEFAULT_ROLE == "customer"