"""Model -> JSON serialisation.

The frontend renders raw field names from the TypeScript interfaces, so this
module is the single place that decides how a row is shaped on the wire. Doing
it here — rather than relying on ORM dicts — keeps datetime formatting and
nullable handling consistent across every router.
"""

from datetime import date, datetime
from typing import Any

from app.models import Shop, ShopInventory


def iso(value: Any) -> Any:
    """Datetimes become ISO-8601 strings; everything else passes through."""
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    return value


def to_dict(obj: Any, fields: list[str]) -> dict[str, Any]:
    """Project a model onto the named fields, formatting datetimes."""
    return {name: iso(getattr(obj, name, None)) for name in fields}


SHOP_FIELDS = [
    "id", "name", "owner_id", "category_id", "category", "subcategory", "business_type",
    "address", "locality", "city", "state", "pincode", "latitude", "longitude",
    "phone", "alt_phone", "email", "website",
    "logo_url", "description", "registration_number", "gst_number",
    "status", "verification_status", "verified_at", "verified_by", "rejection_reason",
    "operating_hours",
    "product_count", "inventory_count", "inventory_freshness", "last_inventory_update",
    "created_at", "updated_at",
]


def serialise_shop(shop: Shop) -> dict[str, Any]:
    payload = to_dict(shop, SHOP_FIELDS)
    payload["owner_name"] = shop.owner.name if shop.owner else None
    return payload


def serialise_inventory(row: ShopInventory) -> dict[str, Any]:
    payload = to_dict(
        row,
        [
            "id", "product_id", "product_name", "quantity", "price", "mrp",
            "stock_status", "freshness_status", "last_updated",
        ],
    )
    # The drill-down keys inventory rows by shop_product_id, not id.
    payload["shop_product_id"] = row.id
    payload["shop_name"] = row.shop.name if row.shop else None
    return payload
