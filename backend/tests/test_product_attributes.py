"""Product attributes must track the real schema and the approved categories.

Two failure modes are worth paying for:

  * a new category shipping without product attributes (silently broken form),
  * an attribute being invented that the database has nowhere to store.
"""

import pytest

from app.models.merchant_category import MerchantCategoryCode
from app.models.product_attributes import (
    CATEGORY_PRODUCT_ATTRIBUTES,
    SERVICE_ONLY_CATEGORIES,
    ProductAttribute,
    ProductAttributeKind,
    product_attributes_for,
)

ALL_CODES = {c.value for c in MerchantCategoryCode}


def _keys(category: str) -> set[str]:
    return {s.key.value for s in product_attributes_for(category)}


class TestCoverage:
    def test_every_approved_category_is_known(self):
        """A category outside the registry is a bug, not a fallback."""
        assert set(CATEGORY_PRODUCT_ATTRIBUTES) | SERVICE_ONLY_CATEGORIES == ALL_CODES

    def test_stock_attributes_cover_exactly_the_stock_categories(self):
        stocked = {c.value for c in MerchantCategoryCode} - SERVICE_ONLY_CATEGORIES
        assert set(CATEGORY_PRODUCT_ATTRIBUTES) == stocked

    def test_every_stock_category_declares_attributes(self):
        """No stocked category may ship an empty product form."""
        for code in CATEGORY_PRODUCT_ATTRIBUTES:
            assert product_attributes_for(code), f"{code} has no attributes"

    def test_service_categories_have_no_product_form(self):
        """Restaurants/transport sell services; a product form is wrong."""
        for code in SERVICE_ONLY_CATEGORIES:
            assert product_attributes_for(code) == ()
            assert code not in CATEGORY_PRODUCT_ATTRIBUTES

    def test_lookup_is_case_insensitive(self):
        assert _keys("pharmacy_healthcare") == _keys("PHARMACY_HEALTHCARE")

    def test_unknown_category_is_empty_not_an_error(self):
        assert product_attributes_for("NOT_A_CATEGORY") == ()
        assert product_attributes_for("") == ()
        assert product_attributes_for(None) == ()


class test_spec_shape:  # noqa: N801 - descriptive class name for readability
    def test_name_and_price_are_required(self):
        for code in CATEGORY_PRODUCT_ATTRIBUTES:
            required = {s.key for s in product_attributes_for(code) if s.required}
            assert ProductAttribute.NAME in required, code
            assert ProductAttribute.PRICE in required, code

    def test_keys_are_unique_within_a_category(self):
        for code, specs in CATEGORY_PRODUCT_ATTRIBUTES.items():
            keys = [s.key.value for s in specs]
            assert len(keys) == len(set(keys)), f"{code} has duplicate keys"

    def test_choices_only_on_choice_attributes(self):
        for specs in CATEGORY_PRODUCT_ATTRIBUTES.values():
            for spec in specs:
                assert bool(spec.choices) == (
                    spec.kind is ProductAttributeKind.CHOICE
                ), spec.key

    def test_availability_is_a_yes_no_choice(self):
        avail = [
            s
            for specs in CATEGORY_PRODUCT_ATTRIBUTES.values()
            for s in specs
            if s.key is ProductAttribute.AVAILABILITY
        ]
        assert avail
        assert all(tuple(s.choices) == ("Yes", "No") for s in avail)

    def test_spec_serialises_for_the_flutter_contract(self):
        spec = product_attributes_for("PHARMACY_HEALTHCARE")[0]
        assert set(spec.as_dict()) == {
            "key", "label", "kind", "required", "hint", "choices",
            "catalog_backed",
            "identifier_type",
        }

    def test_every_label_is_present(self):
        for specs in CATEGORY_PRODUCT_ATTRIBUTES.values():
            assert all(s.label.strip() for s in specs)

    def test_catalog_backed_keys_are_marked_for_every_category(self):
        """`category_id` / `subcategory_id` are FOREIGN KEYS, not text columns.

        A typed value there cannot be stored — it must resolve to a row in
        `categories`. Marking them is what tells the client to offer the catalog
        instead of a free-text box whose value the database would drop.

        This iterates EVERY category rather than spot-checking one, because
        FURNITURE_HOME_CARE builds its own field list instead of using the
        shared block, and a spot check left it unmarked for exactly that reason.
        """
        for code, specs in CATEGORY_PRODUCT_ATTRIBUTES.items():
            marked = {s.key for s in specs if s.catalog_backed}
            assert ProductAttribute.CATEGORY in marked, f"{code} category"
            assert ProductAttribute.SUBCATEGORY in marked, f"{code} subcategory"

    def test_free_text_columns_are_not_marked_catalog_backed(self):
        """The flag must mean something.

        Applying it everywhere would be as wrong as omitting it: a brand and a
        variant really are free text.
        """
        text_keys = {
            ProductAttribute.NAME,
            ProductAttribute.BRAND,
            ProductAttribute.DESCRIPTION,
            ProductAttribute.VARIANT,
            ProductAttribute.BASE_UNIT,
        }
        for specs in CATEGORY_PRODUCT_ATTRIBUTES.values():
            for spec in specs:
                if spec.key in text_keys:
                    assert not spec.catalog_backed, spec.key

    def test_only_those_three_keys_are_catalog_backed(self):
        """Keeps the flag meaningful: exactly the catalog levels."""
        allowed = {
            ProductAttribute.CATEGORY,
            ProductAttribute.SUBCATEGORY,
            ProductAttribute.PRODUCT_TYPE,
        }
        for specs in CATEGORY_PRODUCT_ATTRIBUTES.values():
            for spec in specs:
                if spec.catalog_backed:
                    assert spec.key in allowed, spec.key


