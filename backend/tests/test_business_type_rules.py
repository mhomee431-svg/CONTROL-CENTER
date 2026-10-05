"""The business-type axis, pinned.

Two rules in the spec meet here, and they pull in opposite directions:

  * "Business Type may influence available fields" — Service must drop the stock
    capabilities.
  * "Do not hardcode assumptions that conflict with backend schema" — Wholesale
    gets extra pricing *only when the backend supports it*, and it does not.

The second is why `Wholesale` narrows nothing: there is no wholesale/dealer/
trade-price column anywhere in the schema, so a narrowing rule there would be an
assumption the database cannot honour.
"""

import re
from pathlib import Path

import pytest
from pydantic import ValidationError

from app.models.merchant_category import (
    BUSINESS_TYPES,
    BUSINESS_TYPE_NARROWING,
    CategoryCapability,
    MerchantCategoryCode,
    capabilities_for_category,
    is_known_business_type,
    resolve_capabilities,
)
from app.models.product_attributes import product_attributes_for
from app.schemas.shopkeeper import (
    ShopkeeperProfileCreateRequest,
    ShopkeeperShopCreate,
)

EXPECTED_TYPES = {
    "Retail",
    "Wholesale",
    "Retail + Wholesale",
    "Service",
    "Other",
}


class TestTheVocabulary:
    def test_it_is_exactly_the_five_types_the_spec_lists(self):
        assert set(BUSINESS_TYPES) == EXPECTED_TYPES

    def test_it_has_no_duplicates(self):
        assert len(BUSINESS_TYPES) == len(set(BUSINESS_TYPES))

    def test_every_type_has_a_narrowing_entry(self):
        """A type with no entry would silently behave like `Other`.

        `resolve_capabilities` is permissive for anything it does not recognise,
        so a missing key is indistinguishable from a deliberate "no narrowing" —
        which is how a typo becomes an invisible behaviour change.
        """
        for value in BUSINESS_TYPES:
            assert value in BUSINESS_TYPE_NARROWING, value

    @pytest.mark.parametrize("value", sorted(EXPECTED_TYPES))
    def test_each_type_is_recognised(self, value):
        assert is_known_business_type(value) is True

    @pytest.mark.parametrize("value", [None, "", "   "])
    def test_an_absent_type_is_allowed(self, value):
        """The type is optional; refusing it would break existing shops."""
        assert is_known_business_type(value) is True

    @pytest.mark.parametrize(
        "value",
        [
            "Retail & Wholesale",  # the app's historical typo
            "Retial",
            "Service Provider",
            "retail",  # case differs from the stored vocabulary
        ],
    )
    def test_anything_else_is_refused(self, value):
        assert is_known_business_type(value) is False


class TestTheSchemaEnforcesTheVocabulary:
    """A type outside the list cannot match a narrowing rule, so it is refused
    at the edge rather than stored and silently treated as permissive."""

    # `profile-create` is INITIAL registration, where the spec says the minimum
    # required data is collected — category and business type included.
    @pytest.mark.parametrize("value", sorted(EXPECTED_TYPES))
    def test_create_accepts_every_real_type(self, value):
        assert (
            ShopkeeperProfileCreateRequest(
                shop_name="Tandoor", category="HARDWARE", business_type=value
            ).business_type
            == value
        )

    def test_create_rejects_the_historical_typo(self):
        with pytest.raises(ValidationError):
            ShopkeeperProfileCreateRequest(
                shop_name="Tandoor",
                category="HARDWARE",
                business_type="Retail & Wholesale",
            )

    def test_shop_create_applies_the_same_rule(self):
        with pytest.raises(ValidationError):
            ShopkeeperShopCreate(name="Tandoor", business_type="Retial")

    def test_shop_create_accepts_a_real_type(self):
        assert (
            ShopkeeperShopCreate(
                name="Tandoor", business_type="Service"
            ).business_type
            == "Service"
        )

    @pytest.mark.parametrize("value", [None, "   "])
    def test_an_absent_type_stays_absent_on_the_shop_endpoint(self, value):
        """Adding a SECOND shop may omit the type.

        The rule is applied by a shared function rather than by the field being
        optional, so one endpoint can require it while the other does not — but
        both still normalise a blank to None rather than storing a blank.
        """
        assert ShopkeeperShopCreate(name="Tandoor", business_type=value).business_type is None

    def test_surrounding_whitespace_is_trimmed(self):
        assert (
            ShopkeeperProfileCreateRequest(
                shop_name="Tandoor",
                category="HARDWARE",
                business_type="  Service  ",
            ).business_type
            == "Service"
        )


class TestInitialRegistrationCollectsTheMinimum:
    """The spec: "Initial Shop Registration should collect minimum required data."

    Category and business type are the two that are structurally required rather
    than merely useful — the whole capability model resolves through the
    category, so a shop without one answers 404 on every capability route for
    the rest of its life.
    """

    def test_a_category_is_required(self):
        with pytest.raises(ValidationError):
            ShopkeeperProfileCreateRequest(
                shop_name="Tandoor", business_type="Retail"
            )

    def test_a_business_type_is_required(self):
        with pytest.raises(ValidationError):
            ShopkeeperProfileCreateRequest(shop_name="Tandoor", category="HARDWARE")

    def test_a_blank_category_is_refused(self):
        with pytest.raises(ValidationError):
            ShopkeeperProfileCreateRequest(
                shop_name="Tandoor", category="   ", business_type="Retail"
            )

    def test_an_unknown_category_is_refused(self):
        """It would store, and then every capability lookup returns None."""
        with pytest.raises(ValidationError):
            ShopkeeperProfileCreateRequest(
                shop_name="Tandoor", category="KIRANA", business_type="Retail"
            )

    def test_the_category_is_normalised_to_the_registry_spelling(self):
        assert (
            ShopkeeperProfileCreateRequest(
                shop_name="Tandoor", category="hardware", business_type="Retail"
            ).category
            == "HARDWARE"
        )

    def test_every_registered_category_is_accepted(self):
        """The check must track the registry, not a second list of codes."""
        for code in MerchantCategoryCode:
            assert (
                ShopkeeperProfileCreateRequest(
                    shop_name="Tandoor",
                    category=code.value,
                    business_type="Retail",
                ).category
                == code.value
            )

    def test_location_is_not_required_yet(self):
        """Registration deliberately runs before the location-capture flow.

        Requiring a pin here would mean asking for GPS on the very first screen,
        which is why the capture step exists as its own screen.
        """
        request = ShopkeeperProfileCreateRequest(
            shop_name="Tandoor", category="HARDWARE", business_type="Retail"
        )
        assert not any("location" in n for n in type(request).model_fields)


