"""The product-attribute WRITE path, which did not exist before.

`GET /categories/{code}/product-attributes` was already answering with the
fields a category's products carry. Nothing accepted them back: the create and
update schemas had no attribute field, so a shopkeeper could be told to fill in
a part number and had nowhere to send it.

These tests pin the routing decisions rather than the plumbing, because the
plumbing is mechanical and the decisions are where a wrong answer silently loses
data or invents catalog rows.
"""

import pytest

from app.services.product_attribute_writer import plan_attribute_write


class TestUnknownKeysAreRefused:
    def test_a_key_the_category_never_declared_is_rejected(self):
        plan = plan_attribute_write("HARDWARE", {"unicorn_horn": "3"})
        assert plan.attributes == {}
        assert "unicorn_horn" in plan.rejected

    def test_a_field_from_another_trade_is_rejected(self):
        # Colour is a sports/beauty field; a bolt does not have one.
        plan = plan_attribute_write("HARDWARE", {"color": "Red"})
        assert plan.attributes == {}
        assert "color" in plan.rejected

    def test_a_service_category_rejects_everything(self):
        # Restaurants have no product attributes at all, so every key is unknown.
        plan = plan_attribute_write("RESTAURANTS", {"menu_offerings": "Pizza"})
        assert plan.rejected == {
            "menu_offerings": "This field is not part of your category"
        }

    def test_an_unknown_category_rejects_rather_than_accepts(self):
        plan = plan_attribute_write("NOT_A_CATEGORY", {"material": "Brass"})
        assert plan.attributes == {}
        assert "material" in plan.rejected

    def test_the_plan_is_not_ok_when_anything_was_refused(self):
        assert plan_attribute_write("HARDWARE", {"nope": "1"}).ok is False
        assert plan_attribute_write("HARDWARE", {"material": "Brass"}).ok is True


class TestCatalogValuesMustBeIds:
    """The rule that stops two spellings of one catalog row."""

    def test_a_typed_category_name_is_refused(self):
        plan = plan_attribute_write("HARDWARE", {"category": "Tools"})
        assert "category" in plan.rejected
        assert "category_id" in plan.rejected["category"]
        assert plan.attributes == {}

    def test_a_typed_subcategory_name_is_refused(self):
        plan = plan_attribute_write("HARDWARE", {"subcategory": "Fasteners"})
        assert "subcategory_id" in plan.rejected["subcategory"]


class TestColumnRoutedKeys:
    """One value, one home — never both a column and an attribute row."""

    @pytest.mark.parametrize(
        "key,pointer",
        [
            ("name", "name"),
            ("description", "description"),
            ("brand", "brand_name"),
            ("base_unit", "unit"),
            ("price", "price"),
            ("mrp", "mrp"),
            ("quantity", "quantity"),
            ("availability", "is_available"),
            ("image", "image_key"),
            ("barcode", "barcode"),
        ],
    )
    def test_the_key_is_refused_with_a_pointer_to_its_real_field(
        self, key, pointer
    ):
        plan = plan_attribute_write("HARDWARE", {key: "whatever"})
        assert key in plan.rejected, f"{key} should not be stored as an attribute"
        assert pointer in plan.rejected[key]

    def test_the_refusal_explains_rather_than_just_denying(self):
        plan = plan_attribute_write("HARDWARE", {"price": "5"})
        assert plan.rejected["price"].startswith("Send the price")


class TestIdentifierRouting:
    """Typed identifiers go to `product_identifiers`, keeping their type."""

    def test_an_oem_reference_is_stored_as_an_mpn(self):
        plan = plan_attribute_write(
            "AUTOMOTIVE_PARTS_TOOLS", {"oem_reference_number": "ABC-123"}
        )
        assert plan.identifiers == [("MPN", "ABC-123")]
        assert plan.attributes == {}

    def test_a_part_number_stays_plain_text(self):
        # It is not an IdentifierType, so it must not claim to be one.
        plan = plan_attribute_write("AUTOMOTIVE_PARTS_TOOLS", {"part_number": "P-9"})
        assert plan.attributes == {"part_number": "P-9"}
        assert plan.identifiers == []

    def test_an_ordinary_attribute_never_becomes_an_identifier(self):
        plan = plan_attribute_write("HARDWARE", {"material": "Brass"})
        assert plan.identifiers == []


