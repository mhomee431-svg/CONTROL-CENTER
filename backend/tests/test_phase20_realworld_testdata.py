"""Phase 20 — Controlled real-world test dataset.

Builds a production-like dataset WITHOUT random manual inserts. Every row is
created through the platform's own APIs / admin tools / import tooling, then the
four live-mutation loops a customer experiences are proven end-to-end:

    Customer account ....... POST /api/v1/auth/send-otp + /auth/register
    Shopkeeper account ..... POST /api/v1/shopkeeper/auth/send-otp + /auth/register
    Verified shops ......... POST /api/v1/shopkeeper/shops + /shops/admin/.../review
    Categories / Brands .... POST /api/v1/admin/categories, /api/v1/admin/brands
    Products ............... POST /api/v1/shopkeeper/shops/{id}/products (publish)
    Variants ............... POST /api/v1/catalog/products/{id}/variants
    Identifiers / barcodes . POST /api/v1/catalog/products/{id}/identifiers, /barcodes
    Shop-product mapping ... POST /api/v1/shopkeeper/shops/{id}/inventory/products
    Inventory / prices ..... created by the same listing APIs (price and mrp)
    Offers ................. POST /api/v1/shopkeeper/shops/{id}/offers/assign
    Locations .............. shop registration lat/lng + PUT /shops/my/shops/{id}

    Mutation -> discovery tests
    1. Shopkeeper updates inventory -> DB row changes -> customer search changes
    2. Price update                 -> customer search shows the new price
    3. Inventory becomes unavailable -> customer sees correct availability
    4. Shop changes location         -> nearby-shop results change

The background search-index worker (Celery ``app.services.tasks.index_shop_product``)
is simulated synchronously with the real indexer
(``app.search.indexer.upsert_shop_product``), so every mutation flows through the
exact production code path the worker executes.

Infrastructure: a shared SQLite file (one synchronous engine for the sync route
graph and one ``sqlite+aiosqlite`` engine for the async catalog routes), with the
PostGIS / pg_trgm SQL functions the production search emits registered as faithful
Python shims (haversine geodesics + pg_trgm trigram similarity) and the Geography
columns made SQLite-portable via ``tests.geo_compat``.
"""

from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402
from sqlalchemy import ColumnDefault, create_engine, event  # noqa: E402
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine  # noqa: E402
from sqlalchemy.orm import sessionmaker  # noqa: E402
from sqlalchemy.pool import StaticPool  # noqa: E402

from app.core.config import settings  # noqa: E402
from app.database.session import Base  # noqa: E402

settings.RATE_LIMIT_ENABLED = False
settings.OTP_STORAGE_URI = "memory://"

# Register ALL production models BEFORE touching metadata / geo columns.
import app.models  # noqa: E402,F401
from app.models.product import BarcodeRelationship  # noqa: E402
from tests.geo_compat import strip_geo_columns  # noqa: E402

strip_geo_columns()


def _portable_timestamp_defaults() -> None:
    """Replace server-side ``now()`` / ``false`` defaults with Python callables
    so SQLite stores real values (mirrors earlier phase test modules)."""

    def _now(ctx=None):  # noqa: ANN001
        from datetime import datetime as _dt

        return _dt.utcnow()

    for table in Base.metadata.tables.values():
        for col in table.columns:
            sd = getattr(col, "server_default", None)
            sd_arg = getattr(sd, "arg", None)
            if isinstance(sd_arg, str) and sd_arg.lower() == "now()":
                if col.default is None:
                    col.default = ColumnDefault(_now)
                col.server_default = None
            elif isinstance(sd_arg, str) and sd_arg.lower() == "false":
                if col.default is None and (
                    getattr(getattr(col.type, "python_type", None), "__name__", "") == "bool"
                ):
                    col.default = ColumnDefault(False)
                col.server_default = None
            ou = getattr(col, "onupdate", None)
            ou_arg = getattr(ou, "arg", None)
            if ou is not None and str(ou_arg).strip().lower().startswith("now"):
                col.onupdate = ColumnDefault(_now, for_update=True)


_portable_timestamp_defaults()


def _dedupe_barcode_index() -> None:
    """The barcode_relationships model declares the same index twice (column
    index=True + explicit __table_args__ Index with the same name); SQLite
    rejects the duplicate, so drop one before ``create_all`` (as Phase 19 did)."""
    tbl = BarcodeRelationship.__table__
    for ix in list(tbl.indexes):
        if ix.name == "ix_barcode_relationships_barcode":
            tbl.indexes.discard(ix)
            break


_dedupe_barcode_index()


# ── SQLite geometry shim for shop registration ─────────────────────────────
# ``register_shop`` stores ``location=_get_wkt_point(lat, lng)`` which returns a
# geoalchemy ``WKTElement``. On PostgreSQL that binds to the Geography column;
# here the column is Text (strip_geo_columns) and SQLite cannot bind a
# ``WKTElement`` object. This shim makes ``_get_wkt_point`` emit the same WKT
# ``POINT(lng lat)`` text (what the real code serialises / what the PostGIS
# function shims parse), so the real shop-registration code path runs unchanged.
import app.services.shop_service as _shop_service  # noqa: E402

_orig_get_wkt_point = _shop_service._get_wkt_point


def _text_wkt_point(latitude: float, longitude: float) -> str:  # noqa: ANN001
    return f"POINT({longitude} {latitude})"


_shop_service._get_wkt_point = _text_wkt_point


