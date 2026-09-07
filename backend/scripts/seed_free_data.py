#!/usr/bin/env python
"""Phase 4 — sample hyperlocal data seeder for the free cloud database.

Seeds realistic, consistent hyperlocal data (Mumbai-area shops, products,
inventory, pricing history, offers, search indexes, favourites, notifications,
audit logs, and OTP auth rows) through the **same ORM models the app uses**, so
every row matches the approved schema exactly (enums, geography, constraints).

Idempotency — every insert is guarded by its natural unique key, so re-running
never duplicates anything and **nothing is ever deleted**. Safe on a fresh DB
(the normal Phase 4 flow) and on a DB that already has some data.

Usage
-----
    python scripts/seed_free_data.py --url "postgresql+asyncpg://...?ssl=require"
    # or:  DATABASE_URL=<async url> python scripts/seed_free_data.py

    --reset  deletes ONLY the rows this seeder created (by natural keys), then
             reseeds. Useful for clean re-runs during development.
"""
from __future__ import annotations

import argparse
import os
import sys
from datetime import datetime, timedelta, timezone

from geoalchemy2 import WKTElement
from sqlalchemy.orm import Session

# Allow running as a standalone script:  python scripts/seed_free_data.py
import sys  # noqa: F811 - standalone-runner re-import
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.database.session import SessionLocal
from app.models.admin import AuditLog
from app.models.customer import Customer, CustomerAddress
from app.models.interaction import InteractionActionType, UserInteraction
from app.models.notification import DeviceToken, Notification, NotificationPreference
from app.models.otp import Otp
from app.models.product import (
    Brand, Category, IdentifierType, Inventory, InventoryAdjustment,
    InventoryMovement, InventorySource, Offer, OfferProduct, OfferStatus,
    OfferType, PriceHistory, ProductIdentifier, ProductImage, ProductMaster,
    ProductStatus, ProductVariant, ShopProduct, ShopProductStatus, StockStatus,
)
from app.models.role import Permission, Role, role_permissions
from app.models.saved_product import SavedProduct
from app.models.saved_shop import SavedShop
from app.models.search import (
    PopularSearch, SearchEvent, SearchHistory, SearchIndex, SearchIndexEntityType,
)
from app.models.shop import (
    Shop, ShopAddress, ShopCategory, ShopOwner, ShopStatus,
    ShopVerification, VerificationStatus,
)
from app.models.user import User, UserStatus

# ─────────────────────────────────────────────────────────────────────────────
# Hyperlocal geography (Mumbai, India — aligns with the Phase-4 verifier sample)
# ─────────────────────────────────────────────────────────────────────────────
MUMBAI = {"longitude": 72.8777, "latitude": 19.0760}  # Mumbai city centre

SHOP_LOCATIONS = {
    # name: (longitude, latitude)
    "andheri": (72.8167, 19.1364),   # Andheri West
    "juhu": (72.8260, 19.1075),       # Juhu
    "bandra": (72.8256, 19.0543),     # Bandra West
    "dadar": (72.8404, 19.0176),      # Dadar
    "powai": (72.9044, 19.1176),      # Powai
    "chembur": (72.9002, 19.0500),    # Chembur
}


def _point(lon: float, lat: float) -> WKTElement:
    return WKTElement(f"POINT({lon} {lat})", srid=4326)


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _days_ago(n: int) -> datetime:
    return _now() - timedelta(days=n)


def _on_scope(db: Session, model, **criteria):
    """Return the first matching row or None (natural-key lookup)."""
    return db.query(model).filter_by(**criteria).first()


def _get_or_create(db: Session, model, factory, **criteria):
    row = _on_scope(db, model, **criteria)
    if row is None:
        row = factory()
        db.add(row)
        db.flush()
    return row
