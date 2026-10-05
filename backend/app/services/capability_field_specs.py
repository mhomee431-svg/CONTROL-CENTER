"""Backend-owned specifications for the capability-driven shop fields.

Until this existed, the field set lived in Dart (`capability_fields.dart`) while
the capability set lived here. That split is the bug this closes: the backend
decided WHICH capabilities applied and the client decided WHICH fields that
meant, so a backend change silently could not reach the form, and nothing on this
side could validate what arrived.

Both sides now read the same definitions. The Dart mirror exists only for
presentation — icon names and hint text — and `test_capability_field_specs.py`
fails if the two ever disagree on a key, a label, a kind, or a required flag.

Keys map 1:1 to what the Flutter form submits, and only a capability the category
actually holds contributes fields.
"""

from app.models.merchant_category import CategoryCapability

# Capability → {field key: (label, kind, required, options, max_length)}
#
# `kind` matches the Flutter `CapabilityFieldKind`: TEXT, MULTILINE, NUMBER,
# CHOICE. It decides which input is drawn, never what is stored.
TEXT = "TEXT"
MULTILINE = "MULTILINE"
NUMBER = "NUMBER"
CHOICE = "CHOICE"


class CapabilityFieldSpec:
    def __init__(
        self,
        key: str,
        label: str,
        kind: str = TEXT,
        *,
        required: bool = False,
        options: tuple[str, ...] = (),
        max_length: int | None = None,
    ) -> None:
        self.key = key
        self.label = label
        self.kind = kind
        self.required = required
        self.options = options
        self.max_length = max_length

    def as_dict(self) -> dict:
        return {
            "key": self.key,
            "label": self.label,
            "kind": self.kind,
            "required": self.required,
            "options": list(self.options),
            "max_length": self.max_length,
        }


def _spec(key, label, kind=TEXT, **kw) -> CapabilityFieldSpec:
    return CapabilityFieldSpec(key, label, kind, **kw)


_DAYS = (
    "None", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
    "Sunday",
)

# ── Capability → fields ───────────────────────────────────────────────────────
# Only capabilities that change the SHOP-LEVEL form appear. A capability that
# governs another screen (products, offers, POS, import) contributes nothing,
# because those screens already render themselves.
CAPABILITY_FIELDS: dict[CategoryCapability, tuple[CapabilityFieldSpec, ...]] = {
    CategoryCapability.OPERATING_HOURS: (
        _spec("opening_time", "Opening time", TEXT, required=True),
        _spec("closing_time", "Closing time", TEXT, required=True),
        _spec("closed_on", "Closed on", CHOICE, options=_DAYS),
    ),
    CategoryCapability.SERVICES: (
        _spec(
            "service_summary",
            "Services you offer",
            MULTILINE,
            max_length=400,
        ),
    ),
    CategoryCapability.BOOKING: (
        _spec("booking_lead_hours", "Booking lead time (hours)", NUMBER),
    ),
    CategoryCapability.DOCUMENTS: (
        _spec("gst_number", "GST number", TEXT, max_length=15),
    ),
    CategoryCapability.CONTACT: (
        _spec("contact_phone", "Contact number", TEXT, required=True),
    ),
    CategoryCapability.CATEGORY_SPECIFIC_DATA: (
        _spec(
            "business_highlights",
            "What makes your business stand out",
            MULTILINE,
            max_length=300,
        ),
    ),
}

# ── Service profile → fields ──────────────────────────────────────────────────
# A tour operator's service area is not a transporter's route list and not a
# restaurant's offerings. `CATEGORY_SPECIFIC_DATA` says this trade has data of
# its own; this says which kind. Mirrors the Dart `ServiceCategoryProfile`.
SERVICE_PROFILE_FIELDS: dict[str, tuple[CapabilityFieldSpec, ...]] = {
    "PERSONAL_TRANSPORT_TRAVEL": (
        _spec("service_area", "Service area", TEXT, max_length=200),
        _spec(
            "service_types",
            "Services you arrange",
            MULTILINE,
            max_length=400,
        ),
        _spec(
            "travel_details",
            "Travel or service details",
            MULTILINE,
            max_length=400,
        ),
    ),
    "TRANSPORT": (
        _spec("service_area", "Service area", TEXT, max_length=200),
        _spec("route_fares", "Routes and fares", MULTILINE, max_length=400),
    ),
    "RESTAURANTS": (
        _spec("menu_offerings", "Offerings", MULTILINE, max_length=500),
    ),
}


def category_profile(category_code: str) -> str | None:
    """The service profile for a category, or None when it has none."""
    code = str(category_code or "").strip().upper()
    return code if code in SERVICE_PROFILE_FIELDS else None


def capability_fields_for(
    category_code: str, business_type: str | None = None
) -> list[CapabilityFieldSpec]:
    """Every field this category/business-type pair may submit, in a stable order.

    Order comes from the capability enum rather than a dict's insertion order, so
    adding a capability cannot silently reshuffle an existing form.
    """
    from app.models.merchant_category import capabilities_for_category

    resolved = capabilities_for_category(category_code, business_type)
    if resolved is None:
        return []

    granted = set(resolved.get("capabilities", ()))
    fields: list[CapabilityFieldSpec] = []
    for capability in CategoryCapability:
        if capability.value not in granted:
            continue
        fields.extend(CAPABILITY_FIELDS.get(capability, ()))
        if capability is CategoryCapability.CATEGORY_SPECIFIC_DATA:
            profile = category_profile(category_code)
            if profile:
                fields.extend(SERVICE_PROFILE_FIELDS[profile])
    return fields


def allowed_capability_field_keys(
    category_code: str, business_type: str | None = None
) -> set[str]:
    return {spec.key for spec in capability_fields_for(category_code, business_type)}


def validate_capability_fields(
    category_code: str,
    business_type: str | None,
    submitted: dict | None,
) -> list[str]:
    """Errors for a submission, as `{field}: message` strings.

    Only REQUIRED and shape rules are enforced here. Domain rules needing
    external knowledge — does this GSTIN exist, is this number real — belong to
    verification, not to whether a value is storable.
    """
    specs = {
        spec.key: spec
        for spec in capability_fields_for(category_code, business_type)
    }
    errors: list[str] = []
    # A missing submission is an empty submission, not a licence to skip the
    # required check — otherwise posting `{}` passes validation entirely.
    submitted = submitted or {}

    for key, raw in submitted.items():
        spec = specs.get(key)
        if spec is None:
            # An unapproved key is rejected outright, never coerced.
            errors.append(f"{key}: not a field for this category")
            continue

        text = str(raw).strip()
        if not text:
            if spec.required:
                errors.append(f"{key}: {spec.label} is required")
            continue

        if spec.kind == NUMBER:
            try:
                number = float(text)
            except ValueError:
                errors.append(f"{key}: must be a number")
                continue
            if number < 0:
                errors.append(f"{key}: cannot be negative")
        elif spec.kind == CHOICE and spec.options and text not in spec.options:
            errors.append(f"{key}: must be one of {', '.join(spec.options)}")

        if spec.max_length and len(text) > spec.max_length:
            errors.append(f"{key}: longer than {spec.max_length} characters")

    # Required fields that were OMITTED are errors too. Checking only the keys
    # that arrived would let a client post `{}` and pass, which is exactly what
    # makes "required" decorative.
    for key, spec in specs.items():
        if spec.required and key not in submitted:
            errors.append(f"{key}: {spec.label} is required")

    return errors