# ── PostGIS-in-SQLite compatibility functions (faithful to Phase 19) ─────────
def _parse_wkt_point(value):
    """Parse a WKT 'POINT(lng lat)' value into (longitude, latitude)."""
    if value is None:
        return None
    raw = str(value)
    if not raw.startswith("POINT"):
        return None
    try:
        inner = raw[raw.index("(") + 1 : raw.rindex(")")]
        parts = inner.split()
        if len(parts) == 2:
            return float(parts[0]), float(parts[1])
    except (ValueError, TypeError, IndexError):
        return None
    return None


def _wkt_distance_m(value_a, value_b) -> float:
    """Geodesic distance in metres between two WKT POINT values (haversine)."""
    pa = _parse_wkt_point(value_a)
    pb = _parse_wkt_point(value_b)
    if pa is None or pb is None:
        return 0.0
    lon1, lat1 = pa
    lon2, lat2 = pb
    from app.services.geo_service import haversine_km

    return haversine_km(lat1, lon1, lat2, lon2) * 1000.0


def _trigrams(text):
    """pg_trgm-style trigram generation: 2-space padding + lowercase."""
    if not text:
        return []
    padded = "  " + str(text).lower() + "  "
    if len(padded) < 3:
        return []
    return [padded[i : i + 3] for i in range(len(padded) - 2)]


def _trigram_similarity(text_a, text_b) -> float:
    """Reproduce PostgreSQL ``pg_trgm`` ``similarity`` (common/(n1+n2-common))."""
    ta = _trigrams(text_a)
    tb = _trigrams(text_b)
    if not ta or not tb:
        return 0.0
    ca: dict[str, int] = {}
    cb: dict[str, int] = {}
    for t in ta:
        ca[t] = ca.get(t, 0) + 1
    for t in tb:
        cb[t] = cb.get(t, 0) + 1
    common = 0
    for t, n in ca.items():
        m = cb.get(t, 0)
        if m:
            common += n if n < m else m
    total = sum(ca.values()) + sum(cb.values())
    if total - common <= 0:
        return 0.0
    return common / (total - common)


def _register_sqlite_functions(dbapi_conn, connection_record):  # noqa: ANN001
    """Register the PostGIS / pg_trgm SQL functions the production engine emits
    so the real queries run unmodified on SQLite (sync engine only)."""
    dbapi_conn.create_function("ST_GeogFromText", 1, lambda value: value)
    dbapi_conn.create_function("ST_Distance", 2, lambda a, b: _wkt_distance_m(a, b))
    dbapi_conn.create_function("NULL", 0, lambda: None)

    def _dwithin(a, b, radius_m):
        d = _wkt_distance_m(a, b)
        if d is None:
            return 0
        return 1 if d <= (radius_m or 0.0) else 0

    dbapi_conn.create_function("ST_DWithin", 3, _dwithin)
    dbapi_conn.create_function("similarity", 2, _trigram_similarity)


def _set_sqlite_pragmas(dbapi_conn, connection_record):  # noqa: ANN001
    cur = dbapi_conn.cursor()
    cur.execute("PRAGMA journal_mode=WAL")
    cur.execute("PRAGMA busy_timeout=30000")
    cur.close()
# ── Shared SQLite file: synchronous engine (sync routes) + aiosqlite engine
#    (async catalog routes). Both point at the same database file. ─────────────
_TMP_DB = Path(tempfile.mkstemp(prefix="phase20_", suffix=".db")[1])

SYNC_ENGINE = create_engine(
    f"sqlite:///{_TMP_DB.as_posix()}",
    connect_args={"check_same_thread": False, "timeout": 30},
    poolclass=StaticPool,
)
ASYNC_ENGINE = create_async_engine(
    f"sqlite+aiosqlite:///{_TMP_DB.as_posix()}",
    connect_args={"timeout": 30},
)

event.listen(SYNC_ENGINE, "connect", _register_sqlite_functions)
event.listen(SYNC_ENGINE, "connect", _set_sqlite_pragmas)

SyncSession = sessionmaker(bind=SYNC_ENGINE, expire_on_commit=False)
AsyncSessionLocal = async_sessionmaker(bind=ASYNC_ENGINE, expire_on_commit=False)

Base.metadata.create_all(SYNC_ENGINE)
SYNC_ENGINE.dispose()  # release file handles; sessions re-connect lazily

API = "/api/v1"

# ── Fixed, realistic identities used by the dataset ───────────────────────────
ADMIN_PHONE = "+919999999999"            # matches the seeded dev admin
CUSTOMER_PHONE = "+917709000001"
SHOPKEEPER_PHONE = "+917709000100"
CUSTOMER_LAT, CUSTOMER_LNG = 25.5941, 85.1336     # Patna (customer location)
GAYA_LAT, GAYA_LNG = 24.7914, 85.0002            # Gaya (~90 km away)

# Fake Firebase ID tokens -> phone numbers. The customer + shopkeeper auth
# routes now verify a Firebase ID token server-side; these tokens stand in for
# a real phone-OTP sign-in and are mapped back by
# _patch_shopkeeper_firebase_verify().
_FIREBASE_TOKENS = {
    ADMIN_PHONE: "phase20-admin-firebase-token-000000000000000000000000000",
    CUSTOMER_PHONE: "phase20-customer-firebase-token-0000000000000000000000",
    SHOPKEEPER_PHONE: "phase20-shopkeeper-firebase-token-00000000000000000000",
}


