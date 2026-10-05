"""Product attributes a business category actually uses.

The spec is explicit that a category's fields vary but the UI stays identical,
that category-specific attributes must come from the backend rather than being
invented in Flutter, and that the same applies to product data: a pharmacy is not
an automotive parts shop, and a restaurant is not a stock ledger.

Every attribute below names a REAL destination in the schema — a column that
already exists, or a key of `product_variants.attributes_json`, which is the
schema's own sanctioned place for category-specific data. Nothing here invents a
field the database cannot store:

  * `product_masters`  — name, brand_id, category_id, subcategory_id,
                         base_unit, base_quantity, description
  * `product_variants` — sku, attributes_json (the extension point)
  * `shop_products`    — price, mrp, is_available, sku
  * `inventory`        — quantity

Pharmacy compliance columns (`prescription_required`, `regulatory_class`,
`requires_license_type`) are deliberately NOT exposed, even though they exist on
`product_masters`. The spec lists licence information, regulatory information
and medical product attributes as FUTURE fields, and instructs that regulatory
verification must not be implemented until the backend defines it.

A bare `String(30)` with `server_default="UNCLASSIFIED"`, no enum, no CHECK
constraint and no validation anywhere is scaffolding, not a requirement — there
is no defined set of valid values to offer a shopkeeper, so there is nothing to
build a field on. Exposing them would also be self-justifying: the only reason
those columns appeared "supported" is that this file was the first to look at
them.

The pharmacy's document requirement (drug licence) is a different thing and
stays: it is a pre-existing backend requirement, not an invented field.
"""

import enum


class ProductAttribute(str, enum.Enum):
    """A product attribute, named after where its value is stored."""

    # ── product_masters ──────────────────────────────────────────────────────
    NAME = "name"
    BRAND = "brand"
    CATEGORY = "category"
    SUBCATEGORY = "subcategory"
    # The catalog level ABOVE category — a beauty product type, a sports
    # equipment type. Catalog-backed wherever offered, because the catalog is
    # the only authority on which values exist.
    PRODUCT_TYPE = "product_type"
    DESCRIPTION = "description"
    BASE_UNIT = "base_unit"
    BASE_QUANTITY = "base_quantity"

    # ── product_variants ─────────────────────────────────────────────────────
    SKU = "sku"
    BARCODE = "barcode"
    VARIANT = "variant"
    # The schema's own extension point for category-specific values.
    EXTENSION_ATTRIBUTES = "extension_attributes"
    # Furniture & home care, each named because the spec names them separately
    # and they are separately useful: a shopkeeper filtering by material cannot
    # do it from one free-text box holding "oak, brown, 6 ft".
    #
    # All four land in `product_variants.attributes_json`, which is where the
    # schema already puts category-specific data.
    DIMENSIONS = "dimensions"
    MATERIAL = "material"
    COLOR = "colour"
    ASSEMBLY_SERVICE = "assembly_service"
    # Size / colour / material — reused across household, sports, hardware and
    # furniture rather than re-typed per category. Each is its own key because a
    # shopkeeper must be able to filter by one without the others: a single box
    # reading "large, blue, cotton" is data nobody can query.
    SIZE = "size"

    # Sports. Kept separate because the spec lists them separately, and the
    # values are genuinely different kinds of thing.
    SPORT_TYPE = "sport_type"
    MODEL = "model"
    EQUIPMENT_TYPE = "equipment_type"

    # Books.
    LANGUAGE = "language"
    PUBLICATION_DATE = "publication_date"

    # Automotive and hardware.
    PART_NUMBER = "part_number"
    TOOL_TYPE = "tool_type"
    SPECIFICATION = "specification"

    # Author / creator. Books, media and stationery all need it and none of
    # them can express it through an existing column, so it lands in
    # `product_variants.attributes_json` — the schema's sanctioned extension
    # point. Listed by the spec as "Author/Creator where applicable", so it is
    # optional: a stapler has no author.
    AUTHOR = "author"

    # OEM / OE reference number for an automotive part: the number the
    # manufacturer superseded, which is NOT the same as the part's own number
    # and is how a shop finds a replacement. The schema already models this as
    # `IdentifierType.MPN` in `product_identifiers`.
    OEM_REFERENCE_NUMBER = "oem_reference_number"

    # Vehicle MODEL, recorded as free text and nothing more.
    #
    # Deliberately NOT a compatibility rule: this records what the shopkeeper
    # types and implies nothing about what the part fits. The dangerous field —
    # the one that would encode "fits Maruti Swift" — is refused outright below.
    VEHICLE_MODEL = "vehicle_model"

    # Manufacturer, kept SEPARATE from Brand.
    #
    # The spec lists both, and in this trade they genuinely differ: "Bosch
    # QuietCast" is a brand line, while Bosch is who manufactured the disc. A
    # shop matching a customer against an OE catalogue searches by manufacturer,
    # so collapsing the two loses a lookup.
    #
    # Free text rather than a second catalog-backed field, because
    # `product_masters.brand_id` is a single column already spent on Brand —
    # a second catalog-backed field would promise a second destination the
    # schema does not have.
    MANUFACTURER = "manufacturer"

    # ── shop_products / inventory ────────────────────────────────────────────
    PRICE = "price"
    MRP = "mrp"
    AVAILABILITY = "availability"
    QUANTITY = "quantity"
    IMAGE = "image"

    # ── pharmacy compliance columns on product_masters ───────────────────────
    # DELIBERATELY ABSENT: `prescription_required`, `regulatory_class`,
    # `requires_license_type`, `is_restricted`.
    #
    # Those columns exist on `product_masters`, but have NO defined vocabulary:
    # `regulatory_class` is a bare String(30) defaulting to "UNCLASSIFIED", with
    # no enum, no CHECK constraint and no validation anywhere in the backend.
    # Scaffolding is not a requirement.
    #
    # The spec forbids implementing regulatory fields until the backend defines
    # them, and defining them is exactly what has not happened. So there is no
    # key here to reference — not even an unused one, because an unused key is
    # an invitation to wire one up later without asking the question again.
    #
    # Reintroduce these ONLY when real requirements exist: an enum or CHECK
    # constraint naming the legal classes, a schema, and a validation rule.