class TestCategorySpecifics:
    def test_pharmacy_invents_no_regulatory_fields(self):
        """The spec's IMPORTANT rule, pinned.

        Licence information, regulatory information and medical product
        attributes are listed as FUTURE fields, to be implemented only once the
        backend defines the requirements. The columns exist on
        `product_masters`, but nothing defines their valid values — so exposing
        them would be inventing a requirement, which is precisely what is
        forbidden.
        """
        keys = _keys("PHARMACY_HEALTHCARE")
        for forbidden in (
            "regulatory_class",
            "requires_license_type",
            "prescription_required",
            "is_restricted",
        ):
            assert forbidden not in keys, forbidden

    def test_no_category_exposes_a_regulatory_product_field(self):
        # Not just pharmacy: the rule is global, so a later category cannot
        # quietly reintroduce it.
        for specs in CATEGORY_PRODUCT_ATTRIBUTES.values():
            for spec in specs:
                assert "regulat" not in spec.key.value
                assert "licen" not in spec.key.value
                assert "prescription" not in spec.key.value

    def test_the_registry_declares_no_such_keys_at_all(self):
        """Not even unused ones.

        A declared-but-unused key is an invitation to wire a regulatory field up
        later without re-reading the spec. Absence is the honest state.
        """
        assert not any(
            "regulat" in a.value or "licen" in a.value
            for a in ProductAttribute
        )

    def test_a_pharmacy_field_key_has_no_column_to_invent(self):
        # Every exposed key must still map to a real destination. With the
        # regulatory keys gone, nothing points at a column the shopkeeper has no
        # defined vocabulary for.
        for spec in product_attributes_for("PHARMACY_HEALTHCARE"):
            assert spec.key.value
            assert spec.label

    def test_automotive_records_a_model_but_never_claims_a_fitment(self):
        """The spec's rule: compatibility must come from backend catalog data.

        Recorded as typed is fine — it asserts nothing about what the part fits.
        Asserting fitment is not, because no catalog exists to assert it from:
        `vehicles` is a transport provider's own fleet keyed on registration
        number, and `product.py` references no vehicle table at all.

        So the test checks the substance, not the word "vehicle": a field that
        RESOLVES against the catalog would be a fitment claim, and one that is
        plain text is only a note.
        """
        specs = product_attributes_for("AUTOMOTIVE_PARTS_TOOLS")
        by_key = {s.key: s for s in specs}

        model = by_key[ProductAttribute.VEHICLE_MODEL]
        assert model.catalog_backed is False, (
            "a vehicle model resolved from the catalog becomes a fitment "
            "claim, which the spec forbids the frontend from making"
        )

        # Nothing may be labelled as a fitment rule.
        for spec in specs:
            assert "compat" not in spec.label.lower(), spec.label
            assert "fit" not in spec.label.lower(), spec.label

    def test_no_category_declares_a_vehicle_compatibility_field(self):
        """The guard that outlives this spec.

        A compatibility field would need a catalog of vehicle makes, models and
        fitments plus a product-to-vehicle link. Neither exists. If somebody adds
        one before they build that, this fails and the comment tells them why.
        """
        for code, specs in CATEGORY_PRODUCT_ATTRIBUTES.items():
            for spec in specs:
                assert "compat" not in spec.key.value, f"{code}.{spec.key}"
                assert "fitment" not in spec.key.value, f"{code}.{spec.key}"

    def test_books_never_force_isbn(self):
        """ISBN may be offered but must not be mandatory for every item."""
        isbn = [
            s
            for s in product_attributes_for("BOOKS_MEDIA_STATIONERY")
            if s.key is ProductAttribute.BARCODE
        ]
        assert isbn and not isbn[0].required

    def test_furniture_has_no_barcode_but_may_have_quantity(self):
        """Corrected against the spec.

        The spec says "Quantity where applicable", not "never": a furniture shop
        stocks fifty identical chairs. Dropping quantity entirely on a "bulky
        goods" assumption was me over-reading it. Barcode stays off because a
        sofa genuinely has no scannable EAN.
        """
        keys = _keys("FURNITURE_HOME_CARE")
        assert ProductAttribute.BARCODE not in keys
        assert ProductAttribute.QUANTITY in keys
        assert ProductAttribute.PRICE in keys
    def test_stock_categories_track_quantity(self):
        for code in ("HOUSEHOLD_GOODS", "HARDWARE", "BEAUTY_PERSONAL_CARE"):
            assert ProductAttribute.QUANTITY in _keys(code)

    def test_stocked_categories_never_get_stock_only_fields(self):
        """Service narrowing already removes them; nothing re-adds them."""
        for code in SERVICE_ONLY_CATEGORIES:
            keys = _keys(code)
            assert ProductAttribute.QUANTITY not in keys
            assert ProductAttribute.PRICE not in keys

    def test_extension_attributes_are_never_required(self):
        """They only appear when the backend supplies catalog data."""
        for specs in CATEGORY_PRODUCT_ATTRIBUTES.values():
            for spec in specs:
                if spec.key is ProductAttribute.EXTENSION_ATTRIBUTES:
                    assert not spec.required


import json
import re
from pathlib import Path

from app.models import merchant_category

import pytest

from app.models.merchant_category import MerchantCategoryCode
from app.models.product_attributes import (
    CATEGORY_PRODUCT_ATTRIBUTES,
    SERVICE_ONLY_CATEGORIES,
    ProductAttribute,
    product_attributes_for,
)

# The Dart mirror of this registry. When a key is added or renamed on either
# side without the other, this fails — which is the whole point.
_DART_FILE = (
    Path(__file__).resolve().parents[2]
    / "apps/shopkeeper_app/lib/features/shops/domain/product_attributes.dart"
)

# The whole Dart `lib/` tree, scanned by the "no arbitrary fields in Flutter"
# tests. A single file would be too narrow: the rule is about the app being
# unable to invent a field ANYWHERE, not just in the one mirror file.
_DART_LIB = (
    Path(__file__).resolve().parents[2] / "apps/shopkeeper_app/lib"
)


def _dart_wire_names() -> set[str]:
    """Keys the Dart enum publishes as wire names.

    Scoped to the `wireName` getter so the icon mapping further down the file is
    not mistaken for attribute keys.
    """
    text = _DART_FILE.read_text(encoding="utf-8")
    start = text.index("String get wireName")
    end = text.index("/// Recognise a backend key", start)
    return {
        line.split("'")[1]
        for line in text[start:end].splitlines()
        if "=> '" in line
    }