class TestValueCoercion:
    def test_a_blank_value_is_refused_rather_than_stored_empty(self):
        plan = plan_attribute_write("HARDWARE", {"material": "  "})
        assert "material" in plan.rejected
        assert plan.attributes == {}

    def test_surrounding_whitespace_is_trimmed(self):
        plan = plan_attribute_write("HARDWARE", {"material": "  Brass  "})
        assert plan.attributes == {"material": "Brass"}

    def test_an_over_long_value_is_refused_before_the_database_sees_it(self):
        # `product_attribute_values.value` is VARCHAR(255), so this would be a 500
        # rather than a message if it were left to the column.
        plan = plan_attribute_write("HARDWARE", {"material": "x" * 300})
        assert "material" in plan.rejected
        assert "too long" in plan.rejected["material"]

    def test_a_number_sent_as_a_number_is_accepted(self):
        plan = plan_attribute_write("HARDWARE", {"material": "Brass", "size": 42})
        assert plan.attributes["size"] == "42"

    def test_a_boolean_is_not_treated_as_a_value(self):
        plan = plan_attribute_write("HARDWARE", {"material": True})
        assert "material" in plan.rejected

    def test_an_empty_map_produces_an_empty_plan(self):
        plan = plan_attribute_write("HARDWARE", {})
        assert plan.ok and plan.attributes == {} and plan.identifiers == []

    def test_no_map_produces_an_empty_plan(self):
        assert plan_attribute_write("HARDWARE", None).ok


class TestEveryCategoryRoutesItsOwnFields:
    @pytest.mark.parametrize(
        "category,key",
        [
            ("HARDWARE", "material"),
            ("HARDWARE", "size"),
            ("AUTOMOTIVE_PARTS_TOOLS", "vehicle_model"),
            ("AUTOMOTIVE_PARTS_TOOLS", "manufacturer"),
            ("BOOKS_MEDIA_STATIONERY", "author"),
            ("SPORTS_FITNESS_OUTDOOR", "sport_type"),
        ],
    )
    def test_a_declared_field_is_stored(self, category, key):
        plan = plan_attribute_write(category, {key: "value"})
        assert plan.attributes == {key: "value"}, plan.rejected

    @pytest.mark.parametrize(
        "category,key",
        [
            ("HARDWARE", "author"),
            ("BOOKS_MEDIA_STATIONERY", "material"),
            ("SPORTS_FITNESS_OUTDOOR", "vehicle_model"),
            ("BEAUTY_PERSONAL_CARE", "oem_reference_number"),
        ],
    )
    def test_a_foreign_field_is_refused(self, category, key):
        plan = plan_attribute_write(category, {key: "value"})
        assert key in plan.rejected


class TestCatalogBackedWithNoColumn:
    """`product_type` is marked catalog-backed, but no column exists for it."""

    def test_it_is_refused_with_an_honest_reason(self):
        plan = plan_attribute_write("BEAUTY_PERSONAL_CARE", {"product_type": "Shampoo"})
        assert "product_type" in plan.rejected
        assert "no column" in plan.rejected["product_type"]
        assert plan.attributes == {}

    def test_it_is_not_routed_to_the_category_id_hint(self):
        # There is no product_type_id, so pointing at category_id would be wrong.
        plan = plan_attribute_write("BEAUTY_PERSONAL_CARE", {"product_type": "Shampoo"})
        assert "category_id" not in plan.rejected["product_type"]


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))
