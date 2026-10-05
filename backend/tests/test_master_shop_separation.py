"""ProductMaster and shop-specific data must stay SEPARATE.

The spec is blunt about this: "Do not duplicate the product master for every
shop." Two different failures hide behind that one sentence, so this file holds
both kinds of test:

  * Schema  - a `name` / `brand_id` / `category_id` column on the shop-side
    tables would let two shops disagree about one product with nothing to
    arbitrate between them.
  * Behaviour - two shops listing the same product must land on ONE master,
    keep independent price and stock, and one's edits must not touch the other.

A schema test alone passes while the code still builds a master per shop, and a
behaviour test alone passes while the columns drift. Both are needed.
"""

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.models.base import Base
from app.models.pos import (
    POSDevice,
    POSIntegration,
    POSProductMapping,
    POSSyncJob,
    POSSyncLog,
)
from app.models.product import (
    Inventory,
    InventoryMovement,
    Offer,
    OfferProduct,
    OfferStatus,
    OfferType,
    PriceHistory,
    ProductAttribute,
    ProductAttributeValue,
    ProductIdentifier,
    ProductImage,
    ProductMaster,
    ProductVariant,
    ShopProduct,
)
from app.models.shop import Shop, ShopOwner
from app.models.subscription import Subscription, SubscriptionPlan
from app.models.user import User
from app.services import shopkeeper_service

TABLES = [
    POSIntegration.__table__,
    POSDevice.__table__,
    POSSyncJob.__table__,
    POSSyncLog.__table__,
    POSProductMapping.__table__,
    SubscriptionPlan.__table__,
    Subscription.__table__,
    User.__table__,
    Shop.__table__,
    ShopOwner.__table__,
    ProductMaster.__table__,
    ProductImage.__table__,
    ProductAttribute.__table__,
    ProductAttributeValue.__table__,
    ProductIdentifier.__table__,
    ProductVariant.__table__,
    ShopProduct.__table__,
    Inventory.__table__,
    InventoryMovement.__table__,
    PriceHistory.__table__,
    Offer.__table__,
    OfferProduct.__table__,
]


@pytest.fixture()
def db():
    from tests.geo_compat import strip_geo_columns

    strip_geo_columns()
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine, tables=TABLES)
    session = sessionmaker(bind=engine)()
    yield session
    session.close()
    engine.dispose()


def _user(db) -> User:
    user = User(email="owner@example.com", is_active=True)
    db.add(user)
    db.flush()
    return user


def _shop(db, name: str) -> Shop:
    shop = Shop(
        name=name, description="d", status="ACTIVE", latitude=1.0, longitude=2.0
    )
    db.add(shop)
    db.flush()
    return shop


def _access(shop: Shop):
    return shopkeeper_service.ShopAccess(
        shop=shop,
        role_name="owner",
        is_owner=True,
        permissions={"product:create", "product:update"},
    )


def _list_in_shop(db, access, user, **overrides):
    data = {"name": "Parle-G 250g", "price": 10.0, "quantity": 5}
    data.update(overrides)
    shopkeeper_service.create_product(access, db, user, data)
    db.commit()


class TestTheSchemaKeepsTheListsApart:
    """The spec's two lists, asserted as columns rather than as intent."""

    def test_the_master_owns_the_descriptive_fields(self):
        columns = {c.name for c in ProductMaster.__table__.columns}
        for field in ("name", "brand_id", "category_id", "subcategory_id"):
            assert field in columns, field

    def test_the_shop_listing_stores_no_copy_of_them(self):
        """This is "do not duplicate the master" at the column level.

        A `name` on `shop_products` is exactly how two shops start disagreeing
        about one product with nothing to say which is right.
        """
        columns = {c.name for c in ShopProduct.__table__.columns}
        for master_only in (
            "name",
            "description",
            "brand_id",
            "category_id",
            "subcategory_id",
            "base_unit",
            "slug",
        ):
            assert master_only not in columns, (
                f"ShopProduct duplicates the master's {master_only}"
            )

    def test_the_shop_listing_points_at_the_master(self):
        columns = {c.name for c in ShopProduct.__table__.columns}
        assert "product_master_id" in columns

    def test_stock_lives_on_inventory_not_the_listing(self):
        inventory = {c.name for c in Inventory.__table__.columns}
        assert {"quantity", "reserved_quantity", "low_stock_threshold"} <= inventory
        listing = {c.name for c in ShopProduct.__table__.columns}
        assert "quantity" not in listing

    def test_price_lives_on_the_listing_not_the_master(self):
        """One platform-wide price would stop a shop pricing its own goods."""
        listing = {c.name for c in ShopProduct.__table__.columns}
        master = {c.name for c in ProductMaster.__table__.columns}
        assert {"price", "mrp"} <= listing
        assert not ({"price", "mrp"} & master)

    def test_shop_side_fields_never_reach_the_master(self):
        """These belong to the shop, so their absence from the master matters.

        Note `status` is deliberately NOT in this list: the master carries the
        catalogue approval status and the listing carries ACTIVE/DISCONTINUED.
        Same column name, two different questions — a shop going temporarily
        inactive must not un-approve the product platform-wide.
        """
        master = {c.name for c in ProductMaster.__table__.columns}
        for shop_only in ("is_available", "stock_status", "sku", "shop_id"):
            assert shop_only not in master, shop_only

    def test_the_listing_carries_the_shop_side_fields(self):
        listing = {c.name for c in ShopProduct.__table__.columns}
        for shop_only in ("is_available", "stock_status", "sku", "shop_id"):
            assert shop_only in listing, shop_only

    def test_identifiers_and_images_hang_off_the_master(self):
        assert ProductIdentifier.product_master_id is not None
        image_columns = {c.name for c in ProductImage.__table__.columns}
        assert "product_master_id" in image_columns

    def test_variants_hang_off_the_master(self):
        assert ProductVariant.product_master_id is not None

    def test_offers_belong_to_a_shop_not_the_master(self):
        """The spec lists "offer" under shop-specific data, and the schema
        agrees: an offer has `shop_id` and reaches products only through the
        shop's listings (`offer_products.shop_product_id`). There is no
        master column for it to hang off."""
        offer_columns = {c.name for c in Offer.__table__.columns}
        assert "shop_id" in offer_columns
        assert "product_master_id" not in offer_columns
        link_columns = {c.name for c in OfferProduct.__table__.columns}
        assert "shop_product_id" in link_columns
        assert "product_master_id" not in link_columns


