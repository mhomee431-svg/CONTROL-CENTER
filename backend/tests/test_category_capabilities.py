"""CATEGORY CAPABILITY MODEL — the Category + Business Type -> Capabilities rule.

The spec this implements is that data-entry fields must be capability-driven:
the app renders the form the backend describes rather than one giant form, and
it must not invent category rules the backend does not support. That only holds
if the rule lives in exactly one place, so these tests read the registry itself
and pin the properties the client relies on.

The properties that matter, and why each is a bug if it breaks:

  * every category resolves — a missing entry means the shopkeeper cannot
    register at all, and the client gets a 404 instead of a form
  * CONTACT and LOCATION always survive narrowing — a business that cannot be
    contacted or found is not usable, so narrowing may never remove them
  * a service-led category is NOT a stock ledger — if RESTAURANTS ever gained
    INVENTORY, the app would show a stock screen a restaurant has no use for
  * narrowing only ever removes — it must never ADD a capability the category
    did not have, or "Service" could silently grant POS to a category that
    never had it
"""

from app.models.merchant_category import (
    BUSINESS_TYPES,
    BUSINESS_TYPE_NARROWING,
    MERCHANT_CATEGORIES,
    MERCHANT_CATEGORY_CAPABILITIES,
    MERCHANT_CATEGORY_NAMES,
    CategoryCapability,
    capabilities_for_category,
    resolve_capabilities,
)

# Categories that trade in services/menus/bookings rather than stocked SKUs.
SERVICE_LED = {
    "RESTAURANTS",
    "TRANSPORT",
    "PERSONAL_TRANSPORT_TRAVEL",
}


class TestRegistryCoverage:
    def test_every_approved_category_has_capabilities(self):
        for code, _name in MERCHANT_CATEGORIES:
            assert code in MERCHANT_CATEGORY_CAPABILITIES, (
                f"{code} is an approved category but has no capability set — "
                "the app would receive a 404 instead of a form"
            )

    def test_no_capability_set_exists_for_an_unapproved_category(self):
        # A capability entry for a category the registry does not list is dead
        # configuration nobody will ever exercise.
        approved = {code for code, _ in MERCHANT_CATEGORIES}
        assert set(MERCHANT_CATEGORY_CAPABILITIES) == approved

    def test_no_forbidden_food_category_appears(self):
        for code in MERCHANT_CATEGORY_CAPABILITIES:
            for word in ("GROCERY", "FOOD", "DELIVERY", "SUPERMARKET"):
                assert word not in code, f"{code} is not an approved category"

    def test_every_capability_entry_is_non_empty(self):
        for code, caps in MERCHANT_CATEGORY_CAPABILITIES.items():
            assert caps, f"{code} resolved to no capabilities at all"


class TestResolution:
    def test_known_category_resolves(self):
        resolved = resolve_capabilities("PHARMACY_HEALTHCARE")
        assert resolved is not None
        assert CategoryCapability.PRODUCT_CATALOG in resolved
        assert CategoryCapability.INVENTORY in resolved

    def test_category_code_is_case_insensitive(self):
        assert resolve_capabilities("pharmacy_healthcare") == resolve_capabilities(
            "PHARMACY_HEALTHCARE"
        )

    def test_unknown_category_returns_none(self):
        # None is what makes the route answer 404; returning an empty set would
        # render an empty form with no explanation.
        assert resolve_capabilities("NOT_A_CATEGORY") is None
        assert resolve_capabilities("") is None
        assert resolve_capabilities(None) is None

    def test_service_led_categories_have_no_stock_ledger(self):
        for code in SERVICE_LED:
            resolved = resolve_capabilities(code)
            assert CategoryCapability.PRODUCT_CATALOG not in resolved, (
                f"{code} sells services, not stocked SKUs — a product catalogue "
                "would make the app show a screen the category cannot use"
            )
            assert CategoryCapability.INVENTORY not in resolved, (
                f"{code} has no stock ledger to maintain"
            )
            # BOOKING is asserted per category, not for every service-led one.
            # It used to be a blanket expectation, which quietly assumed that
            # "sells services" implies "can be booked". Personal transport /
            # personal travel breaks that: every booking model in the schema is
            # chained to a `vehicles` row, and a travel agency has no fleet, so
            # granting it there would render a booking screen that cannot book.
            if code == "PERSONAL_TRANSPORT_TRAVEL":
                assert CategoryCapability.BOOKING not in resolved, (
                    "a travel agency has no vehicle to attach a booking to; the "
                    "capability must stay off until a travel booking model exists"
                )
            else:
                assert CategoryCapability.BOOKING in resolved, (
                    f"{code} is backed by transport_bookings"
                )
            assert CategoryCapability.SERVICES in resolved

    def test_stock_categories_keep_their_catalogue(self):
        for code in ("PHARMACY_HEALTHCARE", "HOUSEHOLD_GOODS", "HARDWARE"):
            resolved = resolve_capabilities(code)
            assert CategoryCapability.PRODUCT_CATALOG in resolved
            assert CategoryCapability.INVENTORY in resolved