class ProductAttributeKind(str, enum.Enum):
    """How the value is captured. Decides the input, never the data model."""

    TEXT = "TEXT"
    MULTILINE = "MULTILINE"
    NUMBER = "NUMBER"
    CHOICE = "CHOICE"


class ProductAttributeSpec:
    """One attribute: where it is stored, and what the shopkeeper is asked."""

    def __init__(
        self,
        key: ProductAttribute,
        label: str,
        kind: ProductAttributeKind,
        *,
        required: bool = False,
        hint: str = "",
        choices: tuple[str, ...] = (),
        catalog_backed: bool = False,
        identifier_type: str = "",
    ) -> None:
        self.key = key
        self.label = label
        self.kind = kind
        self.required = required
        self.hint = hint
        self.choices = choices
        # True when the destination is a catalog row rather than a column of
        # free text: `category_id` and `subcategory_id` are foreign keys, so the
        # value has to be RESOLVED against `categories`, not typed. The flag
        # tells the client to offer the catalog instead of a text box, which is
        # the difference between a value the database can store and one it
        # silently drops.
        self.catalog_backed = catalog_backed
        # Which `IdentifierType` this value is stored as. The schema has a real
        # typed identifier table (`product_identifiers`:
        # `identifier_type` + `identifier_value`) with ISBN, EAN, ASIN, MPN and
        # friends. A bare barcode string loses that: an ISBN scanned off a book
        # and an EAN scanned off a shampoo are different identifiers, and the
        # schema already knows how to tell them apart.
        #
        # Empty means "not a typed identifier" — the value is just text.
        self.identifier_type = identifier_type

    def as_dict(self) -> dict:
        return {
            "key": self.key.value,
            "label": self.label,
            "kind": self.kind.value,
            "required": self.required,
            "hint": self.hint,
            "choices": list(self.choices),
            "catalog_backed": self.catalog_backed,
            "identifier_type": self.identifier_type,
        }


def _spec(key, label, kind, **kw) -> ProductAttributeSpec:
    return ProductAttributeSpec(key, label, kind, **kw)


TEXT = ProductAttributeKind.TEXT
MULTILINE = ProductAttributeKind.MULTILINE
NUMBER = ProductAttributeKind.NUMBER
CHOICE = ProductAttributeKind.CHOICE