class TestTwoShopsShareOneMaster:
    """The behavioural half: no master duplication in actual use."""

    def test_two_shops_listing_it_share_one_master(self, db):
        """The spec's line, checked the only way that means anything."""
        user = _user(db)
        kirana = _shop(db, "Kirana")
        supermarket = _shop(db, "Supermarket")

        _list_in_shop(db, _access(kirana), user)
        _list_in_shop(db, _access(supermarket), user)

        assert db.query(ProductMaster).count() == 1, (
            "the same product was duplicated per shop"
        )
        assert db.query(ShopProduct).count() == 2

    def test_both_listings_point_at_that_same_master(self, db):
        user = _user(db)
        kirana = _shop(db, "Kirana")
        supermarket = _shop(db, "Supermarket")

        _list_in_shop(db, _access(kirana), user)
        _list_in_shop(db, _access(supermarket), user)

        master_ids = {sp.product_master_id for sp in db.query(ShopProduct).all()}
        assert len(master_ids) == 1

    def test_each_shop_keeps_its_own_price(self, db):
        user = _user(db)
        kirana = _shop(db, "Kirana")
        supermarket = _shop(db, "Supermarket")

        _list_in_shop(db, _access(kirana), user, price=10.0)
        _list_in_shop(db, _access(supermarket), user, price=12.0)

        prices = {sp.shop_id: float(sp.price) for sp in db.query(ShopProduct).all()}
        assert prices[kirana.id] == 10.0
        assert prices[supermarket.id] == 12.0

    def test_each_shop_keeps_its_own_stock(self, db):
        user = _user(db)
        kirana = _shop(db, "Kirana")
        supermarket = _shop(db, "Supermarket")

        _list_in_shop(db, _access(kirana), user, quantity=5)
        _list_in_shop(db, _access(supermarket), user, quantity=9)

        quantities = {}
        for sp in db.query(ShopProduct).all():
            inv = db.query(Inventory).filter(
                Inventory.shop_product_id == sp.id
            ).one()
            quantities[sp.shop_id] = inv.quantity
        assert quantities[kirana.id] == 5
        assert quantities[supermarket.id] == 9

    def test_one_shop_withdrawing_does_not_delete_the_master(self, db):
        """Removing a listing is a shop decision, never a catalogue one."""
        user = _user(db)
        kirana = _shop(db, "Kirana")
        supermarket = _shop(db, "Supermarket")

        _list_in_shop(db, _access(kirana), user)
        _list_in_shop(db, _access(supermarket), user)

        listing = (
            db.query(ShopProduct).filter(ShopProduct.shop_id == kirana.id).one()
        )
        listing.is_deleted = True
        db.commit()

        assert db.query(ProductMaster).count() == 1, (
            "withdrawing one shop's listing deleted the shared master"
        )
        survivor = (
            db.query(ShopProduct).filter(ShopProduct.shop_id == supermarket.id).one()
        )
        assert survivor.is_deleted is False

    def test_renaming_the_master_reaches_every_shop(self, db):
        """The payoff of sharing: one edit, one place, every listing follows.

        If the name were copied onto each listing, this rename would leave two
        shops advertising different versions of the same product.
        """
        user = _user(db)
        kirana = _shop(db, "Kirana")
        supermarket = _shop(db, "Supermarket")

        _list_in_shop(db, _access(kirana), user)
        _list_in_shop(db, _access(supermarket), user)

        master = db.query(ProductMaster).one()
        master.name = "Parle-G Gold 250g"
        db.commit()

        names = {sp.product_master.name for sp in db.query(ShopProduct).all()}
        assert names == {"Parle-G Gold 250g"}