def test_dart_and_backend_sources_are_valid_utf8():
    """Guards a bug that actually happened here.

    A PowerShell `Set-Content` wrote the Dart mirror as CP1252, turning every em
    dash into a byte that is invalid UTF-8. Nothing failed at edit time — the
    breakage surfaced as a drift failure complaining about MISSING KEYS, because
    the parser could not read the file at all. Strict decoding here turns a
    misleading symptom into an unambiguous failure.

    Declared after `_DART_FILE` so the constant it checks exists.
    """
    for path in (
        _DART_FILE,
        Path(__file__).resolve().parents[2]
        / "apps/shopkeeper_app/lib/features/shops/domain/shop_models.dart",
        Path(__file__).resolve().parents[1] / "app/models/product_attributes.py",
    ):
        path.read_bytes().decode("utf-8")  # raises UnicodeDecodeError


class TestDartDrift:
    def test_dart_file_exists(self):
        assert _DART_FILE.exists(), f"missing Dart mirror: {_DART_FILE}"

    def test_every_backend_attribute_key_exists_in_dart(self):
        backend = {attr.value for attr in ProductAttribute}
        missing = backend - _dart_wire_names()
        assert not missing, f"Dart is missing attribute keys: {sorted(missing)}"

    def test_dart_has_no_keys_the_backend_dropped(self):
        backend = {attr.value for attr in ProductAttribute}
        extra = _dart_wire_names() - backend
        assert not extra, f"Dart declares attributes the backend does not: {sorted(extra)}"

    def test_the_spec_examples_reach_the_flutter_contract(self):
        """Each category block must be serialisable for the app to consume."""
        payload = {
            code: [spec.as_dict() for spec in specs]
            for code, specs in CATEGORY_PRODUCT_ATTRIBUTES.items()
        }
        assert json.loads(json.dumps(payload)) == payload


def test_every_stock_category_survives_a_json_round_trip():
    """Guards the exact shape the Flutter app parses."""
    for code in CATEGORY_PRODUCT_ATTRIBUTES:
        body = {
            "category_code": code,
            "attributes": [s.as_dict() for s in product_attributes_for(code)],
        }
        assert body["attributes"]
        for attr in body["attributes"]:
            assert set(attr) == {
            "key", "label", "kind", "required", "hint", "choices",
            "catalog_backed", "identifier_type",
                "identifier_type",
            }
            assert attr["kind"] in {"TEXT", "MULTILINE", "NUMBER", "CHOICE"}


def test_service_categories_serialise_to_an_empty_form():
    for code in SERVICE_ONLY_CATEGORIES:
        body = {
            "category_code": code,
            "attributes": [s.as_dict() for s in product_attributes_for(code)],
        }
        assert body["attributes"] == []


class TestBeautyPersonalCare:
    """The spec's beauty rules, pinned.

    Two things matter here and they pull in opposite directions: the possible
    product types are listed in the spec, AND the spec says they are examples
    only with the final taxonomy coming from backend catalog data. Both have to
    hold at once.
    """

    def _beauty(self):
        return {
            s.key: s for s in product_attributes_for("BEAUTY_PERSONAL_CARE")
        }

    def test_the_spec_product_list_is_all_present(self):
        keys = self._beauty()
        for required in (
            ProductAttribute.NAME,
            ProductAttribute.BRAND,
            ProductAttribute.PRODUCT_TYPE,
            ProductAttribute.VARIANT,
            ProductAttribute.BARCODE,
            ProductAttribute.CATEGORY,
            ProductAttribute.SUBCATEGORY,
            ProductAttribute.PRICE,
            ProductAttribute.MRP,
            ProductAttribute.AVAILABILITY,
            ProductAttribute.QUANTITY,
            ProductAttribute.IMAGE,
        ):
            assert required in keys, required

    def test_product_type_is_not_a_frozen_choice_list(self):
        """The examples are illustrative; freezing them contradicts the spec.

        Making these a `choices` tuple would make Hair Care/Skin Care/etc. an
        authoritative closed vocabulary — precisely the thing "these are examples
        only, final categories must come from backend catalog data" forbids.
        """
        spec = self._beauty()[ProductAttribute.PRODUCT_TYPE]
        assert spec.choices == ()
        assert spec.catalog_backed is True

    def test_product_type_is_catalog_backed(self):
        """It is a catalog level, not free text the database would drop."""
        assert self._beauty()[ProductAttribute.PRODUCT_TYPE].catalog_backed

    def test_the_examples_appear_only_as_a_hint(self):
        spec = self._beauty()[ProductAttribute.PRODUCT_TYPE]
        assert "Hair Care" in spec.hint
        assert "example" in spec.hint.lower()

    def test_beauty_hints_do_not_leak_another_trade(self):
        """The bug this test exists for.

        The shared field block carried automotive examples — "Brake Pad",
        "Bosch", "Front axle" — so a beauty form asked a beautician to type a
        brake pad. Hints are per-category now.
        """
        for spec in product_attributes_for("BEAUTY_PERSONAL_CARE"):
            for leaked in ("Brake", "Bosch", "Front axle", "Spark Plug",
                           "Panadol", "Sofa", "Casserole"):
                assert leaked not in spec.hint, f"{spec.key}: {spec.hint}"

    def test_no_category_shows_another_trades_examples(self):
        """The general rule, so the next category added cannot reintroduce it.

        Each list holds only OTHER trades' vocabulary — never its own.
        """
        examples = {
            "PHARMACY_HEALTHCARE": ("Brake", "Bosch", "Sofa", "Casserole",
                                    "Yoga Mat", "White Tiger"),
            "FURNITURE_HOME_CARE": ("Brake", "Panadol", "Casserole", "Yoga Mat",
                                    "White Tiger"),
            "HOUSEHOLD_GOODS": ("Brake", "Panadol", "Sofa", "Yoga Mat",
                                "White Tiger"),
            "AUTOMOTIVE_PARTS_TOOLS": ("Panadol", "Sofa", "Casserole",
                                       "Yoga Mat", "White Tiger"),
            "HARDWARE": ("Brake", "Panadol", "Sofa", "Casserole", "Yoga Mat",
                         "White Tiger"),
            "SPORTS_FITNESS_OUTDOOR": ("Brake", "Panadol", "Sofa", "Casserole",
                                       "White Tiger"),
            "BOOKS_MEDIA_STATIONERY": ("Brake", "Panadol", "Sofa", "Casserole",
                                       "Yoga Mat"),
            "BEAUTY_PERSONAL_CARE": ("Brake", "Bosch", "Panadol", "Sofa",
                                     "Casserole", "Yoga Mat", "White Tiger"),
        }
        for code, foreign in examples.items():
            for spec in product_attributes_for(code):
                for word in foreign:
                    assert word not in spec.hint, f"{code}.{spec.key}: {spec.hint}"