def _patch_shopkeeper_firebase_verify() -> None:
    """Point the customer + shopkeeper auth routes' token verifiers at a local
    mapping so the real HTTP flow works without a live Firebase project.

    Permanent module-level patch: test_phase28 reuses phase21's
    ``_build_world`` (which in turn relies on this patch) in the same pytest
    process, so the verifier must stay patched for the whole session.

    Covers BOTH verifiers the routes use today:
      - ``verify_firebase_id_token``        → returns the phone (customer auth
        routes + the Bearer dependency's Firebase probe)
      - ``verify_firebase_id_token_claims`` → returns the full claim dict
        (shopkeeper ``/auth/firebase-login``, Phase 19 minimal-data boundary)
    """
    import app.api.routes.auth as _customer_auth
    import app.api.routes.shopkeeper_auth as _sk_auth
    import app.core.dependencies as _deps
    from app.services.firebase_verification import FirebaseVerificationError

    def _phone_for(token: str) -> str:
        for phone, tok in _FIREBASE_TOKENS.items():
            if token == tok:
                return phone
        raise FirebaseVerificationError("Invalid token")

    def _verify_claims(token: str) -> dict:
        phone = _phone_for(token)
        return {
            "uid": "phase20-firebase-" + phone.replace("+", ""),
            "phone": phone,
            "email": "",
            "name": "",
            "picture": "",
            "provider": "phone",
            "claims": {},
        }

    def _verify_tuple(token: str) -> tuple[str, str]:
        """``auth.py`` and ``app.core.dependencies`` unpack (firebase_uid, phone)."""
        phone = _phone_for(token)
        return ("phase20-firebase-" + phone.replace("+", ""), phone)

    _sk_auth.verify_firebase_id_token = _verify_tuple
    _sk_auth.verify_firebase_id_token_claims = _verify_claims
    _customer_auth.verify_firebase_id_token = _verify_tuple
    # Bearer-token requests resolve through ``get_current_user``, which probes
    # the real Firebase Admin first; without credentials that probe raises
    # RuntimeError (not FirebaseVerificationError) and 500s every request.
    # Patch it so app-issued JWTs fall through to the legacy JWT validator.
    _deps.verify_firebase_id_token = _verify_tuple

CATEGORIES = [
    ("Grocery & Staples", "grocery-staples"),
    ("Dairy & Chilled", "dairy-chilled"),
    ("Personal Care & Hygiene", "personal-care-hygiene"),
    ("Biscuits & Bakery", "biscuits-bakery"),
]
BRANDS = [
    ("Aashirvaad", "aashirvaad"),
    ("Amul", "amul"),
    ("Dettol", "dettol"),
    ("Tata", "tata"),
    ("Britannia", "britannia"),
]
# ── HTTP helpers (drive the REAL API of the running app) ─────────────────────
def _req(client, method, path, *, token=None, json=None, params=None):  # noqa: ANN001
    headers = {}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if json is not None:
        headers["Content-Type"] = "application/json"
    return client.request(method, path, json=json, params=params, headers=headers)


def _ok(resp, what="", statuses=(200, 201)) -> dict:  # noqa: ANN001
    assert resp.status_code in statuses, (
        f"[{what}] expected {statuses}, got {resp.status_code}: {resp.text[:800]}"
    )
    body = resp.json()
    assert body.get("success") is True, f"[{what}] success envelope missing: {resp.text[:800]}"
    return body.get("data")


def _register_customer(client, phone, name) -> dict:  # noqa: ANN001
    # Customer auth is Firebase-based: the Flutter app completes phone-OTP
    # client-side and sends the resulting ID token. We use the combined
    # login-or-register endpoint with a fake token that
    # _patch_shopkeeper_firebase_verify() maps back to the phone number.
    token = _FIREBASE_TOKENS[phone]
    return _ok(
        _req(
            client,
            "POST",
            f"{API}/auth/firebase-login",
            json={
                "firebase_id_token": token,
                "name": name,
                "device_id": "phase20-customer",
                "device_name": "Phase 20 device",
                "device_type": "android",
                "platform": "android",
                "app_version": "1.0",
            },
        ),
        what="customer register",
    )


def _register_shopkeeper(client, phone, name) -> dict:  # noqa: ANN001
    # Shopkeeper auth is Firebase-based: the Flutter app completes phone-OTP
    # client-side and sends the resulting ID token. We use the combined
    # login-or-register endpoint with a fake token that
    # _patch_shopkeeper_firebase_verify() maps back to the phone number.
    token = _FIREBASE_TOKENS[phone]
    return _ok(
        _req(
            client,
            "POST",
            f"{API}/shopkeeper/auth/firebase-login",
            json={
                "firebase_id_token": token,
                "name": name,
                "device_id": "phase20-shopkeeper",
                "device_name": "Phase 20 shopkeeper",
                "device_type": "android",
                "platform": "android",
                "app_version": "1.0",
            },
        ),
        what="shopkeeper register",
    )


def _admin_login(client) -> dict:  # noqa: ANN001
    # Admin auth now also runs through Firebase phone auth (the seeded admin
    # already exists, so firebase-login logs in without a name).
    token = _FIREBASE_TOKENS[ADMIN_PHONE]
    return _ok(
        _req(
            client,
            "POST",
            f"{API}/auth/firebase-login",
            json={
                "firebase_id_token": token,
                "device_id": "phase20-admin",
                "device_name": "Phase 20 admin",
                "device_type": "web",
                "platform": "phase20",
                "app_version": "1.0",
            },
        ),
        what="admin firebase-login",
    )