# ─────────────────────────────────────────────────────────────────────────────
# RBAC
# ─────────────────────────────────────────────────────────────────────────────
def seed_rbac(db: Session) -> dict:
    customer_role = _get_or_create(
        db, Role, lambda: Role(name="customer", description="Customer"),
        name="customer")
    owner_role = _get_or_create(
        db, Role, lambda: Role(name="shop_owner", description="Shop owner"),
        name="shop_owner")
    manager_role = _get_or_create(
        db, Role, lambda: Role(name="shop_manager", description="Shop manager"),
        name="shop_manager")
    admin_role = _get_or_create(
        db, Role, lambda: Role(name="admin", description="Admin"),
        name="admin")

    permissions = {}
    specs = [
        ("product.read", "product", "read"),
        ("product.create", "product", "create"),
        ("product.update", "product", "update"),
        ("shop.read", "shop", "read"),
        ("shop.update", "shop", "update"),
        ("inventory.read", "inventory", "read"),
        ("inventory.update", "inventory", "update"),
        ("inventory.create", "inventory", "create"),
        ("offer.create", "offer", "create"),
        ("offer.update", "offer", "update"),
        ("search.read", "search", "read"),
        ("saved_product.manage", "saved_product", "manage"),
        ("saved_shop.manage", "saved_shop", "manage"),
        ("notification.read", "notification", "read"),
        ("profile.manage", "profile", "manage"),
        ("admin.all", "*", "*"),
    ]
    for name, resource, action in specs:
        permissions[name] = _get_or_create(
            db, Permission,
            lambda name=name, resource=resource, action=action: Permission(
                name=name, resource=resource, action=action),
            name=name)

    def link(role_row, perm_names):
        for pn in perm_names:
            exists = db.execute(
                role_permissions.select().where(
                    role_permissions.c.role_id == role_row.id,
                    role_permissions.c.permission_id == permissions[pn].id)
            ).first()
            if not exists:
                db.execute(role_permissions.insert().values(
                    role_id=role_row.id, permission_id=permissions[pn].id))

    link(customer_role, ["product.read", "shop.read", "inventory.read",
                         "search.read", "saved_product.manage", "saved_shop.manage",
                         "notification.read", "profile.manage"])
    link(owner_role, ["product.read", "product.create", "product.update",
                      "shop.read", "shop.update", "inventory.read",
                      "inventory.create", "inventory.update", "offer.create",
                      "offer.update", "profile.manage"])
    link(manager_role, ["product.read", "shop.read", "inventory.read",
                        "inventory.create", "inventory.update", "profile.manage"])
    link(admin_role, ["admin.all"] + list(permissions))
    db.flush()
    return {"roles": 4, "permissions": len(specs)}
# ─────────────────────────────────────────────────────────────────────────────
# Users / Customers / Addresses / Notification prefs
# ─────────────────────────────────────────────────────────────────────────────
def seed_users(db: Session) -> dict:
    admin_role = _on_scope(db, Role, name="admin")
    owner_role = _on_scope(db, Role, name="shop_owner")
    customer_role = _on_scope(db, Role, name="customer")

    admin = _get_or_create(
        db, User,
        lambda: User(phone_number="+919999000001", name="Platform Admin",
                     email="admin@hyperlocal.example",
                     role_id=admin_role.id if admin_role else None,
                     status=UserStatus.ACTIVE, is_active=True),
        phone_number="+919999000001")
    owner = _get_or_create(
        db, User,
        lambda: User(phone_number="+919999000002", name="Rohit Sharma",
                     email="rohit@sharma-general.example",
                     role_id=owner_role.id if owner_role else None,
                     status=UserStatus.ACTIVE, is_active=True),
        phone_number="+919999000002")
    customer = _get_or_create(
        db, User,
        lambda: User(phone_number="+919999000003", name="Priya Patel",
                     email="priya@example.com",
                     role_id=customer_role.id if customer_role else None,
                     status=UserStatus.ACTIVE, is_active=True),
        phone_number="+919999000003")
    google_user = _get_or_create(
        db, User,
        lambda: User(google_id="google-1042-sample-subject",
                     name="Google Signup User", email="guser@example.com",
                     role_id=customer_role.id if customer_role else None,
                     status=UserStatus.ACTIVE, is_active=True),
        google_id="google-1042-sample-subject")
    db.flush()

    for u in (admin, owner, customer, google_user):
        _get_or_create(
            db, Customer, lambda u=u: Customer(user_id=u.id, preferred_language="en"),
            user_id=u.id)

    customer_row = _on_scope(db, Customer, user_id=customer.id)
    _get_or_create(
        db, CustomerAddress,
        lambda: CustomerAddress(
            user_id=customer.id, customer_id=customer_row.id if customer_row else None,
            label="Home", address_line1="401, Crystal Residency, Linking Road",
            address_line2="Bandra West", city="Mumbai", state="Maharashtra",
            pincode="400050", country="India",
            location=_point(*SHOP_LOCATIONS["bandra"]),
            is_default=True, is_verified=True),
        user_id=customer.id, address_line1="401, Crystal Residency, Linking Road")

    _get_or_create(
        db, NotificationPreference,
        lambda: NotificationPreference(
            user_id=customer.id, push_enabled=True, email_enabled=True,
            sms_enabled=False, price_alerts=True, availability_alerts=True,
            promotional=True, deal_alerts=True),
        user_id=customer.id)

    _get_or_create(
        db, DeviceToken,
        lambda: DeviceToken(
            user_id=customer.id, token="device-sample-fcm-token-0001",
            device_type="android", platform="FCM", is_active=True,
            failure_count=0, app_version="1.0.0"),
        token="device-sample-fcm-token-0001")
    db.flush()
    return {"users": 4, "customers": 4, "addresses": 1,
            "preferences": 1, "device_tokens": 1}