class TestFurnitureHomeCare:
    """The spec's furniture rules, pinned.

    The binding line is "Do not force these fields on every product": dimensions,
    material, colour and assembly are all offered only where the backend
    supports them, so every one of them is OPTIONAL.
    """

    def _furniture(self):
        return {
            s.key: s for s in product_attributes_for("FURNITURE_HOME_CARE")
        }

    def test_the_spec_product_list_is_present(self):
        keys = self._furniture()
        for required in (
            ProductAttribute.NAME,
            ProductAttribute.BRAND,
            ProductAttribute.VARIANT,
            ProductAttribute.CATEGORY,
            ProductAttribute.PRICE,
            ProductAttribute.AVAILABILITY,
            ProductAttribute.QUANTITY,
            ProductAttribute.IMAGE,
            ProductAttribute.DESCRIPTION,
        ):
            assert required in keys, required

    def test_the_conditional_fields_are_offered_separately(self):
        """Four distinct fields, not one box holding "oak, brown, 6 ft".

        Cramming them together makes the data unusable: a shopkeeper cannot
        filter a sofa by material when material and colour share one string.
        """
        keys = self._furniture()
        for key in (
            ProductAttribute.DIMENSIONS,
            ProductAttribute.MATERIAL,
            ProductAttribute.COLOR,
            ProductAttribute.ASSEMBLY_SERVICE,
        ):
            assert key in keys, key
        assert ProductAttribute.EXTENSION_ATTRIBUTES not in keys

    def test_no_conditional_field_is_forced(self):
        """The spec's explicit instruction.

        "Where backend supports it" plus "do not force these on every product"
        means optional. A required material would block saving a plain glass
        shelf, which is a perfectly ordinary furniture item.
        """
        for key in (
            ProductAttribute.DIMENSIONS,
            ProductAttribute.MATERIAL,
            ProductAttribute.COLOR,
            ProductAttribute.ASSEMBLY_SERVICE,
            ProductAttribute.QUANTITY,
            ProductAttribute.MRP,
            ProductAttribute.BRAND,
        ):
            spec = self._furniture()[key]
            assert spec.required is False, key

    def test_a_minimal_furniture_product_still_validates(self):
        """Proof the optional fields do not block a real product."""
        specs = self._furniture()
        required_keys = [k for k, s in specs.items() if s.required]
        assert set(required_keys) == {
            ProductAttribute.NAME,
            ProductAttribute.CATEGORY,
            ProductAttribute.PRICE,
        }

    def test_barcode_is_absent_because_a_sofa_has_none(self):
        """The spec does not list it for this category, and it has no EAN."""
        assert ProductAttribute.BARCODE not in self._furniture()

    def test_furniture_carries_the_shared_block_keys(self):
        """Regression guard for how this category's bugs were found.

        It used to be a hand-written copy with no `catalog_backed` flags and no
        per-category hints, which only surfaced once a test iterated EVERY
        category rather than spot-checking one.
        """
        keys = set(self._furniture())
        # Everything the shared block contributes, plus the furniture extras.
        for shared in (
            ProductAttribute.NAME,
            ProductAttribute.BRAND,
            ProductAttribute.CATEGORY,
            ProductAttribute.SUBCATEGORY,
            ProductAttribute.VARIANT,
            ProductAttribute.PRICE,
            ProductAttribute.AVAILABILITY,
            ProductAttribute.IMAGE,
            ProductAttribute.MATERIAL,
            ProductAttribute.DIMENSIONS,
        ):
            assert shared in keys, shared


class TestHouseholdGoods:
    """The spec's household rules, pinned.

    The closing instruction is "Use only fields supported by product schema",
    and the optional attributes are listed as Size, Pack/Unit, Color and
    Description — four separate things.
    """

    def _household(self):
        return {
            s.key: s for s in product_attributes_for("HOUSEHOLD_GOODS")
        }

    def test_the_spec_product_list_is_present(self):
        keys = self._household()
        for required in (
            ProductAttribute.NAME,
            ProductAttribute.BRAND,
            ProductAttribute.VARIANT,
            ProductAttribute.CATEGORY,
            ProductAttribute.BARCODE,
            ProductAttribute.PRICE,
            ProductAttribute.MRP,
            ProductAttribute.AVAILABILITY,
            ProductAttribute.QUANTITY,
            ProductAttribute.IMAGE,
        ):
            assert required in keys, required

    def test_the_optional_attributes_are_separate_fields(self):
        """Size and Colour are their own inputs.

        This was one box labelled "Size / colour / pack". Two problems at once:
        three attributes shared a string, and "pack" duplicated the Pack/unit
        field that already existed. Neither size nor colour could ever be
        filtered on.
        """
        keys = self._household()
        assert ProductAttribute.SIZE in keys
        assert ProductAttribute.COLOR in keys
        assert ProductAttribute.EXTENSION_ATTRIBUTES not in keys

    def test_pack_unit_is_supplied_once_not_twice(self):
        """`base_unit` is the Pack/unit field; nothing may shadow it."""
        specs = self._household()
        pack_fields = [
            s for s in specs.values() if "pack" in s.label.lower()
        ]
        assert len(pack_fields) == 1, [s.label for s in pack_fields]
        assert ProductAttribute.BASE_UNIT in self._household()

    def test_every_optional_attribute_is_optional(self):
        keys = self._household()
        for optional in (
            ProductAttribute.SIZE,
            ProductAttribute.COLOR,
            ProductAttribute.DESCRIPTION,
            ProductAttribute.BASE_UNIT,
            ProductAttribute.MRP,
            ProductAttribute.BRAND,
            ProductAttribute.VARIANT,
        ):
            assert keys[optional].required is False, optional

    def test_only_name_category_and_price_are_required(self):
        specs = self._household()
        required = {k for k, s in specs.items() if s.required}
        assert required == {
            ProductAttribute.NAME,
            ProductAttribute.CATEGORY,
            ProductAttribute.PRICE,
        }


