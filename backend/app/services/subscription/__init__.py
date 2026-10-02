"""Phase 28 — Subscription & monetization platform package.

    entitlements          ← configurable plan rules (single source of truth)
    subscription_service  ← lifecycle + payment orchestration (module)
"""

from app.services.subscription.entitlements import (  # noqa: F401
    ENTITLEMENT_CATALOG,
    FREE_TIER_ENTITLEMENTS,
    GRACE_PERIOD_DAYS,
    PLAN_TEMPLATES,
    EntitlementDenied,
    derive_shop_capabilities,
    effective_status,
    enforce_feature,
    enforce_limit,
    get_plan_template,
    merge_entitlements,
    resolve_entitlements,
    resolve_shop_entitlements,
    seed_plan_templates,
)

__all__ = [
    "ENTITLEMENT_CATALOG",
    "FREE_TIER_ENTITLEMENTS",
    "GRACE_PERIOD_DAYS",
    "PLAN_TEMPLATES",
    "EntitlementDenied",
    "derive_shop_capabilities",
    "effective_status",
    "enforce_feature",
    "enforce_limit",
    "get_plan_template",
    "merge_entitlements",
    "resolve_entitlements",
    "resolve_shop_entitlements",
    "seed_plan_templates",
]