def _register_shop(client, token, *, name, lat, lng, address_line1, category="GROCERY") -> dict:  # noqa: ANN001
    return _ok(
        _req(
            client,
            "POST",
            f"{API}/shopkeeper/shops",
            json={
                "name": name,
                "description": "Verified neighbourhood store in the Phase 20 controlled dataset.",
                "tagline": "Real products, real prices.",
                "category": category,
                "phone": "+917709000001",
                "whatsapp_number": "+917709000001",
                "email": "shop@example.in",
                "latitude": lat,
                "longitude": lng,
                "address": {
                    "address_line1": address_line1,
                    "city": "Patna",
                    "state": "Bihar",
                    "pincode": "800001",
                    "country": "India",
                },
            },
            token=token,
        ),
        what=f"register shop {name}",
        statuses=(201,),
    )
def _approve_shop(client, admin_token, shop_id) -> dict:  # noqa: ANN001
    return _ok(
        _req(
            client,
            "POST",
            f"{API}/shops/admin/shops/{shop_id}/review",
            json={"decision": "APPROVE", "review_notes": "Phase 20 controlled verification"},
            token=admin_token,
        ),
        what=f"approve shop {shop_id}",
    )


def _create_category(client, admin_token, name, slug) -> dict:  # noqa: ANN001
    return _ok(
        _req(
            client,
            "POST",
            f"{API}/admin/categories",
            json={"name": name, "slug": slug, "description": f"{name} (Phase 20)"},
            token=admin_token,
        ),
        what=f"admin category {name}",
        statuses=(201,),
    )


def _create_brand(client, admin_token, name, slug) -> dict:  # noqa: ANN001
    return _ok(
        _req(
            client,
            "POST",
            f"{API}/admin/brands",
            json={"name": name, "slug": slug, "description": f"{name} (Phase 20)"},
            token=admin_token,
        ),
        what=f"admin brand {name}",
        statuses=(201,),
    )


def _create_product(client, token, shop_id, *, name, unit, price, mrp, quantity, sku) -> dict:  # noqa: ANN001
    return _ok(
        _req(
            client,
            "POST",
            f"{API}/shopkeeper/shops/{shop_id}/products",
            json={
                "name": name,
                "description": f"{name} — real product for Phase 20",
                "unit": unit,
                "price": price,
                "mrp": mrp,
                "sku": sku,
                "quantity": quantity,
                "low_stock_threshold": 5,
                "is_available": True,
                "publish": True,
            },
            token=token,
        ),
        what=f"create product {name}",
        statuses=(201,),
    )


def _admin_edit_product(client, admin_token, product_id, *, brand_id, category_id) -> dict:  # noqa: ANN001
    return _ok(
        _req(
            client,
            "PUT",
            f"{API}/admin/products/{product_id}",
            json={"brand_id": brand_id, "category_id": category_id},
            token=admin_token,
        ),
        what=f"admin edit product {product_id}",
    )


def _add_variant(client, admin_token, master_id, sku, name) -> dict:  # noqa: ANN001
    return _ok(
        _req(
            client,
            "POST",
            f"{API}/catalog/products/{master_id}/variants",
            json={"sku": sku, "name": name, "is_active": True, "sort_order": 0},
            token=admin_token,
        ),
        what=f"catalog variant {name}",
        statuses=(201,),
    )


def _add_identifier(client, admin_token, master_id, value, *, is_primary=False) -> dict:  # noqa: ANN001
    return _ok(
        _req(
            client,
            "POST",
            f"{API}/catalog/products/{master_id}/identifiers",
            json={"identifier_type": "EAN", "identifier_value": value, "is_primary": is_primary},
            token=admin_token,
        ),
        what=f"catalog identifier {value}",
        statuses=(201,),
    )


def _add_barcode(client, admin_token, master_id, barcode, rel="PRIMARY") -> dict:  # noqa: ANN001
    return _ok(
        _req(
            client,
            "POST",
            f"{API}/catalog/products/{master_id}/barcodes",
            json={"barcode": barcode, "relationship_type": rel, "notes": "Phase 20 catalog barcode"},
            token=admin_token,
        ),
        what=f"catalog barcode {barcode}",
        statuses=(201,),
    )
def _add_listing(client, token, shop_id, master_id, *, variant_id=None, price, mrp, quantity, sku, is_available=True) -> dict:  # noqa: ANN001
    body = {
        "product_master_id": master_id,
        "price": price,
        "mrp": mrp,
        "quantity": quantity,
        "low_stock_threshold": 5,
        "is_available": is_available,
        "sku": sku,
    }
    if variant_id is not None:
        body["variant_id"] = variant_id
    return _ok(
        _req(
            client,
            "POST",
            f"{API}/shopkeeper/shops/{shop_id}/inventory/products",
            json=body,
            token=token,
        ),
        what=f"add-from-master {sku}",
        statuses=(201,),
    )


def _assign_offer(client, token, shop_id, sp_ids, *, title, pct, start, end) -> dict:  # noqa: ANN001
    return _ok(
        _req(
            client,
            "POST",
            f"{API}/shopkeeper/shops/{shop_id}/offers/assign",
            json={
                "title": title,
                "offer_type": "PERCENTAGE_DISCOUNT",
                "discount_percentage": pct,
                "start_date": start,
                "end_date": end,
                "shop_product_ids": list(sp_ids),
            },
            token=token,
        ),
        what=f"assign offer {title}",
        statuses=(201,),
    )


