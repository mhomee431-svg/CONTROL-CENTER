"""NOTIFICATION SAFETY — server-side deep-link validation.

The composer validates a deep link in the browser so an operator gets instant
feedback, but that check is *advisory only*: a client can be bypassed, replayed
or simply lie. This module is the authoritative gate. Every notification send
that carries a `deep_link` must pass through :func:`validate_notification_payload`
before a campaign row is ever written.

It enforces the exact three-part contract from the safety spec:

  1. notification type  → must be a supported, known notification type
  2. entity ID          → must match the identifier shape the type requires
  3. supported route    → the resulting path must map to a registered route

Nothing here trusts the caller. An explicit `deep_link` supplied in the request
is re-validated from scratch: external hosts, protocol-relative URLs
(`//evil.com`), scheme-bearing URLs (`javascript:`, `https:`), path traversal and
unregistered routes are all rejected outright.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

# --- Supported notification types ------------------------------------------
#
# This is the server's authoritative allow-list. It mirrors the client registry
# (`src/core/notifications/deepLink.ts`) so the two never drift into a state
# where the console offers a type the API would reject.

NOTIFICATION_TYPES: frozenset[str] = frozenset(
    {
        "ADMIN_BROADCAST",
        "PROMOTION",
        "SYSTEM_MESSAGE",
        "ORDER_UPDATE",
        "PAYMENT_UPDATE",
        "OFFER_ALERT",
        "PRODUCT_ALERT",
        "SHOP_UPDATE",
        "VERIFICATION_UPDATE",
        "SUPPORT_UPDATE",
        "INVENTORY_ALERT",
    }
)

# The entity-id shape a notification type expects.
#   none     → the type must NOT carry an entity id
#   numeric  → a positive integer surrogate key
#   string   → a bounded, safe opaque identifier (slug / code / UUID-ish)
#   optional → either a valid id or no id at all
ENTITY_KIND: dict[str, str] = {
    "ADMIN_BROADCAST": "none",
    "PROMOTION": "optional",
    "SYSTEM_MESSAGE": "none",
    "ORDER_UPDATE": "none",
    "PAYMENT_UPDATE": "none",
    "OFFER_ALERT": "numeric",
    "PRODUCT_ALERT": "numeric",
    "SHOP_UPDATE": "numeric",
    "VERIFICATION_UPDATE": "numeric",
    "SUPPORT_UPDATE": "numeric",
    "INVENTORY_ALERT": "numeric",
}

# Route prefix → path builder for the types that carry a destination. A type
# absent from this map has no client-renderable route and must not carry a link.
_ROUTE_BUILDERS: dict[str, str] = {
    "PAYMENT_UPDATE": "/subscriptions",
    "OFFER_ALERT": "/offers/{id}",
    "PRODUCT_ALERT": "/products/{id}",
    "SHOP_UPDATE": "/businesses/{id}",
    "VERIFICATION_UPDATE": "/verification/{id}",
    "SUPPORT_UPDATE": "/support/{id}",
    "INVENTORY_ALERT": "/inventory/{id}",
}

# Every route prefix the admin console can render. A deep link is only
# "supported" when its pathname equals or is nested under one of these.
SUPPORTED_ROUTE_PREFIXES: tuple[str, ...] = (
    "/dashboard",
    "/customers",
    "/shopkeepers",
    "/businesses",
    "/verification",
    "/products",
    "/categories",
    "/brands",
    "/inventory",
    "/pricing",
    "/offers",
    "/subscriptions",
    "/search",
    "/content",
    "/locations",
    "/imports",
    "/pos",
    "/notifications",
    "/support",
    "/audit",
    "/analytics",
    "/system/health",
    "/system/jobs",
    "/system/flags",
    "/system/settings",
    "/system/live-operations",
    "/admin-users",
    "/settings",
)

# Audience values the API actually honours.
SUPPORTED_AUDIENCES: frozenset[str] = frozenset({"all", "customer", "shopkeeper"})

_NUMERIC_ID_RE = re.compile(r"^[1-9]\d{0,17}$")
_SAFE_STRING_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
_SCHEME_RE = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")


@dataclass(frozen=True)
class ValidationResult:
    """Outcome of a validation attempt.

    `path` is the normalised, root-relative admin path when `valid` is true and
    the type carries a destination; otherwise it is ``None``.
    """

    valid: bool
    path: str | None = None
    code: str | None = None
    message: str | None = None


def is_notification_type(value: str | None) -> bool:
    return bool(value) and value in NOTIFICATION_TYPES


def is_supported_route(pathname: str) -> bool:
    if not pathname or not pathname.startswith("/"):
        return False
    if ".." in pathname or re.search(r"%2e%2e", pathname, re.IGNORECASE):
        return False
    return any(
        pathname == prefix or pathname.startswith(f"{prefix}/")
        for prefix in SUPPORTED_ROUTE_PREFIXES
    )


def validate_entity_id(notification_type: str, entity_id: str | None) -> ValidationResult:
    """Validate an entity id against the shape its type requires."""
    kind = ENTITY_KIND.get(notification_type)
    if kind is None:
        return ValidationResult(
            valid=False,
            code="UNKNOWN_NOTIFICATION_TYPE",
            message=f"Unsupported notification type: {notification_type}",
        )

    raw = (entity_id or "").strip()

    if kind == "none":
        if raw:
            return ValidationResult(
                valid=False,
                code="ENTITY_NOT_ALLOWED",
                message=f"{notification_type} notifications do not accept an entity ID.",
            )
        return ValidationResult(valid=True)

    if not raw:
        if kind == "optional":
            return ValidationResult(valid=True)
        return ValidationResult(
            valid=False,
            code="ENTITY_REQUIRED",
            message=f"{notification_type} notifications require an entity ID.",
        )

    if kind == "numeric":
        if not _NUMERIC_ID_RE.match(raw):
            return ValidationResult(
                valid=False,
                code="INVALID_NUMERIC_ENTITY",
                message="Entity ID must be a positive numeric identifier.",
            )
        return ValidationResult(valid=True, path=raw)

    if kind == "string":
        if not _SAFE_STRING_ID_RE.match(raw):
            return ValidationResult(
                valid=False,
                code="INVALID_STRING_ENTITY",
                message="Entity ID may only contain letters, numbers, hyphens and underscores (max 64 chars).",
            )
        return ValidationResult(valid=True, path=raw)

    # optional: accept whichever safe shape was supplied.
    if not _NUMERIC_ID_RE.match(raw) and not _SAFE_STRING_ID_RE.match(raw):
        return ValidationResult(
            valid=False,
            code="INVALID_STRING_ENTITY",
            message="Entity ID is not a valid identifier.",
        )
    return ValidationResult(valid=True, path=raw)


def validate_explicit_url(url: str | None) -> ValidationResult:
    """Validate a fully-formed URL supplied by a caller.

    Only root-relative admin paths are ever accepted. Everything else — external
    hosts, protocol-relative URLs, scheme-bearing URLs, traversal — is rejected.
    """
    value = (url or "").strip()
    if not value:
        return ValidationResult(valid=True)

    if _SCHEME_RE.match(value):
        return ValidationResult(
            valid=False,
            code="EXTERNAL_URL_BLOCKED",
            message="External or scheme-bearing URLs are not permitted in notifications.",
        )
    if value.startswith("//"):
        return ValidationResult(
            valid=False,
            code="PROTOCOL_RELATIVE_BLOCKED",
            message="Protocol-relative URLs are not permitted.",
        )
    if not value.startswith("/"):
        return ValidationResult(
            valid=False,
            code="MALFORMED_URL",
            message='Deep links must be root-relative admin paths starting with "/".',
        )
    if ".." in value or re.search(r"%2e%2e", value, re.IGNORECASE):
        return ValidationResult(
            valid=False,
            code="TRAVERSAL_BLOCKED",
            message="Path traversal is not permitted.",
        )

    pathname = re.split(r"[?#]", value, maxsplit=1)[0]
    if not is_supported_route(pathname):
        return ValidationResult(
            valid=False,
            code="ROUTE_NOT_SUPPORTED",
            message=f'Route "{pathname}" is not a supported admin route.',
        )
    return ValidationResult(valid=True, path=value)


def build_deep_link(notification_type: str, entity_id: str | None) -> str | None:
    """Build the canonical deep link for a type + entity id, or ``None``."""
    template = _ROUTE_BUILDERS.get(notification_type)
    if template is None:
        return None
    entity = validate_entity_id(notification_type, entity_id)
    if not entity.valid or not entity.path:
        return None
    return template.format(id=entity.path) if "{id}" in template else template


def resolve_deep_link(
    notification_type: str, entity_id: str | None, deep_link: str | None
) -> ValidationResult:
    """Resolve and validate the deep link for a notification payload.

    An explicit `deep_link` supplied by the caller is validated directly and is
    never trusted. When absent, a link is derived from the type + entity id.
    """
    if deep_link is not None and deep_link.strip() != "":
        return validate_explicit_url(deep_link)

    entity = validate_entity_id(notification_type, entity_id)
    if not entity.valid:
        return entity

    template = _ROUTE_BUILDERS.get(notification_type)
    if template is None:
        # A type with no destination is valid and simply carries no link.
        return ValidationResult(valid=True)

    if not entity.path:
        return ValidationResult(
            valid=False,
            code="ENTITY_REQUIRED",
            message=f"{notification_type} notifications require an entity ID to build a route.",
        )

    path = template.format(id=entity.path) if "{id}" in template else template
    if not is_supported_route(path):
        return ValidationResult(
            valid=False,
            code="ROUTE_NOT_SUPPORTED",
            message=f'Route "{path}" is not a supported admin route.',
        )
    return ValidationResult(valid=True, path=path)


@dataclass(frozen=True)
class NotificationPayloadValidation:
    valid: bool
    notification_type: str
    audience: str
    entity_id: str | None
    deep_link: str | None
    code: str | None = None
    message: str | None = None


def validate_notification_payload(
    notification_type: str,
    audience: str,
    entity_id: str | None = None,
    deep_link: str | None = None,
) -> NotificationPayloadValidation:
    """The single entry point every notification send must pass through.

    Returns a :class:`NotificationPayloadValidation`; callers must refuse the
    request when ``valid`` is false.
    """
    if not is_notification_type(notification_type):
        return NotificationPayloadValidation(
            valid=False,
            notification_type=notification_type,
            audience=audience,
            entity_id=entity_id,
            deep_link=deep_link,
            code="UNKNOWN_NOTIFICATION_TYPE",
            message=f"Unsupported notification type: {notification_type}",
        )

    if audience not in SUPPORTED_AUDIENCES:
        return NotificationPayloadValidation(
            valid=False,
            notification_type=notification_type,
            audience=audience,
            entity_id=entity_id,
            deep_link=deep_link,
            code="UNSUPPORTED_AUDIENCE",
            message=f"Unsupported audience: {audience}",
        )

    link = resolve_deep_link(notification_type, entity_id, deep_link)
    if not link.valid:
        return NotificationPayloadValidation(
            valid=False,
            notification_type=notification_type,
            audience=audience,
            entity_id=entity_id,
            deep_link=deep_link,
            code=link.code,
            message=link.message,
        )

    return NotificationPayloadValidation(
        valid=True,
        notification_type=notification_type,
        audience=audience,
        entity_id=entity_id,
        deep_link=link.path,
    )
