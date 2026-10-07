"""Seed the database with an admin account and a working dataset.

Idempotent: re-running it leaves existing rows alone, so it is safe to call on
every start. The sample business (id 1) is fully populated across every tab of
the business drill-down, which is what makes the detail page demonstrable.

Run with:  python -m app.seed
"""

from datetime import datetime, timedelta, timezone

from sqlalchemy import func, select

from app.core.database import Base, SessionLocal, engine
from app.core.security import hash_password
from app.models import (
    AdminUser,
    Announcement,
    AuditLog,
    Banner,
    Brand,
    Category,
    Complaint,
    Faq,
    FeatureFlag,
    HelpContent,
    ImportError,
    ImportJob,
    NotificationCampaign,
    Offer,
    Payment,
    PosIntegration,
    PosSyncRun,
    Product,
    ProductVariant,
    PromotionalCard,
    SearchQuery,
    Shop,
    ShopDocument,
    ShopInventory,
    ShopPricing,
    Subscription,
    SystemMessage,
    SystemSetting,
    User,
)

DEFAULT_ADMIN = "admin"
DEFAULT_PASSWORD = "admin123"

# Every capability the console's PermissionGuard can ask for. The seeded admin
# is the platform owner, so it also bypasses the check.
ALL_PERMISSIONS = [
    "shops.view", "shops.update", "shops.verify", "shops.reject",
    "shops.suspend", "shops.reactivate", "shops.archive",
    "customers.view", "customers.restrict", "customers.status",
    "products.view", "products.update", "products.approve",
    "inventory.view", "offers.view", "offers.update",
    "notifications.send", "content.manage", "imports.manage",
    "pos.manage", "support.update", "system.flags", "system.settings",
]


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _hours_map(open_at: str = "09:00", close_at: str = "21:00", closed_day: str | None = "sunday"):
    days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    return {d: (None if d == closed_day else f"{open_at}-{close_at}") for d in days}