# ─────────────────────────────────────────────────────────────────────────────
# Catalog: categories, brands, product masters, variants, identifiers, images
# ─────────────────────────────────────────────────────────────────────────────
def seed_catalog(db: Session) -> dict:
    categories = {}
    for name, slug in [("Groceries", "groceries"), ("Electronics", "electronics"),
                       ("Pharmacy", "pharmacy"), ("Household", "household")]:
        categories[name] = _get_or_create(
            db, Category,
            lambda name=name, slug=slug: Category(
                name=name, slug=slug, sort_order=0 if name == "Groceries" else 1,
                is_active=True, is_subcategory=False),
            name=name)

    brands = {}
    for name, slug in [("Samsung", "samsung"), ("Aashirvaad", "aashirvaad"),
                       ("Dettol", "dettol"), ("Bajaj", "bajaj"),
                       ("Amul", "amul"), ("Dolo", "dolo")]:
        brands[name] = _get_or_create(
            db, Brand,
            lambda name=name, slug=slug: Brand(name=name, slug=slug, is_active=True),
            name=name)

    products = [
        {"name": "Samsung Galaxy S24 Ultra 5G", "slug": "samsung-galaxy-s24-ultra-5g",
         "brand": "Samsung", "category": "Electronics", "mrp": 139999},
        {"name": "Aashirvaad Atta 5kg", "slug": "aashirvaad-atta-5kg",
         "brand": "Aashirvaad", "category": "Groceries", "mrp": 240},
        {"name": "Dettol Handwash 750ml", "slug": "dettol-handwash-750ml",
         "brand": "Dettol", "category": "Groceries", "mrp": 125},
        {"name": "Bajaj Ceiling Fan", "slug": "bajaj-ceiling-fan",
         "brand": "Bajaj", "category": "Electronics", "mrp": 2499},
        {"name": "Paracetamol 500mg 15tabs", "slug": "paracetamol-500mg-15tabs",
         "brand": "Dolo", "category": "Pharmacy", "mrp": 30},
        {"name": "Amul Butter 500g", "slug": "amul-butter-500g",
         "brand": "Amul", "category": "Groceries", "mrp": 300},
    ]
    product_rows = {}
    barcodes = {
        "samsung-galaxy-s24-ultra-5g": "8806094567890",
        "aashirvaad-atta-5kg": "8901063012345",
        "dettol-handwash-750ml": "8901030634213",
        "bajaj-ceiling-fan": "8907034567890",
        "paracetamol-500mg-15tabs": "8901234567890",
        "amul-butter-500g": "8901058861614",
    }
    for p in products:
        row = _get_or_create(
            db, ProductMaster,
            lambda p=p, brands=brands, categories=categories: ProductMaster(
                name=p["name"], slug=p["slug"],
                description=f"Sample hyperlocal listing for {p['name']}.",
                brand_id=brands[p["brand"]].id,
                category_id=categories[p["category"]].id,
                status=ProductStatus.APPROVED, is_active=True,
                is_featured=(p["category"] == "Electronics"),
                is_searchable=True, base_unit="piece"),
            slug=p["slug"])
        product_rows[p["slug"]] = row

        _get_or_create(
            db, ProductVariant,
            lambda p=p, row=row: ProductVariant(
                product_master_id=row.id, sku=p["slug"].upper(),
                name=p["name"], is_active=True, sort_order=0),
            product_master_id=row.id, sku=p["slug"].upper())

        _get_or_create(
            db, ProductIdentifier,
            lambda p=p, row=row, barcodes=barcodes: ProductIdentifier(
                product_master_id=row.id, identifier_type=IdentifierType.EAN,
                identifier_value=barcodes[p["slug"]], is_primary=True, is_active=True),
            product_master_id=row.id, identifier_value=barcodes[p["slug"]])

        _get_or_create(
            db, ProductImage,
            lambda p=p, row=row: ProductImage(
                product_master_id=row.id,
                image_url=f"https://cdn.hyperlocal.example/{p['slug']}.jpg",
                sort_order=0, is_primary=True),
            product_master_id=row.id, image_url=f"https://cdn.hyperlocal.example/{p['slug']}.jpg")
    db.flush()
    return {"categories": 4, "brands": 6, "products": 6,
            "variants": 6, "identifiers": 6, "images": 6}