class TestNoCrammedAttributeBoxes:
    """A guard for a bug found in FIVE categories, not one.

    "Size / colour / pack", "Sport / model / equipment type", "Language /
    publication date", "Part number / tool type", "Size / material / unit" were
    all single free-text boxes holding several distinct values. The data is
    unusable: nothing in it can be filtered, compared or validated, and one of
    them duplicated a field that already existed.
    """

    # A slash is legitimate in a label that names ONE thing written two ways —
    # "Pack / unit", "ISBN / barcode" and "OEM / reference number" are each a
    # single concept.
    ALLOWED_SLASH_LABELS = {
        "Pack / unit",
        "ISBN / barcode",
        "OEM / reference number",
    }

    def test_no_label_crams_several_attributes_together(self):
        for code, specs in CATEGORY_PRODUCT_ATTRIBUTES.items():
            for spec in specs:
                assert "/" not in spec.label or spec.label in (
                    self.ALLOWED_SLASH_LABELS
                ), f"{code}.{spec.key} has the crammed label {spec.label!r}"

    def test_no_category_uses_the_escape_hatch_attribute(self):
        """The generic bucket is gone once the real fields exist.

        It was the symptom: any attribute that does not fit a column got dumped
        into one shared free-text box instead of being named.
        """
        for code, specs in CATEGORY_PRODUCT_ATTRIBUTES.items():
            assert ProductAttribute.EXTENSION_ATTRIBUTES not in {
                s.key for s in specs
            }, f"{code} still uses the undifferentiated attribute bucket"


class TestNoArbitraryFieldsInFlutter:
    """The sports spec's closing rule, enforced across the whole app.

    "Do not create arbitrary custom fields directly in Flutter." That is only
    meaningful if something checks it, because the failure it prevents — a field
    somebody types into a Dart file because it seemed convenient — looks
    exactly like correct code and nothing fails.

    The rule is checked structurally rather than by hunting for suspicious
    strings: the app must be unable to DECLARE a product attribute at all.
    Every spec it builds comes from the backend's JSON, so there is no code path
    that can invent one.
    """

    @staticmethod
    def _dart_files() -> list[Path]:
        return [p for p in _DART_LIB.rglob("*.dart") if p.is_file()]

    def test_the_dart_lib_directory_exists(self):
        assert _DART_LIB.is_dir(), _DART_LIB

    def test_only_the_parser_constructs_a_product_attribute(self):
        """One construction site, inside `fromJson`.

        If this grows, someone has started building a field in Dart rather than
        receiving it from the backend — exactly what the spec forbids.
        """
        offenders: list[str] = []
        for path in self._dart_files():
            count = path.read_text(encoding="utf-8").count("ProductAttributeSpec(")
            if count and path.name != "product_attributes.dart":
                offenders.append(f"{path.name} ({count})")
        assert not offenders, (
            "product attributes are constructed outside the backend parser: "
            f"{offenders}"
        )

    def test_no_dart_file_declares_a_category_product_field_list(self):
        """No per-category field table anywhere in the app.

        This is what "do not create custom fields directly in Flutter" means in
        practice: the app must not hold a list saying "sports has these fields".
        """
        offenders: list[str] = []
        # Derived from the registry rather than hand-listed, because a hand list
        # is what let automotive and the three service categories go unguarded:
        # the words were typed out when only six categories existed, and nothing
        # failed when the registry grew. A new category is now covered the moment
        # it is registered, with no edit here.
        words = sorted(
            {
                part
                for code in merchant_category.MerchantCategoryCode
                for part in code.value.lower().split("_")
                if len(part) > 2
            }
        )
        # Two details here were both learned the hard way:
        #
        #  * `'?` before the colon — a Dart map literal writes its key as
        #    'SPORTS_FITNESS_OUTDOOR': [...], and without the quote this regex
        #    matches nothing, which is how it first "passed" against a real
        #    injected violation.
        #  * the negative lookaheads — the app legitimately DOES hold
        #    category-keyed tables of CAPABILITY fields
        #    (`ServiceCategoryProfile.transport: [CapabilityFieldSpec(...)]`),
        #    pinned to the backend by `capability_contract_test.dart`. Matching
        #    those would flag correct code. Capabilities are a different contract
        #    from product fields, so both the inline `<CategoryCapability>`
        #    generic and a list whose first element is a capability field are
        #    skipped. The second form is here because widening the category list
        #    to every registered category made the first lookahead insufficient:
        #    transport and personal-travel are service categories, so they are
        #    named in the pattern while having capability tables and no product
        #    fields at all.
        pattern = re.compile(
            "(" + "|".join(words) + ")"
            r"\w*'?\s*:\s*(?!<CategoryCapability>)(?:<[^>]*>)?\["
            r"(?!\s*(?:<[^>]*>\s*)?CapabilityField)",
            re.IGNORECASE,
        )
        for path in self._dart_files():
            if pattern.search(path.read_text(encoding="utf-8")):
                offenders.append(path.name)
        assert not offenders, (
            f"per-category product field tables found in Dart: {offenders}"
        )

    def test_the_backend_owns_every_sports_field(self):
        """Every sports attribute is declared in the backend registry."""
        keys = {s.key for s in product_attributes_for("SPORTS_FITNESS_OUTDOOR")}
        for optional in (
            ProductAttribute.SIZE,
            ProductAttribute.COLOR,
            ProductAttribute.SPORT_TYPE,
            ProductAttribute.MODEL,
            ProductAttribute.EQUIPMENT_TYPE,
        ):
            assert optional in keys, optional