class TestSeparationHoldsAcrossEveryEntryRoute:
    """One master must survive all four doors, not just two hand-typed shops.

    The spec asks for master/shop separation *and* for all four entry routes to
    converge. The interesting case is their overlap: a POS feed or a barcode scan
    arriving for a product a shop already listed by hand. If either route built
    its own master, the shop would hold two listings of one product — the exact
    duplication this spec forbids.
    """

    def test_pos_after_manual_still_lands_on_one_master(self, db):
        from app.models.pos import POSIntegration as _POSIntegration
        from app.services import pos_sync_service
        from app.services.pos_integration.base import POSProductRecord

        user = _user(db)
        shop = _shop(db, "Kirana")
        _list_in_shop(db, _access(shop), user)

        integration = _POSIntegration(
            shop_id=shop.id,
            provider_name="Generic Till",
            integration_type="generic",
            auto_create_products=True,
        )
        db.add(integration)
        db.flush()

        job = pos_sync_service.POSSyncJob(
            shop_id=shop.id,
            integration_id=None,
            sync_type="FULL",
            trigger="TEST",
            status="RUNNING",
        )
        db.add(job)
        db.flush()

        pos_sync_service._apply_record(
            db,
            integration,
            job,
            POSProductRecord(
                pos_product_code="P-1",
                name="Parle-G 250g",
                sku="SKU-1",
                barcode=None,
                price=10.0,
                quantity=5,
            ),
            "fp-1",
        )
        db.commit()

        assert db.query(ProductMaster).count() == 1, (
            "POS minted a second master for a product the shop already listed"
        )
        assert db.query(ShopProduct).count() == 1

    def test_a_pos_record_without_a_sku_adds_no_listing(self, db):
        """The no-SKU variant: POS mints nothing, so nothing can duplicate.

        A record with no SKU carries no information that distinguishes one
        variant from another. Minting a variant anyway leaves the upsert keying
        on a variant the shop's base listing does not have, which splits one
        product into two listings.
        """
        from app.services import pos_sync_service
        from app.services.pos_integration.base import POSProductRecord

        user = _user(db)
        shop = _shop(db, "Kirana")
        _list_in_shop(db, _access(shop), user)

        integration = POSIntegration(
            shop_id=shop.id,
            provider_name="Generic Till",
            integration_type="generic",
            auto_create_products=True,
        )
        db.add(integration)
        db.flush()

        job = pos_sync_service.POSSyncJob(
            shop_id=shop.id,
            integration_id=None,
            sync_type="FULL",
            trigger="TEST",
            status="RUNNING",
        )
        db.add(job)
        db.flush()

        pos_sync_service._apply_record(
            db,
            integration,
            job,
            POSProductRecord(
                pos_product_code="P-NOSKU",
                name="Parle-G 250g",
                sku=None,
                barcode=None,
                price=10.0,
                quantity=5,
            ),
            "fp-nosku",
        )
        db.commit()

        assert db.query(ProductMaster).count() == 1
        assert db.query(ShopProduct).count() == 1, (
            "a SKU-less POS record duplicated the shop's existing listing"
        )

    def test_two_different_products_do_not_get_merged(self, db):
        """Sharing must not collapse genuinely different products into one."""
        user = _user(db)
        kirana = _shop(db, "Kirana")
        supermarket = _shop(db, "Supermarket")

        _list_in_shop(db, _access(kirana), user, name="Parle-G 250g")
        _list_in_shop(db, _access(supermarket), user, name="Amul Butter 500g")

        assert db.query(ProductMaster).count() == 2
        assert db.query(ShopProduct).count() == 2

    def test_one_shops_offer_does_not_follow_the_master(self, db):
        """Behaviour half of the offer rule: Kirana's discount on Parle-G must
        not leak onto Supermarket's listing of the same master."""
        from datetime import datetime, timedelta, timezone

        user = _user(db)
        kirana = _shop(db, "Kirana")
        supermarket = _shop(db, "Supermarket")

        _list_in_shop(db, _access(kirana), user)
        _list_in_shop(db, _access(supermarket), user)
        kirana_listing = (
            db.query(ShopProduct).filter(ShopProduct.shop_id == kirana.id).one()
        )

        now = datetime.now(timezone.utc)
        db.add(
            Offer(
                shop_id=kirana.id,
                title="Kirana-only 10% off",
                offer_type=OfferType.PERCENTAGE_DISCOUNT,
                discount_percentage=10.0,
                status=OfferStatus.ACTIVE,
                start_date=now,
                end_date=now + timedelta(days=7),
            )
        )
        db.flush()
        offer = db.query(Offer).one()
        db.add(OfferProduct(offer_id=offer.id, shop_product_id=kirana_listing.id))
        db.flush()

        links_for_supermarket = (
            db.query(OfferProduct)
            .join(ShopProduct, ShopProduct.id == OfferProduct.shop_product_id)
            .filter(ShopProduct.shop_id == supermarket.id)
            .count()
        )
        assert db.query(ProductMaster).count() == 1
        assert links_for_supermarket == 0


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))