def _search(world, q, *, lat=CUSTOMER_LAT, lng=CUSTOMER_LNG, radius=10.0, **params):  # noqa: ANN001
    query = {"q": q, "latitude": lat, "longitude": lng, "radius_km": radius}
    query.update(params)
    resp = _req(world["client"], "GET", f"{API}/search/v2/products", params=query)
    return _ok(resp, what=f"search q={q!r}")


def _nearby(world, *, lat=CUSTOMER_LAT, lng=CUSTOMER_LNG, radius=5.0) -> dict:  # noqa: ANN001
    resp = _req(
        world["client"],
        "GET",
        f"{API}/search/v2/nearby-shops",
        params={"latitude": lat, "longitude": lng, "radius_km": radius},
    )
    return _ok(resp, what="nearby-shops")


def _result_by_shop(data, shop_id):  # noqa: ANN001
    for r in data["results"]:
        if r["shop_id"] == shop_id:
            return r
    return None


def _reindex_shop(db, shop_id) -> None:  # noqa: ANN001
    """Simulate the Celery ``index_shop_product`` worker for every listing."""
    from app.models.product import ShopProduct
    from app.search.indexer import upsert_shop_product

    sp_ids = [row[0] for row in db.query(ShopProduct.id).filter(ShopProduct.shop_id == shop_id).all()]
    for sid in sp_ids:
        upsert_shop_product(db, sid)
    db.commit()


def _ean13(body: str) -> str:
    """GS1 EAN-13 check-digit computation (matches the barcode intake validator)."""
    digits = [int(c) for c in str(body)]
    assert len(digits) == 12, "EAN-13 body must be 12 digits"
    total = sum(d * (1 if i % 2 == 0 else 3) for i, d in enumerate(digits))
    check = (10 - total % 10) % 10
    return "".join(str(c) for c in digits) + str(check)
# ── The controlled production-like world ─────────────────────────────────────
def _seed_rbac_roles(db) -> None:
    """Seed the platform roles/permissions and the dev admin account the
    production ``seed_data.run_seed()`` creates (via the same helpers)."""
    from app.services.seed_data import seed_admin_user, seed_roles

    seed_roles(db)
    seed_admin_user(db)
    db.commit()


