#!/usr/bin/env python
"""seed_data.py -- bulk-insert massive area-wise dummy data into the AWS DB.

Inserts realistic hyperlocal data across 10 Mumbai-area zones through SQLAlchemy
Core bulk inserts (multi-row VALUES), using the app's real ORM metadata.

Reads credentials from ``--url`` / ``$DATABASE_URL`` / Backend ``.env`` files.

Every seeded row uses ids allocated in the reserved range starting at
``DUMMY_ID_BASE`` and one contiguous block per table; the block map is recorded
in a ``system_settings`` manifest row (``dummy_seed_manifest_v1``) so
``cleanup_data.py`` can roll back ONLY this dummy data later.

Usage:
    python seed_data.py                         # connect via backend/.env
    python seed_data.py --url "postgresql+psycopg://user:pw@host:5432/db"
    python seed_data.py --dry-run               # print the insert plan, no DB
    python seed_data.py --reset                 # cleanup old seed first, then seed
    python seed_data.py --scale small|medium|full   # volume knob (default full)
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
import uuid
from datetime import date, datetime, time as dtime, timedelta, timezone

from sqlalchemy import text

from seed_common import (
    AREAS, BACKEND_DIR, DUMMY_ID_BASE, FIRST_NAMES, LAST_NAMES, MANIFEST_KEY,
    MANIFEST_TABLE, SEED_TAG, Allocator, build_area_shops, count_shop_products,
    make_engine, make_session, make_point, mask_url, resolve_db_url, slugify,
    _days_ago, _now,
)
from seed_catalog import BRANDS, CATALOG, flattened_items

# ── Same ORM models the API uses (guaranteed schema match) ──────────────────
from app.models.admin import (
    AdminAction, AdminNote, AuditLog, Complaint, ProductApproval, Report,
)
from app.models.analytics import (
    InventoryEvent, ProductClick, ProductView, ShopView, SystemMetric,
)
from app.models.analytics_event import AnalyticsDailyAggregate, AnalyticsEvent
from app.models.customer import Customer, CustomerAddress
from app.models.interaction import InteractionActionType, UserInteraction
from app.models.inventory_import import (
    ImportJobStatus, InventoryImportJob, InventoryImportRow,
)
from app.models.notification import (
    DeviceToken, Notification, NotificationDelivery, NotificationPreference,
)
from app.models.otp import Otp
from app.models.pos import (
    POSSyncJob, POSSyncLog, POSDevice, POSIntegration, POSProductMapping,
    POSSyncStatus,
)
from app.models.product import (
    BarcodeRelationship, Brand, Category, FreshnessStatus, IdentifierType,
    Inventory, InventoryAdjustment, InventoryMovement, InventorySource, Offer,
    OfferCondition, OfferProduct, PriceHistory, ProductAttribute,
    ProductAttributeValue, ProductIdentifier, ProductImage, ProductMaster,
    ProductStatus, ProductVariant, ShopProduct, StockStatus,
)
from app.models.role import Permission, Role, role_permissions
from app.models.saved_product import SavedProduct
from app.models.saved_shop import SavedShop
from app.models.search import (
    PopularSearch, SearchEvent, SearchHistory, SearchIndex, SearchIndexEntityType,
)
from app.models.session import AuthSession, TokenBlacklist
from app.models.shop import (
    Shop, ShopAddress, ShopCategory, ShopDocument, ShopHoliday, ShopHour,
    ShopManager, ShopOwner, ShopStatus, ShopVerification, VerificationStatus,
)
from app.models.subscription import (
    BillingCycle, Payment, PaymentEvent, Subscription, SubscriptionPlan,
    SubscriptionStatus,
)
from app.models.system import FeatureFlag, SystemSetting
from app.models.user import User, UserStatus

# Default volume knob (multiplier vs the maximum "full" dataset)
SCALE_MULTIPLIER = {"small": 0.10, "medium": 0.35, "full": 1.0}

REQUEST_HEADERS = {"executemany_mode": "values_plus_batch"}


def plan_counts(scale: str) -> dict:
    """Deterministic row counts per table for the chosen scale."""
    mul = SCALE_MULTIPLIER[scale]

    def R(n: int) -> int:
        return max(1, int(round(n * mul)))

    shops = build_area_shops()
    sp = count_shop_products(shops)

    OWNERS = len(shops)                        # one primary owner user per shop
    MANAGERS = max(1, int(round(120 * mul)))
    CUSTOMERS = max(1, int(round(1250 * mul)))
    PRODS = max(1, int(round(2400 * mul)))
    USERS = OWNERS + MANAGERS + CUSTOMERS + 1   # +1 admin

    N_CAT = len(CATALOG)

    counts = {
        # 🧩 catalog
        "categories": N_CAT,
        "brands": max(1, int(round(len(BRANDS) * mul))),
        "roles": 4,
        "permissions": 16,
        "product_masters": PRODS,
        "product_variants": PRODS,
        "product_images": PRODS,
        "product_attributes": PRODS * 2,
        "product_attribute_values": PRODS * 4,
        "product_identifiers": PRODS,
        "barcode_relationships": max(0, PRODS // 2),
        # 👥 users & auth
        "users": USERS,
        "customers": CUSTOMERS,
        "customer_addresses": CUSTOMERS * 2,
        "notification_preferences": USERS,
        "device_tokens": USERS,
        "auth_sessions": USERS,
        "otps": R(1000),
        "token_blacklist": R(500),
        # 🏪 shops + nested
        "shops": len(shops),
        "shop_addresses": len(shops) * 2,
        "shop_hours": len(shops) * 7,
        "shop_holidays": R(200),
        "shop_documents": len(shops),
        "shop_verifications": len(shops),
        "shop_owners": len(shops),
        "shop_managers": MANAGERS,
        # 📦 catalog at shop level
        "shop_products": sp,
        "inventory": sp,
        "inventory_movements": sp * 2,
        "inventory_adjustments": max(0, sp // 7),
        "price_history": int(sp * 1.8),
        "inventory_events": sp,
        # 🏷️ offers
        "offers": max(1, R(len(shops) * 2)),
        "offer_products": R(1500),
        "offer_conditions": R(500),
        # 🔍 search / discovery
        "search_indexes": sp + PRODS + len(shops) + max(1, int(round(len(BRANDS) * mul))) + N_CAT,
        "saved_products": R(3750),
        "saved_shops": R(2500),
        "user_interactions": R(6000),
        "search_history": R(5000),
        "search_events": R(6000),
        "popular_searches": max(1, int(round(40 * mul))),
        # 🔔 notifications
        "notifications": USERS * 2,
        "notification_deliveries": USERS,
        # 💳 subscriptions / payments
        "subscription_plans": 4,
        "subscriptions": R(200),
        "payments": R(200),
        "payment_events": R(200),
        # 🧾 POS integrations
        "pos_integrations": max(1, R(150)),
        "pos_devices": max(1, R(150)),
        "pos_sync_jobs": max(1, R(150)),
        "pos_sync_logs": max(1, R(300)),
        "pos_product_mappings": max(1, sp // 8),
        # 📥 inventory import jobs
        "inventory_import_jobs": max(1, R(60)),
        "inventory_import_rows": max(1, R(1200)),
        # 📊 analytics / monitoring
        "product_views": sp,
        "shop_views": max(1, R(1500)),
        "product_clicks": max(1, R(5600)),
        "system_metrics": max(1, R(240)),
        "analytics_events": max(1, R(12000)),
        "analytics_daily_aggregates": 24,
        # 🛡️ admin & audit
        "audit_logs": max(1, R(1000)),
        "admin_actions": max(1, R(120)),
        "admin_notes": max(1, R(60)),
        "product_approvals": max(1, R(500)),
        "reports": max(1, R(40)),
        "complaints": max(1, R(200)),
        # ⚙️ system flags + manifest row
        "feature_flags": 12,
        "system_settings": 13,   # 12 feature flags + 1 manifest
    }
    return counts
def insert_rows(db, table, rows, chunk: int = 300, label: str = ""):
    """Multi-row VALUES insert in chunks (fast, minimal round-trips)."""
    total = len(rows)
    for i in range(0, total, chunk):
        db.execute(table.insert().values(list(rows[i:i + chunk])))
    return total


def _bump_sequences(db, tables: list[str]) -> None:
    """Advance each table's id sequence past the reserved dummy blocks."""
    for t in tables:
        try:
            seq = db.execute(
                text("SELECT pg_get_serial_sequence('public.' || :t, 'id')"), {"t": t}
            ).scalar()
            if not seq:
                continue
            db.execute(
                text(f"SELECT setval(:seq, (SELECT COALESCE(MAX(id), 0) + 1 FROM {t}))"),
                {"seq": seq},
            )
        except Exception as exc:  # best-effort
            print(f"  [warn] sequence bump failed for {t}: {exc}")


class Seeder:
    def __init__(self, db, allocator: Allocator, scale: str):
        self.db = db
        self.alloc = allocator
        self.scale = scale
        self.manifest = {"seed_version": "1.0", "created_at": _now().isoformat(),
                         "base_id": allocator.base, "tables": {}, "notes": []}

    # ---- Step 0: manifest placeholder (written before any other row) ----
    def begin_manifest(self) -> None:
        st = SystemSetting.__table__
        # The manifest row takes the FIRST reserved id of the system_settings block
        st_ids = list(self.alloc.ids(MANIFEST_TABLE))
        self.manifest_row_id = st_ids[0] if st_ids else None
        self.db.execute(st.insert().values([{
            "id": self.manifest_row_id,
            "key": MANIFEST_KEY,
            "value": json.dumps({"tables": {}}, sort_keys=True),
            "value_type": "json",
            "description": f"{SEED_TAG} rollback ledger for db_seed area seeder",
            "is_secret": False,
        }]))