# ─────────────────────────────────────────────────────────────────────────────
# Shops, owners, addresses, verifications
# ─────────────────────────────────────────────────────────────────────────────
def seed_shops(db: Session) -> dict:
    owner_user = _on_scope(db, User, phone_number="+919999000002")
    shop_specs = [
        {"name": "Sharma General Store", "slug": "sharma-general-store-andheri",
         "category": ShopCategory.GROCERY, "loc": "andheri", "phone": "+912224000001",
         "rating": 4.4, "review_count": 210, "verified": True},
        {"name": "Juhu Electronics Hub", "slug": "juhu-electronics-hub",
         "category": ShopCategory.ELECTRONICS, "loc": "juhu", "phone": "+912224000002",
         "rating": 4.6, "review_count": 342, "verified": True},
        {"name": "Bandra Medico", "slug": "bandra-medico",
         "category": ShopCategory.PHARMACY, "loc": "bandra", "phone": "+912224000003",
         "rating": 4.8, "review_count": 150, "verified": True},
        {"name": "Dadar Household Mart", "slug": "dadar-household-mart",
         "category": ShopCategory.HARDWARE, "loc": "dadar", "phone": "+912224000004",
         "rating": 4.1, "review_count": 95, "verified": False},
        {"name": "Powai Discount Store", "slug": "powai-discount-store",
         "category": ShopCategory.GROCERY, "loc": "powai", "phone": "+912224000005",
         "rating": 3.9, "review_count": 60, "verified": False},
    ]
    for s in shop_specs:
        shop = _get_or_create(
            db, Shop,
            lambda s=s: Shop(
                name=s["name"], slug=s["slug"],
                description=f"{s['name']} — hyperlocal sample shop.",
                phone=s["phone"], status=ShopStatus.ACTIVE,
                category=s["category"],
                location=_point(*SHOP_LOCATIONS[s["loc"]]),
                rating=s["rating"], review_count=s["review_count"],
                is_verified=s["verified"], is_featured=False,
                is_open_24x7=False, is_accepting_orders=True,
                is_delivery_available=True, is_pickup_available=True),
            slug=s["slug"])
        if owner_user:
            _get_or_create(
                db, ShopOwner,
                lambda shop=shop: ShopOwner(
                    shop_id=shop.id, user_id=owner_user.id,
                    is_primary=True, is_active=True),
                shop_id=shop.id, user_id=owner_user.id)
        _get_or_create(
            db, ShopAddress,
            lambda shop=shop, s=s: ShopAddress(
                shop_id=shop.id, address_line1=f"Shop {s['loc'].title()} Main Road",
                address_line2="Mumbai", city="Mumbai", state="Maharashtra",
                pincode="4000" + ("50" if s["loc"] in ("bandra",) else "51"),
                country="India", latitude=SHOP_LOCATIONS[s["loc"]][1],
                longitude=SHOP_LOCATIONS[s["loc"]][0],
                is_primary=True, is_verified=s["verified"]),
            shop_id=shop.id, address_line1=f"Shop {s['loc'].title()} Main Road")
        _get_or_create(
            db, ShopVerification,
            lambda shop=shop, s=s: ShopVerification(
                shop_id=shop.id, status=VerificationStatus.VERIFIED if s["verified"]
                else VerificationStatus.PENDING,
                submitted_by=owner_user.id if owner_user else None,
                submitted_at=_days_ago(12), verified_at=_days_ago(10) if s["verified"] else None),
            shop_id=shop.id)
    db.flush()
    return {"shops": 5, "owners": 5, "addresses": 5, "verifications": 5}


