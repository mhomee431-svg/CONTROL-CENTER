"""Excel / CSV entry: category + subcategory columns, and the import schema.

The spec lists the columns a shopkeeper may use and then says the rules must
come from a "backend-supported import schema". Two consequences:

  * `Category` / `Subcategory` are actual columns, resolved against the catalog
    the same way a barcode or a variant is — an unknown one is a row error, and
    the import never invents catalog entries.
  * The Column Mapping step has ONE source of truth: `import_schema()`. If the
    sample workbook and the schema could drift, the shopkeeper would fill in a
    column the validator does not read, and every row would fail for a reason
    they cannot see.

Classification is fill-if-empty on the master: a bulk import must not
re-classify a product that another shop has already placed in a catalog.
"""

from types import SimpleNamespace

import pytest

from app.models.product import Category
from app.services import excel_import_service as svc

VALID_BARCODE = "8901234567890"  # EAN-13, correct GS1 check digit

EXCEL_HEADERS = [
    "Barcode", "Product Name", "Brand", "Variant",
    "SKU", "Price", "MRP", "Quantity", "Availability",
]

# The spec's own list, in the order it prints them.
SPEC_COLUMNS = [
    "Product Name", "Brand", "Category", "Subcategory", "Variant",
    "Barcode", "Price", "MRP", "Stock", "Availability",
]


class MockQuery:
    """Just enough of a SQLAlchemy query for the helpers under test."""

    def __init__(self, db, model):
        self._db, self._model = db, model

    def filter(self, *args, **kwargs):
        return self

    def all(self):
        return list(self._db.rows.get(self._model, []))

    def first(self):
        rows = self.all()
        return rows[0] if rows else None


class MockDB:
    def __init__(self):
        self.rows = {}
        self.added = []

    def set(self, model, items):
        self.rows[model] = list(items)

    def query(self, model):
        return MockQuery(self, model)

    def add(self, obj):
        self.added.append(obj)

    def add_all(self, objs):
        self.added.extend(objs)

    def flush(self):
        return None


def _root(name="Groceries", cid=3):
    return SimpleNamespace(id=cid, name=name, is_subcategory=False, parent_id=None)


def _sub(name="Snacks", cid=4, parent=3):
    return SimpleNamespace(id=cid, name=name, is_subcategory=True, parent_id=parent)


def _catalog_db(*categories):
    """A MockDB where the barcode resolves to a real master.

    Without this the barcode lookup fails first and the row returns before
    category is ever reached — the category rules would then never be exercised
    and the tests would pass against dead code.
    """
    from app.models.product import ProductIdentifier, ProductMaster

    db = MockDB()
    master = SimpleNamespace(id=5, name="Basmati Rice 1kg", variants=[])
    db.set(ProductMaster, [master])
    db.set(
        ProductIdentifier,
        [SimpleNamespace(identifier_value=VALID_BARCODE, product_master_id=5,
                          is_active=True)],
    )
    db.set(Category, list(categories))
    return db


def _values(**kw):
    """A `values` dict exactly as `create_import` builds it before validating."""
    base = {field: None for field in svc.FIELD_ALIASES}
    base.update(
        {
            "barcode": VALID_BARCODE,
            "product_name": "Basmati Rice 1kg",
            "price": 120.0,
            "mrp": 150.0,
            "quantity": 50,
        }
    )
    base.update(kw)
    return base