# ---- Step 1: RBAC (adopt existing; create missing; all recorded) -----
    def seed_rbac(self) -> dict:
        db = self.db
        roles_to_ensure = {"customer": "default customer", "shop_owner": "shop business role",
                           "shop_manager": "shop manager role", "admin": "platform admin"}
        perms = [("product.read", "product", "read"), ("product.create", "product", "create"),
                 ("product.update", "product", "update"), ("shop.read", "shop", "read"),
                 ("shop.update", "shop", "update"), ("inventory.read", "inventory", "read"),
                 ("inventory.update", "inventory", "update"), ("inventory.create", "inventory", "create"),
                 ("offer.create", "offer", "create"), ("offer.update", "offer", "update"),
                 ("search.read", "search", "read"), ("saved_product.manage", "saved_product", "manage"),
                 ("saved_shop.manage", "saved_shop", "manage"), ("notification.read", "notification", "read"),
                 ("profile.manage", "profile", "manage"), ("admin.all", "admin", "all")]
        role_ids: dict[str, int] = {}
        created_roles: list[int] = []
        created_perms: list[int] = []

        existing_perm = {r[0]: r[1] for r in db.query(Permission.name, Permission.id).all()}
        perm_rows = []
        for (name, res, act) in perms:
            if name not in existing_perm:
                perm_rows.append((name, res, act))
        perm_ids = list(self.alloc.ids("permissions"))[:len(perm_rows)]
        perm_map: dict[str, int] = dict(existing_perm)
        final_rows = []
        for (pname, res, act), pid in zip(perm_rows, perm_ids):
            final_rows.append({"id": pid, "name": pname, "description": f"{SEED_TAG} {pname}",
                               "resource": res, "action": act})
            perm_map[pname] = pid
            created_perms.append(pid)
        if final_rows:
            insert_rows(db, Permission.__table__, final_rows, chunk=50, label="permissions")

        existing_role = {r[0]: r[1] for r in db.query(Role.name, Role.id).all()}
        role_ids_avail = iter(self.alloc.ids("roles"))
        role_rows = []
        for rname, rdesc in roles_to_ensure.items():
            if rname in existing_role:
                role_ids[rname] = existing_role[rname]
                continue
            rid = next(role_ids_avail)
            role_rows.append({"id": rid, "name": rname, "description": f"{SEED_TAG} {rdesc}"})
            role_ids[rname] = rid
            created_roles.append(rid)
        if role_rows:
            insert_rows(db, Role.__table__, role_rows, chunk=20, label="roles")

        link_map = {
            "customer": ["product.read", "shop.read", "search.read", "saved_product.manage",
                         "saved_shop.manage", "notification.read", "profile.manage"],
            "shop_owner": ["product.create", "product.update", "shop.update", "inventory.read",
                           "inventory.update", "inventory.create", "offer.create", "offer.update"],
            "shop_manager": ["product.update", "inventory.update", "inventory.create", "offer.update"],
            "admin": ["admin.all", "product.create", "inventory.update", "shop.update"],
        }
        link_rows = []
        for rname, plist in link_map.items():
            rid = role_ids.get(rname)
            if not rid:
                continue
            for pname in plist:
                pid = perm_map.get(pname)
                if pid:
                    link_rows.append({"role_id": rid, "permission_id": pid})
        seen = set()
        uniq = []
        for lr in link_rows:
            k = (lr["role_id"], lr["permission_id"])
            if k not in seen:
                seen.add(k)
                uniq.append(lr)
        if uniq:
            db.execute(role_permissions.insert().values(uniq))

        self.manifest["roles"] = role_ids
        self.manifest["created_roles"] = created_roles
        self.manifest["created_permissions"] = created_perms
        return role_ids
# ---- Step 2: categories & brands (adopt-if-exists) ---------------------
    def seed_categories_brands(self) -> dict:
        db = self.db
        existing_cat = {r[0]: r[1] for r in db.query(Category.name, Category.id).all()}
        cat_rows = []
        cat_ids: dict[str, int] = {}
        created_cats: list[int] = []
        cat_id_iter = iter(self.alloc.ids("categories"))
        for cname, _items in CATALOG:
            if cname in existing_cat:
                cat_ids[cname] = existing_cat[cname]
                continue
            cid = next(cat_id_iter)
            cat_rows.append({"id": cid, "name": cname, "slug": f"dummy-{slugify(cname)}",
                             "description": f"{SEED_TAG} hyperlocal category",
                             "sort_order": len(cat_rows), "is_active": True,
                             "is_subcategory": False})
            cat_ids[cname] = cid
            created_cats.append(cid)
        if cat_rows:
            insert_rows(db, Category.__table__, cat_rows, chunk=50, label="categories")
        db.flush()

        n_brands = self.alloc.block("brands")[1]
        existing_brand = {r[0]: r[1] for r in db.query(Brand.name, Brand.id).all()}
        brand_rows = []
        brand_ids: dict[str, int] = {}
        created_brands: list[int] = []
        brand_id_iter = iter(self.alloc.ids("brands"))
        for bname in BRANDS:
            if len(brand_rows) >= n_brands:
                break
            if bname in existing_brand:
                if bname not in brand_ids:
                    brand_ids[bname] = existing_brand[bname]
                continue
            if bname in brand_ids:
                continue
            bid = next(brand_id_iter)
            brand_rows.append({"id": bid, "name": bname, "slug": f"dummy-{slugify(bname)}",
# ---- Step 3: product masters + variants + images + attrs + ids ----------
    def seed_products(self, cat_ids: dict, brand_ids: dict) -> dict:
        db = self.db
        n_prod = self.alloc.block("product_masters")[1]
        cat_names = [c for c, _ in CATALOG]
        brand_names = list(brand_ids.keys())
        items = flattened_items()

        prod_ids = list(self.alloc.ids("product_masters"))
        var_ids = list(self.alloc.ids("product_variants"))
        img_ids = list(self.alloc.ids("product_images"))
        attr_ids = list(self.alloc.ids("product_attributes"))
        aval_ids = list(self.alloc.ids("product_attribute_values"))
        iden_ids = list(self.alloc.ids("product_identifiers"))
        brel_ids = list(self.alloc.ids("barcode_relationships"))

        prod_rows, var_rows, img_rows, attr_rows, aval_rows, iden_rows, brel_rows = (
            [], [], [], [], [], [], [])
        bcode = 700000000
        for p in range(n_prod):
            bcode += 1
            barcode = f"8904{bcode:09d}"
            cname = cat_names[p % len(cat_names)]
            bname = brand_names[p % len(brand_names)] if brand_names else BRANDS[0]
            _c, itname, unit, pmin, pmax, packs = items[p % len(items)]
            pack = packs[p % len(packs)]
            price = round(pmin + ((p * 7) % (pmax - pmin + 1)), 2)

            pid, vid = prod_ids[p], var_ids[p]
            prod_rows.append({
                "id": pid, "name": f"{bname} {itname} {pack}", "slug": f"dummy-product-{pid:08d}",
                "description": f"{SEED_TAG} {itname}, {unit}", "short_description": f"{itname} {unit}",
                "category_id": cat_ids.get(cname), "subcategory_id": None,
                "brand_id": brand_ids.get(bname), "status": ProductStatus.APPROVED.value,
                "is_active": True, "is_featured": (p % 17 == 0), "is_searchable": True,
                "base_unit": unit, "base_quantity": 1.0, "search_metadata": json.dumps({"seeded": True}),
            })
            var_rows.append({
                "id": vid, "product_master_id": pid, "sku": f"DSKU-{pid:09d}",
                "name": prod_rows[-1]["name"], "description": f"{SEED_TAG} default variant",
                "attributes_json": json.dumps({"unit": unit}), "is_active": True, "sort_order": 0,
            })
            img_rows.append({
                "id": img_ids[p], "product_master_id": pid, "variant_id": vid,
                "image_url": f"https://cdn.example.in/seeded/p{pid:09d}.jpg",
                "thumbnail_url": f"https://cdn.example.in/seeded/p{pid:09d}_t.jpg",
                "alt_text": prod_rows[-1]["name"], "sort_order": 0, "is_primary": True,
            })
            a_a = attr_ids[p * 2]
            attr_rows.append({"id": a_a, "product_master_id": pid, "name": "Pack Size",
                              "is_variant_defining": True, "sort_order": 0})
            aval_rows.append({"id": aval_ids[p * 4], "attribute_id": a_a, "value": pack, "sort_order": 0})
            if p * 2 + 1 < len(attr_ids):
                a_b = attr_ids[p * 2 + 1]
                attr_rows.append({"id": a_b, "product_master_id": pid, "name": "Unit",
                                  "is_variant_defining": False, "sort_order": 1})
                aval_rows.append({"id": aval_ids[p * 4 + 1], "attribute_id": a_b, "value": unit,
                                  "sort_order": 0})
            iden_rows.append({
                "id": iden_ids[p], "product_master_id": pid,
                "identifier_type": IdentifierType.EAN.value, "identifier_value": barcode,
                "is_primary": True, "is_active": True,
            })
            if p % 2 == 0 and p < len(brel_ids):
                brel_rows.append({
                    "id": brel_ids[p], "product_master_id": pid, "barcode": barcode,
                    "relationship_type": "PRIMARY", "related_product_master_id": None,
                    "is_active": True, "notes": f"{SEED_TAG} barcode record",
                })

        insert_rows(db, ProductMaster.__table__, prod_rows, chunk=250, label="product_masters")
        db.flush()
        insert_rows(db, ProductVariant.__table__, var_rows, chunk=250, label="product_variants")
        insert_rows(db, ProductImage.__table__, img_rows, chunk=250, label="product_images")
        insert_rows(db, ProductAttribute.__table__, attr_rows, chunk=300, label="product_attributes")
        insert_rows(db, ProductAttributeValue.__table__, aval_rows, chunk=300, label="product_attribute_values")
        insert_rows(db, ProductIdentifier.__table__, iden_rows, chunk=300, label="product_identifiers")
        if brel_rows:
            insert_rows(db, BarcodeRelationship.__table__, brel_rows, chunk=300, label="barcode_relationships")

        return {"prod_ids": prod_ids, "var_ids": var_ids, "img_ids": img_ids}
                               "description": f"{SEED_TAG} brand", "is_active": True})
            brand_ids[bname] = bid
            created_brands.append(bid)
        while len(brand_rows) < n_brands:    # padded fallback names
            bname = f"{SEED_TAG} Household {len(brand_rows) + 1}"
            bid = next(brand_id_iter)
            brand_rows.append({"id": bid, "name": bname, "slug": f"dummy-brand-h{len(brand_rows):03d}",
                               "description": f"{SEED_TAG} brand", "is_active": True})
            brand_ids[bname] = bid
            created_brands.append(bid)
        if brand_rows:
            insert_rows(db, Brand.__table__, brand_rows, chunk=50, label="brands")
        db.flush()

        self.manifest["categories_created"] = created_cats
        self.manifest["brands_created"] = created_brands
        return {"cat_ids": cat_ids, "brand_ids": brand_ids}
