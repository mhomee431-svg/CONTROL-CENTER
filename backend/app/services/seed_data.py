"""Seed the database with sample data for development and testing."""
from sqlalchemy.orm import Session
from geoalchemy2 import WKTElement

from app.database.session import SessionLocal
from app.models.product import (
    Category,
    Brand,
    ProductMaster,
    ProductStatus,
    ShopProduct,
    ShopProductStatus,
    StockStatus,
    InventorySource,
    Inventory,
    ProductIdentifier,
    IdentifierType,
)
from app.models.role import Permission, Role
from app.models.shop import Shop, ShopStatus
from app.models.user import User, UserStatus


# ── RBAC Seeding ────────────────────────────────────────────────────────────
ROLE_PERMISSIONS: dict[str, list[tuple[str, str]]] = {
    "customer": [
        ("product", "read"),
        ("shop", "read"),
        ("inventory", "read"),
        ("search", "read"),
        ("saved_product", "create"),
        ("saved_product", "read"),
        ("saved_product", "delete"),
        ("saved_shop", "create"),
        ("saved_shop", "read"),
        ("saved_shop", "delete"),
        ("notification", "read"),
        ("profile", "read"),
        ("profile", "update"),
        ("location", "read"),
    ],
    "shop_owner": [
        ("product", "read"),
        ("shop", "read"),
        ("shop", "update"),
        ("shop", "delete"),
        ("inventory", "create"),
        ("inventory", "read"),
        ("inventory", "update"),
        ("inventory", "delete"),
        ("shop_product", "create"),
        ("shop_product", "read"),
        ("shop_product", "update"),
        ("shop_product", "delete"),
        ("offer", "create"),
        ("offer", "read"),
        ("offer", "update"),
        ("offer", "delete"),
        ("order", "read"),
        ("order", "update"),
        ("customer", "read"),
        ("report", "read"),
        ("notification", "read"),
        ("profile", "read"),
        ("profile", "update"),
    ],
    "shop_manager": [
        ("product", "read"),
        ("shop", "read"),
        ("inventory", "create"),
        ("inventory", "read"),
        ("inventory", "update"),
        ("shop_product", "create"),
        ("shop_product", "read"),
        ("shop_product", "update"),
        ("order", "read"),
        ("order", "update"),
        ("customer", "read"),
        ("notification", "read"),
        ("profile", "read"),
        ("profile", "update"),
    ],
    "admin": [
        ("*", "*"),
        ("user", "create"),
        ("user", "read"),
        ("user", "update"),
        ("user", "delete"),
        ("role", "create"),
        ("role", "read"),
        ("role", "update"),
        ("role", "delete"),
        ("permission", "create"),
        ("permission", "read"),
        ("permission", "update"),
        ("permission", "delete"),
        ("shop", "create"),
        ("shop", "read"),
        ("shop", "update"),
        ("shop", "delete"),
        ("product", "create"),
        ("product", "read"),
        ("product", "update"),
        ("product", "delete"),
        ("inventory", "create"),
        ("inventory", "read"),
        ("inventory", "update"),
        ("inventory", "delete"),
        ("category", "create"),
        ("category", "read"),
        ("category", "update"),
        ("category", "delete"),
        ("report", "read"),
        ("system", "read"),
        ("system", "update"),
    ],
}


def seed_roles(db: Session) -> None:
    """Create the core roles and their permissions."""
    for role_name, perms in ROLE_PERMISSIONS.items():
        role = db.query(Role).filter(Role.name == role_name).first()
        if role is None:
            role = Role(name=role_name, description=f"{role_name} role")
            db.add(role)
            db.flush()

        # Add permissions (create if not exists)
        for resource, action in perms:
            if resource == "*" and action == "*":
                continue  # wildcard handled at evaluation time
            perm = (
                db.query(Permission)
                .filter(
                    Permission.resource == resource,
                    Permission.action == action,
                )
                .first()
            )
            if perm is None:
                perm = Permission(
                    name=f"{action}:{resource}",
                    description=f"Can {action} {resource}",
                    resource=resource,
                    action=action,
                )
                db.add(perm)
                db.flush()
            if perm not in role.permissions:
                role.permissions.append(perm)
    db.commit()