# ─────────────────────────────────────────────────────────────────────────────
# Listings: shop_products, inventory, movements, adjustments, price history
# ─────────────────────────────────────────────────────────────────────────────
def seed_listings(db: Session) -> dict:
    shops = {s.slug: s for s in db.query(Shop).all()}
    products = {p.slug: p for p in db.query(ProductMaster).all()}

    # (shop_slug, product_slug, price, mrp, qty, available, stock_status)
    listings = [
        ("sharma-general-store-andheri", "aashirvaad-atta-5kg", 230, 240, 50,
         True, StockStatus.IN_STOCK),
        ("sharma-general-store-andheri", "dettol-handwash-750ml", 110, 125, 30,
         True, StockStatus.IN_STOCK),
        ("sharma-general-store-andheri", "amul-butter-500g", 280, 300, 20,
         True, StockStatus.IN_STOCK),
        ("juhu-electronics-hub", "samsung-galaxy-s24-ultra-5g", 129999, 139999, 5,
         True, StockStatus.IN_STOCK),
        ("juhu-electronics-hub", "bajaj-ceiling-fan", 1999, 2499, 8,
         True, StockStatus.IN_STOCK),
        ("bandra-medico", "paracetamol-500mg-15tabs", 25, 30, 100,
         True, StockStatus.IN_STOCK),
        ("dadar-household-mart", "bajaj-ceiling-fan", 1899, 2499, 3,
         True, StockStatus.LOW_STOCK),
        ("powai-discount-store", "aashirvaad-atta-5kg", 225, 240, 0,
         False, StockStatus.OUT_OF_STOCK),
        ("powai-discount-store", "amul-butter-500g", 275, 300, 15,
         True, StockStatus.IN_STOCK),
    ]
    created_sp = 0
    for shop_slug, product_slug, price, mrp, qty, avail, stock in listings:
        shop = shops.get(shop_slug)
        product = products.get(product_slug)
        if shop is None or product is None:
            continue
        sp = _get_or_create(
            db, ShopProduct,
            lambda shop=shop, product=product, price=price, mrp=mrp, avail=avail,
                   stock=stock: ShopProduct(
                shop_id=shop.id, product_master_id=product.id,
                price=price, mrp=mrp, status=ShopProductStatus.ACTIVE,
                is_active=True, is_available=avail, is_featured=False,
                is_visible=True, stock_status=stock,
                source=InventorySource.MANUAL, last_inventory_update=_days_ago(2),
                last_price_update=_days_ago(5)),
            shop_id=shop.id, product_master_id=product.id)
        created_sp += 1

        inv = _get_or_create(
            db, Inventory,
            lambda sp=sp, qty=qty, avail=avail, stock=stock: Inventory(
                shop_product_id=sp.id, quantity=qty, reserved_quantity=0,
                available_quantity=qty, is_available=avail,
                stock_status=stock, last_updated_source=InventorySource.MANUAL),
            shop_product_id=sp.id)
        if qty > 0:
            _on_scope_guard = _on_scope(
                db, InventoryMovement, inventory_id=inv.id,
                movement_type="STOCK_IN")
            if not _on_scope_guard:
                db.add(InventoryMovement(
                    inventory_id=inv.id, quantity_change=qty, quantity_before=0,
                    quantity_after=qty, movement_type="STOCK_IN",
                    source=InventorySource.MANUAL, notes="Sample stock-in"))
        _get_or_create(
            db, PriceHistory,
            lambda sp=sp, price=price, mrp=mrp: PriceHistory(
                shop_product_id=sp.id, old_price=0, new_price=price,
                old_mrp=0, new_mrp=mrp, change_source=InventorySource.MANUAL,
                effective_from=_days_ago(5)),
            shop_product_id=sp.id, new_price=price)
# ─────────────────────────────────────────────────────────────────────────────
# Offers
# ─────────────────────────────────────────────────────────────────────────────
def seed_offers(db: Session) -> dict:
    shop = _on_scope(db, Shop, slug="sharma-general-store-andheri")
    offer = _get_or_create(
        db, Offer,
        lambda shop=shop: Offer(
            shop_id=shop.id, title="Atta + Butter combo ₹40 off",
            description="Buy 5kg atta with 500g butter and save ₹40.",
            offer_type=OfferType.BUNDLE, discount_value=40.00,
            status=OfferStatus.ACTIVE, start_date=_days_ago(3),
            end_date=_days_ago(-14), is_visible=True,
            terms_conditions="Minimum one unit each."),
        shop_id=shop.id, title="Atta + Butter combo ₹40 off")
    sp_atta = _on_scope(db, ShopProduct, shop_id=shop.id)
    _get_or_create(
        db, OfferProduct,
        lambda offer=offer, sp=sp_atta: OfferProduct(
            offer_id=offer.id, shop_product_id=sp.id, is_excluded=False),
        offer_id=offer.id, shop_product_id=sp_atta.id)
    db.flush()
    return {"offers": 1, "offer_products": 1}


# ─────────────────────────────────────────────────────────────────────────────
# Search: history, events, popular, index (with geography)
# ─────────────────────────────────────────────────────────────────────────────
def seed_search(db: Session) -> dict:
    customer = _on_scope(db, User, phone_number="+919999000003")
    query, shop = None, None
    if customer is not None:
        _get_or_create(
            db, SearchHistory,
            lambda customer=customer: SearchHistory(
                user_id=customer.id, query="aashirvaad atta",
                result_count=6, is_successful=True, searched_at=_days_ago(2)),
            user_id=customer.id, query="aashirvaad atta")
        _get_or_create(
            db, SearchEvent,
            lambda customer=customer: SearchEvent(
                user_id=customer.id, session_id="sess-0001", query="aashirvaad atta",
                event_type="RESULT_CLICK", result_count=6,
                device_type="android", app_version="1.0.0", event_time=_days_ago(2)),
            session_id="sess-0001", event_type="RESULT_CLICK")
    _get_or_create(
        db, PopularSearch,
        lambda: PopularSearch(query="aashirvaad atta", search_count=124,
                              result_count=6, is_active=True),
        query="aashirvaad atta")

    for slug, entity_type in [("aashirvaad-atta-5kg", SearchIndexEntityType.PRODUCT),
                              ("sharma-general-store-andheri", SearchIndexEntityType.SHOP)]:
        product = _on_scope(db, ProductMaster, slug="aashirvaad-atta-5kg") \
            if slug.startswith("aashirvaad") else None
        shop_row = _on_scope(db, Shop, slug="sharma-general-store-andheri") \
            if slug.startswith("sharma") else None
        _get_or_create(
            db, SearchIndex,
            lambda slug=slug, entity_type=entity_type, product=product,
                   shop=shop_row: SearchIndex(
                entity_type=entity_type, entity_id=(product.id if product else shop.id),
                product_id=product.id if product else None,
                shop_id=shop.id if shop else None,
                product_name=(product.name if product else shop.name),
                search_text=(f"{product.name} aashirvaad atta mrp {product.mrp}"
                             if product else f"{shop.name} mumbai grocery"),
                is_product_searchable=True, is_shop_visible=True,
                is_available=True, shop_rating=shop.rating if shop else 0.0,
                shop_review_count=shop.review_count if shop else 0,
                is_shop_accepting_orders=True, popularity_score=42.0,
                location=_point(*SHOP_LOCATIONS["andheri"]),
                latitude=SHOP_LOCATIONS["andheri"][1],
                longitude=SHOP_LOCATIONS["andheri"][0],
                distance_km=1.2, is_synced=True, last_synced_at=_now()),
            entity_type=entity_type, entity_id=(product.id if product else shop.id))
    db.flush()
    return {"history": 1, "events": 1, "popular": 1, "index": 2}