class TestCategoryAndSubcategoryColumns:
    def test_a_category_column_is_read(self):
        db = _catalog_db(_root())
        clean, errors = svc.validate_row(db, _values(category="Groceries"), set())
        assert errors == []
        assert clean["category"] == "Groceries"
        assert clean["category_id"] == 3

    def test_an_unknown_category_is_a_row_error(self):
        """The import never invents catalog entries."""
        db = _catalog_db(_root())
        _clean, errors = svc.validate_row(db, _values(category="Spacefood"), set())
        assert errors[0]["code"] == "UNKNOWN_CATEGORY"
        assert errors[0]["field"] == "category"

    def test_the_header_word_is_recognised(self):
        """Whatever the shopkeeper calls the column, the alias table reads it."""
        assert "category" in svc.FIELD_ALIASES
        assert "sub category" in svc.FIELD_ALIASES["subcategory"]
        mapped = svc.map_headers(["Dept", "Sub-category"])
        assert set(mapped) == {"category", "subcategory"}

    def test_a_subcategory_is_scoped_to_its_parent(self):
        db = _catalog_db(_root(), _sub())
        clean, errors = svc.validate_row(
            db, _values(category="Groceries", subcategory="Snacks"), set()
        )
        assert errors == []
        assert clean["subcategory_id"] == 4

    def test_a_same_named_subcategory_of_another_parent_is_not_borrowed(self):
        """Two categories can each have a "Snacks"; the sheet's Category decides.

        The wrong parent's row is seeded FIRST, so a lookup that ignored the
        parent would return it and still look correct.
        """
        db = _catalog_db(
            _root(),
            _sub(name="Snacks", cid=5, parent=9),  # another shop's tree
            _sub(name="Snacks", cid=4, parent=3),  # this sheet's category
        )
        clean, errors = svc.validate_row(
            db, _values(category="Groceries", subcategory="Snacks"), set()
        )
        assert errors == []
        assert clean["subcategory_id"] == 4

    def test_a_name_from_another_level_is_rejected(self):
        """A root name offered as a subcategory must not be quietly accepted."""
        db = _catalog_db(_root())
        _clean, errors = svc.validate_row(
            db, _values(category="Groceries", subcategory="Groceries"), set()
        )
        assert errors[0]["code"] == "UNKNOWN_SUBCATEGORY"

    def test_a_subcategory_name_offered_as_a_category_is_rejected(self):
        """The mirror image: a subcategory filed as a top-level category.

        This is the case the parent-scope check cannot catch on its own — there
        is no parent to scope against on a root lookup — so it is the only test
        that actually pins the level rule itself.
        """
        db = _catalog_db(_root(), _sub())
        _clean, errors = svc.validate_row(db, _values(category="Snacks"), set())
        assert errors[0]["code"] == "UNKNOWN_CATEGORY"
        assert errors[0]["field"] == "category"


class TestClassificationNeverOverwritesAnotherShop:
    def test_an_unclassified_master_is_classified(self):
        master = SimpleNamespace(
            id=5, category_id=None, subcategory_id=None, brand_id=None
        )
        svc._apply_catalog_classification(
            MockDB(), master, {"category_id": 3, "subcategory_id": 4}
        )
        assert master.category_id == 3
        assert master.subcategory_id == 4

    def test_an_existing_classification_survives_the_import(self):
        """The master is shared: this shop's sheet must not re-file it."""
        master = SimpleNamespace(id=5, category_id=9, subcategory_id=9, brand_id=None)
        svc._apply_catalog_classification(
            MockDB(), master, {"category_id": 3, "subcategory_id": 4}
        )
        assert master.category_id == 9
        assert master.subcategory_id == 9

    def test_a_brand_the_catalog_does_not_know_is_left_alone(self):
        """Unknown brands must not error — the sample sheet names them too."""
        master = SimpleNamespace(id=5, category_id=None, subcategory_id=None, brand_id=None)
        svc._apply_catalog_classification(MockDB(), master, {"brand_id": None})
        assert master.brand_id is None

    def test_a_known_brand_is_applied_once(self):
        master = SimpleNamespace(id=5, category_id=None, subcategory_id=None, brand_id=None)
        svc._apply_catalog_classification(MockDB(), master, {"brand_id": 12})
        svc._apply_catalog_classification(MockDB(), master, {"brand_id": 99})
        assert master.brand_id == 12


class TestTheImportSchemaForTheMappingStep:
    def test_every_spec_column_is_declared(self):
        labels = {f["label"] for f in svc.import_schema()["fields"]}
        for column in SPEC_COLUMNS:
            assert column in labels, column

    def test_the_schema_and_the_sample_describe_the_same_columns(self):
        """Derived, not restated: a sample column the schema would not read is
        the exact failure this pair of artefacts exists to prevent."""
        sample = set(svc.map_headers(list(svc._SAMPLE_HEADER)))
        for field in svc.import_schema()["fields"]:
            assert field["in_sample"] == (field["name"] in sample), field["name"]

    def test_at_least_one_identifier_is_declared_required(self):
        schema = svc.import_schema()
        assert set(schema["required_any_of"]) == {"Barcode", "SKU", "Product Name"}

    def test_every_field_carries_its_rule(self):
        for field in svc.import_schema()["fields"]:
            assert field["rules"], field["name"]

    def test_the_schema_route_is_declared_before_the_job_route(self):
        """`/inventory-imports/{job_id}` takes an int path param, so a later
        declaration would swallow `schema` as a bad job id (422) instead of
        routing it. The order is load-bearing, not cosmetic."""
        from app.api.routes.inventory_intake import router

        paths = [r.path for r in router.routes]
        schema_at = paths.index("/shopkeeper/inventory-imports/schema")
        job_at = paths.index("/shopkeeper/inventory-imports/{job_id}")
        assert schema_at < job_at

    def test_the_sample_workbook_still_has_valid_rows(self):
        """Adding two columns must not have broken the template."""
        rows = svc.xlsx_lite.read_workbook(svc.build_sample_workbook())
        assert rows[0][-2:] == ["Category", "Subcategory"]
        for row in rows[1:]:
            assert len(row) == len(rows[0])


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))