def seed_admin_user(db: Session) -> None:
    """Create a default admin user for development (phone: +919999999999)."""
    admin_role = db.query(Role).filter(Role.name == "admin").first()
    if admin_role is None:
        seed_roles(db)
        admin_role = db.query(Role).filter(Role.name == "admin").first()

    admin = db.query(User).filter(User.phone_number == "+919999999999").first()
    if admin is None:
        admin = User(
            phone_number="+919999999999",
            name="System Admin",
            role_id=admin_role.id if admin_role else None,
            status=UserStatus.ACTIVE,
            is_active=True,
        )
        db.add(admin)
    db.commit()


def seed_categories(db: Session) -> None:
    categories = [
        {"name": "Electronics", "slug": "electronics", "icon_url": "https://via.placeholder.com/150?text=Electronics"},
        {"name": "Groceries", "slug": "groceries", "icon_url": "https://via.placeholder.com/150?text=Groceries"},
        {"name": "Medicines", "slug": "medicines", "icon_url": "https://via.placeholder.com/150?text=Medicines"},
        {"name": "Hardware", "slug": "hardware", "icon_url": "https://via.placeholder.com/150?text=Hardware"},
        {"name": "Fashion", "slug": "fashion", "icon_url": "https://via.placeholder.com/150?text=Fashion"},
    ]
    for c in categories:
        if not db.query(Category).filter(Category.name == c["name"]).first():
            db.add(Category(**c))
    db.commit()


def seed_brands(db: Session) -> None:
    brands = [
        {"name": "Samsung", "slug": "samsung"},
        {"name": "Aashirvaad", "slug": "aashirvaad"},
        {"name": "Dettol", "slug": "dettol"},
        {"name": "Bajaj", "slug": "bajaj"},
        {"name": "Dolo", "slug": "dolo"},
        {"name": "Amul", "slug": "amul"},
    ]
    for b in brands:
        if not db.query(Brand).filter(Brand.name == b["name"]).first():
            db.add(Brand(**b))
    db.commit()


def seed_shops(db: Session) -> None:
    shops = [
        {
            "name": "Gupta Electronics",
            "description": "Your trusted neighborhood electronics store since 2010.",
            "image_url": "https://via.placeholder.com/300?text=Gupta+Electronics",
            "phone": "+919876543210",
            "status": ShopStatus.ACTIVE,
            "category": "Electronics",
            "location": WKTElement("POINT(85.1376 25.5941)", srid=4326),
            "rating": 4.5,
            "review_count": 342,
            "is_verified": True,
            "opening_hours": "Mon-Sun, 10:00 AM - 9:00 PM",
        },
        {
            "name": "Sharma General Store",
            "description": "Everything you need for daily life at fair prices.",
            "image_url": "https://via.placeholder.com/300?text=Sharma+Store",
            "phone": "+919876543211",
            "status": ShopStatus.ACTIVE,
            "category": "Groceries",
            "location": WKTElement("POINT(85.1400 25.6100)", srid=4326),
            "rating": 4.2,
            "review_count": 210,
            "is_verified": False,
            "opening_hours": "Mon-Sun, 8:00 AM - 10:00 PM",
        },
        {
            "name": "Patna Medical Hall",
            "description": "Pharmacy with genuine medicines and health products.",
            "image_url": "https://via.placeholder.com/300?text=Medical+Hall",
            "phone": "+919876543212",
            "status": ShopStatus.ACTIVE,
            "category": "Medicines",
            "location": WKTElement("POINT(85.1500 25.6150)", srid=4326),
            "rating": 4.8,
            "review_count": 150,
            "is_verified": True,
            "opening_hours": "Mon-Sun, 9:00 AM - 11:00 PM",
        },
        {
            "name": "City Electronics Outlet",
            "description": "Latest gadgets and home appliances.",
            "image_url": "https://via.placeholder.com/300?text=City+Electronics",
            "phone": "+919876543213",
            "status": ShopStatus.ACTIVE,
            "category": "Electronics",
            "location": WKTElement("POINT(85.1300 25.6200)", srid=4326),
            "rating": 4.0,
            "review_count": 95,
            "is_verified": False,
            "opening_hours": "Mon-Sun, 10:00 AM - 8:30 PM",
        },
    ]
    for s in shops:
        if not db.query(Shop).filter(Shop.name == s["name"]).first():
            db.add(Shop(**s))
    db.commit()