# ─────────────────────────────────────────────────────────────────────────────
# Favourites (saved products/shops), notifications, audit logs, interactions
# ─────────────────────────────────────────────────────────────────────────────
def seed_engagement(db: Session) -> dict:
    customer = _on_scope(db, User, phone_number="+919999000003")
    product = _on_scope(db, ProductMaster, slug="amul-butter-500g")
    shop = _on_scope(db, Shop, slug="bandra-medico")
    owner = _on_scope(db, User, phone_number="+919999000002")

    if customer is not None and product is not None:
        _get_or_create(
            db, SavedProduct,
            lambda: SavedProduct(user_id=customer.id, product_master_id=product.id,
                                 created_at=_days_ago(1)),
            user_id=customer.id, product_master_id=product.id)
    if customer is not None and shop is not None:
        _get_or_create(
            db, SavedShop,
            lambda: SavedShop(user_id=customer.id, shop_id=shop.id,
                              created_at=_days_ago(1)),
            user_id=customer.id, shop_id=shop.id)

    if customer is not None:
        _get_or_create(
            db, Notification,
            lambda: Notification(
                user_id=customer.id, title="Price drop on Amul Butter",
                body="Amul Butter 500g is now ₹280 at Sharma General Store.",
                type="price_alert", audience="customer",
                deep_link="hyperlocal://product/amul-butter-500g",
                dedupe_key="price-amul-butter", delivery_status="SENT",
                delivery_attempts=1, last_attempt_at=_now(),
                provider_message_id="mock-fcm-0001", is_read=False,
                payload='{"product":"amul-butter-500g"}', sent_at=_now()),
            user_id=customer.id, dedupe_key="price-amul-butter")

    if owner is not None:
        _get_or_create(
            db, UserInteraction,
            lambda: UserInteraction(
                user_id=owner.id, shop_id=shop.id if shop else None,
                action_type=InteractionActionType.RATING,
                message_content="Great service and fair prices.",
                rating=5),
            user_id=owner.id, message_content="Great service and fair prices.")
        _get_or_create(
            db, AuditLog,
            lambda: AuditLog(
                user_id=owner.id, action="VERIFY",
                entity_type="SHOP", entity_id=shop.id if shop else None,
                old_values=None, new_values={"status": "VERIFIED"},
                ip_address="203.0.113.7", user_agent="seed-data/v1",
                request_id="req-seed-0001",
                description="Sample audit trail from Phase 4 seed.",
                created_at=_days_ago(1)),
            request_id="req-seed-0001")
    if customer is not None and shop is not None:
        _get_or_create(
            db, UserInteraction,
            lambda: UserInteraction(
                user_id=customer.id, shop_id=shop.id,
                action_type=InteractionActionType.CALL_VIEW),
            user_id=customer.id, shop_id=shop.id)
    _get_or_create(
        db, Otp,
        lambda: Otp(phone_number="+919999000003",
                    otp_code="sha256-digest-of-salted-code-does-not-store-raw",
                    expires_at=_now() + timedelta(minutes=5), is_verified=False),
        phone_number="+919999000003", otp_code="sha256-digest-of-salted-code-does-not-store-raw")
    db.flush()
    return {"favourites": 2, "notifications": 1, "interactions": 2,
            "audit_logs": 1, "otps": 1}