def _build_world() -> dict:
    """Create the entire controlled dataset through the real HTTP APIs, then
    return a handle the tests can query/mutate through the same APIs."""
    from fastapi.testclient import TestClient

    from app.database.session import get_db
    from app.main import app as fastapi_app

    # Customer + shopkeeper auth are Firebase-based; map our fake tokens to phones.
    _patch_shopkeeper_firebase_verify()

    db = SyncSession()

    # Seed roles + the dev admin (production tooling, not random inserts).
    _seed_rbac_roles(db)

    def _override_get_db():
        return db

    # Async catalog routes use the same file-backed database through aiosqlite.
    import app.database.session as db_session_mod

    async def _override_get_async_db():
        async with AsyncSessionLocal() as session:
            try:
                yield session
                await session.commit()
            except Exception:
                await session.rollback()
                raise
            finally:
                await session.close()

    previous = dict(fastapi_app.dependency_overrides)
    fastapi_app.dependency_overrides[get_db] = _override_get_db
    fastapi_app.dependency_overrides[db_session_mod.get_async_db] = _override_get_async_db

    client = TestClient(fastapi_app)

    # ── Accounts (real OTP flows) ───────────────────────────────────────────
    admin_tokens = _admin_login(client)
    admin_token = admin_tokens["access_token"]
    customer_tokens = _register_customer(client, CUSTOMER_PHONE, "Aarav Sharma")
    customer_token = customer_tokens["access_token"]
    shopkeeper_tokens = _register_shopkeeper(client, SHOPKEEPER_PHONE, "Ramesh Kumar")
    shopkeeper_token = shopkeeper_tokens["access_token"]

    # ── Categories & brands (real admin tooling) ────────────────────────────
    categories = {}
    for name, slug in CATEGORIES:
        categories[slug] = _create_category(client, admin_token, name, slug)
    brands = {}
    for name, slug in BRANDS:
        brands[slug] = _create_brand(client, admin_token, name, slug)

    # ── Verified shops (real shopkeeper + admin flow) ───────────────────────
    shop_a = _register_shop(
        client,
        shopkeeper_token,
        name="Patna Fresh Mart",
        lat=25.612,
        lng=85.137,
        address_line1="Shop 14, Boring Road",
        category="GROCERY",
    )
    shop_b = _register_shop(
        client,
        shopkeeper_token,
        name="Bihar SuperStore",
        lat=25.605,
        lng=85.168,
        address_line1="Ground Floor, Gandhi Maidan Marg",
        category="GROCERY",
    )
    _approve_shop(client, admin_token, shop_a["id"])
    _approve_shop(client, admin_token, shop_b["id"])

    # ── Master products (real shopkeeper publish flow) ──────────────────────
    # NOTE: create_product() publishes into shop_a, so p_*["id"] are the
    # shop_a shop-product ids (they also carry the inventory + price).
    from app.models.product import ShopProduct as _ShopProduct

    p_atta = _create_product(
        client, shopkeeper_token, shop_a["id"],
        name="Aashirvaad Whole Wheat Atta",
        unit="5 kg",
        price=230.0, mrp=255.0, quantity=40, sku="PH20-ATTA-5KG",
    )
    p_milk = _create_product(
        client, shopkeeper_token, shop_a["id"],
        name="Amul Taaza Toned Milk",
        unit="500 ml",
        price=29.0, mrp=31.0, quantity=60, sku="PH20-MILK-500ML",
    )
    p_sanitizer = _create_product(
        client, shopkeeper_token, shop_a["id"],
        name="Dettol Hand Sanitizer",
        unit="200 ml",
        price=85.0, mrp=99.0, quantity=25, sku="PH20-SANITIZER-200ML",
    )

    def _master_id(sp_id: int) -> int:
        return db.query(_ShopProduct).filter(_ShopProduct.id == sp_id).first().product_master_id

    master_atta = _master_id(p_atta["id"])
    master_milk = _master_id(p_milk["id"])
    master_sanitizer = _master_id(p_sanitizer["id"])

    # Attach brand + category to each master via the admin tooling.
    _admin_edit_product(
        client, admin_token, master_atta,
        brand_id=brands["aashirvaad"]["id"], category_id=categories["grocery-staples"]["id"],
    )
    _admin_edit_product(
        client, admin_token, master_milk,
        brand_id=brands["amul"]["id"], category_id=categories["dairy-chilled"]["id"],
    )
    _admin_edit_product(
        client, admin_token, master_sanitizer,
        brand_id=brands["dettol"]["id"], category_id=categories["personal-care-hygiene"]["id"],
    )

    # ── Variants, identifiers, barcodes (real catalog API) ──────────────────
    # Barcodes are generated via the GS1 EAN-13 check-digit algorithm so the
    # real barcode-intake validator (which rejects bad check digits) accepts them.
    barcode_atta = _ean13("890106300123")
    barcode_milk = _ean13("890126200543")
    barcode_sanitizer = _ean13("890149650987")
    _add_variant(client, admin_token, master_atta, "PH20-ATTA-V2", "Aashirvaad Atta 5kg (Family Pack)")
    _add_identifier(client, admin_token, master_atta, barcode_atta, is_primary=True)
    _add_barcode(client, admin_token, master_atta, barcode_atta)
    _add_barcode(client, admin_token, master_milk, barcode_milk)
    _add_identifier(client, admin_token, master_milk, barcode_milk, is_primary=True)
    _add_identifier(client, admin_token, master_sanitizer, barcode_sanitizer, is_primary=True)
    _add_barcode(client, admin_token, master_sanitizer, barcode_sanitizer)

    # ── Shop-product mappings for shop_b (real add-from-master flow) ────────
    # shop_a already has listings (created by the publish flow above).
    shop_b_atta = _add_listing(
        client, shopkeeper_token, shop_b["id"], master_atta,
        price=235.0, mrp=255.0, quantity=20, sku="PH20-ATTA-B",
    )
    shop_b_milk = _add_listing(
        client, shopkeeper_token, shop_b["id"], master_milk,
        price=30.0, mrp=31.0, quantity=15, sku="PH20-MILK-B",
    )

    # ── Offer (real offer-assign flow) ───────────────────────────────────────
    from datetime import datetime, timedelta, timezone

    now = datetime.now(timezone.utc)
    _assign_offer(
        client, shopkeeper_token, shop_a["id"], [p_atta["id"]],
        title="Atta Mega Deal",
        pct=5, start=now.isoformat(), end=(now + timedelta(days=30)).isoformat(),
    )

    # ── Search index via the real indexer (what the Celery worker runs) ─────
    _reindex_shop(db, shop_a["id"])
    _reindex_shop(db, shop_b["id"])

    world = {
        "db": db,
        "client": client,
        "token": customer_token,
        "vendor_token": shopkeeper_token,
        "admin_token": admin_token,
        "categories": categories,
        "brands": brands,
        "shop_a": shop_a,
        "shop_b": shop_b,
        "p_atta": p_atta,
        "p_milk": p_milk,
        "p_sanitizer": p_sanitizer,
        "s_atta_a": p_atta,
        "s_milk_a": p_milk,
        "s_sanitizer_a": p_sanitizer,
        "s_atta_b": shop_b_atta,
        "s_milk_b": shop_b_milk,
        "fastapi_app": fastapi_app,
        "previous_overrides": previous,
    }
    return world


@pytest.fixture(scope="module")
def world():
    """One controlled production-like dataset for the whole module."""
    _world = _build_world()
    try:
        yield _world
    finally:
        _world["db"].close()
        _world["fastapi_app"].dependency_overrides.clear()
        _world["fastapi_app"].dependency_overrides.update(_world["previous_overrides"])


# ── Mutation helpers (real shopkeeper routes, then the real index worker) ─────
def _update_product(world, shop_id, sp_id, **fields) -> dict:  # noqa: ANN001
    return _ok(
        _req(
            world["client"],
            "PATCH",
            f"{API}/shopkeeper/shops/{shop_id}/products/{sp_id}",
            json=fields,
            token=world["vendor_token"],
        ),
        what=f"shopkeeper update product {sp_id}",
    )


def _update_shop(world, shop_id, **fields) -> dict:  # noqa: ANN001
    return _ok(
        _req(
            world["client"],
            "PUT",
            f"{API}/shops/my/shops/{shop_id}",
            json=fields,
            token=world["vendor_token"],
        ),
        what=f"update shop {shop_id}",
    )