def seed_products(db: Session) -> None:
    # Fetch brand and category IDs
    samsung = db.query(Brand).filter(Brand.name == "Samsung").first()
    aashirvaad = db.query(Brand).filter(Brand.name == "Aashirvaad").first()
    dettol = db.query(Brand).filter(Brand.name == "Dettol").first()
    bajaj = db.query(Brand).filter(Brand.name == "Bajaj").first()
    dolo = db.query(Brand).filter(Brand.name == "Dolo").first()
    amul = db.query(Brand).filter(Brand.name == "Amul").first()

    electronics = db.query(Category).filter(Category.name == "Electronics").first()
    groceries = db.query(Category).filter(Category.name == "Groceries").first()
    medicines = db.query(Category).filter(Category.name == "Medicines").first()
    hardware = db.query(Category).filter(Category.name == "Hardware").first()

    products = [
        {
            "name": "Samsung Galaxy S24 Ultra 5G",
            "slug": "samsung-galaxy-s24-ultra-5g",
            "description": "Dynamic AMOLED 2X display, titanium frame, Snapdragon 8 Gen 3 for Galaxy.",
            "brand_id": samsung.id if samsung else None,
            "category_id": electronics.id if electronics else None,
            "status": ProductStatus.APPROVED,
            "is_searchable": True,
        },
        {
            "name": "Aashirvaad Atta 5kg",
            "slug": "aashirvaad-atta-5kg",
            "description": "100% whole wheat atta, perfect for soft rotis.",
            "brand_id": aashirvaad.id if aashirvaad else None,
            "category_id": groceries.id if groceries else None,
            "status": ProductStatus.APPROVED,
            "is_searchable": True,
        },
        {
            "name": "Dettol Handwash 750ml",
            "slug": "dettol-handwash-750ml",
            "description": "Antibacterial handwash for family protection.",
            "brand_id": dettol.id if dettol else None,
            "category_id": groceries.id if groceries else None,
            "status": ProductStatus.APPROVED,
            "is_searchable": True,
        },
        {
            "name": "Bajaj Ceiling Fan",
            "slug": "bajaj-ceiling-fan",
            "description": "High-speed ceiling fan with energy-efficient motor.",
            "brand_id": bajaj.id if bajaj else None,
            "category_id": hardware.id if hardware else None,
            "status": ProductStatus.APPROVED,
            "is_searchable": True,
        },
        {
            "name": "Paracetamol 500mg",
            "slug": "paracetamol-500mg",
            "description": "Pain relief and fever reduction tablets.",
            "brand_id": dolo.id if dolo else None,
            "category_id": medicines.id if medicines else None,
            "status": ProductStatus.APPROVED,
            "is_searchable": True,
        },
        {
            "name": "Amul Butter 500g",
            "slug": "amul-butter-500g",
            "description": "Delicious creamy butter made from fresh milk.",
            "brand_id": amul.id if amul else None,
            "category_id": groceries.id if groceries else None,
            "status": ProductStatus.APPROVED,
            "is_searchable": True,
        },
    ]
    for p in products:
        if not db.query(ProductMaster).filter(ProductMaster.slug == p["slug"]).first():
            db.add(ProductMaster(**p))
    db.commit()

    # Add identifiers for seeded products
    product_identifiers = [
        {"slug": "samsung-galaxy-s24-ultra-5g", "identifier_type": "EAN", "identifier_value": "8806094567890", "is_primary": True},
        {"slug": "aashirvaad-atta-5kg", "identifier_type": "EAN", "identifier_value": "8901063012345", "is_primary": True},
        {"slug": "dettol-handwash-750ml", "identifier_type": "EAN", "identifier_value": "8901030634213", "is_primary": True},
        {"slug": "bajaj-ceiling-fan", "identifier_type": "EAN", "identifier_value": "8907034567890", "is_primary": True},
        {"slug": "paracetamol-500mg", "identifier_type": "EAN", "identifier_value": "8901234567890", "is_primary": True},
        {"slug": "amul-butter-500g", "identifier_type": "EAN", "identifier_value": "8901058861614", "is_primary": True},
    ]
    for spec in product_identifiers:
        product = db.query(ProductMaster).filter(ProductMaster.slug == spec["slug"]).first()
        if product and not db.query(ProductIdentifier).filter(
            ProductIdentifier.product_master_id == product.id,
            ProductIdentifier.identifier_value == spec["identifier_value"],
        ).first():
            db.add(
                ProductIdentifier(
                    product_master_id=product.id,
                    identifier_type=spec["identifier_type"],
                    identifier_value=spec["identifier_value"],
                    is_primary=spec["is_primary"],
                )
            )
    db.commit()