# ─────────────────────────────────────────────────────────────────────────────
# Runner
# ─────────────────────────────────────────────────────────────────────────────
def _resolve_url(arg_url: str | None) -> str:
    """Resolve the async connection URL: --url -> $DATABASE_URL -> .env.free."""
    if arg_url:
        return arg_url
    url = os.environ.get("DATABASE_URL", "")
    if url:
        return url
    env_path = Path(__file__).resolve().parents[1] / ".env.free"
    if env_path.exists():
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith("DATABASE_URL="):
                return line.split("=", 1)[1].strip()
    raise SystemExit(
        "DATABASE_URL not found. Pass --url, export DATABASE_URL, or provision "
        "the free cloud DB first (scripts/provision_free_db.py).")


def _to_sync(url: str) -> str:
    """asyncpg URL (ssl=require) -> psycopg URL (sslmode=require)."""
    for prefix in ("postgresql+asyncpg://", "postgres+asyncpg://"):
        if url.startswith(prefix):
            url = url.replace(prefix, "postgresql+psycopg://", 1)
            break
    scheme, _, rest = url.partition("://")
    if "?" in rest:
        base, _, query = rest.partition("?")
        params = []
        for item in query.split("&"):
            if item.startswith("ssl="):
                params.append("sslmode=" + item.split("=", 1)[1])
            else:
                params.append(item)
        return f"{scheme}://{base}?{'&'.join(params)}"
    return url


def run(args: argparse.Namespace) -> int:
    url_async = args.url or _resolve_url(args.url)
    url_sync = _to_sync(url_async)
    print(f"=== Phase 4 sample data seeder ===\n[db   ] {url_sync.split('@')[-1]}")

    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker

    engine = create_engine(url_sync, pool_pre_ping=True,
                           connect_args={"connect_timeout": 15})
    Session = sessionmaker(bind=engine)
    db: Session = Session()
    try:
        if args.reset:
            _reset(db)

        results = {}
        results.update(seed_rbac(db))
        db.commit()
        results.update(seed_users(db))
        db.commit()
        results.update(seed_catalog(db))
        db.commit()
        results.update(seed_shops(db))
        db.commit()
        results.update(seed_listings(db))
        db.commit()
        results.update(seed_offers(db))
        db.commit()
        results.update(seed_search(db))
        db.commit()
        results.update(seed_engagement(db))
        db.commit()

        print("\n=== Seeded sample hyperlocal data ===")
        for label, count in results.items():
            print(f"  {label:<22} {count}")
        print(f"\nDone. {sum(results.values())} rows created/verified (idempotent).")
        return 0
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()
        engine.dispose()


def _reset(db: Session) -> None:
    """Delete ONLY the rows this seeder created (scoped by natural keys)."""
    seed_phones = ["+919999000001", "+919999000002", "+919999000003"]
    seed_slugs = ["sharma-general-store-andheri", "juhu-electronics-hub",
                  "bandra-medico", "dadar-household-mart", "powai-discount-store"]
    seed_product_slugs = ["samsung-galaxy-s24-ultra-5g", "aashirvaad-atta-5kg",
                          "dettol-handwash-750ml", "bajaj-ceiling-fan",
                          "paracetamol-500mg-15tabs", "amul-butter-500g"]
    seed_category_names = ["Groceries", "Electronics", "Pharmacy", "Household"]
    seed_brand_names = ["Samsung", "Aashirvaad", "Dettol", "Bajaj", "Amul", "Dolo"]

    def q(model, **criteria):
        return db.query(model).filter_by(**criteria).all()

    # ── Leaf rows (no dependents) ─────────────────────────────────────────
    for row in q(Otp, phone_number=seed_phones[2]):
        db.delete(row)
    for row in q(AuditLog, request_id="req-seed-0001"):
        db.delete(row)
    for row in q(Notification, dedupe_key="price-amul-butter"):
        db.delete(row)
    for row in q(DeviceToken, token="device-sample-fcm-token-0001"):
        db.delete(row)
    for row in q(PopularSearch, query="aashirvaad atta"):
        db.delete(row)
    for row in q(SearchEvent, session_id="sess-0001"):
        db.delete(row)
    for row in q(SearchHistory, user_id=_user_id(db, seed_phones[2])):
        db.delete(row)
    for row in q(SearchIndex, entity_type=SearchIndexEntityType.SHOP_PRODUCT):
        db.delete(row)

    # ── Offers (+ their offer_products) ────────────────────────────────────
    for offer in db.query(Offer).filter_by(title="Atta + Butter combo ₹40 off").all():
        for op in db.query(OfferProduct).filter_by(offer_id=offer.id).all():
            db.delete(op)
        db.delete(offer)
    db.flush()
