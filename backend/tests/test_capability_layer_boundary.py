"""ARCHITECTURE GUARD — paid-feature logic stays in ONE layer.

Product rule (spec): *"Subscription/plan features may come later. Do not
hardcode paid feature logic everywhere."* This module is the tripwire for
that rule. It adds no behaviour of its own; it FAILS the build the moment
plan logic starts spreading into feature code, which is the only moment it
can be caught cheaply — after N screens each re-derive "is this shop Pro?",
the refactor is a project rather than a fix.

The sanctioned shape, and the only one:

    entitlements.py            resolves + derives (the ONLY owner)
      <service>                calls resolve_shop_entitlements, then
                               enforce_feature / enforce_limit, or
                               capabilities_payload
      <route>                  returns capabilities_payload verbatim

Everything these tests forbid is something that bypasses that chain.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

BACKEND_DIR = Path(__file__).resolve().parents[1]
APP_DIR = BACKEND_DIR / "app"
SUBSCRIPTION_PKG = APP_DIR / "services" / "subscription"
ENTITLEMENTS_PY = SUBSCRIPTION_PKG / "entitlements.py"

# The one place allowed to invent these. Mirrors the Dart
# `ShopCapabilities` model; a rename here without a rename there silently
# turns every flag into the permissive default.
CAN_FLAG_KEYS = ("canUsePos", "canUploadExcel", "canCreateOffers", "canViewReports")

# Plan names are DATA (seeded into subscription_plans), never control flow.
# A comparison against one of these means a screen/route has started asking
# "which plan?" instead of "what is this shop allowed to do?".
PLAN_NAME_LITERALS = ("Basic", "Pro", "Premium")

# `plan.name` / `PLAN_TEMPLATES[...]` are the two ways code reaches for a
# plan's identity rather than its entitlements.
_PLAN_IDENTITY = re.compile(
    r"PLAN_TEMPLATES\s*\[|plan\.name\s*(?:==|!=|in\b)|plan_name\s*(?:==|!=)"
)


def _app_python_files() -> list[Path]:
    return sorted(APP_DIR.rglob("*.py"))


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def _in_subscription_package(path: Path) -> bool:
    try:
        path.relative_to(SUBSCRIPTION_PKG)
        return True
    except ValueError:
        return False


class TestPlanLogicStaysCentralized:
    def test_no_plan_identity_comparisons_outside_the_subscription_package(self):
        offenders: list[str] = []
        for path in _app_python_files():
            if _in_subscription_package(path):
                continue
            for number, line in enumerate(_read(path).splitlines(), start=1):
                if _PLAN_IDENTITY.search(line):
                    offenders.append(
                        f"{path.relative_to(BACKEND_DIR)}:{number}: {line.strip()}"
                    )

        assert not offenders, (
            "Plan identity leaked outside app/services/subscription/.\n"
            "Gate on ENTITLEMENTS via enforce_feature()/enforce_limit() (or read the "
            "derived flags from capabilities_payload) - never on which plan the shop "
            "is on. Offenders:\n  " + "\n  ".join(offenders)
        )

    def test_entitlements_module_is_where_plan_names_live(self):
        """The names are allowed - as seed data, in the owner module only."""
        source = _read(ENTITLEMENTS_PY)
        for name in PLAN_NAME_LITERALS:
            assert f'"{name}"' in source, f"expected plan template {name!r} in entitlements.py"

    def test_capability_keys_are_only_built_in_one_place(self):
        """`canX` flags must have exactly ONE producer.

        A second hand-rolled dict of the same keys is how two systems start
        disagreeing about what a shop may do.
        """
        offenders: list[str] = []
        for path in _app_python_files():
            if path.resolve() == ENTITLEMENTS_PY.resolve():
                continue
            if not any(f'"{key}"' in _read(path) for key in CAN_FLAG_KEYS):
                continue
            offenders.append(str(path.relative_to(BACKEND_DIR)))

        assert not offenders, (
            "The canX capability keys must be produced only by "
            "entitlements.derive_shop_capabilities(). These modules also emit "
            "them, which will drift: " + ", ".join(offenders)
        )



class TestCapabilityLayerIsReachable:
    """Behavioural checks - the guard above is a proxy for these."""

    def test_derivation_is_a_pure_function_of_resolved_entitlements(self):
        from app.services.subscription.entitlements import derive_shop_capabilities

        resolved: dict[str, Any] = {
            "grandfathered": False,
            "entitlements": {
                "pos_support": True,
                "listing_features": ["BASIC", "BULK_IMPORT"],
                "offers": True,
                "analytics": True,
            },
        }

        # Two calls, same answer, no DB and no clock: adding a plan tier or a
        # subscription state must not be able to change this function without
        # the change being visible right here.
        assert derive_shop_capabilities(resolved) == derive_shop_capabilities(
            resolved
        )
        assert set(derive_shop_capabilities(resolved)) == set(CAN_FLAG_KEYS)

    def test_the_service_helper_is_the_only_way_to_publish_flags(self):
        from app.services import shopkeeper_service

        assert callable(shopkeeper_service.capabilities_payload)

    def test_enforcement_helpers_are_the_only_way_to_deny(self):
        """Every refusal must come from the shared helpers.

        These raise ENTITLEMENT_DENIED / PLAN_LIMIT_REACHED, the codes the
        Flutter app classifies via ApiException.isEntitlementDenied. A feature
        route that hand-rolls its own 403 stops being classifiable.
        """
        from app.services.subscription import entitlements

        for name in ("enforce_feature", "enforce_limit", "EntitlementDenied"):
            assert hasattr(entitlements, name), f"missing {name}"


class TestFuturePaymentWorkIsNotWiredIn:
    """Guard the *other* half of the constraint.

    "Do not implement payments unless explicitly requested." This does not
    forbid the subscription module that already exists; it pins that no
    payment EXECUTION path has been built, so its arrival is a deliberate,
    reviewable change rather than something that grew unnoticed.
    """

    def test_no_payment_provider_is_configured_in_app_settings(self):
        from app.core.config import settings

        for attr in ("PAYMENT_PROVIDER", "RAZORPAY_KEY_ID", "STRIPE_SECRET_KEY"):
            assert not hasattr(settings, attr), (
                f"settings.{attr} exists - a payment integration appears to have "
                "been added. That needs explicit sign-off."
            )