class _Examples:
    """Per-category example values for the shared fields' hints.

    A hint is the one place the app shows a concrete value, so a shared hint
    leaks one trade's vocabulary into every other trade's form — a beauty
    product form asking for "Brake Pad" and a "Bosch" brand. The field names
    and types are genuinely common; the examples are not, so they are supplied
    per category instead.

    These are EXAMPLES ONLY, shown to make the field legible. They are never a
    closed list, and never a substitute for the catalog: the spec is explicit
    that final categories and subcategories come from backend catalog data.
    """

    __slots__ = ("name", "brand", "category", "variant")

    def __init__(self, name, brand, category, variant):
        self.name = name
        self.brand = brand
        self.category = category
        self.variant = variant


def _stocked_core(ex: _Examples) -> tuple[ProductAttributeSpec, ...]:
    """The fields every STOCKED category shares, hinted for that trade."""
    return (
        _spec(ProductAttribute.NAME, "Product name", TEXT, required=True,
              hint=ex.name),
        _spec(ProductAttribute.BRAND, "Brand", TEXT, hint=ex.brand),
        _spec(ProductAttribute.CATEGORY, "Category", TEXT, required=True,
              hint=ex.category, catalog_backed=True),
        _spec(ProductAttribute.SUBCATEGORY, "Subcategory", TEXT,
              catalog_backed=True),
        _spec(ProductAttribute.DESCRIPTION, "Description", MULTILINE),
        _spec(ProductAttribute.VARIANT, "Variant", TEXT, hint=ex.variant),
        _spec(ProductAttribute.PRICE, "Price", NUMBER, required=True),
        _spec(ProductAttribute.MRP, "MRP", NUMBER, hint="Where applicable"),
        _spec(ProductAttribute.AVAILABILITY, "Available", CHOICE,
              choices=("Yes", "No")),
        _spec(ProductAttribute.IMAGE, "Product image", TEXT, hint="Optional"),
    )


# Stock-keeping categories additionally track quantity and a scannable code.
_STOCKED_INVENTORY: tuple[ProductAttributeSpec, ...] = (
    _spec(ProductAttribute.BARCODE, "Barcode", TEXT,
          hint="EAN / UPC where available"),
    _spec(ProductAttribute.QUANTITY, "Quantity", NUMBER),
    _spec(ProductAttribute.BASE_UNIT, "Pack / unit", TEXT,
          hint="piece, pack, kg"),
)

