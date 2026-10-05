"""Field length limits — the ONE place the maximum width of a text field lives.

Every limit here mirrors a real column width in ``app/models/product.py``. That
coupling is the whole point of this module:

  * ProductMaster.name            String(255)
  * ProductVariant.name           String(255)
  * ProductVariant.sku            String(100)
  * ShopProduct.sku               String(100)
  * ProductIdentifier.value       String(100)
  * Brand.name                    String(120)
  * Category.name                 String(100)

Without this, an over-long value reaches the database and PostgreSQL rejects it
with ``value too long for type character varying(255)`` — a 500, at the storage
layer, after the request has been accepted. The shopkeeper sees "something went
wrong" and cannot tell which value or how much to cut. Validating here turns
that into a 422 that names the field, the limit and the actual length.

The limits are also PUBLISHED through ``excel_import_service.import_schema()``
so the client mirrors them instead of hardcoding a second set that drifts.
"""

from typing import Any

#: Canonical field name -> maximum length, mirroring the column width.
FIELD_LIMITS: dict[str, int] = {
    "product_name": 255,
    "variant": 255,
    "sku": 100,
    "barcode": 100,
    "brand": 120,
    "category": 100,
    "subcategory": 100,
}

#: Longest a value may be before it is truncated on the way in.
MAX_PRODUCT_NAME = FIELD_LIMITS["product_name"]


def _display(value: Any) -> str:
    return str(value if value is not None else "").strip()


def text_length_error(field: str, value: Any) -> str | None:
    """A shopkeeper-facing message when ``value`` is too long for ``field``.

    Returns ``None`` when the value fits (or when the field has no recorded
    limit). The message names the field, the limit and what was actually sent,
    because "too long" alone leaves the shopkeeper counting characters.
    """
    limit = FIELD_LIMITS.get(field)
    if limit is None:
        return None
    actual = len(_display(value))
    if actual <= limit:
        return None
    return (
        f"{_label(field)} is {actual} characters; the maximum is {limit}. "
        "Shorten it before importing."
    )


def text_length_problems(values: dict[str, Any]) -> list[tuple[str, str]]:
    """Every ``(field, message)`` over-length pair, in limit order.

    A dict so callers can report all of them at once: fixing a spreadsheet means
    editing cells, and one error per round trip is one round trip per mistake.
    """
    problems: list[tuple[str, str]] = []
    for field in FIELD_LIMITS:
        message = text_length_error(field, values.get(field))
        if message is not None:
            problems.append((field, message))
    return problems


def _label(field: str) -> str:
    return {
        "product_name": "Product name",
        "variant": "Variant",
        "sku": "SKU",
        "barcode": "Barcode",
        "brand": "Brand",
        "category": "Category",
        "subcategory": "Subcategory",
    }.get(field, field.replace("_", " ").capitalize())


def enforce_text_lengths(values: dict[str, Any], *, context: str = "") -> None:
    """Raise a 422 ``ValidationError`` naming the first over-length field.

    For the request paths (manual create / update), where there is exactly one
    offending value worth reporting — unlike a spreadsheet, where the shopkeeper
    has to edit cells and benefits from hearing about all of them at once.
    """
    problems = text_length_problems(values)
    if not problems:
        return
    from app.core.exceptions import ValidationError

    field, message = problems[0]
    if context:
        message = f"{context}: {message}"
    raise ValidationError(message, data={"reason_code": "FIELD_TOO_LONG",
                                         "field": field})

