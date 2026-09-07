"""Phase 26 — Admin-specific permission system.

Extends the global RBAC with a fine-grained admin module catalog.

Admin SUB-ROLES are regular ``Role`` rows whose name starts with ``admin``:
    - ``admin``            → full platform control (SUPER_ADMIN semantics)
    - ``admin_support``    → complaints + users(read) + notes
    - ``admin_moderator``  → shop verification + product approval
    - ``admin_analyst``    → dashboard / reports / analytics (read-only)

Authorization model:
    - The base ``admin`` role carries the implicit wildcard ("*", "*") —
      it can perform every operation in :data:`ADMIN_MODULE_PERMISSIONS`.
    - Sub-roles carry explicit catalogs; they can never exceed them.
    - Every critical operation still requires an explicit
      ``(resource, action)`` check via :func:`has_admin_permission`.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:  # pragma: no cover - typing only
    from app.models.user import User

# ── Full admin module catalog ────────────────────────────────────────────
#: (resource, action) pairs covering every Phase 26 admin module.
ADMIN_MODULE_PERMISSIONS: list[tuple[str, str]] = [
    # Dashboard & analytics
    ("dashboard", "read"),
    ("analytics", "read"),
    # Customers
    ("customer", "read"),
    ("customer", "update"),   # suspend / ban / activate
    # Shopkeepers
    ("shopkeeper", "read"),
    ("shopkeeper", "update"),
    # Shops
    ("shop", "read"),
    ("shop", "verify"),
    ("shop", "reject"),
    ("shop", "suspend"),
    ("shop", "reactivate"),
    ("shop", "delete"),
    # Products
    ("product", "read"),
    ("product", "review"),
    ("product", "approve"),
    ("product", "reject"),
    ("product", "update"),
    ("product", "archive"),
    # Catalog taxonomy
    ("category", "create"),
    ("category", "read"),
    ("category", "update"),
    ("category", "delete"),
    ("brand", "create"),
    ("brand", "read"),
    ("brand", "update"),
    ("brand", "delete"),
    ("identifier", "read"),
    ("identifier", "delete"),
    # Inventory monitoring
    ("inventory", "read"),
    # Offers / subscriptions / payments
    ("offer", "read"),
    ("offer", "update"),
    ("subscription", "read"),
    ("subscription", "update"),
    ("payment", "read"),
    # Reports
    ("report", "read"),
    ("report", "generate"),
    # Complaints
    ("complaint", "read"),
    ("complaint", "update"),
    # Notifications
    ("notification", "read"),
    ("notification", "create"),
    # Platform configuration
    ("system_setting", "read"),
    ("system_setting", "update"),
    ("feature_flag", "read"),
    ("feature_flag", "update"),
    # Governance
    ("audit_log", "read"),
    ("admin_action", "read"),
    ("admin_note", "read"),
    ("admin_note", "create"),
    ("admin_note", "update"),
    ("admin_note", "delete"),
    # Merchant Onboarding
    ("merchant_onboarding", "read"),
    ("merchant_onboarding", "review"),
]

_ADMIN_KEYS = {f"{action}:{resource}" for resource, action in ADMIN_MODULE_PERMISSIONS}


def admin_permission_key(resource: str, action: str) -> str:
    """Canonical ``action:resource`` key."""
    return f"{action}:{resource}"


def full_admin_keys() -> set[str]:
    """Every admin permission key (the ``admin`` super role)."""
    return set(_ADMIN_KEYS)


# ── Sub-role catalogs (strict subsets) ───────────────────────────────────
ADMIN_SUBROLE_PERMISSIONS: dict[str, list[tuple[str, str]]] = {
    "admin_support": [
        ("dashboard", "read"),
        ("customer", "read"),
        ("shopkeeper", "read"),
        ("complaint", "read"),
        ("complaint", "update"),
        ("admin_note", "read"),
        ("admin_note", "create"),
        ("admin_note", "update"),
        ("notification", "read"),
        ("notification", "create"),
    ],
    "admin_moderator": [
        ("dashboard", "read"),
        ("shop", "read"),
        ("shop", "verify"),
        ("shop", "reject"),
        ("product", "read"),
        ("product", "review"),
        ("product", "approve"),
        ("product", "reject"),
        ("product", "archive"),
        ("admin_note", "read"),
        ("admin_note", "create"),
        ("audit_log", "read"),
        ("merchant_onboarding", "read"),
        ("merchant_onboarding", "review"),
    ],
    "admin_analyst": [
        ("dashboard", "read"),
        ("analytics", "read"),
        ("report", "read"),
        ("report", "generate"),
        ("customer", "read"),
        ("shop", "read"),
        ("product", "read"),
        ("inventory", "read"),
        ("subscription", "read"),
        ("payment", "read"),
    ],
}


def effective_admin_permissions(role_name: str | None) -> set[str]:
    """Resolve effective admin permission keys for a role name."""
    if role_name is None:
        return set()
    if role_name == "admin":
        return full_admin_keys()
    return {
        admin_permission_key(r, a)
        for r, a in ADMIN_SUBROLE_PERMISSIONS.get(role_name, [])
    }


def has_admin_permission(perms: set[str], resource: str, action: str) -> bool:
    """Check an effective-admin-permission key set."""
    return admin_permission_key(resource, action) in perms


def describe_admin_role(role_name: str | None) -> dict:
    """Human-readable summary of an admin role for API payloads."""
    if role_name is None:
        return {"name": None, "level": "none", "permissions": []}
    if role_name == "admin":
        return {
            "name": role_name,
            "level": "SUPER",
            "permissions": sorted(full_admin_keys()),
        }
    perms = effective_admin_permissions(role_name)
    return {
        "name": role_name,
        "level": "SUB" if perms else "none",
        "permissions": sorted(perms),
    }


def user_is_admin_family(user: "User") -> bool:
    """True when the user carries any admin-family role."""
    name = user.role.name if user.role is not None else None
    return name == "admin" or name in ADMIN_SUBROLE_PERMISSIONS