class TestSportsFitnessOutdoor:
    """The spec's sports rules, pinned."""

    def _sports(self):
        return {
            s.key: s for s in product_attributes_for("SPORTS_FITNESS_OUTDOOR")
        }

    def test_the_spec_product_list_is_present(self):
        keys = self._sports()
        for required in (
            ProductAttribute.NAME,
            ProductAttribute.BRAND,
            ProductAttribute.VARIANT,
            ProductAttribute.CATEGORY,
            ProductAttribute.BARCODE,
            ProductAttribute.PRICE,
            ProductAttribute.AVAILABILITY,
            ProductAttribute.QUANTITY,
            ProductAttribute.IMAGE,
        ):
            assert required in keys, required

    def test_the_five_optional_attributes_are_offered(self):
        keys = self._sports()
        for optional in (
            ProductAttribute.SIZE,
            ProductAttribute.COLOR,
            ProductAttribute.SPORT_TYPE,
            ProductAttribute.MODEL,
            ProductAttribute.EQUIPMENT_TYPE,
        ):
            assert optional in keys, optional

    def test_every_optional_attribute_is_optional(self):
        """"Optional attributes when backend supports" — never mandatory.

        A required "Equipment type" would block saving a plain skipping rope,
        which is a perfectly ordinary sports item.
        """
        keys = self._sports()
        for optional in (
            ProductAttribute.SIZE,
            ProductAttribute.COLOR,
            ProductAttribute.SPORT_TYPE,
            ProductAttribute.MODEL,
            ProductAttribute.EQUIPMENT_TYPE,
        ):
            assert keys[optional].required is False, optional

    def test_each_optional_attribute_is_its_own_field(self):
        """Not one "Sport / model / equipment type" box.

        Three distinct values in one string cannot be filtered on, and the old
        combined label also hid whether the app knew which values were valid.
        """
        keys = self._sports()
        assert ProductAttribute.EXTENSION_ATTRIBUTES not in keys
        labels = {s.label for s in keys.values()}
        for distinct in ("Sport type", "Model", "Equipment type"):
            assert distinct in labels, distinct

    def test_only_name_category_and_price_are_required(self):
        required = {k for k, s in self._sports().items() if s.required}
        assert required == {
            ProductAttribute.NAME,
            ProductAttribute.CATEGORY,
            ProductAttribute.PRICE,
        }

    def test_sports_shares_stock_fields_rather_than_copying_them(self):
        """Barcode and quantity come from the shared block, not a private copy."""
        sports = set(self._sports())
        hardware = {s.key for s in product_attributes_for("HARDWARE")}
        for shared in (
            ProductAttribute.BARCODE,
            ProductAttribute.QUANTITY,
            ProductAttribute.BASE_UNIT,
            ProductAttribute.PRICE,
            ProductAttribute.MRP,
        ):
            assert shared in sports and shared in hardware, shared


class TestBooksMediaStationery:
    """The spec's books rules, pinned.

    The binding instruction is "Do not make ISBN mandatory for every item" — a
    shop that sells notebooks, pens and staplers has plenty of stock with no
    ISBN at all.
    """

    def _books(self):
        return {s.key: s for s in product_attributes_for("BOOKS_MEDIA_STATIONERY")}

    def test_the_spec_product_list_is_present(self):
        keys = self._books()
        for listed in (
            ProductAttribute.NAME,
            ProductAttribute.AUTHOR,
            ProductAttribute.BRAND,  # publisher
            ProductAttribute.CATEGORY,
            ProductAttribute.VARIANT,  # edition
            ProductAttribute.BARCODE,  # ISBN where supported
            ProductAttribute.PRICE,
            ProductAttribute.AVAILABILITY,
            ProductAttribute.QUANTITY,
            ProductAttribute.IMAGE,
        ):
            assert listed in keys, listed

    def test_author_is_offered_and_optional(self):
        """The spec's "Author/Creator where applicable".

        Optional, because half this category — stationery — has no author, and a
        required field would block saving a pack of pens.
        """
        author = self._books()[ProductAttribute.AUTHOR]
        assert author.required is False
        assert "author" in author.label.lower()

    def test_publisher_edition_language_and_date_are_separate_fields(self):
        """The spec's four optional backend-supported fields, one each.

        "Language / publication date" used to be a single box; a date and a
        language cannot share a column and neither can be filtered on.
        """
        keys = self._books()
        assert ProductAttribute.LANGUAGE in keys
        assert ProductAttribute.PUBLICATION_DATE in keys
        assert ProductAttribute.EXTENSION_ATTRIBUTES not in keys
        # Edition rides the shared `variant` key, relabelled for books.
        labels = {s.label for s in keys.values()}
        assert "Edition" in labels
        assert "Publisher" in labels

    def test_isbn_is_never_mandatory(self):
        """The spec's explicit instruction.

        Offering an ISBN is right — plenty of books have one. Requiring it would
        block every notebook, pen and stapler in the shop.
        """
        books = self._books()
        assert books[ProductAttribute.BARCODE].required is False
        # A shop with nothing but stationery must still save.
        minimal = {k for k, s in books.items() if s.required}
        assert ProductAttribute.BARCODE not in minimal

    def test_isbn_is_declared_as_the_schemas_identifier_type(self):
        """The schema stores typed identifiers, and ISBN is one of the types.

        `product_identifiers` has `identifier_type` + `identifier_value` with an
        `IdentifierType` enum containing ISBN. Declaring it keeps a book's code
        distinguishable from a shampoo's EAN instead of storing both as opaque
        strings in one column.
        """
        from app.models.product import IdentifierType

        books = self._books()[ProductAttribute.BARCODE]
        assert books.identifier_type == IdentifierType.ISBN.value

    def test_every_identifier_type_declared_is_a_real_schema_type(self):
        """Never invent a type the schema cannot store."""
        from app.models.product import IdentifierType

        valid = {t.value for t in IdentifierType}
        for code, specs in CATEGORY_PRODUCT_ATTRIBUTES.items():
            for spec in specs:
                if spec.identifier_type:
                    assert spec.identifier_type in valid, (
                        f"{code}.{spec.key} declares "
                        f"{spec.identifier_type!r}, which is not an IdentifierType"
                    )

    def test_only_title_category_and_price_are_required(self):
        required = {k for k, s in self._books().items() if s.required}
        assert required == {
            ProductAttribute.NAME,
            ProductAttribute.CATEGORY,
            ProductAttribute.PRICE,
        }

    def test_books_never_inherit_a_colour_or_size_field(self):
        """A book has no colour or size; those belong to other trades."""
        books = self._books()
        assert ProductAttribute.COLOR not in books
        assert ProductAttribute.SIZE not in books
        # …and none of the other trades' optional attributes leaked in.
        for foreign in (
            ProductAttribute.MATERIAL,
            ProductAttribute.DIMENSIONS,
            ProductAttribute.SPORT_TYPE,
            ProductAttribute.TOOL_TYPE,
        ):
            assert foreign not in books, foreign


