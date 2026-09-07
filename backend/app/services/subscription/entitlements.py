"""Phase 28 — Configurable plan entitlements (single source of truth).

Every monetization rule lives HERE and only here. Services, routes and tests
consume resolved entitlement dicts — none of them hardcode plan rules.

Entitlement keys (all optional per plan; missing → free-tier fallback):

    max_products         int|None   product/listing cap (None = unlimited)
    max_active_offers    int|None   concurrent offer cap  (None = unlimited)
    listing_features     list[str]  listing capabilities (BASIC, MEDIA, VARIANTS, BULK_IMPORT)
    analytics            bool       basic analytics dashboard
    advanced_analytics   bool       advanced/deep analytics suite
    offers               bool       may create offers at all
    pos_support          bool       POS integrations allowed
    featured_listing     bool       shop/product may be featured
    support_level        str        COMMUNITY | EMAIL | PRIORITY

Plan templates (Basic / Pro / Premium) are data, seeded into
``subscription_plans`` via :func:`seed_plan_templates`; operators can then
tune prices/entitlements in the DB (``features_json``) without code changes —
resolution always re-reads the row.
"""

from __future__ import annotations

from typing import Any, Optional

from sqlalchemy.orm import Session

from app.core.exceptions import AppError
from app.models.subscription import BillingCycle, Subscription, SubscriptionPlan, SubscriptionStatus

# ── Entitlement catalog ──────────────────────────────────────────────────────
ENTITLEMENT_CATALOG: dict[str, dict[str, Any]] = {
    "max_products": {"type": "limit", "description": "Maximum active product listings (null = unlimited)"},
    "max_active_offers": {"type": "limit", "description": "Maximum concurrent offers (null = unlimited)"},
    "listing_features": {"type": "list", "description": "Listing capabilities", "values": ["BASIC", "MEDIA", "VARIANTS", "BULK_IMPORT"]},
    "analytics": {"type": "bool", "description": "Basic analytics dashboard"},
    "advanced_analytics": {"type": "bool", "description": "Advanced analytics suite"},
    "offers": {"type": "bool", "description": "May create and run offers"},
    "pos_support": {"type": "bool", "description": "POS integrations supported"},
    "featured_listing": {"type": "bool", "description": "Eligible for featured placement"},
    "support_level": {"type": "enum", "description": "Support tier", "values": ["COMMUNITY", "EMAIL", "PRIORITY"]},
}


# ── Free tier (no subscription / expired / canceled) ─────────────────────────
FREE_TIER_ENTITLEMENTS: dict[str, Any] = {
    "max_products": 10,
    "max_active_offers": 0,
    "listing_features": ["BASIC"],
    "analytics": False,
    "advanced_analytics": False,
    "offers": False,
    "pos_support": False,
    "featured_listing": False,
    "support_level": "COMMUNITY",
}

# ── Platform-level monetization knobs ────────────────────────────────────────
GRACE_PERIOD_DAYS = 3           # PAST_DUE window after period end before EXPIRED
GRACE_ENTITLEMENTS_FULL = True  # features remain available during grace


# ── Plan templates (data — never referenced by feature code directly) ────────
PLAN_TEMPLATES: dict[str, dict[str, Any]] = {
    "Basic": {
        "display_name": "Basic",
        "description": "Essentials to get your shop online.",
        "price_monthly": 199.0,
        "price_annual": 1999.0,
        "currency": "INR",
        "trial_days": 0,
        "sort_order": 1,
        "entitlements": {
            "max_products": 50,
            "max_active_offers": 1,
            "listing_features": ["BASIC", "MEDIA"],
            "analytics": True,
            "advanced_analytics": False,
            "offers": True,
            "pos_support": False,
            "featured_listing": False,
            "support_level": "COMMUNITY",
        },
    },
    "Pro": {
        "display_name": "Pro",
        "description": "For growing shops that need reach and insight.",
        "price_monthly": 499.0,
        "price_annual": 4999.0,
        "currency": "INR",
        "trial_days": 14,
        "sort_order": 2,
        "entitlements": {
            "max_products": 250,
            "max_active_offers": 5,
            "listing_features": ["BASIC", "MEDIA", "VARIANTS"],
            "analytics": True,
            "advanced_analytics": False,
            "offers": True,
            "pos_support": True,
            "featured_listing": True,
            "support_level": "EMAIL",
        },
    },
    "Premium": {
        "display_name": "Premium",
        "description": "Unlimited scale, full analytics and priority support.",
        "price_monthly": 999.0,
        "price_annual": 9999.0,
        "currency": "INR",
        "trial_days": 30,
        "sort_order": 3,
        "entitlements": {
            "max_products": None,
            "max_active_offers": None,
            "listing_features": ["BASIC", "MEDIA", "VARIANTS", "BULK_IMPORT"],
            "analytics": True,
            "advanced_analytics": True,
            "offers": True,
            "pos_support": True,
            "featured_listing": True,
            "support_level": "PRIORITY",
        },
    },
}


