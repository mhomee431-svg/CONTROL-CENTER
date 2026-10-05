"""Writing the category attributes the product-attributes endpoint advertises.

`GET /categories/{code}/product-attributes` tells a client which fields this
category's products actually carry. Until this module existed there was nowhere
to PUT them: the create/update schemas had no attribute field at all, so the
contract was readable but not writable.

Every decision here follows from one rule — the BACKEND owns the taxonomy, and a
value the database cannot store must never be accepted quietly:

  * A key the category does not declare is REJECTED, not stored. Accepting it
    would let a client invent a field and the shop would believe it was saved.
  * A catalog-backed field (category, subcategory) is REJECTED here and must
    arrive as an id. Accepting a typed name would create a second, unresolvable
    spelling of a row that already has an id.
  * A field that already owns a real column or request field is REJECTED here
    rather than duplicated into the attribute table, so there is exactly one
    place to look for it.
  * A field the spec types as an identifier is written to `product_identifiers`
    with that type. An MPN filed as loose text could never be found again by
    the catalog search that looks identifiers up by (type, value).
  * Everything else is written to the `product_attributes` /
    `product_attribute_values` pair the catalog already models.

Nothing here auto-creates catalog rows. A shopkeeper typing a brand the catalog
has never heard of gets told so, rather than a duplicate row that later splits
in two ("Brass" and "brass ").
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from sqlalchemy.orm import Session

from app.models.product import (
    ProductAttribute,
    ProductAttributeValue,
    ProductIdentifier,
    ProductMaster,
)
from app.models.product_attributes import product_attributes_for

# Storage limits are the schema's, not ours: `product_attributes.name` is
# VARCHAR(100) and `product_attribute_values.value` is VARCHAR(255). Checking
# here turns a 500 from the database into a message the shopkeeper can act on.
_MAX_NAME = 100
_MAX_VALUE = 255

# Keys that already have a home on ProductMaster / ShopProduct / Inventory or in
# the create-update payload. Sending them inside `attributes` would leave two
# possible sources for one value, so each is refused with a pointer to the field
# that actually owns it.
_COLUMN_ROUTED: dict[str, str] = {
    "name": "Send the product name as `name`",
    "description": "Send the description as `description`",
    "brand": "Send the brand as `brand_name`",
    "base_unit": "Send the unit as `unit`",
    "price": "Send the price as `price`",
    "mrp": "Send the MRP as `mrp`",
    "quantity": "Send the stock as `quantity`",
    "availability": "Send availability as `is_available`",
    "image": "Attach the image with `image_key`",
    "barcode": "Send the barcode as `barcode` (add `barcode_type` when the "
               "category types it)",
}

# Catalog-backed keys are refused with a message that explains the id contract.
# The spec marks these `catalog_backed` precisely because typing a name creates
# a value nothing can resolve back to a row.
_CATALOG_KEYS: dict[str, str] = {
    "category": "category_id",
    "subcategory": "subcategory_id",
}

# `product_type` is marked catalog-backed, but the schema carries no
# `product_type_id` column — there is no id to send either. Saying so is the
# honest answer; the alternative is inventing a destination, which is the exact
# failure this module exists to prevent.
_NO_DESTINATION = (
    "This field is category-specific but the catalogue has no column to store "
    "it in yet, so it cannot be saved"
)


@dataclass
class AttributeWritePlan:
    """Where each submitted attribute is meant to land."""

    #: (identifier_type, value) pairs for `product_identifiers`.
    identifiers: list[tuple[str, str]] = field(default_factory=list)

    #: attribute name → value, for the product_attributes EAV pair.
    attributes: dict[str, str] = field(default_factory=dict)

    #: key → why it was refused, so the client can show it against the input.
    rejected: dict[str, str] = field(default_factory=dict)

    @property
    def ok(self) -> bool:
        return not self.rejected


def _coerce(raw: Any, spec: Any) -> tuple[str | None, str]:
    """Normalise one submitted value.

    Returns `(value, error)`. Exactly one is meaningful: a non-empty error means
    the value is unusable. Returning the message as if it were the value is the
    bug this shape prevents — the caller would then store "Material is too long"
    as the shopkeeper's material.
    """
    if isinstance(raw, bool):
        return None, f"{spec.label} must be filled in correctly"
    if isinstance(raw, (int, float)):
        value = str(raw)
    elif isinstance(raw, str):
        value = raw.strip()
    else:
        return None, f"{spec.label} must be filled in correctly"
    if not value:
        return None, f"{spec.label} must be filled in correctly"

    kind = spec.kind.value if hasattr(spec.kind, "value") else str(spec.kind)
    if kind == "NUMBER":
        try:
            float(value)
        except ValueError:
            return None, f"{spec.label} must be a number"
    if kind == "CHOICE" and spec.choices and value not in spec.choices:
        return None, f"{spec.label} must be one of: {', '.join(spec.choices)}"
    if len(value) > _MAX_VALUE:
        # Checked here because `product_attribute_values.value` is VARCHAR(255);
        # left to the column this is a 500 rather than a message.
        return None, f"{spec.label} is too long (max {_MAX_VALUE} characters)"
    return value, ""


def plan_attribute_write(
    category_code: str, raw: dict[str, Any] | None
) -> AttributeWritePlan:
    """Decide where every submitted attribute belongs, refusing what cannot land.

    An unknown or unroutable key lands in [AttributeWritePlan.rejected] instead
    of raising, so the caller can report every problem at once instead of making
    the shopkeeper resubmit to discover the next one.
    """
    plan = AttributeWritePlan()
    if not raw:
        return plan

    code = str(category_code or "").strip().upper()
    specs = {s.key.value: s for s in product_attributes_for(code)} if code else {}

    for key, raw_value in raw.items():
        name = str(key or "").strip()
        if not name:
            continue
        spec = specs.get(name)
        if spec is None:
            plan.rejected[name] = "This field is not part of your category"
            continue
        if spec.catalog_backed:
            column = _CATALOG_KEYS.get(name)
            plan.rejected[name] = (
                f"Send {column} instead of a name" if column else _NO_DESTINATION
            )
            continue
        routed = _COLUMN_ROUTED.get(name)
        if routed is not None:
            plan.rejected[name] = routed
            continue

        value, error = _coerce(raw_value, spec)
        if error:
            plan.rejected[name] = error
            continue

        if spec.identifier_type:
            plan.identifiers.append((spec.identifier_type, value))
        else:
            plan.attributes[name] = value

    return plan


def _find_or_create_attribute(
    db: Session, master: ProductMaster, name: str
) -> ProductAttribute:
    existing = (
        db.query(ProductAttribute)
        .filter(
            ProductAttribute.product_master_id == master.id,
            ProductAttribute.name == name,
        )
        .first()
    )
    if existing is not None:
        return existing
    created = ProductAttribute(
        product_master_id=master.id,
        name=name,
        is_variant_defining=False,
        sort_order=0,
    )
    db.add(created)
    db.flush()
    return created


def persist_attribute_values(
    db: Session, master: ProductMaster, plan: AttributeWritePlan
) -> None:
    """Write a plan onto a product master.

    Existing values for a name are REPLACED rather than appended to: resubmitting
    a corrected "Material: brass" must not leave "steel" behind as a second value
    the catalog would then report as if both were true.
    """
    for name, value in plan.attributes.items():
        attribute = _find_or_create_attribute(db, master, name[:_MAX_NAME])
        for stale in (
            db.query(ProductAttributeValue)
            .filter(ProductAttributeValue.attribute_id == attribute.id)
            .all()
        ):
            db.delete(stale)
        db.add(
            ProductAttributeValue(
                attribute_id=attribute.id,
                value=value,
                sort_order=0,
            )
        )

    for id_type, value in plan.identifiers:
        already = (
            db.query(ProductIdentifier)
            .filter(
                ProductIdentifier.product_master_id == master.id,
                ProductIdentifier.identifier_type == id_type,
                ProductIdentifier.identifier_value == value,
            )
            .first()
        )
        if already is not None:
            continue
        db.add(
            ProductIdentifier(
                product_master_id=master.id,
                identifier_type=id_type,
                identifier_value=value,
                # Not primary: the barcode path already claims that role, and a
                # catalogue scan must keep resolving to it.
                is_primary=False,
                is_active=True,
            )
        )

    db.flush()