# ── Per-category product attributes ───────────────────────────────────────────
# Only categories that sell STOCKED items appear here at all. A restaurant or a
# transport provider has no product form: the backend grants it neither
# PRODUCT_CATALOG nor INVENTORY, so there is nothing for this map to declare.
CATEGORY_PRODUCT_ATTRIBUTES: dict[str, tuple[ProductAttributeSpec, ...]] = {
    # Pharmacy adds nothing of its own yet, and that is deliberate: the spec
    # lists licence information, regulatory information and medical product
    # attributes as FUTURE fields, to be implemented only once the backend
    # defines the requirements. Until then a pharmacy looks like any other
    # stocked shop — the drug-licence DOCUMENT requirement is separate and
    # already handled by the onboarding requirements endpoint.
    "PHARMACY_HEALTHCARE": (
        *_stocked_core(_Examples("Panadol 650", "Panadol", "Analgesics", "10 tablets")),
        *_STOCKED_INVENTORY,
    ),
    # Beauty & personal care. The spec's possible product types (Hair Care, Skin
    # Care, Personal Care, Cosmetics, Grooming) are EXAMPLES ONLY — they are
    # illustrative, and the spec is explicit that the final taxonomy comes from
    # backend catalog data. So they are not a fixed `choices` list here: doing
    # that would freeze five illustrative words into an authoritative vocabulary
    # and contradict the very next line of the spec. What is real is the
    # STRUCTURE — a product type sits above category/subcategory in the catalog
    # (`categories.parent_id`), so it is catalog-backed, not free text.
    "BEAUTY_PERSONAL_CARE": (
        *_stocked_core(_Examples("Anti-Frizz Shampoo", "Mamaearth",
                                "Hair Care", "250 ml")),
        *_STOCKED_INVENTORY,
        _spec(ProductAttribute.PRODUCT_TYPE, "Product type", TEXT,
              hint="Hair Care, Skin Care, Personal Care… (examples only; "
                   "the list comes from the catalog)",
              catalog_backed=True),
    ),
        # Furniture & home care. Shares the common stocked block so it cannot drift
    # from it — the earlier hand-written copy here had no `catalog_backed` flags
    # and no per-category hints at all, which is exactly how bugs hide.
    #
    # Two spec rules shape what follows:
    #   * "Quantity where applicable" — so quantity IS offered. A furniture shop
    #     absolutely has stock (fifty identical chairs); the earlier version
    #     dropped quantity entirely on a "bulky goods" assumption, which is not
    #     the same as "where applicable". It stays optional and unrequired.
    #   * barcode stays off: a sofa genuinely has no scannable EAN, and the spec
    #     does not list it for this category.
    "FURNITURE_HOME_CARE": (
        *_stocked_core(_Examples("Three-seater sofa", "Nilkamal",
                                "Living Room", "Oak / 3-seater")),
        _spec(ProductAttribute.QUANTITY, "Quantity", NUMBER,
              hint="Where applicable — bulky items are often made to order"),
        _spec(ProductAttribute.DIMENSIONS, "Dimensions", TEXT,
              hint="Where the backend supports it"),
        _spec(ProductAttribute.MATERIAL, "Material", TEXT,
              hint="Where the backend supports it"),
        _spec(ProductAttribute.COLOR, "Colour", TEXT,
              hint="Where the backend supports it"),
        _spec(ProductAttribute.ASSEMBLY_SERVICE, "Assembly or service",
              MULTILINE,
              hint="Where the backend supports it"),
    ),
    "HOUSEHOLD_GOODS": (
        *_stocked_core(_Examples("Steel Casserole", "Pigeon", "Cookware", "3 litres")),
        *_STOCKED_INVENTORY,
        # The spec's optional attributes, one key each and all optional.
        #
        # This used to be a single "Size / colour / pack" box. That is not a
        # field, it is three fields with a slash between them — and it repeated
        # `base_unit`, which already covers pack/unit. Unusable data: a shopper
        # filtering casseroles by size would also match ones filtered by colour.
        #
        # Pack/unit is NOT repeated here; `_STOCKED_INVENTORY` supplies it.
        _spec(ProductAttribute.SIZE, "Size", TEXT,
              hint="Where the backend supports it"),
        _spec(ProductAttribute.COLOR, "Colour", TEXT,
              hint="Where the backend supports it"),
    ),
    "SPORTS_FITNESS_OUTDOOR": (
        *_stocked_core(_Examples("Yoga Mat", "Decathlon", "Fitness", "6 mm grey")),
        *_STOCKED_INVENTORY,
        # The spec's optional attributes, one key each. This was a single
        # "Sport / model / equipment type" box — three distinct values sharing a
        # string, so none of them could ever be filtered on.
        _spec(ProductAttribute.SPORT_TYPE, "Sport type", TEXT,
              hint="Where the backend supports it"),
        _spec(ProductAttribute.MODEL, "Model", TEXT,
              hint="Where the backend supports it"),
        _spec(ProductAttribute.SIZE, "Size", TEXT,
              hint="Where the backend supports it"),
        _spec(ProductAttribute.COLOR, "Colour", TEXT,
              hint="Where the backend supports it"),
        _spec(ProductAttribute.EQUIPMENT_TYPE, "Equipment type", TEXT,
              hint="Where the backend supports it"),
    ),
    "BOOKS_MEDIA_STATIONERY": (
        # A book has a publisher and an edition, not a colour.
        _spec(ProductAttribute.NAME, "Title", TEXT, required=True,
              hint="Book title"),
        _spec(ProductAttribute.BRAND, "Publisher", TEXT,
              hint="Penguin"),
        _spec(ProductAttribute.CATEGORY, "Category", TEXT, required=True,
              hint="Fiction", catalog_backed=True),
        _spec(ProductAttribute.SUBCATEGORY, "Subcategory", TEXT,
              catalog_backed=True),
        _spec(ProductAttribute.DESCRIPTION, "Description", MULTILINE),
        _spec(ProductAttribute.VARIANT, "Edition", TEXT, hint="Paperback"),
        _spec(ProductAttribute.PRICE, "Price", NUMBER, required=True),
        _spec(ProductAttribute.MRP, "MRP", NUMBER),
        _spec(ProductAttribute.AVAILABILITY, "Available", CHOICE,
              choices=("Yes", "No")),
        _spec(ProductAttribute.IMAGE, "Cover image", TEXT),
        # ISBN is offered where supported and is NEVER mandatory for every item,
        # as the spec requires.
        _spec(ProductAttribute.BARCODE, "ISBN / barcode", TEXT,
              hint="Where supported", identifier_type="ISBN"),
        _spec(ProductAttribute.QUANTITY, "Quantity", NUMBER),
        # The spec's "Author/Creator where applicable". Optional: a stapler has
        # no author, and forcing one would block half this category's stock.
        _spec(ProductAttribute.AUTHOR, "Author or creator", TEXT,
              hint="Where applicable"),
        # The spec's optional attributes, one key each. This was a single
        # "Language / publication date" box; a date and a language are not the
        # same kind of value and cannot share a column.
        _spec(ProductAttribute.LANGUAGE, "Language", TEXT,
              hint="Where the backend supports it"),
        _spec(ProductAttribute.PUBLICATION_DATE, "Publication date", TEXT,
              hint="Where the backend supports it"),
    ),
    "AUTOMOTIVE_PARTS_TOOLS": (
        *_stocked_core(_Examples("Brake Pad", "Bosch", "Brakes", "Front axle")),
        *_STOCKED_INVENTORY,
        # Compatibility is NOT modelled, and that is a finding rather than an omission.
        #
        # The spec lists "Vehicle compatibility" as a backend-supported optional
        # field and then forbids assuming compatibility in the frontend. Checked
        # against the schema, the backend does not support it:
        #
        #   * `vehicles` is "a physical vehicle owned by a transport provider" —
        #     a provider's own fleet, keyed on `registration_number`. It is not a
        #     catalog of vehicle makes and models.
        #   * `product.py` has no vehicle reference at all, so there is no table
        #     linking a part to the vehicles it fits.
        #
        # With no catalog and no link, a compatibility field could only be
        # invented, and inventing it is exactly what the spec forbids. It stays
        # absent until a catalog exists; `test_no_vehicle_compatibility_field`
        # fails the moment somebody adds one without the backing table.
        #
        # These two fields are what the schema CAN store today:
        #
        # Part number is in the spec's CORE list (the part's own number), while
        # the OEM reference is the optional one (the number it replaces). They
        # are genuinely different values and confusing them is how a shop orders
        # the wrong part, so they stay separate fields.
        _spec(ProductAttribute.PART_NUMBER, "Part number", TEXT,
              hint="Where the backend supports it"),
        _spec(ProductAttribute.OEM_REFERENCE_NUMBER, "OEM / reference number",
              TEXT, hint="Where the backend supports it",
              identifier_type="MPN"),
        _spec(ProductAttribute.VEHICLE_MODEL, "Vehicle model", TEXT,
              hint="Recorded as typed. Not a fitment rule — that comes from the "
                   "backend catalog."),
        _spec(ProductAttribute.MANUFACTURER, "Manufacturer", TEXT,
              hint="Who made the part, when that differs from the brand"),
        _spec(ProductAttribute.TOOL_TYPE, "Tool type", TEXT,
              hint="Where the backend supports it"),
        _spec(ProductAttribute.SPECIFICATION, "Specification", MULTILINE,
              hint="Where the backend supports it"),
    ),
    "HARDWARE": (
        *_stocked_core(_Examples("M8 Hex Bolt", "Fischer", "Fasteners", "50 mm zinc")),
        *_STOCKED_INVENTORY,
        # This was a single "Size / material / unit" box. Unit already has a
        # field of its own (`base_unit`), so that label both duplicated it and
        # buried two genuinely separate attributes beside a third.
        _spec(ProductAttribute.SIZE, "Size", TEXT,
              hint="Where the backend supports it"),
        _spec(ProductAttribute.MATERIAL, "Material", TEXT,
              hint="Where the backend supports it"),
        _spec(ProductAttribute.SPECIFICATION, "Specification", MULTILINE,
              hint="Where the backend supports it"),
    ),
    # Restaurants, Transport and Personal Transport are intentionally ABSENT.
}

# Categories that sell services rather than stocked SKUs. They have no product
# form, which is the point: forcing one is what the spec forbids.
SERVICE_ONLY_CATEGORIES = frozenset(
    {"RESTAURANTS", "TRANSPORT", "PERSONAL_TRANSPORT_TRAVEL"}
)


def product_attributes_for(category_code: str) -> tuple[ProductAttributeSpec, ...]:
    """Attributes for a stocked category, or empty for a service-only one.

    Empty rather than an error: a category with no product catalogue is a valid
    answer, not a failure, so the form simply does not render.
    """
    return CATEGORY_PRODUCT_ATTRIBUTES.get(str(category_code or "").upper(), ())