# ── Template helpers ─────────────────────────────────────────────────────────
def get_plan_template(name: str) -> Optional[dict]:
    """Case-insensitive template lookup; ``None`` for unknown plans."""
    for key, template in PLAN_TEMPLATES.items():
        if key.lower() == (name or "").strip().lower():
            return template
    return None


def seed_plan_templates(db: Session) -> list[SubscriptionPlan]:
    """Idempotently upsert the Basic/Pro/Premium plans into the database.

    Existing rows are updated with template pricing unless an operator
    overrode ``features_json`` manually.
    """
    plans: list[SubscriptionPlan] = []
    for name, tpl in PLAN_TEMPLATES.items():
        plan = db.query(SubscriptionPlan).filter(SubscriptionPlan.name == name).first()
        if plan is None:
            plan = SubscriptionPlan(name=name)
            db.add(plan)
        plan.description = tpl["description"]
        plan.price_monthly = tpl["price_monthly"]
        plan.price_annual = tpl["price_annual"]
        plan.currency = tpl["currency"]
        plan.billing_cycle = BillingCycle.MONTHLY
        plan.trial_days = tpl["trial_days"]
        plan.sort_order = tpl["sort_order"]
        plan.is_active = True
        if not plan.features_json:
            plan.features_json = dict(tpl["entitlements"])
        plans.append(plan)
    db.flush()
    return plans


# ── Resolution ───────────────────────────────────────────────────────────────
def merge_entitlements(base: dict, override: dict | None) -> dict:
    """Merge an override dict over *base*, dropping unknown keys."""
    merged = dict(base)
    for key, value in (override or {}).items():
        if key in ENTITLEMENT_CATALOG:
            merged[key] = value
    return merged


def resolve_entitlements(plan: SubscriptionPlan | None) -> dict:
    """Effective entitlements for a plan row.

    ``plan.features_json`` wins; the legacy ``max_products`` column is
    honoured when features_json omits it. Unknown keys are ignored so older
    rows stay forward-compatible.
    """
    merged = dict(FREE_TIER_ENTITLEMENTS)
    if plan is None:
        return merged
    overrides = dict(plan.features_json or {})
    if "max_products" not in overrides and plan.max_products is not None:
        overrides["max_products"] = plan.max_products
    return merge_entitlements(merged, overrides)


def entitlement_value(entitlements: dict, key: str) -> Any:
    if key not in ENTITLEMENT_CATALOG:
        raise KeyError(f"Unknown entitlement '{key}'")
    return entitlements.get(key)


def has_feature(entitlements: dict, key: str) -> bool:
    """Boolean-feature check (analytics, pos_support, ...)."""
    return bool(entitlements.get(key))


def within_limit(entitlements: dict, key: str, current_count: int) -> bool:
    """Limit check; ``None`` means unlimited."""
    limit = entitlements.get(key)
    return limit is None or current_count < int(limit)


def has_listing_feature(entitlements: dict, feature: str) -> bool:
    return feature in (entitlements.get("listing_features") or [])


# ── Shop-scoped status + enforcement ─────────────────────────────────────────
_PAID_STATUSES = {SubscriptionStatus.ACTIVE, SubscriptionStatus.TRIALING}


def effective_status(subscription: Subscription | None, now=None) -> str:
    """Lazily computed lifecycle status (no cron required).

    ACTIVE past its period end → PAST_DUE (grace); PAST_DUE past the grace
    window → EXPIRED. Other statuses pass through unchanged.
    """
    from datetime import datetime, timedelta, timezone

    if subscription is None:
        return SubscriptionStatus.EXPIRED.value
    now = now or datetime.now(timezone.utc)

    def _aware(dt):
        if dt is None:
            return None
        return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)

    status = subscription.status
    end = _aware(subscription.current_period_end)
    if status == SubscriptionStatus.ACTIVE and end is not None and now > end:
        return SubscriptionStatus.PAST_DUE.value
    if status == SubscriptionStatus.PAST_DUE and end is not None:
        if now > end + timedelta(days=GRACE_PERIOD_DAYS):
            return SubscriptionStatus.EXPIRED.value
        return SubscriptionStatus.PAST_DUE.value
    return status.value