class TestServiceDropsStockAndKeepsBusinessFields:
    """The spec's service example: no stock quantity, but contact, location and a
    service description still apply."""

    def test_it_drops_every_stock_shaped_capability(self):
        resolved = set(resolve_capabilities("HARDWARE", "Service") or ())
        for capability in (
            CategoryCapability.PRODUCT_CATALOG,
            CategoryCapability.INVENTORY,
            CategoryCapability.BARCODE,
            CategoryCapability.IMPORT,
            CategoryCapability.POS,
        ):
            assert capability not in resolved, capability

    def test_it_keeps_the_fields_a_service_business_needs(self):
        resolved = set(resolve_capabilities("RESTAURANTS", "Service") or ())
        for capability in (
            CategoryCapability.CONTACT,
            CategoryCapability.LOCATION,
            CategoryCapability.SERVICES,
            CategoryCapability.OPERATING_HOURS,
            CategoryCapability.PRICE,
        ):
            assert capability in resolved, capability

    def test_a_service_business_has_no_product_form(self):
        assert product_attributes_for("RESTAURANTS") == ()

    @pytest.mark.parametrize("code", ["RESTAURANTS", "TRANSPORT", "HARDWARE"])
    def test_no_type_ever_loses_contact_or_location(self, code):
        for value in BUSINESS_TYPES:
            resolved = set(resolve_capabilities(code, value) or ())
            assert CategoryCapability.CONTACT in resolved, (code, value)
            assert CategoryCapability.LOCATION in resolved, (code, value)


class TestWholesaleAddsNothingTheSchemaCannotHold:
    """"...additional pricing structures only when backend supports them." """

    def test_the_schema_has_no_wholesale_pricing_column(self):
        pattern = re.compile(
            r"(\w*(?:wholesale|dealer|trade_price|tier\w*|min_qty|bulk)\w*)\s*:"
            r"\s*Mapped",
            re.IGNORECASE,
        )
        import app.models as models_pkg

        hits = []
        for path in Path(models_pkg.__path__[0]).glob("*.py"):
            for match in pattern.finditer(path.read_text(encoding="utf-8")):
                hits.append(f"{path.name}:{match.group(1)}")
        assert not hits, f"wholesale pricing now exists and needs a rule: {hits}"

    def test_wholesale_narrows_nothing(self):
        """Correct today precisely because that check above passes."""
        assert BUSINESS_TYPE_NARROWING["Wholesale"] == ()

    def test_wholesale_keeps_the_catalogue_and_stock(self):
        resolved = set(resolve_capabilities("HARDWARE", "Wholesale") or ())
        assert CategoryCapability.PRODUCT_CATALOG in resolved
        assert CategoryCapability.INVENTORY in resolved

    @pytest.mark.parametrize("value", ["Wholesale", "Retail + Wholesale"])
    def test_the_combined_type_keeps_stock_too(self, value):
        resolved = set(resolve_capabilities("HARDWARE", value) or ())
        assert CategoryCapability.PRODUCT_CATALOG in resolved
        assert CategoryCapability.INVENTORY in resolved


class TestRetailAndOtherStayPermissive:
    @pytest.mark.parametrize("value", ["Retail", "Other"])
    def test_neither_narrows_anything(self, value):
        assert BUSINESS_TYPE_NARROWING[value] == ()

    @pytest.mark.parametrize("value", ["Retail", "Other", "Retail + Wholesale"])
    def test_stock_survives_all_three(self, value):
        resolved = set(resolve_capabilities("HARDWARE", value) or ())
        assert CategoryCapability.PRODUCT_CATALOG in resolved


class TestUnknownTypesStayPermissiveRatherThanLockingTheShopOut:
    """Documented behaviour, and deliberately the opposite of the schema rule.

    The schema refuses a bad value at write time; the resolver stays permissive
    for rows written before that validation existed. Hiding a capability wrongly
    is worse than showing one, because showing it fails at submit and says so.
    """

    def test_an_unrecognised_type_keeps_the_full_catalogue(self):
        resolved = set(resolve_capabilities("HARDWARE", "Retial") or ())
        assert CategoryCapability.PRODUCT_CATALOG in resolved

    def test_a_missing_type_keeps_the_full_catalogue(self):
        for value in (None, "", "   "):
            resolved = set(resolve_capabilities("HARDWARE", value) or ())
            assert CategoryCapability.PRODUCT_CATALOG in resolved, repr(value)


class TestTheClientContractAdvertisesTheSameTypes:
    @pytest.mark.parametrize("value", BUSINESS_TYPES)
    def test_the_capabilities_endpoint_answers_for_every_type(self, value):
        payload = capabilities_for_category("HARDWARE", value)
        assert payload is not None, value
        assert "capabilities" in payload, value


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))