def seed() -> None:
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        if db.scalar(select(func.count()).select_from(AdminUser)):
            print("[seed] Database already seeded — nothing to do.")
            return

        # --- Admins -------------------------------------------------------
        owner = AdminUser(
            username=DEFAULT_ADMIN,
            name="Platform Owner",
            email="owner@hyperlocal.test",
            hashed_password=hash_password(DEFAULT_PASSWORD),
            role_name="Platform Owner",
            level="SUPER",
            is_owner=True,
            permissions=ALL_PERMISSIONS,
        )
        support = AdminUser(
            username="support",
            name="Support Admin",
            email="support@hyperlocal.test",
            hashed_password=hash_password("support123"),
            role_name="Support Admin",
            level="SUB",
            is_owner=False,
            permissions=["shops.view", "customers.view", "products.view", "inventory.view"],
        )
        db.add_all([owner, support])
        db.flush()

        # --- Taxonomy -----------------------------------------------------
        categories = {}
        for name in ["Grocery", "Pharmacy", "Electronics", "Hardware", "Bakery"]:
            c = Category(name=name, slug=name.lower(), is_active=True)
            db.add(c)
            db.flush()
            categories[name] = c

        brands = {}
        for name in ["Tata", "Amul", "Samsung", "Local Choice"]:
            b = Brand(name=name, slug=name.lower().replace(" ", "-"), is_active=True)
            db.add(b)
            db.flush()
            brands[name] = b

        # --- Customers and owners ----------------------------------------
        customers = []
        for i in range(1, 9):
            u = User(
                name=f"Customer {i}",
                phone=f"90000000{i:02d}",
                email=f"customer{i}@example.test",
                status="ACTIVE",
                city="Mumbai" if i % 2 else "Pune",
                state="Maharashtra",
                search_count=i * 3,
                viewed_product_count=i * 2,
                viewed_shop_count=i,
                saved_product_count=i,
                saved_shop_count=max(i - 2, 0),
                last_active=_now() - timedelta(days=i),
            )
            db.add(u)
            customers.append(u)

        owners = []
        for i in range(1, 5):
            u = User(
                name=f"Owner {i}",
                phone=f"80000000{i:02d}",
                email=f"owner{i}@example.test",
                status="ACTIVE",
                city="Mumbai",
                state="Maharashtra",
            )
            db.add(u)
            owners.append(u)
        db.flush()

        # --- Shops --------------------------------------------------------
        shop_specs = [
            ("Sharma Super Mart", "Grocery", "Mumbai", "VERIFIED", "ACTIVE"),
            ("Wellness Pharmacy", "Pharmacy", "Pune", "VERIFIED", "ACTIVE"),
            ("Gupta Electronics", "Electronics", "Mumbai", "PENDING", "PENDING"),
            ("Krishna Hardware", "Hardware", "Nagpur", "VERIFIED", "ACTIVE"),
            ("Sweet Corner Bakery", "Bakery", "Pune", "NEEDS_CORRECTION", "INACTIVE"),
        ]
        shops = []
        for idx, (name, cat, city, verif, status) in enumerate(shop_specs, start=1):
            s = Shop(
                name=name,
                owner_id=owners[(idx - 1) % len(owners)].id,
                category_id=categories[cat].id,
                category=cat,
                subcategory="Retail",
                business_type="RETAIL" if idx % 2 else "WHOLESALE",
                address=f"{100 + idx}, Main Road",
                locality="Andheri West" if city == "Mumbai" else "Kothrud",
                city=city,
                state="Maharashtra",
                pincode=f"4000{idx:02d}",
                latitude=19.0760 + idx * 0.01,
                longitude=72.8777 + idx * 0.01,
                phone=f"70000000{idx:02d}",
                alt_phone=f"71000000{idx:02d}",
                email=f"contact{idx}@shop.test",
                website="https://example.com" if idx == 1 else None,
                description=f"{name} — a neighbourhood {cat.lower()} store.",
                registration_number=f"REG-{idx:05d}",
                gst_number=f"27ABCDE1234F1Z{idx}",
                status=status,
                verification_status=verif,
                verified_at=_now() - timedelta(days=30) if verif == "VERIFIED" else None,
                verified_by="Platform Owner" if verif == "VERIFIED" else None,
                rejection_reason=(
                    "GST certificate is illegible — please re-upload."
                    if verif == "NEEDS_CORRECTION"
                    else None
                ),
                operating_hours=_hours_map(closed_day="sunday" if idx % 2 else None),
                inventory_freshness="FRESH" if idx % 2 else "STALE",
                last_inventory_update=_now() - timedelta(hours=idx * 20),
            )
            db.add(s)
            shops.append(s)
        db.flush()

        # --- Products and variants ---------------------------------------
        products = []
        product_specs = [
            ("Basmati Rice 5kg", "Grocery", "Local Choice", 450, 520),
            ("Full Cream Milk 1L", "Grocery", "Amul", 60, 68),
            ("Paracetamol 500mg", "Pharmacy", "Local Choice", 25, 32),
            ("LED Bulb 9W", "Electronics", "Samsung", 99, 149),
            ("Hammer 500g", "Hardware", "Local Choice", 180, 240),
        ]
        for i, (name, cat, brand, price, mrp) in enumerate(product_specs, start=1):
            p = Product(
                name=name,
                brand_id=brands[brand].id,
                brand_name=brand,
                category_id=categories[cat].id,
                category_name=cat,
                barcode=f"89000000000{i:02d}",
                status="APPROVED" if i <= 3 else "PENDING",
                shop_count=2,
                description=f"{name} from {brand}.",
                mrp=float(mrp),
                unit="pack",
                image_url=f"https://picsum.photos/seed/product{i}/400/400",
            )
            db.add(p)
            db.flush()
            db.add(
                ProductVariant(
                    product_id=p.id,
                    name=f"{name} — Standard",
                    variant_name="Standard",
                    sku=f"SKU-{i:04d}",
                    barcode=f"8900000001{i:02d}",
                    mrp=float(mrp),
                    price=float(price),
                    unit="pack",
                    status="ACTIVE",
                )
            )
            products.append(p)
        db.flush()

        # --- Inventory, pricing, documents per shop ----------------------
        for idx, shop in enumerate(shops, start=1):
            for p in products[: 3 if idx > 3 else 5]:
                qty = 0 if idx == 5 else 12 * idx
                db.add(
                    ShopInventory(
                        shop_id=shop.id,
                        product_id=p.id,
                        product_name=p.name,
                        quantity=qty,
                        price=p.mrp - 10 if p.mrp else None,
                        mrp=p.mrp,
                        stock_status="OUT_OF_STOCK" if qty == 0 else "IN_STOCK",
                        freshness_status="FRESH" if idx % 2 else "STALE",
                        availability="AVAILABLE" if qty else "UNAVAILABLE",
                        last_updated=_now() - timedelta(hours=idx * 20),
                        last_updated_source="POS_SYNC",
                        sync_source="POS_SYNC" if idx != 4 else "MANUAL_IMPORT",
                        sync_status="FAILED" if idx == 4 else "SUCCESS",
                        sync_error="Provider token expired" if idx == 4 else None,
                    )
                )
                shop.product_count = (shop.product_count or 0) + 1
                shop.inventory_count = (shop.inventory_count or 0) + 1
            db.flush()

            db.add(
                ShopPricing(
                    shop_id=shop.id,
                    product_id=products[0].id,
                    product_name=products[0].name,
                    sku="SKU-0001",
                    barcode=products[0].barcode,
                    price=440.0,
                    mrp=520.0,
                    currency="INR",
                )
            )

            for doc_type, title in [("GST_CERTIFICATE", "GST Certificate"), ("FSSAI_LICENSE", "FSSAI Licence")]:
                db.add(
                    ShopDocument(
                        shop_id=shop.id,
                        doc_type=doc_type,
                        title=title,
                        file_name=f"{doc_type.lower()}-{shop.id}.pdf",
                        file_url=f"https://files.example.test/{doc_type.lower()}-{shop.id}.pdf",
                        status="VERIFIED" if shop.verification_status == "VERIFIED" else "PENDING",
                        uploaded_at=_now() - timedelta(days=45),
                        expires_at=_now() + timedelta(days=320),
                        verified_at=_now() - timedelta(days=40) if shop.verification_status == "VERIFIED" else None,
                    )
                )

            db.add(
                Offer(
                    shop_id=shop.id,
                    title=f"{shop.name} — Festive {idx * 5}% Off",
                    discount_type="PERCENT",
                    discount_value=float(idx * 5),
                    status="ACTIVE" if idx % 2 else "PAUSED",
                    starts_at=_now() - timedelta(days=10),
                    ends_at=_now() + timedelta(days=20),
                    valid_from=_now() - timedelta(days=10),
                    valid_until=_now() + timedelta(days=20),
                )
            )

        # --- Audit trail (the History tab) -------------------------------
        for shop in shops:
            for offset, action in enumerate(
                ["shop.created", "shop.verification.verified", "shop.updated"]
            ):
                db.add(
                    AuditLog(
                        action=action,
                        entity_type="shop",
                        entity_id=shop.id,
                        user_id=owner.id,
                        admin_user="Platform Owner",
                        ip_address="127.0.0.1",
                        details={"note": f"{action} during onboarding"},
                        created_at=_now() - timedelta(days=30 - offset * 5),
                    )
                )
        for i in range(1, 6):
            db.add(
                AuditLog(
                    action="customer.viewed",
                    entity_type="user",
                    entity_id=i,
                    user_id=support.id,
                    admin_user="Support Admin",
                    ip_address="127.0.0.1",
                    details={"description": f"Support reviewed customer {i}"},
                )
            )

        # --- Searches -----------------------------------------------------
        for i in range(30):
            db.add(
                SearchQuery(
                    user_id=customers[i % len(customers)].id,
                    query=["rice", "milk", "bulb", "hammer", "paracetamol"][i % 5],
                    result_count=0 if i % 7 == 0 else (i % 9) + 1,
                    location="Mumbai",
                    searched_at=_now() - timedelta(days=i % 14),
                )
            )

        # --- Subscriptions & payments ------------------------------------
        for idx, shop in enumerate(shops[:4], start=1):
            sub = Subscription(
                shop_id=shop.id,
                shop_name=shop.name,
                plan_name="Growth" if idx % 2 else "Starter",
                status="ACTIVE",
                amount=999.0 * idx,
                currency="INR",
                started_at=_now() - timedelta(days=90),
                expires_at=_now() + timedelta(days=275),
            )
            db.add(sub)
            db.flush()
            db.add(
                Payment(
                    subscription_id=sub.id,
                    shop_name=shop.name,
                    amount=sub.amount,
                    currency="INR",
                    status="SUCCESS",
                    method="UPI",
                    reference=f"PAY-{sub.id:05d}",
                    paid_at=_now() - timedelta(days=idx * 10),
                )
            )

        # --- Complaints ---------------------------------------------------
        for i in range(1, 6):
            db.add(
                Complaint(
                    ticket_number=f"TKT-{i:05d}",
                    reporter_type="customer" if i % 2 else "shopkeeper",
                    reporter_name=str(i),
                    complaint_type=["WRONG_PRICE", "STOCK_MISMATCH", "APP_ISSUE"][i % 3],
                    priority=["LOW", "MEDIUM", "HIGH", "URGENT"][i % 4],
                    status=["OPEN", "IN_PROGRESS", "RESOLVED"][i % 3],
                    description=f"Issue reported by record {i}.",
                )
            )

        # --- Notifications ------------------------------------------------
        db.add(
            NotificationCampaign(
                title="Festive Season Live",
                body="Offers are now live in your area.",
                notification_type="PROMO",
                audience="all",
                status="SENT",
                deep_link="/offers",
                recipients_total=12,
                recipients_sent=12,
                recipients_failed=0,
                sent_by="Platform Owner",
                sent_at=_now() - timedelta(days=3),
            )
        )

        # --- Content ------------------------------------------------------
        db.add(Banner(title="Festive Sale", subtitle="Up to 40% off", status="PUBLISHED", placement="HOME_TOP", sort_order=1))
        db.add(Announcement(title="Platform Maintenance", body="Scheduled maintenance on Sunday.", status="PUBLISHED", audience="all"))
        db.add(Faq(question="How do I add a product?", answer="Use the Import Center.", category="Products", status="PUBLISHED"))
        db.add(HelpContent(title="Getting started", slug="getting-started", body="Welcome to the console.", section="Basics", status="PUBLISHED"))
        db.add(PromotionalCard(title="Refer a shop", description="Earn credits.", status="PUBLISHED", cta_label="Invite"))
        db.add(SystemMessage(title="Scheduled downtime", body="Sunday 02:00–04:00 IST.", severity="WARNING", status="PUBLISHED"))

        # --- POS ----------------------------------------------------------
        for idx, shop in enumerate(shops[:3], start=1):
            pos = PosIntegration(
                shop_id=shop.id,
                shop_name=shop.name,
                provider=["SQUARE", "SHOPIFY", "MARG"][idx - 1],
                status="CONNECTED" if idx != 3 else "DISCONNECTED",
                last_sync=_now() - timedelta(hours=idx * 6),
                external_ref=f"EXT-{idx:04d}",
            )
            db.add(pos)
            db.flush()
            db.add(PosSyncRun(integration_id=pos.id, status="SUCCESS", rows_synced=120 * idx, message="Nightly sync"))

        # --- Imports ------------------------------------------------------
        for idx, shop in enumerate(shops[:3], start=1):
            job = ImportJob(
                shop_id=shop.id,
                shop_name=shop.name,
                source=["CSV", "EXCEL", "POS"][idx - 1],
                filename=f"catalogue-{shop.id}.csv",
                status="COMPLETED" if idx != 2 else "FAILED",
                rows_total=100 * idx,
                rows_processed=100 * idx if idx != 2 else 40,
                rows_failed=0 if idx != 2 else 60,
            )
            db.add(job)
            db.flush()
            if idx == 2:
                for r in range(1, 6):
                    db.add(
                        ImportError(
                            import_id=job.id,
                            row_number=r,
                            column_name="barcode",
                            message="Barcode is not a valid EAN-13",
                            raw_value=f"123{r}",
                        )
                    )

        # --- System -------------------------------------------------------
        for name, enabled in [
            ("new_search_ranking", True),
            ("pos_auto_sync", True),
            ("customer_chat_support", False),
        ]:
            db.add(FeatureFlag(name=name, is_enabled=enabled, rollout_percentage=100 if enabled else 0, scope="GLOBAL"))

        for key, value, vtype, desc in [
            ("platform_name", "HyperLocal", "string", "Display name"),
            ("max_products_per_shop", "5000", "int", "Upper bound on catalogue size"),
            ("support_email", "support@hyperlocal.test", "string", "Public support address"),
            ("payment_gateway_key", "sk_live_xxxxx", "string", "Gateway secret"),
        ]:
            db.add(
                SystemSetting(
                    key=key,
                    value=value,
                    value_type=vtype,
                    description=desc,
                    is_secret=key.endswith("_key"),
                )
            )

        db.commit()
        print("[seed] Seeded successfully.")
        print(f"[seed] Admin login -> username: {DEFAULT_ADMIN}  password: {DEFAULT_PASSWORD}")
        print("[seed] Read-only admin -> username: support  password: support123")
    finally:
        db.close()


if __name__ == "__main__":
    seed()