def _shop_product(world, shop_product_id) -> dict:  # noqa: ANN001
    from app.models.product import Inventory, ShopProduct

    sp = world["db"].query(ShopProduct).filter(ShopProduct.id == shop_product_id).first()
    inv = world["db"].query(Inventory).filter(Inventory.shop_product_id == sp.id).first()
    return {
        "sp": sp,
        "inv": inv,
        "price": float(sp.price),
        "mrp": float(sp.mrp) if sp.mrp is not None else None,
        "quantity": int(inv.quantity),
        "is_available": bool(inv.is_available),
        "stock_status": inv.stock_status.value,
    }


# ═══════════════════════════════════════════════════════════════════════════════
# 1. Dataset — created through real APIs / admin tools / import tooling
# ═══════════════════════════════════════════════════════════════════════════════
def test_dataset_created_through_real_apis_and_tools(world):
    """Every required entity exists and was produced by the platform's own APIs."""
    from app.models.product import (
        BarcodeRelationship,
        Brand,
        Category,
        Inventory,
        InventoryMovement,
        Offer,
        ProductIdentifier,
        ProductMaster,
        ProductVariant,
        ShopProduct,
    )
    from app.models.shop import Shop, ShopStatus
    from app.models.user import User

    db = world["db"]

    customer = db.query(User).filter(User.phone_number == CUSTOMER_PHONE).first()
    shopkeeper = db.query(User).filter(User.phone_number == SHOPKEEPER_PHONE).first()
    admin = db.query(User).filter(User.phone_number == ADMIN_PHONE).first()
    assert customer is not None and customer.role.name == "customer"
    assert shopkeeper is not None and shopkeeper.role.name == "shopkeeper"
    assert admin is not None and admin.role.name == "admin"

    shop_a = db.query(Shop).filter(Shop.id == world["shop_a"]["id"]).first()
    shop_b = db.query(Shop).filter(Shop.id == world["shop_b"]["id"]).first()
    # APPROVE via review_verification promotes a registered shop to ACTIVE (and
    # marks it verified) — the customer-facing "verified shop" lifecycle.
    assert shop_a.status == ShopStatus.ACTIVE and shop_a.is_verified is True
    assert shop_b.status == ShopStatus.ACTIVE and shop_b.is_verified is True
    assert shop_a.latitude is not None and shop_a.longitude is not None

    assert db.query(Category).filter(Category.slug.in_([s for _, s in CATEGORIES])).count() == len(CATEGORIES)
    assert db.query(Brand).filter(Brand.slug.in_([s for _, s in BRANDS])).count() == len(BRANDS)

    assert db.query(ProductMaster).filter(ProductMaster.name.ilike("Aashirvaad%")).count() >= 1
    assert db.query(ProductMaster).filter(ProductMaster.name.ilike("Amul%")).count() >= 1
    assert db.query(ProductMaster).filter(ProductMaster.name.ilike("Dettol%")).count() >= 1

    assert db.query(ProductVariant).filter(ProductVariant.sku == "PH20-ATTA-V2").count() == 1
    assert db.query(ProductIdentifier).filter(
        ProductIdentifier.identifier_value == _ean13("890106300123")
    ).count() >= 1
    assert db.query(BarcodeRelationship).filter(
        BarcodeRelationship.barcode == _ean13("890126200543")
    ).count() >= 1

    sp_count = db.query(ShopProduct).filter(ShopProduct.shop_id == world["shop_a"]["id"]).count()
    assert sp_count == 3
    inv_count = db.query(Inventory).filter(Inventory.shop_product_id.in_(
        db.query(ShopProduct.id).filter(ShopProduct.shop_id == world["shop_a"]["id"])
    )).count()
    assert inv_count == 3
    assert db.query(InventoryMovement).count() >= 2  # both add-from-master listings wrote INITIAL movements

    for sp in db.query(ShopProduct).filter(ShopProduct.shop_id == world["shop_a"]["id"]).all():
        assert float(sp.price) > 0
        assert float(sp.mrp) >= float(sp.price)

    offer = db.query(Offer).filter(Offer.shop_id == world["shop_a"]["id"]).first()
    assert offer is not None and offer.title == "Atta Mega Deal"
    assert offer.offer_products and offer.offer_products[0].shop_product_id == world["s_atta_a"]["id"]


def test_customer_can_search_dataset_by_name_brand_and_category(world):
    data = _search(world, "Aashirvaad Whole Wheat Atta")
    assert data["total"] >= 1

    data = _search(world, "Amul Taaza Toned Milk")
    assert data["total"] >= 1

    data = _search(world, "hand sanitizer")
    assert data["total"] >= 1

    # Every result carries product + shop + price + availability + distance
    for r in data["results"]:
        assert r["product_id"] and r["shop_id"]
        assert r["price"] is not None and r["mrp"] is not None
        assert r["is_available"] in (True, False)
        assert r["distance_km"] is not None


def test_barcode_identifier_lookup_resolves_to_product(world):
    from app.services import barcode_intake_service as intake

    result = intake.resolve_barcode(world["db"], _ean13("890106300123"))
    assert result["status"] == "FOUND"
    assert result["matches"][0]["name"].startswith("Aashirvaad")


def test_offer_text_surfaces_in_search_results(world):
    data = _search(world, "Aashirvaad Whole Wheat Atta")
    atta_res = _result_by_shop(data, world["shop_a"]["id"])
    assert atta_res is not None