class TestBusinessTypeNarrowing:
    def test_service_type_drops_stock_capabilities(self):
        resolved = resolve_capabilities("HOUSEHOLD_GOODS", "Service")
        assert CategoryCapability.PRODUCT_CATALOG not in resolved
        assert CategoryCapability.INVENTORY not in resolved
        assert CategoryCapability.BARCODE not in resolved
        assert CategoryCapability.POS not in resolved

    def test_narrowing_never_removes_contact_or_location(self):
        # The safety invariant. Narrowing may hide stock features but must never
        # leave a business unfindable or uncontactable.
        for code, _ in MERCHANT_CATEGORIES:
            for business_type in BUSINESS_TYPES:
                resolved = resolve_capabilities(code, business_type)
                assert resolved is not None
                assert CategoryCapability.CONTACT in resolved, (
                    f"{code}/{business_type} lost CONTACT"
                )
                assert CategoryCapability.LOCATION in resolved, (
                    f"{code}/{business_type} lost LOCATION"
                )

    def test_narrowing_only_removes_and_never_adds(self):
        # Otherwise "Service" could silently grant a capability the category never
        # had, and the client would render a screen the backend refuses.
        for code, _caps in MERCHANT_CATEGORIES:
            base = set(resolve_capabilities(code) or ())
            for business_type in BUSINESS_TYPES:
                narrowed = set(resolve_capabilities(code, business_type) or ())
                unexpected = narrowed - base
                assert unexpected <= {
                    CategoryCapability.CONTACT,
                    CategoryCapability.LOCATION,
                }, (
                    f"{code}/{business_type} gained {unexpected} — narrowing "
                    "may only remove stock-shaped capabilities"
                )

    def test_retail_and_wholesale_do_not_narrow(self):
        for code, _ in MERCHANT_CATEGORIES:
            for business_type in ("Retail", "Wholesale", "Retail + Wholesale"):
                assert (
                    resolve_capabilities(code, business_type)
                    == resolve_capabilities(code)
                )

    def test_unknown_business_type_is_permissive(self):
        # Wrongly hiding a capability locks a shopkeeper out of something they
        # may be entitled to; wrongly showing one surfaces on submit. The
        # permissive failure is the safer one.
        assert resolve_capabilities("HOUSEHOLD_GOODS", "Something Else") == (
            resolve_capabilities("HOUSEHOLD_GOODS")
        )
        assert resolve_capabilities("HOUSEHOLD_GOODS", None) == (
            resolve_capabilities("HOUSEHOLD_GOODS")
        )

    def test_resolution_is_deterministic(self):
        # The client renders the list in the order it arrives; unstable order
        # would make the form reshuffle between rebuilds.
        first = resolve_capabilities("PHARMACY_HEALTHCARE", "Retail")
        for _ in range(5):
            assert resolve_capabilities("PHARMACY_HEALTHCARE", "Retail") == first

    def test_no_capability_is_duplicated(self):
        for code, _ in MERCHANT_CATEGORIES:
            for business_type in BUSINESS_TYPES:
                resolved = resolve_capabilities(code, business_type)
                assert len(resolved) == len(set(resolved)), (
                    f"{code}/{business_type} produced a duplicate capability"
                )


class TestVocabulary:
    def test_business_types_match_the_wizard_options(self):
        assert set(BUSINESS_TYPES) == set(BUSINESS_TYPE_NARROWING)

    def test_business_types_are_non_empty_and_unique(self):
        assert BUSINESS_TYPES
        assert len(set(BUSINESS_TYPES)) == len(BUSINESS_TYPES)

    def test_capability_names_are_stable_strings(self):
        # They cross the wire; a rename here is a client-visible break.
        for capability in CategoryCapability:
            assert capability.value.isupper()
            assert " " not in capability.value


class TestUiContract:
    def test_contract_shape(self):
        data = capabilities_for_category("RESTAURANTS", "Service")
        assert data is not None
        assert data["category_code"] == "RESTAURANTS"
        assert data["business_type"] == "Service"
        assert isinstance(data["capabilities"], list)
        assert all(isinstance(c, str) for c in data["capabilities"])

    def test_unknown_category_yields_no_contract(self):
        assert capabilities_for_category("NOPE") is None

    def test_contract_capabilities_match_the_resolver(self):
        for code, _ in MERCHANT_CATEGORIES:
            for business_type in (None, *BUSINESS_TYPES):
                data = capabilities_for_category(code, business_type)
                expected = [c.value for c in resolve_capabilities(code, business_type)]
                assert data["capabilities"] == expected

    def test_every_category_has_a_display_name(self):
        for code, name in MERCHANT_CATEGORIES:
            assert MERCHANT_CATEGORY_NAMES[code] == name