# ---- Step 4: users / customers / addresses / prefs / devices / otps ----
    def seed_users(self, role_ids: dict) -> dict:
        db = self.db
        n_users = self.alloc.block("users")[1]
        n_cust = self.alloc.block("customers")[1]
        shop_count = self.alloc.block("shops")[1]

        user_ids = list(self.alloc.ids("users"))
        cust_ids = list(self.alloc.ids("customers"))
        addr_ids = list(self.alloc.ids("customer_addresses"))
        pref_ids = list(self.alloc.ids("notification_preferences"))
        dev_ids = list(self.alloc.ids("device_tokens"))
        sess_ids = list(self.alloc.ids("auth_sessions"))
        otp_ids = list(self.alloc.ids("otps"))

        user_rows, cust_rows, addr_rows, pref_rows, dev_rows, sess_rows = ([], [], [], [], [], [])
        addr_id_iter = iter(addr_ids)
        cust_id_iter = iter(cust_ids)

        r_customer = role_ids["customer"]
        r_owner = role_ids["shop_owner"]
        r_manager = role_ids["shop_manager"]
        r_admin = role_ids["admin"]

        owner_end = shop_count
        mgr_start, mgr_end = owner_end, owner_end + self.alloc.block("shop_managers")[1]
        cust_end = mgr_end + n_cust
        admin_idx = min(cust_end, n_users - 1)
        name_pool = [(f, l) for f in FIRST_NAMES for l in LAST_NAMES]

        for u in range(n_users):
            fname, lname = name_pool[u % len(name_pool)]
            if u < owner_end:
                role = r_owner
            elif u < mgr_end:
                role = r_manager
            elif u < min(cust_end, n_users):
                role = r_customer
            else:
                role = r_admin
            uid = user_ids[u]
            user_rows.append({
                "id": uid, "phone_number": f"+919999{u + 1000:06d}", "google_id": None,
                "name": f"{fname} {lname}", "email": f"seed.user{u + 1000}@hyperlocal-seed.example",
                "avatar_url": None, "password_hash": None, "role_id": role,
                "status": UserStatus.ACTIVE.value, "is_active": True,
                "last_login_at": None, "last_login_ip": None,
            })
            if mgr_start <= u < min(cust_end, n_users):
                cid = next(cust_id_iter)
                cust_rows.append({
                    "id": cid, "user_id": uid,
                    "date_of_birth": _days_ago(9500 + (u % 9000)),
                    "gender": "male" if u % 2 else "female",
                    "preferred_language": "en" if u % 3 else "hi",
                    "default_address_id": None,
                })
            pref_rows.append({"id": pref_ids[u], "user_id": uid, "push_enabled": True,
                              "email_enabled": True, "sms_enabled": False, "price_alerts": u % 4 != 0,
                              "availability_alerts": True, "promotional": u % 5 == 0, "deal_alerts": True})
            dev_rows.append({
                "id": dev_ids[u], "user_id": uid,
                "token": f"fcm-seed-{u + 1000:06d}-{uuid.uuid4().hex[:12]}",
                "device_type": "android" if u % 3 else "ios", "platform": "FCM", "is_active": True,
                "failure_count": 0, "last_used_at": _days_ago(u % 30), "expires_at": None,
                "app_version": "1.0.0",
            })
            sess_rows.append({
                "id": sess_ids[u], "session_id": str(uuid.uuid4()), "user_id": uid,
                "device_id": f"dev-{u + 1000:06d}", "device_name": "Pixel SEED", "device_type": "android",
                "platform": "Android 14", "app_version": "1.0.0", "ip_address": None, "user_agent": None,
                "refresh_token_hash": hashlib.sha256(f"seed-refresh-{u}".encode()).hexdigest(),
                "refresh_token_expires_at": _days_ago(-14), "is_active": True,
                "last_activity_at": _days_ago(u % 15), "expires_at": _days_ago(-16),
            })
# addresses: 2 per customer (deterministic per area)
        for c in range(n_cust):
            u = mgr_start + c
            if u >= n_users:
                break
            uid = user_ids[u]
            cid = cust_ids[c]
            area = AREAS[c % len(AREAS)]
            a1 = next(addr_id_iter)
            addr_rows.append({"id": a1, "user_id": uid, "customer_id": cid, "label": "Home",
                              "address_line1": f"Plot {c % 90 + 1}, Sector {c % 12 + 1}, {area[1]}",
                              "address_line2": None, "city": area[5], "state": "Maharashtra",
                              "pincode": area[4], "country": "India", "location": None,
                              "is_default": True, "is_verified": False})
            a2 = next(addr_id_iter)
            addr_rows.append({"id": a2, "user_id": uid, "customer_id": cid, "label": "Work",
                              "address_line1": f"Shop {c % 60 + 1}, Market Yard, {area[1]}",
                              "address_line2": "CST Road", "city": area[5], "state": "Maharashtra",
                              "pincode": area[4], "country": "India", "location": None,
                              "is_default": False, "is_verified": False})
        for c in range(len(cust_rows)):
            cust_rows[c]["default_address_id"] = addr_ids[c * 2]

        insert_rows(db, User.__table__, user_rows, chunk=300, label="users")
        db.flush()
        insert_rows(db, Customer.__table__, cust_rows, chunk=300, label="customers")
        insert_rows(db, CustomerAddress.__table__, addr_rows, chunk=300, label="customer_addresses")
        insert_rows(db, NotificationPreference.__table__, pref_rows, chunk=300, label="notification_preferences")
        insert_rows(db, DeviceToken.__table__, dev_rows, chunk=300, label="device_tokens")
        insert_rows(db, AuthSession.__table__, sess_rows, chunk=300, label="auth_sessions")

        otp_rows = []
        for o in range(len(otp_ids)):
            otp_rows.append({"id": otp_ids[o], "phone_number": f"+919999{o + 2000:06d}",
                             "otp_code": hashlib.sha256(f"seed-otp-{o}".encode()).hexdigest(),
                             "expires_at": _now() + timedelta(minutes=5), "is_verified": o % 2 == 0})
        insert_rows(db, Otp.__table__, otp_rows, chunk=300, label="otps")

        return {"user_ids": user_ids, "customer_ids": cust_ids, "addr_ids": addr_ids,
                "owner_end": owner_end, "mgr_start": mgr_start, "mgr_end": mgr_end,
                "cust_end": cust_end, "admin_idx": admin_idx, "dev_ids": dev_ids,
                "cust_start": mgr_start, "user_rows": user_rows}
# ---- Step 5: shops + shop-address/hours/holidays/docs/verif/owners -----
    def seed_shops(self, users_meta: dict, role_ids: dict) -> dict:
        db = self.db
        shops = build_area_shops()
        n_shops = len(shops)
        shop_ids = list(self.alloc.ids("shops"))
        addr_ids = list(self.alloc.ids("shop_addresses"))
        hour_ids = list(self.alloc.ids("shop_hours"))
        holi_ids = list(self.alloc.ids("shop_holidays"))
        doc_ids = list(self.alloc.ids("shop_documents"))
        ver_ids = list(self.alloc.ids("shop_verifications"))
        own_ids = list(self.alloc.ids("shop_owners"))
        mgr_ids = list(self.alloc.ids("shop_managers"))

        user_ids = users_meta["user_ids"]
        owner_end = users_meta["owner_end"]
        mgr_start, mgr_end = users_meta["mgr_start"], users_meta["mgr_end"]
        admin_idx = users_meta["admin_idx"]

        shop_rows, saddr_rows, shour_rows, sholi_rows = ([], [], [], [])
        sdoc_rows, sver_rows, sown_rows, smgr_rows = ([], [], [], [])
        addr_iter, hour_iter, holi_iter = iter(addr_ids), iter(hour_ids), iter(holi_ids)
        doc_iter, ver_iter, own_iter, mgr_iter = (iter(doc_ids), iter(ver_ids), iter(own_ids), iter(mgr_ids))

        for si, sh in enumerate(shops):
            sid = shop_ids[si]
            owner_uid = user_ids[si % owner_end]
            status = ShopStatus.VERIFIED.value if si % 4 else ShopStatus.ACTIVE.value
            rating = round(3.2 + ((si * 13) % 18) / 10.0, 1)   # 3.2 .. 5.0
            shop_rows.append({
                "id": sid, "name": sh["name"], "slug": sh["slug"],
                "description": f"{SEED_TAG} {sh['name']} in {sh['area_name']}",
                "tagline": f"Neighbourhood {sh['category'].title()}",
                "image_url": f"https://cdn.example.in/seeded/shop{sid:09d}.jpg",
                "cover_image_url": None, "logo_url": None,
                "phone": f"+9122{si:07d}", "alternate_phone": None,
                "email": f"shop{si:04d}@hyperlocal-seed.example",
                "website_url": None, "whatsapp_number": f"+9122{si:07d}",
                "status": status, "rating": rating, "review_count": (si * 37) % 200,
                "is_verified": si % 4 != 0, "is_featured": si % 11 == 0,
                "is_open_24x7": sh["category"] in ("RESTAURANT", "PHARMACY") and si % 3 == 0,
                "is_accepting_orders": True,
                "category": ShopCategory[sh["category"]].value,
                "subcategories": None,
                "location": make_point(sh["lon"], sh["lat"]),
                "latitude": sh["lat"], "longitude": sh["lon"],
                "verified_at": _days_ago(60 + si % 200) if si % 4 != 0 else None,
                "last_inventory_update": _days_ago(si % 7),
                "min_order_amount": 49.0 if sh["category"] in ("GROCERY", "VEGETABLES", "DAIRY") else 99.0,
                "delivery_radius_km": 3.0 + (si % 5), "delivery_fee": 0.0,
                "free_delivery_above": 499.0 if si % 3 else 0.0,
                "is_delivery_available": True, "is_pickup_available": True,
                "gstin": f"27AAAA{sid}1ZC", "fssai_license": f"FSSAI-{sid:06d}",
                "established_year": 1995 + (si % 28), "created_by": owner_uid,
            })
            a1 = next(addr_iter)
            saddr_rows.append({"id": a1, "shop_id": sid,
                               "address_line1": f"Shop {si % 80 + 1}, {sh['area_name']} Main Road",
                               "address_line2": sh["area_name"], "city": sh["city"],
                               "state": "Maharashtra", "pincode": sh["pincode"],
                               "country": "India", "latitude": sh["lat"], "longitude": sh["lon"],
                               "is_primary": True, "is_verified": False})
            a2 = next(addr_iter)
            saddr_rows.append({"id": a2, "shop_id": sid,
                               "address_line1": f"Godown {si % 20 + 1}, Market Yard, {sh['area_name']}",
                               "address_line2": None, "city": sh["city"], "state": "Maharashtra",
                               "pincode": sh["pincode"], "country": "India",
                               "latitude": sh["lat"], "longitude": sh["lon"],
                               "is_primary": False, "is_verified": False})
            for dow in range(7):
                shour_rows.append({"id": next(hour_iter), "shop_id": sid, "day_of_week": dow,
                                   "open_time": dtime(8, 0), "close_time": dtime(21, 30),
                                   "is_closed": dow == 6 and si % 3 == 0})
