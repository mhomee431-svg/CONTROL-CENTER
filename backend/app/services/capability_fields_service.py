"""Persistence for the capability-driven fields a shop submitted.

The rule this module enforces: the backend registry decides which keys exist,
and anything else is refused rather than stored. Without that, the JSON document
on `shops` would silently become an unvalidated blob that any client could fill
with arbitrary keys — the opposite of a capability model.

Only SHOP-LEVEL capability fields are handled. Product attributes are a separate
contract with their own endpoint and their own storage.
"""

from app.models import merchant_category
from app.models.product_attributes import product_attributes_for
from app.services.capability_field_specs import (
    allowed_capability_field_keys,
    validate_capability_fields,
)


def sanitise_capability_fields(
    category_code: str,
    business_type: str | None,
    submitted: dict | None,
) -> tuple[dict, list[str]]:
    """Split a submission into `{stored, rejected_keys}`.

    Rejecting rather than filtering silently matters: the caller can tell the
    shopkeeper which field was not accepted instead of dropping it and looking
    like a save bug.
    """
    if not submitted:
        return {}, []

    allowed = allowed_capability_field_keys(category_code, business_type)
    stored: dict = {}
    rejected: list[str] = []

    for key, value in submitted.items():
        text = str(value).strip()
        if key not in allowed:
            rejected.append(key)
            continue
        # A blank is "not provided", which must be distinguishable from
        # explicitly-empty, so blanks are dropped rather than written.
        if text:
            stored[key] = text

    return stored, rejected


def has_product_form(category_code: str, business_type: str | None) -> bool:
    """Whether this category has a product form at all.

    Two independent answers must agree: the capability must include
    PRODUCT_CATALOG, and the registry must declare attributes. A category with
    one but not the other would render a form that cannot be saved, or save a
    form nobody can fill.
    """
    resolved = merchant_category.capabilities_for_category(
        category_code, business_type
    )
    if resolved is None:
        return False
    capabilities = resolved.get("capabilities", ())
    return (
        merchant_category.CategoryCapability.PRODUCT_CATALOG.value in capabilities
        and bool(product_attributes_for(category_code))
    )


__all__ = [
    "sanitise_capability_fields",
    "has_product_form",
    "validate_capability_fields",
]