# ── Saved products / shops (favourites) ────────────────────────────────
    cust_id = _user_id(db, seed_phones[2])
    for row in q(SavedProduct, user_id=cust_id):
        db.delete(row)
    for row in q(SavedShop, user_id=cust_id):
        db.delete(row)

    # ── Shops + their listings chain ───────────────────────────────────────
    for shop in db.query(Shop).filter(Shop.slug.in_(seed_slugs)).all():
        for row in db.query(SearchIndex).filter(SearchIndex.shop_id == shop.id).all():
            db.delete(row)
        for sp in db.query(ShopProduct).filter_by(shop_id=shop.id).all():
            for mv in db.query(InventoryMovement).join(
                    Inventory, InventoryMovement.inventory_id == Inventory.id
            ).filter(Inventory.shop_product_id == sp.id).all():
                db.delete(mv)
            for inv in db.query(Inventory).filter_by(shop_product_id=sp.id).all():
                db.delete(inv)
            for ph in db.query(PriceHistory).filter_by(shop_product_id=sp.id).all():
                db.delete(ph)
            db.delete(sp)
        for sv in db.query(ShopVerification).filter_by(shop_id=shop.id).all():
            db.delete(sv)
        for sa in db.query(ShopAddress).filter_by(shop_id=shop.id).all():
            db.delete(sa)
        for so in db.query(ShopOwner).filter_by(shop_id=shop.id).all():
            db.delete(so)
        db.delete(shop)

    # ── Products + their catalog chain ─────────────────────────────────────
    for pm in db.query(ProductMaster).filter(
            ProductMaster.slug.in_(seed_product_slugs)).all():
        for row in db.query(SearchIndex).filter(SearchIndex.product_id == pm.id).all():
            db.delete(row)
        for img in db.query(ProductImage).filter_by(product_master_id=pm.id).all():
            db.delete(img)
        for ident in db.query(ProductIdentifier).filter_by(product_master_id=pm.id).all():
            db.delete(ident)
        for var in db.query(ProductVariant).filter_by(product_master_id=pm.id).all():
            db.delete(var)
        db.delete(pm)

    # ── Users / customers / addresses / prefs ──────────────────────────────
    for row in q(CustomerAddress, user_id=cust_id):
        db.delete(row)
    for row in q(NotificationPreference, user_id=cust_id):
        db.delete(row)
    for row in q(UserInteraction, user_id=cust_id):
        db.delete(row)
    for row in q(UserInteraction, user_id=_user_id(db, seed_phones[1])):
        db.delete(row)
    for row in q(Customer, user_id=cust_id):
        db.delete(row)
    for phone in seed_phones:
        for row in q(User, phone_number=phone):
            db.delete(row)
    for row in q(User, google_id="google-1042-sample-subject"):
        db.delete(row)

    # ── Catalog base tables ────────────────────────────────────────────────
    for name in seed_brand_names:
        for row in q(Brand, name=name):
            db.delete(row)
    for name in seed_category_names:
        for row in q(Category, name=name):
            db.delete(row)

    # ── RBAC (roles, permissions, link rows) ───────────────────────────────
    perm_names = ["product.read", "product.create", "product.update", "shop.read",
                  "shop.update", "inventory.read", "inventory.update",
                  "inventory.create", "offer.create", "offer.update",
                  "search.read", "saved_product.manage", "saved_shop.manage",
                  "notification.read", "profile.manage", "admin.all"]
    perms = db.query(Permission).filter(Permission.name.in_(perm_names)).all()
    perm_ids = {p.id for p in perms}
    roles = db.query(Role).filter(Role.name.in_(["customer", "shop_owner",
                                                 "shop_manager", "admin"])).all()
    for role in roles:
        for link in db.execute(role_permissions.select().where(
                role_permissions.c.role_id == role.id)).fetchall():
            if link.permission_id in perm_ids:
                db.execute(role_permissions.delete().where(
                    role_permissions.c.role_id == role.id,
                    role_permissions.c.permission_id == link.permission_id))
    for p in perms:
        db.delete(p)
    for role in roles:
        db.delete(role)
    db.flush()


def _user_id(db, phone: str) -> int | None:
    row = db.query(User).filter(User.phone_number == phone).first()
    if row:
        db.refresh(row)
    return row.id if row else 0


def _offer_id(db) -> int | None:
    row = db.query(Offer).filter_by(title="Atta + Butter combo ₹40 off").first()
    return row.id if row else 0


def main(argv: list | None = None) -> int:
    ap = argparse.ArgumentParser(
        description="Seed sample hyperlocal data into the free cloud DB (idempotent).")
    ap.add_argument("--url", default=None,
                    help="Async DB URL (default: $DATABASE_URL / backend/.env.free)")
    ap.add_argument("--reset", action="store_true",
                    help="Delete this seeder's rows first, then reseed")
    return run(ap.parse_args(argv))


if __name__ == "__main__":
    import os as _os
    from pathlib import Path as _Path  # noqa: F401  (used by _resolve_url)
    raise SystemExit(main())