if si % 3 == 0:
                sholi_rows.append({"id": next(holi_iter), "shop_id": sid,
                                   "holiday_date": date(2026, 1, 26),
                                   "reason": "Republic Day", "is_recurring_yearly": True})
                if si % 7 == 0:
                    sholi_rows.append({"id": next(holi_iter), "shop_id": sid,
                                       "holiday_date": date(2026, 8, 15),
                                       "reason": "Independence Day", "is_recurring_yearly": True})
            sdoc_rows.append({"id": next(doc_iter), "shop_id": sid, "document_type": "GST",
                              "document_url": f"https://cdn.example.in/seeded/docs/gst{sid:09d}.pdf",
                              "document_number": f"27AAAA{sid}1ZC", "expires_at": None,
                              "is_verified": si % 4 != 0, "rejection_reason": None})
            sver_rows.append({"id": next(ver_iter), "shop_id": sid,
                              "status": VerificationStatus.VERIFIED.value if si % 4 else VerificationStatus.PENDING.value,
                              "submitted_by": owner_uid, "reviewed_by": user_ids[admin_idx] if si % 4 else None,
                              "review_notes": f"{SEED_TAG} verified", "submitted_at": _days_ago(70),
                              "reviewed_at": _days_ago(60) if si % 4 else None,
                              "verified_at": _days_ago(60) if si % 4 else None, "expires_at": None})
            sown_rows.append({"id": next(own_iter), "shop_id": sid, "user_id": owner_uid,
                              "is_primary": True, "is_active": True})
            if mgr_start + si < mgr_end:
                try:
                    mid = next(mgr_iter)
                except StopIteration:
                    mid = None
                if mid is not None:
                    smgr_rows.append({"id": mid, "shop_id": sid, "user_id": user_ids[mgr_start + si],
                                      "permissions": json.dumps(["inventory.update", "offer.update"]),
                                      "is_active": True})

        insert_rows(db, Shop.__table__, shop_rows, chunk=150, label="shops")
        db.flush()
        insert_rows(db, ShopAddress.__table__, saddr_rows, chunk=300, label="shop_addresses")
        insert_rows(db, ShopHour.__table__, shour_rows, chunk=400, label="shop_hours")
        insert_rows(db, ShopHoliday.__table__, sholi_rows, chunk=100, label="shop_holidays")
        insert_rows(db, ShopDocument.__table__, sdoc_rows, chunk=200, label="shop_documents")
        insert_rows(db, ShopVerification.__table__, sver_rows, chunk=200, label="shop_verifications")
        insert_rows(db, ShopOwner.__table__, sown_rows, chunk=200, label="shop_owners")
        insert_rows(db, ShopManager.__table__, smgr_rows, chunk=100, label="shop_managers")
        return {"shop_ids": shop_ids, "shop_specs": shops}

    # ---- product info helpers (same deterministic formulas) ----------------
    @staticmethod
    def prod_info(p: int) -> tuple:
        items = flattened_items()
        _c, itname, unit, pmin, pmax, packs = items[p % len(items)]
        price = round(pmin + ((p * 7) % (pmax - pmin + 1)), 2)
        return price, itname, unit

    @staticmethod
    def prod_mrp(price: float, p: int) -> float:
        return round(price * 1.2 + (p % 20), 2)

    @staticmethod
    def sp_flat_offset(si: int, k: int, specs: list) -> int:
        """Flat index of a (shop idx, listing idx) in the concatenated listing order."""
        offset = 0
        for i, sh in enumerate(specs):
            if i == si:
                return offset + k
            offset += sh["num_listings"]
        return offset + k

    # ---- Step 6: shop_products + inventory + price/inventory history --------
    def seed_shop_products(self, shops_meta: dict, prods_meta: dict, users_meta: dict) -> dict:
        db = self.db
        shop_ids = shops_meta["shop_ids"]
        specs = shops_meta["shop_specs"]
        prod_ids = prods_meta["prod_ids"]
        var_ids = prods_meta["var_ids"]
        n_prod = len(prod_ids)

        sp_ids = list(self.alloc.ids("shop_products"))
        inv_ids = list(self.alloc.ids("inventory"))
        mov_ids = list(self.alloc.ids("inventory_movements"))
        adj_ids = list(self.alloc.ids("inventory_adjustments"))
        ph_ids = list(self.alloc.ids("price_history"))
        iev_ids = list(self.alloc.ids("inventory_events"))

        sp_rows, inv_rows, mov_rows, adj_rows, ph_rows, iev_rows = ([], [], [], [], [], [])
        mov_iter, adj_iter, ph_iter, iev_iter = iter(mov_ids), iter(adj_ids), iter(ph_ids), iter(iev_ids)

        owner_users = users_meta["user_ids"]
        owner_end = users_meta["owner_end"]

        for si, sh in enumerate(specs):
            sid = shop_ids[si]
            start_p = (si * 47) % n_prod
            for k in range(sh["num_listings"]):
                p = (start_p + k) % n_prod
                pid, vid = prod_ids[p], var_ids[p]
                price, _it, _un = self.prod_info(p)
                mrp = self.prod_mrp(price, p)
                flat = self.sp_flat_offset(si, k, specs)
                sid_sp = sp_ids[flat]
                stock = "IN_STOCK" if (p + k) % 7 else "LIMITED_STOCK"
                qty = 4 + ((p * 17 + k * 3) % 95)
                sp_rows.append({
                    "id": sid_sp, "shop_id": sid, "product_master_id": pid, "variant_id": vid,
                    "sku": f"DP-{si:03d}-{k:05d}",
                    "status": ShopProductStatus.ACTIVE.value, "price": price, "mrp": mrp,
                    "is_active": True, "is_available": True, "is_featured": k % 19 == 0,
                    "is_visible": True, "stock_status": stock,
                    "freshness_status": FreshnessStatus.RECENTLY_UPDATED.value,
                    "last_inventory_update": _days_ago((p + k) % 5),
                    "last_price_update": _days_ago((p + k) % 20),
                    "source": InventorySource.MANUAL.value,
                })
                iv = inv_ids[flat]
                inv_rows.append({
                    "id": iv, "shop_product_id": sid_sp,
                    "quantity": qty, "reserved_quantity": qty // 5,
                    "available_quantity": qty - qty // 5,
                    "is_available": True, "stock_status": stock, "low_stock_threshold": 5,
                    "last_updated_by": owner_users[si % owner_end],
                    "last_updated_source": InventorySource.MANUAL.value,
                    "freshness_status": FreshnessStatus.RECENTLY_UPDATED.value,
                })