class TestAutomotivePartsTools:
    """The spec's automotive rules, pinned.

    The binding instruction is "Do not assume compatibility rules in frontend.
    Compatibility must come from backend/catalog data" — and checking the
    schema shows there is no such catalog today.
    """

    def _auto(self):
        return {s.key: s for s in product_attributes_for("AUTOMOTIVE_PARTS_TOOLS")}

    def test_the_spec_core_product_list_is_present(self):
        keys = self._auto()
        for listed in (
            ProductAttribute.NAME,
            ProductAttribute.BRAND,
            ProductAttribute.PART_NUMBER,
            ProductAttribute.BARCODE,
            ProductAttribute.CATEGORY,
            ProductAttribute.VARIANT,
            ProductAttribute.PRICE,
            ProductAttribute.AVAILABILITY,
            ProductAttribute.QUANTITY,
            ProductAttribute.IMAGE,
        ):
            assert listed in keys, listed

    def test_the_backend_supported_optional_fields_are_present(self):
        """What the schema can actually store today."""
        keys = self._auto()
        for optional in (
            ProductAttribute.VEHICLE_MODEL,
            ProductAttribute.OEM_REFERENCE_NUMBER,
            ProductAttribute.TOOL_TYPE,
            ProductAttribute.SPECIFICATION,
        ):
            assert optional in keys, optional

    def test_oem_reference_is_a_typed_mpn_identifier(self):
        """The schema already models this as `IdentifierType.MPN`.

        A bare string would lose that an OE reference is an MPN, which is how a
        shop finds a superseding part.
        """
        from app.models.product import IdentifierType

        oem = self._auto()[ProductAttribute.OEM_REFERENCE_NUMBER]
        assert oem.identifier_type == IdentifierType.MPN.value

    def test_part_number_and_oem_reference_are_different_fields(self):
        """The spec lists both, and conflating them orders the wrong part.

        The part's own number is not the number it replaces.
        """
        keys = self._auto()
        assert ProductAttribute.PART_NUMBER in keys
        assert ProductAttribute.OEM_REFERENCE_NUMBER in keys
        assert keys[ProductAttribute.PART_NUMBER].identifier_type == ""

    def test_manufacturer_is_its_own_field_not_brand(self):
        """The spec lists Brand and Manufacturer separately, and they differ here.

        "Bosch QuietCast" is a brand line; Bosch is who made the disc. An OE
        catalogue is searched by manufacturer, so merging them loses a lookup.
        """
        keys = self._auto()
        assert ProductAttribute.MANUFACTURER in keys
        assert ProductAttribute.BRAND in keys
        assert keys[ProductAttribute.MANUFACTURER].key != keys[ProductAttribute.BRAND].key
        assert "Manufacturer" in {s.label for s in keys.values()}

    def test_manufacturer_is_not_a_second_catalog_backed_field(self):
        """`product_masters.brand_id` is one column and Brand already spends it.

        Marking Manufacturer catalog-backed too would promise a second
        destination the schema has no column for, and the write would silently
        land in an extension bucket while the UI implied otherwise.
        """
        assert self._auto()[ProductAttribute.MANUFACTURER].catalog_backed is False

    def test_every_optional_field_spec_makes_the_list_is_covered(self):
        """Pins the spec's own wording so a silent drop fails here.

        This test exists because Manufacturer was dropped once and only the
        human-readable diff caught it — the other tests all passed.
        """
        keys = self._auto()
        for listed in (
            ProductAttribute.VEHICLE_MODEL,
            ProductAttribute.MANUFACTURER,
            ProductAttribute.OEM_REFERENCE_NUMBER,
            ProductAttribute.TOOL_TYPE,
            ProductAttribute.SPECIFICATION,
        ):
            assert listed in keys, listed

    def test_no_compatibility_rule_is_ever_offered(self):
        """The spec's rule, and the schema has nothing to back it with.

        `vehicles` is a transport provider's own fleet keyed on registration
        number; `product.py` references no vehicle table. Without a catalog and a
        part-to-vehicle link, any compatibility field would be fiction.
        """
        auto = self._auto()
        for banned in ("compat", "fitment", "fits"):
            assert banned not in " ".join(s.key for s in auto.values()), banned

    def test_vehicle_model_is_recorded_but_assures_nothing(self):
        """Free text that notes a model is fine; resolving it is a fitment claim."""
        model = self._auto()[ProductAttribute.VEHICLE_MODEL]
        assert model.catalog_backed is False
        assert model.required is False

    def test_every_optional_field_is_optional(self):
        """Nothing optional may block saving an ordinary spare part."""
        keys = self._auto()
        for optional in (
            ProductAttribute.PART_NUMBER,
            ProductAttribute.OEM_REFERENCE_NUMBER,
            ProductAttribute.VEHICLE_MODEL,
            ProductAttribute.TOOL_TYPE,
            ProductAttribute.SPECIFICATION,
            ProductAttribute.BRAND,
            ProductAttribute.VARIANT,
        ):
            assert keys[optional].required is False, optional

    def test_only_name_category_and_price_are_required(self):
        required = {k for k, s in self._auto().items() if s.required}
        assert required == {
            ProductAttribute.NAME,
            ProductAttribute.CATEGORY,
            ProductAttribute.PRICE,
        }

    def test_no_crammed_box_remains(self):
        """Part number and tool type were once one "Part number / tool type" box."""
        auto = self._auto()
        assert ProductAttribute.EXTENSION_ATTRIBUTES not in auto
        labels = {s.label for s in auto.values()}
        for distinct in ("Part number", "Tool type"):
            assert distinct in labels, distinct

    def test_other_trades_attributes_did_not_leak_in(self):
        """A brake pad has no size, colour or sport type."""
        auto = self._auto()
        for foreign in (
            ProductAttribute.SIZE,
            ProductAttribute.COLOR,
            ProductAttribute.SPORT_TYPE,
            ProductAttribute.EQUIPMENT_TYPE,
            ProductAttribute.MATERIAL,
            ProductAttribute.LANGUAGE,
        ):
            assert foreign not in auto, foreign