def resolve_shop_entitlements(db: Session, shop) -> dict:
    """Resolve the governing subscription + entitlements for a shop.

    Resolution ladder:
      * No subscription rows at all → ``UNSUBSCRIBED`` / grandfathered: the
        shop predates monetization (or simply never subscribed) and keeps
        full legacy behaviour — enforcement helpers skip it.
      * Live subscription (ACTIVE / TRIALING / PAST_DUE / INCOMPLETE) →
        governed by the plan; PAST_DUE keeps paid features during grace,
        INCOMPLETE grants nothing yet.
      * Latest row terminal (CANCELED / EXPIRED) → free tier entitlements.

    Returns::

        {"status": str, "in_grace": bool, "is_paid": bool,
         "plan_name": str|None, "subscription_id": int|None,
         "grandfathered": bool, "entitlements": {...}}
    """
    latest = (
        db.query(Subscription)
        .filter(Subscription.shop_id == shop.id)
        .order_by(Subscription.id.desc())
        .first()
    )

    if latest is None:
        return {
            "status": "UNSUBSCRIBED",
            "in_grace": False,
            "is_paid": False,
            "plan_name": None,
            "subscription_id": None,
            "grandfathered": True,
            "entitlements": {},
        }

    status = effective_status(latest)
    if (
        latest.status in (SubscriptionStatus.CANCELED, SubscriptionStatus.EXPIRED)
        or status in (SubscriptionStatus.EXPIRED.value, SubscriptionStatus.INCOMPLETE.value)
    ):
        # Terminal / never-activated subscriptions grant only the free tier.
        return {
            "status": status if latest.status not in (
                SubscriptionStatus.CANCELED,) else SubscriptionStatus.CANCELED.value,
            "in_grace": False,
            "is_paid": False,
            "plan_name": latest.plan.name if latest.plan else None,
            "subscription_id": latest.id,
            "grandfathered": False,
            "entitlements": dict(FREE_TIER_ENTITLEMENTS),
        }

    in_grace = status == SubscriptionStatus.PAST_DUE.value
    entitlements_resolved = resolve_entitlements(latest.plan)
    return {
        "status": status,
        "in_grace": in_grace,
        "is_paid": True,
        "plan_name": latest.plan.name if latest.plan else None,
        "subscription_id": latest.id,
        "grandfathered": False,
        "entitlements": entitlements_resolved,
    }


class EntitlementDenied(AppError):
    """Raised when a shop attempts a feature its plan does not grant."""

    def __init__(self, message: str, error_code: str = "ENTITLEMENT_DENIED", data: dict | None = None):
        super().__init__(message, error_code=error_code, status_code=403, data=data)


def enforce_feature(resolved: dict, key: str) -> None:
    """Boolean-gate a shopkeeper capability on the resolved entitlements."""
    if resolved.get("grandfathered"):
        return  # shop never entered the subscription system — legacy behaviour
    if resolved["status"] == SubscriptionStatus.EXPIRED.value:
        raise EntitlementDenied(
            "Your subscription has expired. Renew to restore paid features.",
            error_code="SUBSCRIPTION_EXPIRED",
        )
    if not has_feature(resolved["entitlements"], key):
        raise EntitlementDenied(
            f"Your current plan does not include '{key}'. Upgrade to unlock this feature."
        )


def enforce_limit(resolved: dict, key: str, current_count: int) -> None:
    """Limit-gate a shopkeeper capability on the resolved entitlements."""
    if resolved.get("grandfathered"):
        return  # shop never entered the subscription system — legacy behaviour
    if not within_limit(resolved["entitlements"], key, current_count):
        limit = resolved["entitlements"].get(key)
        raise AppError(
            f"Plan limit reached for {key} (limit: {limit}). Upgrade your plan to add more.",
            error_code="PLAN_LIMIT_REACHED",
            status_code=403,
            data={"entitlement": key, "limit": limit, "current": current_count},
        )