try:
                    m1 = next(mov_iter)
                except StopIteration:
                    m1 = None
                if m1 is not None:
                    mov_rows.append({"id": m1, "inventory_id": iv, "quantity_change": +qty,
                                     "quantity_before": 0, "quantity_after": qty,
                                     "movement_type": "RESTOCK", "source": InventorySource.MANUAL.value,
                                     "reference_type": "seed", "notes": f"{SEED_TAG} stock-in"})
                try:
                    m2 = next(mov_iter)
                except StopIteration:
                    m2 = None
                if m2 is not None:
                    mov_rows.append({"id": m2, "inventory_id": iv, "quantity_change": -(qty // 3),
                                     "quantity_before": qty, "quantity_after": qty - qty // 3,
                                     "movement_type": "SALE", "source": InventorySource.MANUAL.value,
                                     "reference_type": "seed", "notes": f"{SEED_TAG} sale out"})
                try:
                    ph_id = next(ph_iter)
                except StopIteration:
                    ph_id = None
                if ph_id is not None:
                    ph_rows.append({"id": ph_id, "shop_product_id": sid_sp,
                                    "old_price": round(price * 1.05, 2), "new_price": price,
                                    "old_mrp": mrp, "new_mrp": mrp,
                                    "changed_by": owner_users[si % owner_end],
                                    "change_source": InventorySource.MANUAL.value,
                                    "effective_from": _days_ago(30), "effective_to": None})
                try:
                    ie_id = next(iev_iter)
                except StopIteration:
                    ie_id = None
                if ie_id is not None:
                    iev_rows.append({"id": ie_id, "shop_product_id": sid_sp, "event_type": "STOCK",
                                     "quantity_change": qty, "source": InventorySource.MANUAL.value,
                                     "reference_type": "SEED", "notes": f"{SEED_TAG} initial stock",
                                     "created_by": owner_users[si % owner_end],
                                     "occurred_at": _days_ago((p + k) % 5)})

        # inventory adjustments (subset of inventories)
        taken = min(len(adj_ids), len(sp_ids) // 7)
        for i in range(taken):
            inv_id = inv_ids[i * 7]
            adj_rows.append({"id": adj_ids[i], "inventory_id": inv_id, "adjustment_type": "STOCK_COUNT",
                             "quantity_adjustment": -1, "reason": f"{SEED_TAG} cycle count",
                             "approved_by": owner_users[0], "approved_at": _days_ago(3)})

        insert_rows(db, ShopProduct.__table__, sp_rows, chunk=250, label="shop_products")
        db.flush()
        insert_rows(db, Inventory.__table__, inv_rows, chunk=250, label="inventory")
        insert_rows(db, InventoryMovement.__table__, mov_rows, chunk=300, label="inventory_movements")
        if adj_rows:
            insert_rows(db, InventoryAdjustment.__table__, adj_rows, chunk=200, label="inventory_adjustments")
        insert_rows(db, PriceHistory.__table__, ph_rows, chunk=300, label="price_history")
        insert_rows(db, InventoryEvent.__table__, iev_rows, chunk=250, label="inventory_events")
        return {"sp_ids": sp_ids, "inv_ids": inv_ids, "specs": specs}
# ---- Step 7: offers / offer_products / offer_conditions ---------------
    def seed_offers(self, shops_meta: dict, sp_meta: dict) -> dict:
        db = self.db
        shop_ids = shops_meta["shop_ids"]
        sp_ids = sp_meta["sp_ids"]
        specs = sp_meta["specs"]

        off_ids = list(self.alloc.ids("offers"))
        op_ids = list(self.alloc.ids("offer_products"))
        oc_ids = list(self.alloc.ids("offer_conditions"))

        offer_rows, op_rows, oc_rows = [], [], []
        op_iter = iter(op_ids)
        oc_iter = iter(oc_ids)
        n_offers = len(off_ids)

        for oi in range(n_offers):
            sid = shop_ids[oi % len(shop_ids)]
            sh_name = specs[oi % len(specs)]["name"]
            otype = oi % 4
            offer_rows.append({
                "id": off_ids[oi], "shop_id": sid,
                "title": f"{SEED_TAG} {sh_name} Mega Discount {oi}",
                "description": f"{SEED_TAG} limited-time hyperlocal offer",
                "offer_type": (["PERCENTAGE_DISCOUNT", "FLAT_DISCOUNT", "BUY_X_GET_Y", "FREE_SHIPPING"])[otype],
                "discount_value": None if otype == 0 else round(20 + oi % 80, 0),
                "discount_percentage": (5 + oi % 25) if otype == 0 else None,
                "min_purchase_amount": 199.0 if oi % 2 else None,
                "max_discount_amount": 150.0 if otype == 1 else None,
                "buy_quantity": 2 if otype == 2 else None,
                "get_quantity": 1 if otype == 2 else None,
                "status": OfferStatus.ACTIVE.value if oi % 6 else OfferStatus.PAUSED.value,
                "start_date": _days_ago(3), "end_date": _days_ago(-10),
                "is_visible": True, "terms_conditions": f"{SEED_TAG} terms",
            })
            # 3 offer products per offer
            for j in range(3):
                try:
                    op_id = next(op_iter)
                except StopIteration:
                    op_id = None
                if op_id is None:
                    break
                sp_target = sp_ids[(oi * 13 + j) % len(sp_ids)]
                op_rows.append({"id": op_id, "offer_id": off_ids[oi], "shop_product_id": sp_target,
                                "is_excluded": j == 2 and oi % 4 == 0})
            # condition
            try:
                oc_id = next(oc_iter)
            except StopIteration:
                oc_id = None
            if oc_id is not None:
                oc_rows.append({"id": oc_id, "offer_id": off_ids[oi],
                                "condition_type": "MIN_AMOUNT", "condition_value": "199", "operator": ">="})

        insert_rows(db, Offer.__table__, offer_rows, chunk=200, label="offers")
        insert_rows(db, OfferProduct.__table__, op_rows, chunk=300, label="offer_products")
        insert_rows(db, OfferCondition.__table__, oc_rows, chunk=200, label="offer_conditions")
        return {"offer_ids": off_ids}
# ---- Step 8: search index + saved items + interactions + search rows ---
    def seed_search_and_saves(self, cat_ids: dict, brand_ids: dict, prods_meta: dict,
                              shops_meta: dict, sp_meta: dict, users_meta: dict) -> dict:
        db = self.db
        prod_ids = prods_meta["prod_ids"]
        var_ids = prods_meta["var_ids"]
        shop_ids = shops_meta["shop_ids"]
        specs = shops_meta["shop_specs"]
        sp_ids = sp_meta["sp_ids"]
        sp_specs = sp_meta["specs"]
        user_ids = users_meta["user_ids"]
        cust_start, cust_end = users_meta["cust_start"], users_meta["cust_end"]
        n_prod = len(prod_ids)

        si_ids = list(self.alloc.ids("search_indexes"))
        saved_p_ids = list(self.alloc.ids("saved_products"))
        saved_s_ids = list(self.alloc.ids("saved_shops"))
        inter_ids = list(self.alloc.ids("user_interactions"))
        hist_ids = list(self.alloc.ids("search_history"))
        ev_ids = list(self.alloc.ids("search_events"))
        pop_ids = list(self.alloc.ids("popular_searches"))

        si_rows, sp_rows2, ss_rows2, inter_rows, hist_rows, ev_rows, pop_rows = ([], [], [], [], [], [], [])
        si_iter = iter(si_ids)

        # ── SHOP_PRODUCT index rows
        flat = 0
        for si, sh in enumerate(specs):
            sid = shop_ids[si]
            sh_name = sh["name"]
            for k in range(sh["num_listings"]):
                p = (si * 47 + k) % n_prod
                price, itname, unit = self.prod_info(p)
                mrp = self.prod_mrp(price, p)
                sp_row_id = sp_ids[flat]
                si_rows.append({
                    "id": next(si_iter),
                    "entity_type": SearchIndexEntityType.SHOP_PRODUCT.value,
                    "entity_id": sp_row_id, "product_id": prod_ids[p],
                    "shop_product_id": sp_row_id, "shop_id": sid,
                    "brand_id": None, "category_id": None, "variant_id": var_ids[p],
                    "product_name": f"{itname} {unit}".strip(),
                    "brand_name": None, "category_name": None, "subcategory_name": None,
                    "variant_name": f"{itname} {unit}",
                    "search_text": f"{sh_name} {itname} {unit} {price}".lower(),
                    "search_vector": None, "barcode": None, "sku": f"DP-{si:03d}-{k:05d}",
                    "is_product_searchable": True, "is_shop_visible": True,
                    "price": price, "mrp": mrp, "is_available": True,
                    "stock_status": "IN_STOCK" if (p + k) % 7 else "LIMITED_STOCK",
                    "freshness_status": "RECENTLY_UPDATED",
                    "last_inventory_update": _days_ago((p + k) % 5),
                    "shop_name": sh_name, "shop_rating": 3.2 + ((si * 13) % 18) / 10.0,
                    "shop_review_count": (si * 37) % 200, "is_shop_accepting_orders": True,
                    "location": make_point(sh["lon"], sh["lat"]),
                    "latitude": sh["lat"], "longitude": sh["lon"], "distance_km": round(0.3 + (k % 40) / 10.0, 1),
                    "popularity_score": float((p + k) % 50), "is_synced": True,
                    "last_synced_at": _days_ago(1),
                })
                flat += 1
# ── PRODUCT / SHOP / BRAND / CATEGORY index rows
        for p in range(n_prod):
            price, itname, unit = self.prod_info(p)
            si_rows.append({
                "id": next(si_iter), "entity_type": SearchIndexEntityType.PRODUCT.value,
                "entity_id": prod_ids[p], "product_id": prod_ids[p], "shop_product_id": None,
                "shop_id": None, "brand_id": None, "category_id": None, "variant_id": var_ids[p],
                "product_name": f"{itname} {unit}".strip(), "brand_name": None, "category_name": None,
                "subcategory_name": None, "variant_name": f"{itname} {unit}",
                "search_text": f"{itname} {unit}".lower(), "search_vector": None,
                "barcode": None, "sku": f"DSKU-{prod_ids[p]:09d}",
                "is_product_searchable": True, "is_shop_visible": False,
                "price": price, "mrp": self.prod_mrp(price, p), "is_available": True,
                "stock_status": "IN_STOCK", "freshness_status": "RECENTLY_UPDATED",
                "last_inventory_update": None, "shop_name": None, "shop_rating": 0.0,
                "shop_review_count": 0, "is_shop_accepting_orders": False,
                "location": None, "latitude": None, "longitude": None, "distance_km": None,
                "popularity_score": float(p % 50), "is_synced": True, "last_synced_at": _days_ago(1),
            })
        for sid, sh in zip(shop_ids, specs):
            si_rows.append({
                "id": next(si_iter), "entity_type": SearchIndexEntityType.SHOP.value,
                "entity_id": sid, "product_id": None, "shop_product_id": None, "shop_id": sid,
                "brand_id": None, "category_id": None, "variant_id": None,
                "product_name": sh["name"], "brand_name": None, "category_name": None,
                "subcategory_name": None, "variant_name": None,
                "search_text": f"{sh['name']} {sh['area_name']}".lower(), "search_vector": None,
                "barcode": None, "sku": None, "is_product_searchable": False, "is_shop_visible": True,
                "price": None, "mrp": None, "is_available": True, "stock_status": None,
                "freshness_status": None, "last_inventory_update": None,
                "shop_name": sh["name"], "shop_rating": 3.2 + ((sh["idx"] * 13) % 18) / 10.0,
                "shop_review_count": (sh["idx"] * 37) % 200, "is_shop_accepting_orders": True,
                "location": make_point(sh["lon"], sh["lat"]), "latitude": sh["lat"],
                "longitude": sh["lon"], "distance_km": 0.0,
                "popularity_score": 0.0, "is_synced": True, "last_synced_at": _days_ago(1),
            })
        for bname, bid in brand_ids.items():
            try:
                sidx_id = next(si_iter)
            except StopIteration:
                break
            si_rows.append({
                "id": sidx_id, "entity_type": SearchIndexEntityType.BRAND.value, "entity_id": bid,
                "product_id": None, "shop_product_id": None, "shop_id": None,
                "brand_id": bid, "category_id": None, "variant_id": None,
                "product_name": bname, "brand_name": bname, "category_name": None,
                "subcategory_name": None, "variant_name": None,
                "search_text": bname.lower(), "search_vector": None, "barcode": None, "sku": None,
                "is_product_searchable": True, "is_shop_visible": False, "price": None, "mrp": None,
                "is_available": True, "stock_status": None, "freshness_status": None,
                "last_inventory_update": None, "shop_name": None, "shop_rating": 0.0,
                "shop_review_count": 0, "is_shop_accepting_orders": False, "location": None,
                "latitude": None, "longitude": None, "distance_km": None,
                "popularity_score": 0.0, "is_synced": True, "last_synced_at": _days_ago(1),
            })
        for cname in cat_ids:
            try:
                sidx_id = next(si_iter)
            except StopIteration:
                break
            si_rows.append({
                "id": sidx_id, "entity_type": SearchIndexEntityType.CATEGORY.value,
                "entity_id": cat_ids[cname], "product_id": None, "shop_product_id": None,
                "shop_id": None, "brand_id": None, "category_id": cat_ids[cname], "variant_id": None,
                "product_name": cname, "brand_name": None, "category_name": cname,
                "subcategory_name": None, "variant_name": None,
                "search_text": cname.lower(), "search_vector": None, "barcode": None, "sku": None,
                "is_product_searchable": True, "is_shop_visible": False, "price": None, "mrp": None,
                "is_available": True, "stock_status": None, "freshness_status": None,
                "last_inventory_update": None, "shop_name": None, "shop_rating": 0.0,
                "shop_review_count": 0, "is_shop_accepting_orders": False, "location": None,
                "latitude": None, "longitude": None, "distance_km": None,
                "popularity_score": 0.0, "is_synced": True, "last_synced_at": _days_ago(1),
            })
# ── saved products / saved shops (one block each, user-scoped) ---------
        cust_range = user_ids[cust_start:min(cust_end, len(user_ids))]
        for i in range(len(saved_p_ids)):
            u = user_ids[cust_start + (i % len(cust_range))] if cust_range else user_ids[0]
            prod = prod_ids[i % n_prod]
            sp_rows2.append({"id": saved_p_ids[i], "user_id": u, "product_master_id": prod,
                             "created_at": _days_ago(i % 20)})
        for i in range(len(saved_s_ids)):
            u = user_ids[cust_start + (i % len(cust_range))] if cust_range else user_ids[0]
            shop = shop_ids[i % len(shop_ids)]
            ss_rows2.append({"id": saved_s_ids[i], "user_id": u, "shop_id": shop,
                             "created_at": _days_ago(i % 15)})

        # ── user interactions (calls / messages / ratings)
        actions = [(InteractionActionType.CALL_VIEW.value, None, None),
                   (InteractionActionType.MESSAGE.value, "Is this item available? Please share today's price.", "SEED sample query"),
                   (InteractionActionType.RATING.value, "Good shop, fresh stock!", "Very responsive.")]
        for i in range(len(inter_ids)):
            u = user_ids[cust_start + (i % len(cust_range))] if cust_range else user_ids[0]
            shop = shop_ids[(i * 3) % len(shop_ids)]
            atype, msg, msg2 = actions[i % 3]
            rating = None
            content = None
            if atype == "rating":
                rating = 3 + (i % 3)
                content = msg2 if i % 2 else msg
            elif atype == "message":
                content = msg
            inter_rows.append({"id": inter_ids[i], "user_id": u, "shop_id": shop,
                               "action_type": atype, "message_content": content,
                               "rating": rating})

        # ── search history / events / popular searches
        queries = ["wheat atta", "basmati rice", "paracetamol", "charging cable", "milk",
                   "bread", "cooking oil", "baby diapers", "onion", "ice cream", "toothpaste", "soap"]
        for i in range(len(hist_ids)):
            u = user_ids[cust_start + (i % len(cust_range))] if cust_range else user_ids[0]
            q = queries[(i * 5) % len(queries)]
            hist_rows.append({"id": hist_ids[i], "user_id": u, "query": q,
                              "result_count": 5 + (i % 80), "is_successful": True,
                              "searched_at": _days_ago(i % 10)})
        for i in range(len(ev_ids)):
            u = user_ids[cust_start + (i % len(cust_range))] if cust_range else user_ids[0]
            q = queries[(i * 7) % len(queries)]
            et = ["SEARCH", "SUGGESTION_CLICK", "RESULT_CLICK", "CONVERSION"][i % 4]
            ev_rows.append({"id": ev_ids[i], "user_id": u, "session_id": f"sess-{i % 4000:05d}",
                            "query": q, "event_type": et, "result_count": 5 + (i % 80),
                            "clicked_product_id": prod_ids[i % n_prod],
                            "clicked_shop_id": shop_ids[(i * 3) % len(shop_ids)],
                            "clicked_shop_product_id": sp_ids[i % len(sp_ids)],
                            "device_type": "android", "app_version": "1.0.0",
                            "event_time": _days_ago(i % 14)})
        for i in range(len(pop_ids)):
            q = queries[i % len(queries)]
            pop_rows.append({"id": pop_ids[i], "query": q, "search_count": 200 + i * 37,
                             "result_count": 20, "is_active": True})

        insert_rows(db, SearchIndex.__table__, si_rows, chunk=250, label="search_indexes")
        insert_rows(db, SavedProduct.__table__, sp_rows2, chunk=300, label="saved_products")
        insert_rows(db, SavedShop.__table__, ss_rows2, chunk=300, label="saved_shops")
        insert_rows(db, UserInteraction.__table__, inter_rows, chunk=300, label="user_interactions")
        insert_rows(db, SearchHistory.__table__, hist_rows, chunk=300, label="search_history")
        insert_rows(db, SearchEvent.__table__, ev_rows, chunk=300, label="search_events")
        insert_rows(db, PopularSearch.__table__, pop_rows, chunk=50, label="popular_searches")
        return {"cust_ids": user_ids[cust_start:min(cust_end, len(user_ids))]}
# ---- Step 9: notifications + delivery records -------------------------
    def seed_notifications(self, users_meta: dict) -> None:
        db = self.db
        notif_ids = list(self.alloc.ids("notifications"))
        deliv_ids = list(self.alloc.ids("notification_deliveries"))
        user_ids = users_meta["user_ids"]
        dev_ids = users_meta["dev_ids"]

        notif_rows, deliv_rows = [], []
        titles = ["Order update", "Price drop alert", "Stock back in", "New discount", "Weekly digest"]
        bodies = ["Your order has been confirmed", "The price of an item you saved went down",
                  "An out-of-stock product is available again", "A shop near you launched a new offer",
                  "Here is what changed in your neighbourhood this week"]
        for i in range(len(notif_ids)):
            u = user_ids[i % len(user_ids)]
            t = titles[i % len(titles)]
            nid = notif_ids[i]
            notif_rows.append({
                "id": nid, "user_id": u, "title": t, "body": bodies[i % len(bodies)],
                "type": "price_alert" if i % 2 else "system", "audience": "customer",
                "deep_link": "app://offer" if i % 3 == 0 else None,
                "dedupe_key": f"seed-{i}", "delivery_status": "SENT",
                "delivery_attempts": 1, "is_read": i % 3 == 0,
                "payload": json.dumps({"seeded": True}), "sent_at": _days_ago(i % 10),
            })
            if i < len(deliv_ids):
                deliv_rows.append({
                    "id": deliv_ids[i], "notification_id": nid,
                    "device_token_id": dev_ids[i % len(dev_ids)],
                    "status": "SENT", "attempts": 1, "provider_message_id": f"fcm-{i:06d}",
                    "error": None, "permanent_failure": False,
                    "attempted_at": _days_ago(i % 10), "delivered_at": _days_ago(i % 10),
                })
        insert_rows(db, Notification.__table__, notif_rows, chunk=300, label="notifications")
        insert_rows(db, NotificationDelivery.__table__, deliv_rows, chunk=300, label="notification_deliveries")

    # ---- Step 10: subscription plans / subscriptions / payments ----------
    def seed_subscriptions(self, users_meta: dict, shops_meta: dict) -> None:
        db = self.db
        plan_ids = list(self.alloc.ids("subscription_plans"))
        sub_ids = list(self.alloc.ids("subscriptions"))
        pay_ids = list(self.alloc.ids("payments"))
        pev_ids = list(self.alloc.ids("payment_events"))
        user_ids = users_meta["user_ids"]
        owner_end = users_meta["owner_end"]
        shop_ids = shops_meta["shop_ids"]

        plans = [
            ("Seed Free", 0, 0, "1 shop", 0, 100),
            ("Seed Starter", 299, 2990, "3 shops", 0, 1500),
            ("Seed Growth", 799, 7990, "10 shops", 7, 5000),
            ("Seed Enterprise", 2499, 24990, "Unlimited shops", 14, 50000),
        ]
        plan_rows = []
        for i, (pname, pm, pa, feat, trial, maxp) in enumerate(plans):
            plan_rows.append({
                "id": plan_ids[i], "name": pname, "description": f"{SEED_TAG} tier {i + 1}",
                "price_monthly": pm, "price_annual": pa, "currency": "INR",
                "billing_cycle": BillingCycle.MONTHLY.value, "is_active": True,
                "features_json": json.dumps({"label": feat}), "max_shops": (i + 1) * 3,
                "max_products": maxp, "trial_days": trial, "sort_order": i,
            })
        insert_rows(db, SubscriptionPlan.__table__, plan_rows, chunk=10, label="subscription_plans")

        sub_rows, pay_rows, pev_rows = [], [], []
        for i in range(len(sub_ids)):
            u = user_ids[i % len(user_ids)]
            plan = plan_ids[i % len(plan_ids)]
            sid_shop = shop_ids[i % len(shops_meta["shop_ids"])]
            sub_rows.append({
                "id": sub_ids[i], "user_id": u, "shop_id": sid_shop, "plan_id": plan,
                "status": SubscriptionStatus.ACTIVE.value, "is_auto_renew": True,
                "current_period_start": _days_ago(i % 20 + 10), "current_period_end": _days_ago(-(30 - i % 20)),
                "cancel_at_period_end": False, "trial_ends_at": None, "created_by": u,
            })
            if i < len(pay_ids):
                pay_rows.append({
                    "id": pay_ids[i], "subscription_id": sub_ids[i],
                    "payment_provider": "RAZORPAY", "provider_order_id": f"order_seed_{i:06d}",
                    "transaction_id": f"pay_seed_{i:06d}", "amount": 299.0 if i % 3 else 799.0,
                    "currency": "INR", "status": "SUCCESS", "payment_method": "UPI",
                    "billing_cycle": "MONTHLY", "invoice_number": f"INV-SEED-{i:06d}",
                    "paid_at": _days_ago(i % 20), "refunded_at": None, "failure_reason": None,
                    "payment_metadata": json.dumps({"seeded": True}),
                })
            if i < len(pev_ids):
                pev_rows.append({
                    "id": pev_ids[i], "provider": "RAZORPAY", "event_id": f"evt_seed_{i:06d}",
                    "event_type": "payment.captured", "payment_id": pay_ids[i] if i < len(pay_ids) else None,
                    "payload": json.dumps({"seeded": True}), "received_at": _days_ago(i % 20),
                })
        insert_rows(db, Subscription.__table__, sub_rows, chunk=100, label="subscriptions")
        insert_rows(db, Payment.__table__, pay_rows, chunk=100, label="payments")
        insert_rows(db, PaymentEvent.__table__, pev_rows, chunk=100, label="payment_events")
# ---- Step 11: POS integrations + devices + sync jobs + mappings --------
    def seed_pos(self, users_meta: dict, shops_meta: dict, prods_meta: dict, sp_meta: dict) -> None:
        db = self.db
        integ_ids = list(self.alloc.ids("pos_integrations"))
        dev_ids = list(self.alloc.ids("pos_devices"))
        job_ids = list(self.alloc.ids("pos_sync_jobs"))
        log_ids = list(self.alloc.ids("pos_sync_logs"))
        map_ids = list(self.alloc.ids("pos_product_mappings"))
        shop_ids = shops_meta["shop_ids"]
        user_ids = users_meta["user_ids"]
        prod_ids = prods_meta["prod_ids"]
        sp_ids = sp_meta["sp_ids"]
        owner_end = users_meta["owner_end"]

        integ_rows, dev_rows, job_rows, log_rows, map_rows = ([], [], [], [], [])
        providers = ["Marg", "Busy", "Vyapar", "MeraBilling", "Intuit"]
        log_iter = iter(log_ids)

        for i in range(len(integ_ids)):
            sid = shop_ids[i % len(shop_ids)]
            prov = providers[i % len(providers)]
            integ_rows.append({
                "id": integ_ids[i], "shop_id": sid, "provider_name": prov,
                "integration_type": "API", "api_base_url": f"https://pos.example.in/{prov.lower()}",
                "status": "ACTIVE", "last_sync_at": _days_ago(i % 4), "last_sync_status": "COMPLETED",
                "config_json": json.dumps({"seeded": True}), "provider_code": prov.lower(),
                "sync_enabled": True, "sync_interval_minutes": 60,
                "auto_create_products": True, "conflict_strategy": "PRESERVE_PLATFORM",
                "last_successful_sync_at": _days_ago(i % 4), "consecutive_failures": 0,
            })
            dev_rows.append({
                "id": dev_ids[i], "shop_id": sid, "integration_id": integ_ids[i],
                "device_identifier": f"POS-SEED-{integ_ids[i]:08d}",
                "device_name": f"Billing Counter {i % 20 + 1}", "device_type": "POS_TERMINAL",
                "is_active": True, "last_connected_at": _days_ago(1), "firmware_version": "1.0." + str(i % 9),
            })
            if i < len(job_ids):
                job_rows.append({
                    "id": job_ids[i], "shop_id": sid, "integration_id": integ_ids[i],
                    "sync_type": "FULL", "status": POSSyncStatus.COMPLETED.value,
                    "started_at": _days_ago(2), "completed_at": _days_ago(2),
                    "items_processed": 20 + i % 50, "items_succeeded": 20 + i % 50,
                    "items_failed": 0, "created_by": user_ids[i % owner_end],
                    "idempotency_key": f"seed-pos-{i:06d}", "trigger": "SCHEDULED",
                })
                for _l in range(2):
                    try:
                        lid = next(log_iter)
                    except StopIteration:
                        break
                    log_rows.append({"id": lid, "sync_job_id": job_ids[i], "log_level": "INFO",
                                     "message": f"{SEED_TAG} sync completed", "item_reference": None,
                                     "error_code": None, "stack_trace": None, "logged_at": _days_ago(2)})
            if i < len(map_ids):
                map_rows.append({
                    "id": map_ids[i], "integration_id": integ_ids[i], "shop_id": sid,
                    "pos_product_code": f"POS-{i:07d}", "pos_sku": None,
                    "barcode": f"8904{800000000 + i:09d}",
                    "product_master_id": prod_ids[i % len(prod_ids)],
                    "variant_id": prods_meta["var_ids"][i % len(prod_ids)],
                    "shop_product_id": sp_ids[i % len(sp_ids)],
                    "last_synced_hash": hashlib.sha256(f"seed-map-{i}".encode()).hexdigest(),
                    "last_synced_at": _days_ago(1), "last_conflict_json": None, "is_active": True,
                })
        insert_rows(db, POSIntegration.__table__, integ_rows, chunk=100, label="pos_integrations")
        insert_rows(db, POSDevice.__table__, dev_rows, chunk=100, label="pos_devices")
        insert_rows(db, POSSyncJob.__table__, job_rows, chunk=100, label="pos_sync_jobs")
        insert_rows(db, POSSyncLog.__table__, log_rows, chunk=200, label="pos_sync_logs")
        insert_rows(db, POSProductMapping.__table__, map_rows, chunk=200, label="pos_product_mappings")
# ---- Step 12: inventory import jobs + rows ------------------------------
    def seed_import_jobs(self, users_meta: dict, shops_meta: dict) -> None:
        db = self.db
        job_ids = list(self.alloc.ids("inventory_import_jobs"))
        row_ids = list(self.alloc.ids("inventory_import_rows"))
        shop_ids = shops_meta["shop_ids"]
        user_ids = users_meta["user_ids"]
        owner_end = users_meta["owner_end"]

        job_rows, row_rows = [], []
        row_iter = iter(row_ids)
        for i in range(len(job_ids)):
            sid = shop_ids[i % len(shop_ids)]
            job_rows.append({
                "id": job_ids[i], "shop_id": sid, "uploaded_by": user_ids[i % owner_end],
                "filename": f"stock-{i + 1:03d}.xlsx", "file_size_bytes": 10_000 + i * 137,
                "idempotency_key": f"seed-import-{i:06d}",
                "status": ImportJobStatus.COMPLETED.value, "total_rows": 20, "valid_rows": 20,
                "error_rows": 0, "processed_rows": 20, "failed_rows": 0,
                "started_at": _days_ago(5), "completed_at": _days_ago(5),
            })
            for r in range(5):
                try:
                    rid = next(row_iter)
                except StopIteration:
                    break
                row_rows.append({
                    "id": rid, "job_id": job_ids[i], "row_number": r + 1, "status": "PROCESSED",
                    "raw_data": json.dumps({"barcode": f"8904{r:09d}"}),
                    "normalized_data": json.dumps({"price": 99}),
                    "error_code": None, "error_message": None, "error_field": None,
                    "product_master_id": None, "variant_id": None, "shop_product_id": None,
                })
        insert_rows(db, InventoryImportJob.__table__, job_rows, chunk=100, label="inventory_import_jobs")
        insert_rows(db, InventoryImportRow.__table__, row_rows, chunk=300, label="inventory_import_rows")
# ---- Step 13: analytics / monitoring data --------------------------------
    def seed_analytics(self, users_meta: dict, prods_meta: dict, shops_meta: dict,
                       sp_meta: dict, cat_ids: dict) -> None:
        db = self.db
        pv_ids = list(self.alloc.ids("product_views"))
        sv_ids = list(self.alloc.ids("shop_views"))
        pc_ids = list(self.alloc.ids("product_clicks"))
        sm_ids = list(self.alloc.ids("system_metrics"))
        ae_ids = list(self.alloc.ids("analytics_events"))
        agg_ids = list(self.alloc.ids("analytics_daily_aggregates"))

        prod_ids = prods_meta["prod_ids"]
        shop_ids = shops_meta["shop_ids"]
        sp_ids = sp_meta["sp_ids"]
        user_ids = users_meta["user_ids"]
        cust_start, cust_end = users_meta["cust_start"], users_meta["cust_end"]
        n_prod = len(prod_ids)
        customers = user_ids[cust_start:min(cust_end, len(user_ids))] or user_ids[:1]

        pv_rows, sv_rows, pc_rows, sm_rows, ae_rows, agg_rows = ([], [], [], [], [], [])
        for i in range(len(pv_ids)):
            pv_rows.append({"id": pv_ids[i], "product_master_id": prod_ids[i % n_prod],
                            "user_id": customers[i % len(customers)], "session_id": f"sess-{i % 9000:05d}",
                            "device_type": "android", "app_version": "1.0.0",
                            "viewed_at": _days_ago(i % 30)})
        for i in range(len(sv_ids)):
            sv_rows.append({"id": sv_ids[i], "shop_id": shop_ids[i % len(shop_ids)],
                            "user_id": customers[i % len(customers)], "session_id": f"sess-{i % 3000:05d}",
                            "device_type": "android", "app_version": "1.0.0",
                            "viewed_at": _days_ago(i % 30)})
        for i in range(len(pc_ids)):
            pc_rows.append({"id": pc_ids[i], "product_master_id": prod_ids[i % n_prod],
                            "user_id": customers[i % len(customers)], "session_id": f"sess-{i % 8000:05d}",
                            "source": "SEARCH", "clicked_at": _days_ago(i % 14),
                            "query": "seed search", "shop_id": shop_ids[(i * 3) % len(shop_ids)],
                            "shop_product_id": sp_ids[i % len(sp_ids)]})
        metric_names = ["cpu_usage", "memory_usage", "api_latency_p95", "error_rate", "queue_depth"]
        for i in range(len(sm_ids)):
            sm_rows.append({"id": sm_ids[i], "metric_name": metric_names[i % len(metric_names)],
                            "metric_value": round(10 + (i * 7) % 85, 2),
                            "unit": "percent", "shop_id": shop_ids[i % len(shop_ids)] if i % 4 else None,
                            "source": "DB_QUERY", "recorded_at": _days_ago(i % 7)})

        event_names = ["product_search", "product_view", "shop_view", "directions_click",
                       "save_product", "offer_view", "checkout_start", "freshness_outcome"]
        actor_types = ["CUSTOMER", "SHOPKEEPER", "PLATFORM"]
        import uuid as _uuid
        for i in range(len(ae_ids)):
            ae_rows.append({
                "id": ae_ids[i], "event_name": event_names[i % len(event_names)],
                "actor_type": actor_types[i % 3],
                "actor_id": customers[i % len(customers)] if i % 3 else None,
                "session_id": f"ae-{_uuid.uuid4().hex[:8]}",
                "shop_id": shop_ids[i % len(shop_ids)] if i % 4 else None,
                "product_master_id": prod_ids[i % n_prod] if i % 2 else None,
                "category_id": list(cat_ids.values())[i % len(cat_ids)] if cat_ids else None,
                "query": "seed" if i % 5 == 0 else None,
                "metric_value": round((i % 900) / 10.0, 2), "props": json.dumps({"seeded": True}),
                "device_type": "android", "app_version": "1.0.0", "occurred_at": _days_ago(i % 14),
            })
        for i in range(len(agg_ids)):
            agg_rows.append({"id": agg_ids[i], "aggregate_date": date(2026, 1, 1),
                             "event_name": event_names[i % len(event_names)],
                             "actor_type": actor_types[i % 3], "shop_id": None,
                             "product_master_id": None, "category_id": None,
                             "event_count": 100 + i * 7, "distinct_sessions": 50 + i,
                             "distinct_actors": 20 + i, "metric_sum": 9000.0 + i,
                             "computed_at": _days_ago(i)})

        insert_rows(db, ProductView.__table__, pv_rows, chunk=300, label="product_views")
        insert_rows(db, ShopView.__table__, sv_rows, chunk=300, label="shop_views")
        insert_rows(db, ProductClick.__table__, pc_rows, chunk=300, label="product_clicks")
        insert_rows(db, SystemMetric.__table__, sm_rows, chunk=200, label="system_metrics")
        insert_rows(db, AnalyticsEvent.__table__, ae_rows, chunk=300, label="analytics_events")
        insert_rows(db, AnalyticsDailyAggregate.__table__, agg_rows, chunk=50, label="analytics_daily_aggregates")

    # ---- Step 14: admin & audit data ------------------------------------
    def seed_admin_audit(self, users_meta: dict, prods_meta: dict, shops_meta: dict,
                         sp_meta: dict) -> None:
        db = self.db
        al_ids = list(self.alloc.ids("audit_logs"))
        aa_ids = list(self.alloc.ids("admin_actions"))
        an_ids = list(self.alloc.ids("admin_notes"))
        pa_ids = list(self.alloc.ids("product_approvals"))
        rep_ids = list(self.alloc.ids("reports"))
        comp_ids = list(self.alloc.ids("complaints"))

        user_ids = users_meta["user_ids"]
        admin_idx = users_meta["admin_idx"]
        admin_uid = user_ids[admin_idx] if admin_idx < len(user_ids) else user_ids[0]
        shop_ids = shops_meta["shop_ids"]
        prod_ids = prods_meta["prod_ids"]
        cust_start, cust_end = users_meta["cust_start"], users_meta["cust_end"]
        customers = user_ids[cust_start:min(cust_end, len(user_ids))] or user_ids[:1]

        al_rows, aa_rows, an_rows, pa_rows, rep_rows, comp_rows = ([], [], [], [], [], [])
        for i in range(len(al_ids)):
            target_type = ["SHOP", "PRODUCT", "USER", "OFFER"][i % 4]
            tgt_id = [shop_ids[i % len(shop_ids)], prod_ids[i % len(prod_ids)],
                      user_ids[i % len(user_ids)], i * 11][i % 4]
            al_rows.append({"id": al_ids[i], "user_id": customers[i % len(customers)],
                            "action": ["CREATE", "UPDATE", "VERIFY", "DELETE"][i % 4],
                            "entity_type": target_type, "entity_id": tgt_id if tgt_id else i,
                            "old_values": {"seeded": True}, "new_values": {"seeded": True},
                            "ip_address": "10.0.0.1", "user_agent": "seed-agent",
                            "request_id": f"req-{i:08d}",
                            "description": f"{SEED_TAG} record {i}",
                            "created_at": _days_ago(i % 30)})
        for i in range(len(aa_ids)):
            aa_rows.append({"id": aa_ids[i], "admin_user_id": admin_uid,
                            "action_type": "VERIFY_SHOP" if i % 2 else "SUSPEND_USER",
                            "target_type": "SHOP" if i % 2 else "USER",
                            "target_id": shop_ids[i % len(shop_ids)] if i % 2
                            else user_ids[i % len(user_ids)],
                            "action_data": {"seeded": True},
                            "description": f"{SEED_TAG} admin action",
                            "ip_address": "10.0.1.2", "performed_at": _days_ago(i % 30)})
        for i in range(len(an_ids)):
            an_rows.append({"id": an_ids[i], "admin_user_id": admin_uid,
                            "entity_type": "SHOP", "entity_id": shop_ids[i % len(shop_ids)],
                            "note": f"{SEED_TAG} follow-up note", "is_private": True,
                            "created_by": admin_uid})
        for i in range(len(pa_ids)):
            pa_rows.append({"id": pa_ids[i], "product_master_id": prod_ids[i % len(prod_ids)],
                            "shop_id": shop_ids[i % len(shop_ids)],
                            "submitted_by": user_ids[i % len(user_ids)],
                            "status": "APPROVED" if i % 4 else "PENDING",
                            "requested_by": user_ids[i % len(user_ids)],
                            "reviewed_by": admin_uid if i % 4 else None,
                            "review_notes": f"{SEED_TAG} auto-approved" if i % 4 else None,
                            "submitted_at": _days_ago(8), "reviewed_at": _days_ago(7) if i % 4 else None,
                            "submission_data": {"seeded": True}})
        report_types = ["SALES", "INVENTORY", "SEARCH_ANALYTICS", "FRESHNESS"]
        for i in range(len(rep_ids)):
            rep_rows.append({"id": rep_ids[i], "report_type": report_types[i % len(report_types)],
                             "report_name": f"{SEED_TAG} report {i}",
                             "parameters_json": {"shop_id": shop_ids[i % len(shop_ids)]},
                             "result_json": {"rows": 100, "generated": True},
                             "generated_by": admin_uid, "file_url": None,
                             "status": "READY", "started_at": _days_ago(2),
                             "completed_at": _days_ago(2), "error_message": None})
        priorities = ["LOW", "MEDIUM", "HIGH", "URGENT"]
        for i in range(len(comp_ids)):
            comp_rows.append({"id": comp_ids[i],
                              "complainant_user_id": customers[i % len(customers)],
                              "complaint_type": "WRONG_PRICE",
                              "subject": f"{SEED_TAG} pricing complaint {i}",
                              "description": "Price shown on app does not match the counter.",
                              "entity_type": "PRODUCT", "entity_id": prod_ids[i % len(prod_ids)],
                              "status": "RESOLVED" if i % 3 else "OPEN",
                              "priority": priorities[i % len(priorities)],
                              "assigned_to": admin_uid,
                              "resolution_notes": "checked and updated" if i % 3 else None,
                              "resolved_at": _days_ago(4) if i % 3 else None})

        insert_rows(db, AuditLog.__table__, al_rows, chunk=300, label="audit_logs")
        insert_rows(db, AdminAction.__table__, aa_rows, chunk=100, label="admin_actions")
        insert_rows(db, AdminNote.__table__, an_rows, chunk=100, label="admin_notes")
        insert_rows(db, ProductApproval.__table__, pa_rows, chunk=200, label="product_approvals")
        insert_rows(db, Report.__table__, rep_rows, chunk=100, label="reports")
        insert_rows(db, Complaint.__table__, comp_rows, chunk=200, label="complaints")

    # ---- Step 15: feature flags + final manifest --------------------------
    def seed_feature_flags_and_manifest(self) -> None:
        db = self.db
        flag_ids = list(self.alloc.ids("feature_flags"))

        flags = [
            ("seed_dummy_mode", True), ("search_geo_enabled", True),
            ("offers_enabled", True), ("pos_sync_enabled", True),
            ("subscriptions_enabled", True), ("notifications_enabled", True),
            ("analytics_enabled", True), ("inventory_import_enabled", True),
            ("google_oauth_enabled", False), ("saved_items_enabled", True),
            ("barcode_scan_enabled", True), ("freshness_labels_enabled", True),
        ]
        flag_rows = []
        for i, (fname, enabled) in enumerate(flags):
            flag_rows.append({"id": flag_ids[i], "name": fname,
                              "description": f"{SEED_TAG} feature flag",
                              "is_enabled": enabled, "default_enabled": False,
                              "rollout_percentage": 100, "scope": "GLOBAL",
                              "target_ids_json": None, "conditions_json": None,
                              "updated_by": None})
        insert_rows(db, FeatureFlag.__table__, flag_rows, chunk=50, label="feature_flags")

        # finalise manifest ledger with every table block
        tables = {}
        for t, b in self.alloc.blocks.items():
            if t == MANIFEST_TABLE:
                continue
            tables[t] = {"start": b["start"], "count": b["count"],
                         "end": b["start"] + b["count"] - 1}
        self.manifest["tables"] = tables
        self.manifest["manifest_row_id"] = self.manifest_row_id
        payload = json.dumps(self.manifest, sort_keys=True)

        db.execute(SystemSetting.__table__.update()
                   .where(SystemSetting.__table__.c.key == MANIFEST_KEY)
                   .values({"value": payload}))

    # ---- Master orchestrator ---------------------------------------------
    def run(self) -> dict:
        db = self.db
        self.begin_manifest()
        role_ids = self.seed_rbac()
        cb = self.seed_categories_brands()
        prods = self.seed_products(cb["cat_ids"], cb["brand_ids"])
        users = self.seed_users(role_ids)
        shops = self.seed_shops(users, role_ids)
        sp = self.seed_shop_products(shops, prods, users)
        self.seed_offers(shops, sp)
        self.seed_search_and_saves(cb["cat_ids"], cb["brand_ids"], prods, shops, sp, users)
        self.seed_notifications(users)
        self.seed_subscriptions(users, shops)
        self.seed_pos(users, shops, prods, sp)
        self.seed_import_jobs(users, shops)
        self.seed_analytics(users, prods, shops, sp, cb["cat_ids"])
        self.seed_admin_audit(users, prods, shops, sp)
        self.seed_feature_flags_and_manifest()
        return self.manifest


# ── CLI / main ──────────────────────────────────────────────────────────────
def main(argv: list | None = None) -> int:
    ap = argparse.ArgumentParser(
        prog="seed_data.py",
        description="Bulk-insert area-wise dummy data into the AWS hyperlocal DB.",
    )
    ap.add_argument("--url", default=None,
                    help="DB URL (sync or async). Default: $DATABASE_URL / backend/.env")
    ap.add_argument("--scale", choices=("small", "medium", "full"), default="full",
                    help="Volume multiplier (default full = maximum data)")
    ap.add_argument("--dry-run", action="store_true",
                    help="Print the row-count plan and exit without connecting")
    ap.add_argument("--reset", action="store_true",
                    help="Run cleanup_data.py first, then seed")
    args = ap.parse_args(argv)

    # ── dry-run: print the deterministic plan, never touch the DB ────────
    plan = plan_counts(args.scale)
    if args.dry_run:
        total = sum(plan.values())
        print(f"=== SEED PLAN (scale={args.scale}) ===")
        print(f"Reserved ID base      : {DUMMY_ID_BASE}")
        print(f"Total rows to insert  : {total:,}")
        print(f"Areas                 : {len(AREAS)}")
        for t, c in sorted(plan.items()):
            print(f"  {t:<32} {c:>10,}")
        print()
        print("Run without --dry-run to actually insert.")
        return 0

    url = resolve_db_url(args.url)
    if not url:
        print("[X] No database URL found.", file=sys.stderr)
        print("    Pass --url, set $DATABASE_URL, or add backend/.env", file=sys.stderr)
        return 2
    print(f"[i] Connecting to {mask_url(url)}  (scale={args.scale})")

    engine = make_engine(url)
    db = make_session(engine)
    try:
        # verify connectivity early
        db.execute(text("SELECT 1"))

        if args.reset:
            from cleanup_data import run_cleanup
            print("[i] --reset: cleaning previous seed first")
            removed = run_cleanup(db, dry_run=False)
            print(f"[i] --reset: removed {removed} rows")

        alloc = Allocator()
        for table_name, count in plan.items():
            alloc.allocate(table_name, count)

        seeder = Seeder(db, alloc, args.scale)
        start = time.time()
        manifest = seeder.run()
        elapsed = time.time() - start

        # move sequences past the reserved block so future real inserts stay safe
        _bump_sequences(db, list(plan.keys()))

        db.commit()

        total = sum(plan.values())
        print(f"\n=== SEED COMPLETE ===")
        print(f"  rows inserted : {total:,}")
        print(f"  elapsed       : {elapsed:.1f}s")
        print(f"  manifest row  : system_settings.key='{MANIFEST_KEY}' "
              f"(id={manifest.get('manifest_row_id')})")
        print(f"  cleanup       : python cleanup_data.py --url <same-url>")
        return 0
    except KeyboardInterrupt:
        db.rollback()
        print("\nAborted.", file=sys.stderr)
        return 130
    except Exception as exc:
        db.rollback()
        print(f"[X] Seeding failed: {exc}", file=sys.stderr)
        return 1
    finally:
        db.close()
        engine.dispose()


if __name__ == "__main__":
    raise SystemExit(main())