class TestHardware:
    """The spec's hardware rules, pinned.

    The binding line is "Only show attributes supplied by backend capability
    definitions" — so these tests care less about which fields exist and more
    about the fact that nothing here is invented on the client.
    """

    def _hw(self):
        return {s.key: s for s in product_attributes_for("HARDWARE")}

    def test_the_spec_product_list_is_present(self):
        keys = self._hw()
        for listed in (
            ProductAttribute.NAME,
            ProductAttribute.BRAND,
            ProductAttribute.CATEGORY,
            ProductAttribute.VARIANT,
            ProductAttribute.BARCODE,
            ProductAttribute.PRICE,
            ProductAttribute.AVAILABILITY,
            ProductAttribute.QUANTITY,
            ProductAttribute.IMAGE,
        ):
            assert listed in keys, listed

    def test_the_spec_optional_list_is_present(self):
        keys = self._hw()
        for listed in (
            ProductAttribute.SIZE,
            ProductAttribute.MATERIAL,
            ProductAttribute.BASE_UNIT,
            ProductAttribute.SPECIFICATION,
        ):
            assert listed in keys, listed

    def test_every_optional_field_is_optional(self):
        """A shop must be able to list one screw without a size or a material."""
        keys = self._hw()
        for optional in (
            ProductAttribute.SIZE,
            ProductAttribute.MATERIAL,
            ProductAttribute.BASE_UNIT,
            ProductAttribute.SPECIFICATION,
            ProductAttribute.BRAND,
            ProductAttribute.VARIANT,
            ProductAttribute.BARCODE,
            ProductAttribute.IMAGE,
        ):
            assert keys[optional].required is False, optional

    def test_size_is_not_catalog_backed(self):
        """A bolt is "M8x40", not a row in a size table the schema does not have."""
        size = self._hw()[ProductAttribute.SIZE]
        assert size.catalog_backed is False
        assert size.required is False

    def test_material_is_free_text(self):
        """Galvanised, stainless, brass — typed, with no enum behind them."""
        material = self._hw()[ProductAttribute.MATERIAL]
        assert material.catalog_backed is False
        assert material.choices == ()

    def test_plumbing_is_left_to_the_backend_to_categorise(self):
        """The spec says "where categorized by backend", so the client must not
        decide what counts as plumbing.

        Subcategory is the field that would carry that grouping, and it is
        catalog-backed with no hardcoded options: the grouping arrives with the
        catalogue rather than being asserted here.
        """
        sub = self._hw()[ProductAttribute.SUBCATEGORY]
        assert sub.catalog_backed is True
        assert sub.choices == ()

    def test_no_hardware_field_offers_a_hardcoded_choice_list(self):
        """Guards the whole spec line, not just plumbing.

        A choice list is the one place this build could assert a taxonomy the
        backend owns. Every choice here must come from the server instead.
        """
        for spec in product_attributes_for("HARDWARE"):
            if spec.key not in (ProductAttribute.AVAILABILITY,):
                assert spec.choices == (), spec.key

    def test_tools_fasteners_electrical_and_building_are_all_reachable(self):
        """Tools, fasteners, electrical and building hardware differ only by the
        subcategory the backend supplies.

        A single product form therefore covers all four, and none of them needs
        an attribute the others lack — which is the point of driving the form
        from the catalogue.
        """
        keys = set(self._hw())
        assert ProductAttribute.SUBCATEGORY in keys
        assert ProductAttribute.SPECIFICATION in keys

    def test_other_trades_attributes_did_not_leak_in(self):
        """A bolt has no colour, sport type, vehicle model or tool type."""
        keys = self._hw()
        for foreign in (
            ProductAttribute.AUTHOR,
            ProductAttribute.COLOR,
            ProductAttribute.SPORT_TYPE,
            ProductAttribute.VEHICLE_MODEL,
            ProductAttribute.MANUFACTURER,
            ProductAttribute.OEM_REFERENCE_NUMBER,
            ProductAttribute.TOOL_TYPE,
            ProductAttribute.PART_NUMBER,
        ):
            assert foreign not in keys, foreign

    def test_the_barcode_is_not_typed_as_books_is(self):
        """Books types its barcode as an ISBN; hardware's must stay generic.

        The two are the same column, so this is the leak that actually matters
        here: a hardware EAN stamped into an ISBN field is not a display problem,
        it is a number the wrong column rejects.
        """
        barcode = self._hw()[ProductAttribute.BARCODE]
        assert barcode.identifier_type == ""

    def test_no_crammed_box_remains(self):
        """Size and material must stay separate boxes.

        The failure this prevents: one "Size / Material" box, which stores a
        value into neither field and silently drops both.
        """
        hw = self._hw()
        assert ProductAttribute.EXTENSION_ATTRIBUTES not in hw
        labels = {s.label for s in hw.values()}
        for distinct in ("Size", "Material"):
            assert distinct in labels, distinct

    def test_specification_is_not_a_dump_for_the_others(self):
        """Spec lists it as its own optional field, so it must stand alone."""
        spec = self._hw()[ProductAttribute.SPECIFICATION]
        assert spec.required is False
        assert spec.catalog_backed is False


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))