def seed_shop_products_and_inventory(db: Session) -> None:
    """Create shop_products and inventory relationships for seeded data."""
    # Fetch products and shops
    galaxy = db.query(ProductMaster).filter(ProductMaster.name == "Samsung Galaxy S24 Ultra 5G").first()
    atta = db.query(ProductMaster).filter(ProductMaster.name == "Aashirvaad Atta 5kg").first()
    dettol = db.query(ProductMaster).filter(ProductMaster.name == "Dettol Handwash 750ml").first()
    fan = db.query(ProductMaster).filter(ProductMaster.name == "Bajaj Ceiling Fan").first()
    paracetamol = db.query(ProductMaster).filter(ProductMaster.name == "Paracetamol 500mg").first()
    butter = db.query(ProductMaster).filter(ProductMaster.name == "Amul Butter 500g").first()

    gupta = db.query(Shop).filter(Shop.name == "Gupta Electronics").first()
    sharma = db.query(Shop).filter(Shop.name == "Sharma General Store").first()
    medical = db.query(Shop).filter(Shop.name == "Patna Medical Hall").first()
    city = db.query(Shop).filter(Shop.name == "City Electronics Outlet").first()

    shop_product_specs = [
        # (shop, product, price, mrp, quantity, is_available, stock_status)
        (gupta, galaxy, 129999, 139999, 5, True, StockStatus.IN_STOCK),
        (city, galaxy, 134999, 139999, 0, False, StockStatus.OUT_OF_STOCK),
        (sharma, atta, 230, 240, 50, True, StockStatus.IN_STOCK),
        (sharma, dettol, 110, 125, 30, True, StockStatus.IN_STOCK),
        (gupta, fan, 1999, 2499, 8, True, StockStatus.IN_STOCK),
        (city, fan, 1899, 2499, 3, True, StockStatus.LOW_STOCK),
        (medical, paracetamol, 25, 30, 100, True, StockStatus.IN_STOCK),
        (sharma, butter, 280, 300, 20, True, StockStatus.IN_STOCK),
    ]

    for shop, product, price, mrp, qty, available, stock_status in shop_product_specs:
        if shop is None or product is None:
            continue
        # Check if shop_product already exists
        existing = (
            db.query(ShopProduct)
            .filter(
                ShopProduct.shop_id == shop.id,
                ShopProduct.product_master_id == product.id,
            )
            .first()
        )
        if existing:
            continue

        sp = ShopProduct(
            shop_id=shop.id,
            product_master_id=product.id,
            price=price,
            mrp=mrp,
            is_available=available,
            stock_status=stock_status,
            status=ShopProductStatus.ACTIVE,
            source=InventorySource.MANUAL,
            last_inventory_update=None,
            last_price_update=None,
        )
        db.add(sp)
        db.flush()  # Ensure sp.id is available

        inv = Inventory(
            shop_product_id=sp.id,
            quantity=qty,
            available_quantity=qty,
            is_available=available,
            stock_status=stock_status,
            last_updated_source=InventorySource.MANUAL,
        )
        db.add(inv)

    db.commit()


def run_seed() -> None:
    """Run all seed functions."""
    db = SessionLocal()
    try:
        seed_roles(db)
        seed_admin_user(db)
        seed_categories(db)
        seed_brands(db)
        seed_shops(db)
        seed_products(db)
        seed_shop_products_and_inventory(db)
        print("Database seeded successfully.")
    finally:
        db.close()


if __name__ == "__main__":
    run_seed()