"""Phase 22 — Shopkeeper-specific permission system.

Defines the permission catalog for the Shopkeeper App and helpers to:
  - Ensure the ``shopkeeper`` role exists with the full catalog
  - Resolve a user's *effective* permissions for a specific shop
    (owner ⇒ full catalog, manager ⇒ intersection with granted subset,
    admin ⇒ full catalog)

Authorization is ASSOCIATION-DRIVEN: a shopkeeper may only manage shops
where an active ``ShopOwner`` or ``ShopManager`` row links them to the
shop. Role alone never grants access to a shop's resources.
"""

from __future__ import annotations

import json
import logging
from typing import TYPE_CHECKING

from app.models.role import Permission, Role

if TYPE_CHECKING:  # pragma: no cover - typing only
    from sqlalchemy.orm import Session

    from app.models.shop import ShopManager, ShopOwner
    from app.models.user import User

logger = logging.getLogger("app.core.shopkeeper_permissions")

# ── Shopkeeper role name ─────────────────────────────────────────────────
SHOPKEEPER_ROLE_NAME = "shopkeeper"

# ── Permission catalog (resource, action) pairs ──────────────────────────
#: Full catalog granted to shop OWNERS (and admins).
SHOPKEEPER_PERMISSIONS: list[tuple[str, str]] = [
    # Dashboard / overview
    ("dashboard", "read"),
    # Shop profile & settings
    ("shop", "read"),
    ("shop", "update"),
    ("shop", "create"),
    # Products
    ("product", "read"),
    ("product", "create"),
    ("product", "update"),
    ("product", "delete"),
    # Inventory
    ("inventory", "read"),
    ("inventory", "update"),
    # Offers
    ("offer", "read"),
]

#: Reduced catalog for shop MANAGERS — inventory & products, no settings.
SHOPKEEPER_MANAGER_PERMISSIONS: list[tuple[str, str]] = [
    ("dashboard", "read"),
    ("shop", "read"),
    ("product", "read"),
    ("product", "create"),
    ("product", "update"),
    ("inventory", "read"),
    ("inventory", "update"),
    ("offer", "read"),
]


def permission_key(resource: str, action: str) -> str:
    """Canonical ``action:resource`` key used on the wire."""
    return f"{action}:{resource}"


def ensure_shopkeeper_role(db: "Session") -> Role:
    """Create (idempotently) the ``shopkeeper`` role with its permissions."""
    role = db.query(Role).filter(Role.name == SHOPKEEPER_ROLE_NAME).first()
    if role is None:
        role = Role(name=SHOPKEEPER_ROLE_NAME, description="Shopkeeper app user")
        db.add(role)
        db.flush()

    for resource, action in SHOPKEEPER_PERMISSIONS:
        perm = (
            db.query(Permission)
            .filter(Permission.resource == resource, Permission.action == action)
            .first()
        )
        if perm is None:
            perm = Permission(
                name=f"{action}:{resource}",
                description=f"Can {action} {resource}",
                resource=resource,
                action=action,
            )
            db.add(perm)
            db.flush()
        if perm not in role.permissions:
            role.permissions.append(perm)

    db.flush()
    return role


def _manager_granted_keys(manager: "ShopManager") -> set[str] | None:
    """Parse a manager's granted-permission JSON into keys.

    ``None`` (or unparseable) means "no explicit restriction" → the full
    manager catalog applies. An explicit list restricts further.
    """
    raw = getattr(manager, "permissions", None)
    if not raw:
        return None
    try:
        entries = json.loads(raw)
    except (TypeError, ValueError):
        return None
    if not isinstance(entries, list):
        return None
    keys: set[str] = set()
    for entry in entries:
        if isinstance(entry, str) and ":" in entry:
            action, resource = entry.split(":", 1)
            keys.add(permission_key(resource.strip(), action.strip()))
    return keys


def effective_shop_permissions(
    role_name: str | None,
    is_owner: bool,
    manager: "ShopManager | None",
) -> set[str]:
    """Compute effective permission keys for a user's membership in a shop."""
    if role_name == "admin":
        return {permission_key(r, a) for r, a in SHOPKEEPER_PERMISSIONS}

    if is_owner:
        catalog = SHOPKEEPER_PERMISSIONS
    elif manager is not None:
        catalog = SHOPKEEPER_MANAGER_PERMISSIONS
    else:
        return set()

    keys = {permission_key(r, a) for r, a in catalog}

    # Managers may be additionally restricted by their granted JSON subset.
    if manager is not None and not is_owner:
        granted = _manager_granted_keys(manager)
        if granted is not None:
            keys &= granted
    return keys


def has_permission(perms: set[str], resource: str, action: str) -> bool:
    """Check an effective-permission key set."""
    return permission_key(resource, action) in perms


def describe_permissions(perms: set[str]) -> list[str]:
    """Sorted stable list for API payloads."""
    return sorted(perms)


def sync_owner_role(db: "Session", user: "User") -> None:
    """Ensure a user who owns at least one shop carries the shopkeeper role."""
    role = (
        db.query(Role).filter(Role.name == SHOPKEEPER_ROLE_NAME).first()
    )
    if role is not None and (user.role is None or user.role.name != SHOPKEEPER_ROLE_NAME):
        user.role_id = role.id
        db.flush()