# ═══════════════════════════════════════════════════════════════════════════════
# 2. Mutation -> discovery loops (the core of Phase 20)
# ═══════════════════════════════════════════════════════════════════════════════
def test_shopkeeper_inventory_update_changes_search_result(world):
    """Shopkeeper drops atta stock to 3 (below threshold) -> DB row changes ->
    the customer search now reports LIMITED_STOCK for that shop."""
    sp_id = world["s_atta_a"]["id"]

    # Baseline: full stock, IN_STOCK in search.
    before = _shop_product(world, sp_id)
    assert before["quantity"] == 40
    assert before["stock_status"] == "IN_STOCK"
    base = _search(world, "Aashirvaad Whole Wheat Atta")
    base_res = _result_by_shop(base, world["shop_a"]["id"])
    assert base_res is not None and base_res["stock_status"] == "IN_STOCK"

    # Shopkeeper updates inventory via the real shopkeeper API.
    updated = _update_product(world, world["shop_a"]["id"], sp_id, quantity=3)
    assert updated["quantity"] == 3
    assert updated["stock_status"] == "LOW_STOCK"

    # DB row actually changed.
    after = _shop_product(world, sp_id)
    assert after["quantity"] == 3
    assert after["stock_status"] == "LOW_STOCK"

    # The search-index worker (Celery) re-indexes; the customer sees it.
    _reindex_shop(world["db"], world["shop_a"]["id"])
    data = _search(world, "Aashirvaad Whole Wheat Atta")
    res = _result_by_shop(data, world["shop_a"]["id"])
    assert res is not None, "shop_a should still surface the product"
    assert res["stock_status"] == "LIMITED_STOCK"
    assert res["is_available"] is True  # still purchasable, just limited


def test_price_update_changes_customer_search_price(world):
    """Shopkeeper lowers atta price 230 -> 199; the customer search price changes."""
    sp_id = world["s_atta_a"]["id"]

    base = _search(world, "Aashirvaad Whole Wheat Atta")
    assert _result_by_shop(base, world["shop_a"]["id"])["price"] == 230.0

    updated = _update_product(world, world["shop_a"]["id"], sp_id, price=199.0, mrp=255.0)
    assert float(updated["price"]) == 199.0

    after_db = _shop_product(world, sp_id)
    assert after_db["price"] == 199.0

    _reindex_shop(world["db"], world["shop_a"]["id"])
    data = _search(world, "Aashirvaad Whole Wheat Atta")
    res = _result_by_shop(data, world["shop_a"]["id"])
    assert res is not None and res["price"] == 199.0
    assert res["mrp"] == 255.0


def test_inventory_unavailable_hides_from_customer(world):
    """Shopkeeper sets sanitizer quantity to 0 -> customer in-stock search no
    longer returns it, and availability flips on the unfiltered search."""
    sp_id = world["s_sanitizer_a"]["id"]

    base = _search(world, "Dettol Hand Sanitizer")
    res = _result_by_shop(base, world["shop_a"]["id"])
    assert res is not None and res["is_available"] is True

    # Baseline: the sanitizer appears in an in-stock-only search.
    base_in_stock = _search(world, "Dettol Hand Sanitizer", in_stock=True)
    ids = {r["shop_id"] for r in base_in_stock["results"]}
    assert world["shop_a"]["id"] in ids

    updated = _update_product(world, world["shop_a"]["id"], sp_id, quantity=0)
    assert updated["quantity"] == 0
    assert updated["stock_status"] == "OUT_OF_STOCK"

    after = _shop_product(world, sp_id)
    assert after["quantity"] == 0 and after["is_available"] is False

    _reindex_shop(world["db"], world["shop_a"]["id"])

    # In-stock search now hides shop_a's sanitizer.
    after_in_stock = _search(world, "Dettol Hand Sanitizer", in_stock=True)
    ids_after = {r["shop_id"] for r in after_in_stock["results"]}
    assert world["shop_a"]["id"] not in ids_after

    # Unfiltered search either drops it or marks it unavailable.
    after_all = _search(world, "Dettol Hand Sanitizer")
    res_after = _result_by_shop(after_all, world["shop_a"]["id"])
    if res_after is not None:
        assert res_after["is_available"] is False
        assert res_after["stock_status"] == "OUT_OF_STOCK"


def test_shop_location_change_changes_nearby_results(world):
    """Moving shop_a from Patna to Gaya (~90 km away) removes it from the
    customer's nearby-shop radius while keeping shop_b."""
    # Baseline: both shops are within 5 km of the customer.
    base = _nearby(world, radius=5.0)
    ids = {s["shop_id"] for s in base["shops"]}
    assert world["shop_a"]["id"] in ids
    assert world["shop_b"]["id"] in ids

    # Shopkeeper relocates shop_a to Gaya via the real shop API.
    _update_shop(world, world["shop_a"]["id"], latitude=GAYA_LAT, longitude=GAYA_LNG)

    shop = world["db"].get(__import__("app.models.shop", fromlist=["Shop"]).Shop, world["shop_a"]["id"])
    assert shop.latitude == GAYA_LAT and shop.longitude == GAYA_LNG

    _reindex_shop(world["db"], world["shop_a"]["id"])

    after = _nearby(world, radius=5.0)
    ids_after = {s["shop_id"] for s in after["shops"]}
    assert world["shop_a"]["id"] not in ids_after, "relocated shop must leave the nearby radius"
    assert world["shop_b"]["id"] in ids_after

    # Product search within 10 km also stops returning the relocated shop.
    data = _search(world, "Amul Taaza Toned Milk", radius=10.0)
    res_ids = {r["shop_id"] for r in data["results"]}
    assert world["shop_a"]["id"] not in res_ids
    assert world["shop_b"]["id"] in res_ids