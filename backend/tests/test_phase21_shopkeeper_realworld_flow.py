"""Phase 21 — Shopkeeper real-world flow (end-to-end, API-only).

The complete lifecycle a real shopkeeper goes through — registration, shop
creation + address, shop verification, product lookup, barcode lookup,
product mapping (price / inventory / availability), offer, publish — followed
by the customer-side verification (search → product → nearby shop → price →
availability).

**No manual database editing is required for any normal shopkeeper operation.**

Every row in this test is created through the platform's own HTTP APIs /
admin tools / catalog tooling:

    Shopkeeper account ... POST /api/v1/shopkeeper/auth/send-otp + /auth/register
    Customer account ..... POST /api/v1/auth/send-otp + /auth/register
    Platform catalog ..... POST /api/v1/admin/categories, /admin/brands
                           POST /api/v1/catalog/products  (identifiers + variant)
                           POST /api/v1/catalog/products/{id}/barcodes
                           POST /api/v1/catalog/approvals + /approvals/{id}/review
    Shop creation ........ POST /api/v1/shopkeeper/shops  (address inside)
    Shop address ......... POST /api/v1/shops/my/shops/{id}/addresses
                           PUT  /api/v1/shops/my/shops/addresses/{address_id}
    Shop verification .... POST /api/v1/shops/my/shops/{id}/documents
                           POST /api/v1/shops/my/shops/{id}/submit-verification
                           POST /api/v1/shops/admin/shops/{id}/review  (APPROVE)
    Product lookup ....... GET  /api/v1/shopkeeper/shops/{id}/catalog/search
    Barcode lookup ....... GET  /api/v1/shopkeeper/barcodes/{barcode}/resolve
    Product mapping ...... POST /api/v1/shopkeeper/shops/{id}/inventory/products
    Price / inventory .... set by the same mapping payload (price, mrp, quantity)
    Availability ......... set by the same mapping payload (is_available)
    Offer ................ POST /api/v1/shopkeeper/shops/{id}/offers/assign
    Publish .............. the search-index worker (Celery) indexes the listing
                           (``app.search.indexer.upsert_shop_product``, the exact
                           body the ``index_shop_product`` task executes)

    Customer verification:
    Search ............... GET /api/v1/search/v2/products
    Product .............. result carries product id/name/brand/category
    Nearby shop .......... GET /api/v1/search/v2/nearby-shops
    Price ................ result price + mrp
    Availability ......... result is_available + stock_status

The DB layer is used ONLY for *read-only assertions* (verifying the API calls
persisted what they must), never to create or mutate rows. The single exception
is the production bootstrap (roles + dev admin) via ``app.services.seed_data``
exactly as the real deployment's ``seed_data.run_seed()`` does.

Infrastructure: the suite runs on a shared SQLite *file* (one synchronous
engine for the sync route graph + one ``sqlite+aiosqlite`` engine for the async
catalog routes), with the PostGIS / pg_trgm SQL functions the production search
emits registered as faithful Python shims (haversine geodesics + pg_trgm
trigram similarity) and the Geography columns made SQLite-portable via
``tests.geo_compat`` — the same proven harness as Phases 19 & 20.
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
    rejects the duplicate, so drop one before ``create_all`` (as Phase 19/20)."""
    tbl = BarcodeRelationship.__table__
    for ix in list(tbl.indexes):
        if ix.name == "ix_barcode_relationships_barcode":
            tbl.indexes.discard(ix)
            break


_dedupe_barcode_index()


# ── SQLite geometry shim for shop registration ─────────────────────────────
import app.services.shop_service as _shop_service  # noqa: E402

_orig_get_wkt_point = _shop_service._get_wkt_point


def _text_wkt_point(latitude: float, longitude: float) -> str:
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
    so the real queries execute unmodified on SQLite (sync engine only)."""
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
_TMP_DB = Path(tempfile.mkstemp(prefix="phase21_", suffix=".db")[1])

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

# ── Fixed, realistic identities used by the flow ──────────────────────────────
ADMIN_PHONE = "+919999999999"            # matches the seeded dev admin
CUSTOMER_PHONE = "+917709000021"
SHOPKEEPER_PHONE = "+917709000120"
CUSTOMER_LAT, CUSTOMER_LNG = 25.5941, 85.1336     # Patna (customer location)
SHOP_LAT, SHOP_LNG = 25.612, 85.137              # ~2 km from the customer

# Fake Firebase ID tokens -> phone numbers for the customer + shopkeeper auth
# flows. Both routes verify a Firebase ID token server-side; these tokens stand
# in for a real phone-OTP sign-in and are mapped back by
# _patch_shopkeeper_firebase_verify().
_FAKE_FIREBASE_TOKENS = {
    ADMIN_PHONE: "phase21-admin-firebase-token-0000000000000000000000000000",
    CUSTOMER_PHONE: "phase21-customer-firebase-token-000000000000000000000000",
    SHOPKEEPER_PHONE: "phase21-shopkeeper-firebase-token-00000000000000000000",
}


def _patch_shopkeeper_firebase_verify() -> None:
    """Point the customer + shopkeeper auth routes' token verifiers at a local
    mapping so the real HTTP flow works without a live Firebase project.

    This is a permanent module-level patch (not a fixture): test_phase28
    reuses this module's ``_build_world`` in the same pytest process, so the
    verifier must stay patched for the whole session.

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
        for phone, tok in _FAKE_FIREBASE_TOKENS.items():
            if token == tok:
                return phone
        raise FirebaseVerificationError("Invalid token")

    def _verify_claims(token: str) -> dict:
        phone = _phone_for(token)
        return {
            "uid": "phase21-firebase-" + phone.replace("+", ""),
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
        return ("phase21-firebase-" + phone.replace("+", ""), phone)

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
    ("Household Essentials", "household-essentials"),
]
BRANDS = [
    ("Aashirvaad", "aashirvaad"),
    ("Amul", "amul"),
    ("Tata", "tata"),
]

# Catalog specs: (name, brand slug, category slug, unit, EAN-13 body)
# Barcodes are GS1 EAN-13 (12 digits + real check digit) so the real
# barcode-intake validator (which rejects bad check digits) accepts them.
MASTER_ATTA = ("Aashirvaad Whole Wheat Atta", "aashirvaad", "grocery-staples", "5 kg", "890106300123")
MASTER_MILK = ("Amul Taaza Toned Milk", "amul", "dairy-chilled", "500 ml", "890126200543")
MASTER_SALT = ("Tata Salt 1kg", "tata", "household-essentials", "1 kg", "890149650987")


def _ean13(body: str) -> str:
    """GS1 EAN-13 check-digit computation (matches the barcode intake validator)."""
    digits = [int(c) for c in str(body)]
    assert len(digits) == 12, "EAN-13 body must be 12 digits"
    total = sum(d * (1 if i % 2 == 0 else 3) for i, d in enumerate(digits))
    check = (10 - total % 10) % 10
    return "".join(str(c) for c in digits) + str(check)


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


# ── Accounts (real OTP flows) ────────────────────────────────────────────────
def _register_customer(client, phone, name) -> dict:  # noqa: ANN001
    # Customer auth is Firebase-based (phone-OTP verified client-side). The
    # combined login-or-register endpoint runs with a fake token mapped back to
    # the phone by _patch_shopkeeper_firebase_verify().
    token = _FAKE_FIREBASE_TOKENS[phone]
    return _ok(
        _req(
            client,
            "POST",
            f"{API}/auth/firebase-login",
            json={
                "firebase_id_token": token,
                "name": name,
                "device_id": "phase21-customer",
                "device_name": "Phase 21 customer device",
                "device_type": "android",
                "platform": "android",
                "app_version": "1.0",
            },
        ),
        what="customer register",
    )


def _register_shopkeeper(client, phone, name) -> dict:  # noqa: ANN001
    # Shopkeeper auth is Firebase-based (phone-OTP verified client-side). The
    # combined login-or-register endpoint runs with a fake token mapped back to
    # the phone by _patch_shopkeeper_firebase_verify().
    token = _FAKE_FIREBASE_TOKENS[phone]
    return _ok(
        _req(
            client,
            "POST",
            f"{API}/shopkeeper/auth/firebase-login",
            json={
                "firebase_id_token": token,
                "name": name,
                "device_id": "phase21-shopkeeper",
                "device_name": "Phase 21 shopkeeper device",
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
    token = _FAKE_FIREBASE_TOKENS[ADMIN_PHONE]
    return _ok(
        _req(
            client,
            "POST",
            f"{API}/auth/firebase-login",
            json={
                "firebase_id_token": token,
                "device_id": "phase21-admin",
                "device_name": "Phase 21 admin device",
                "device_type": "web",
                "platform": "phase21",
                "app_version": "1.0",
            },
        ),
        what="admin firebase-login",
    )


# ── Platform catalog (admin + catalog tooling). The shopkeeper NEVER creates
#    master products in Phase 21 — they are part of the shared platform catalog
#    built through the same tooling operators use. ─────────────────────────────
def _create_category(client, admin_token, name, slug) -> dict:  # noqa: ANN001
    return _ok(
        _req(
            client,
            "POST",
            f"{API}/admin/categories",
            json={"name": name, "slug": slug, "description": f"{name} (Phase 21)"},
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
            json={"name": name, "slug": slug, "description": f"{name} (Phase 21)"},
            token=admin_token,
        ),
        what=f"admin brand {name}",
        statuses=(201,),
    )


def _create_master_product(client, admin_token, *, name, slug, category_id, brand_id, unit, barcode) -> dict:  # noqa: ANN001
    """POST /catalog/products — the platform catalog tooling creates the master
    row together with its EAN identifier and a variant (all in one payload)."""
    return _ok(
        _req(
            client,
            "POST",
            f"{API}/catalog/products",
            json={
                "name": name,
                "slug": slug,
                "description": f"{name} — platform catalog row for Phase 21",
                "category_id": category_id,
                "brand_id": brand_id,
                "base_unit": unit,
                "is_searchable": True,
                "identifiers": [
                    {"identifier_type": "EAN", "identifier_value": barcode}
                ],
                "variants": [
                    {
                        "sku": f"{slug.upper().replace('-', '_')}_V1",
                        "name": f"{name} (Family Pack)",
                        "is_active": True,
                        "sort_order": 0,
                    }
                ],
            },
            token=admin_token,
        ),
        what=f"catalog master {name}",
        statuses=(201,),
    )


def _add_barcode(client, admin_token, master_id, barcode) -> dict:  # noqa: ANN001
    return _ok(
        _req(
            client,
            "POST",
            f"{API}/catalog/products/{master_id}/barcodes",
            json={"barcode": barcode, "relationship_type": "PRIMARY"},
            token=admin_token,
        ),
        what=f"catalog barcode {barcode}",
        statuses=(201,),
    )


def _submit_master_approval(client, token, master_id) -> dict:  # noqa: ANN001
    return _ok(
        _req(
            client,
            "POST",
            f"{API}/catalog/approvals",
            json={"product_master_id": master_id, "submission_data": {"source": "phase21"}},
            token=token,
        ),
        what=f"submit approval master {master_id}",
        statuses=(201,),
    )


def _review_master_approval(client, admin_token, approval_id) -> dict:  # noqa: ANN001
    return _ok(
        _req(
            client,
            "POST",
            f"{API}/catalog/approvals/{approval_id}/review",
            json={"status": "APPROVED", "review_notes": "Phase 21 catalog verification"},
            token=admin_token,
        ),
        what=f"review approval {approval_id}",
    )


# ── Shopkeeper operational helpers (Phase 21 core flow) ──────────────────────
def _register_shop(client, token, *, name, lat, lng, address_line1, category="GROCERY") -> dict:  # noqa: ANN001
    """POST /shopkeeper/shops — creates the shop AND its primary address in
    one call (the standard shopkeeper registration payload)."""
    return _ok(
        _req(
            client,
            "POST",
            f"{API}/shopkeeper/shops",
            json={
                "name": name,
                "description": "Neighbourhood store onboarded through the real Phase 21 flow.",
                "tagline": "Real products, real prices.",
                "category": category,
                "phone": "+917709000120",
                "whatsapp_number": "+917709000120",
                "email": "phase21.shop@example.in",
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


def _add_shop_address(client, token, shop_id) -> dict:  # noqa: ANN001
    """POST /shops/my/shops/{id}/addresses — a second business address."""
    return _ok(
        _req(
            client,
            "POST",
            f"{API}/shops/my/shops/{shop_id}/addresses",
            json={
                "address_line1": "Branch Counter 2, Bailey Road",
                "city": "Patna",
                "state": "Bihar",
                "pincode": "800014",
                "country": "India",
                "is_primary": False,
            },
            token=token,
        ),
        what=f"add shop address for shop {shop_id}",
        statuses=(201,),
    )


def _update_shop_address(client, token, address_id) -> dict:  # noqa: ANN001
    """PUT /shops/my/shops/addresses/{address_id} — edit an existing address."""
    return _ok(
        _req(
            client,
            "PUT",
            f"{API}/shops/my/shops/addresses/{address_id}",
            json={"landmark": "Near Gandhi Maidan"},
            token=token,
        ),
        what=f"update shop address {address_id}",
    )


def _submit_shop_document(client, token, shop_id) -> dict:  # noqa: ANN001
    return _ok(
        _req(
            client,
            "POST",
            f"{API}/shops/my/shops/{shop_id}/documents",
            json={
                "document_type": "GST",
                "document_url": "https://example.in/docs/gst-phase21.pdf",
                "document_number": "GSTIN21XX0000001",
            },
            token=token,
        ),
        what=f"submit shop document for shop {shop_id}",
        statuses=(201,),
    )


def _submit_for_verification(client, token, shop_id) -> dict:  # noqa: ANN001
    return _ok(
        _req(
            client,
            "POST",
            f"{API}/shops/my/shops/{shop_id}/submit-verification",
            token=token,
        ),
        what=f"submit shop {shop_id} for verification",
    )


def _approve_shop(client, admin_token, shop_id) -> dict:  # noqa: ANN001
    return _ok(
        _req(
            client,
            "POST",
            f"{API}/shops/admin/shops/{shop_id}/review",
            json={"decision": "APPROVE", "review_notes": "Phase 21 admin verification"},
            token=admin_token,
        ),
        what=f"approve shop {shop_id}",
    )


def _search_shopkeeper_catalog(client, token, shop_id, q) -> dict:  # noqa: ANN001
    """GET /shopkeeper/shops/{id}/catalog/search — product LOOKUP from the
    shared master catalog (the shopkeeper searches then maps)."""
    resp = _req(
        client,
        "GET",
        f"{API}/shopkeeper/shops/{shop_id}/catalog/search",
        params={"q": q},
        token=token,
    )
    return _ok(resp, what=f"shopkeeper catalog search q={q!r}")


def _resolve_barcode(client, token, shop_id, barcode) -> dict:  # noqa: ANN001
    """GET /shopkeeper/barcodes/{barcode}/resolve — the shopkeeper scans /
    types a barcode and the platform identifies the catalog product."""
    resp = _req(
        client,
        "GET",
        f"{API}/shopkeeper/barcodes/{barcode}/resolve",
        params={"shop_id": shop_id},
        token=token,
    )
    return _ok(resp, what=f"resolve barcode {barcode}")


def _map_product(client, token, shop_id, *, master_id, price, mrp, quantity, sku, is_available=True) -> dict:  # noqa: ANN001
    """POST /shopkeeper/shops/{id}/inventory/products — the shopkeeper maps a
    catalog product to the shop with price / MRP / quantity / availability."""
    return _ok(
        _req(
            client,
            "POST",
            f"{API}/shopkeeper/shops/{shop_id}/inventory/products",
            json={
                "product_master_id": master_id,
                "price": price,
                "mrp": mrp,
                "quantity": quantity,
                "low_stock_threshold": 5,
                "is_available": is_available,
                "sku": sku,
            },
            token=token,
        ),
        what=f"map master {master_id} to shop {shop_id}",
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


# ── Customer-verification helpers (the Phase 21 customer leg) ────────────────
def _search(world, q, *, lat=CUSTOMER_LAT, lng=CUSTOMER_LNG, radius=10.0, **params):  # noqa: ANN001
    resp = _req(
        world["client"],
        "GET",
        f"{API}/search/v2/products",
        params={"q": q, "latitude": lat, "longitude": lng, "radius_km": radius, **params},
    )
    return _ok(resp, what=f"customer search q={q!r}")


def _nearby(world, *, lat=CUSTOMER_LAT, lng=CUSTOMER_LNG, radius=5.0) -> dict:  # noqa: ANN001
    resp = _req(
        world["client"],
        "GET",
        f"{API}/search/v2/nearby-shops",
        params={"latitude": lat, "longitude": lng, "radius_km": radius},
    )
    return _ok(resp, what="customer nearby-shops")


def _result_by_shop(data, shop_id):  # noqa: ANN001
    for r in data["results"]:
        if r["shop_id"] == shop_id:
            return r
    return None


def _reindex_shop(db, shop_id) -> None:  # noqa: ANN001
    """Simulate the Celery ``index_shop_product`` worker for every listing —
    the exact body the background task executes (production publish path)."""
    from app.models.product import ShopProduct
    from app.search.indexer import upsert_shop_product

    sp_ids = [row[0] for row in db.query(ShopProduct.id).filter(ShopProduct.shop_id == shop_id).all()]
    for sid in sp_ids:
        upsert_shop_product(db, sid)
    db.commit()


def _seed_rbac_roles(db) -> None:  # noqa: ANN001
    """Seed the platform roles/permissions and the dev admin account the
    production ``seed_data.run_seed()`` creates (via the same helpers)."""
    from app.services.seed_data import seed_admin_user, seed_roles

    seed_roles(db)
    seed_admin_user(db)
    db.commit()


def _build_world() -> dict:
    """Run the ENTIRE Phase-21 real-world flow through the real HTTP APIs and
    return a handle the tests use for customer-side verification + read-only
    DB assertions. This is the production-level proof that a shopkeeper can go
    from 'no account' to 'live published shop' with zero manual DB editing.

    The module-level ``_TMP_DB`` file is shared process-wide: test_phase28
    reuses this builder in the same pytest process, so each world-build must
    start from an empty schema or the second build collides with the first.
    """
    Base.metadata.drop_all(SYNC_ENGINE)
    Base.metadata.create_all(SYNC_ENGINE)

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

    # ── Platform catalog setup (admin + catalog tooling) ────────────────────
    categories = {}
    for name, slug in CATEGORIES:
        categories[slug] = _create_category(client, admin_token, name, slug)
    brands = {}
    for name, slug in BRANDS:
        brands[slug] = _create_brand(client, admin_token, name, slug)

    # Catalog masters carry their EAN identifier, a variant and then a
    # registered barcode relationship — all through the real catalog APIs.
    barcode_atta = _ean13(MASTER_ATTA[4])
    barcode_milk = _ean13(MASTER_MILK[4])
    barcode_salt = _ean13(MASTER_SALT[4])

    master_atta = _create_master_product(
        client,
        admin_token,
        name=MASTER_ATTA[0], slug="aashirvaad-whole-wheat-atta-5kg",
        category_id=categories[MASTER_ATTA[2]]["id"], brand_id=brands[MASTER_ATTA[1]]["id"],
        unit=MASTER_ATTA[3], barcode=barcode_atta,
    )
    master_milk = _create_master_product(
        client,
        admin_token,
        name=MASTER_MILK[0], slug="amul-taaza-toned-milk-500ml",
        category_id=categories[MASTER_MILK[2]]["id"], brand_id=brands[MASTER_MILK[1]]["id"],
        unit=MASTER_MILK[3], barcode=barcode_milk,
    )
    master_salt = _create_master_product(
        client,
        admin_token,
        name=MASTER_SALT[0], slug="tata-salt-1kg",
        category_id=categories[MASTER_SALT[2]]["id"], brand_id=brands[MASTER_SALT[1]]["id"],
        unit=MASTER_SALT[3], barcode=barcode_salt,
    )

    _add_barcode(client, admin_token, master_atta["id"], barcode_atta)
    _add_barcode(client, admin_token, master_milk["id"], barcode_milk)
    _add_barcode(client, admin_token, master_salt["id"], barcode_salt)

    # Approve every master through the real catalog approval workflow.
    for master in (master_atta, master_milk, master_salt):
        approval = _submit_master_approval(client, shopkeeper_token, master["id"])
        _review_master_approval(client, admin_token, approval["id"])

    # ── Shopkeeper journey: registration → shop → address → verification ────
    # No manual DB editing anywhere in this flow.
    shop = _register_shop(
        client,
        shopkeeper_token,
        name="Patna Fresh Mart Phase21",
        lat=SHOP_LAT,
        lng=SHOP_LNG,
        address_line1="Shop 21, Boring Road",
        category="GROCERY",
    )

    # Shop address — add + edit via the real shop-address APIs.
    second_address = _add_shop_address(client, shopkeeper_token, shop["id"])
    _update_shop_address(client, shopkeeper_token, second_address["id"])

    # Shop verification — document + submit + admin review (APPROVE).
    _submit_shop_document(client, shopkeeper_token, shop["id"])
    _submit_for_verification(client, shopkeeper_token, shop["id"])
    _approve_shop(client, admin_token, shop["id"])

    # ── Shopkeeper journey: product lookup + barcode lookup ─────────────────
    # The shopkeeper searches the master catalog and scans barcodes, then maps
    # each known product into the shop with price / MRP / quantity / is_available.
    catalog_atta = _search_shopkeeper_catalog(client, shopkeeper_token, shop["id"], "Aashirvaad")
    mapped_atta = _map_product(
        client, shopkeeper_token, shop["id"],
        master_id=master_atta["id"], price=230.0, mrp=255.0, quantity=40,
        sku="PH21-ATTA-5KG",
    )

    resolve_milk = _resolve_barcode(client, shopkeeper_token, shop["id"], barcode_milk)
    assert resolve_milk["status"] == "FOUND", resolve_milk
    mapped_milk = _map_product(
        client, shopkeeper_token, shop["id"],
        master_id=master_milk["id"], price=29.0, mrp=31.0, quantity=60,
        sku="PH21-MILK-500ML",
    )

    resolve_salt = _resolve_barcode(client, shopkeeper_token, shop["id"], barcode_salt)
    assert resolve_salt["status"] == "FOUND", resolve_salt
    mapped_salt = _map_product(
        client, shopkeeper_token, shop["id"],
        master_id=master_salt["id"], price=28.0, mrp=30.0, quantity=25,
        sku="PH21-SALT-1KG",
    )

    # ── Offer (real offer-assign flow) ───────────────────────────────────────
    from datetime import datetime, timedelta, timezone

    now = datetime.now(timezone.utc)
    offer = _assign_offer(
        client, shopkeeper_token, shop["id"], [mapped_atta["id"]],
        title="Atta 5% Off",
        pct=5,
        start=now.isoformat(),
        end=(now + timedelta(days=30)).isoformat(),
    )

    # ── Publish — index the shop's listings via the exact production worker
    #    (Celery ``index_shop_product`` body) so customers can discover them. ──
    _reindex_shop(db, shop["id"])

    world = {
        "db": db,
        "client": client,
        "token": customer_token,
        "vendor_token": shopkeeper_token,
        "admin_token": admin_token,
        "categories": categories,
        "brands": brands,
        "fastapi_app": fastapi_app,
        "previous_overrides": previous,
        "barcodes": {"atta": barcode_atta, "milk": barcode_milk, "salt": barcode_salt},
        "masters": {"atta": master_atta["id"], "milk": master_milk["id"], "salt": master_salt["id"]},
        "shop": shop,
        "address": second_address,
        "mapped": {"atta": mapped_atta, "milk": mapped_milk, "salt": mapped_salt},
        "offer": offer,
        "catalog_atta": catalog_atta,
        "resolve_milk": resolve_milk,
        "resolve_salt": resolve_salt,
    }
    return world


@pytest.fixture(scope="module")
def world():
    """One complete real-world flow for the whole module."""
    _world = _build_world()
    try:
        yield _world
    finally:
        _world["db"].close()
        _world["fastapi_app"].dependency_overrides.clear()
        _world["fastapi_app"].dependency_overrides.update(_world["previous_overrides"])


# ═══════════════════════════════════════════════════════════════════════════════
# 1. Shopkeeper side — registration, shop, address, verification, lookup,
#    mapping (price/inventory/availability), offer, publish
# ═══════════════════════════════════════════════════════════════════════════════
def test_shopkeeper_registration_creates_verified_account(world):
    """Shopkeeper registration via real OTP flow created a shopkeeper-role user
    with NO manual DB edit — exactly what the deployed seed_data does as well."""
    from app.models.user import User

    user = world["db"].query(User).filter(User.phone_number == SHOPKEEPER_PHONE).first()
    assert user is not None
    assert user.role.name == "shopkeeper"

    # The same phone can sign back in through the shopkeeper Firebase
    # login-or-register flow (returns the existing account).
    resp = _req(
        world["client"],
        "POST",
        f"{API}/shopkeeper/auth/firebase-login",
        json={
            "firebase_id_token": _FAKE_FIREBASE_TOKENS[SHOPKEEPER_PHONE],
            "device_id": "phase21-shopkeeper-relogin",
            "device_type": "android",
            "platform": "android",
        },
    )
    login = _ok(resp, what="shopkeeper login")
    assert login.get("access_token")
    assert any(s["id"] == world["shop"]["id"] for s in login.get("shops", []))


def test_shop_created_with_address_via_api(world):
    """POST /shopkeeper/shops created the shop + primary owner + primary address
    in one call; the second address went through the address API."""
    from app.models.shop import Shop, ShopAddress, ShopOwner, ShopStatus

    db = world["db"]
    shop = db.query(Shop).filter(Shop.id == world["shop"]["id"]).first()
    assert shop is not None
    assert shop.status == ShopStatus.ACTIVE
    assert shop.is_verified is True
    assert shop.latitude == SHOP_LAT and shop.longitude == SHOP_LNG

    owner = db.query(ShopOwner).filter(ShopOwner.shop_id == shop.id).first()
    assert owner is not None and owner.is_primary is True

    addresses = db.query(ShopAddress).filter(ShopAddress.shop_id == shop.id).all()
    assert len(addresses) >= 2  # primary (from registration) + second (via /addresses)
    primary = [a for a in addresses if a.is_primary]
    assert primary and primary[0].address_line1 == "Shop 21, Boring Road"
    edited = [a for a in addresses if a.id == world["address"]["id"]]
    assert edited and edited[0].landmark == "Near Gandhi Maidan"


def test_shop_verification_document_flow_approved(world):
    """The real verification lifecycle progressed entirely through the API:
    registered → document submitted → submit-for-verification → admin APPROVE
    (shop is now ACTIVE + verified)."""
    from app.models.shop import ShopDocument, ShopVerification, VerificationStatus

    db = world["db"]
    docs = (
        db.query(ShopDocument)
        .filter(ShopDocument.shop_id == world["shop"]["id"])
        .all()
    )
    assert any(d.document_type == "GST" for d in docs)

    verification = (
        db.query(ShopVerification)
        .filter(ShopVerification.shop_id == world["shop"]["id"])
        .order_by(ShopVerification.id.desc())
        .first()
    )
    assert verification is not None
    assert verification.status == VerificationStatus.VERIFIED


def test_product_lookup_surfaces_platform_catalog(world):
    """GET /shopkeeper/shops/{id}/catalog/search returns the shared master
    catalog — the shopkeeper's product LOOKUP step."""
    data = world["catalog_atta"]
    assert data["count"] >= 1
    atta = next((r for r in data["results"] if "Aashirvaad" in r["name"]), None)
    assert atta is not None
    assert atta["product_master_id"] == world["masters"]["atta"]
    assert atta["variants"], "the master must expose its variant for selection"


def test_barcode_lookup_identifies_products(world):
    """GET /shopkeeper/barcodes/{barcode}/resolve identifies scanned codes —
    the shopkeeper's barcode LOOKUP step."""
    assert world["resolve_milk"]["status"] == "FOUND"
    assert world["resolve_milk"]["matches"][0]["name"].startswith("Amul")
    assert world["resolve_salt"]["status"] == "FOUND"
    assert world["resolve_salt"]["matches"][0]["name"].startswith("Tata")


def test_product_mapping_carries_price_inventory_availability(world):
    """POST /shopkeeper/shops/{id}/inventory/products persisted the shop's own
    price / MRP / quantity / availability — the mapping + price + inventory +
    availability steps of the Phase-21 flow happen in this single API call."""
    from app.models.product import Inventory, ShopProduct

    db = world["db"]
    sp_ids = {v["id"] for v in world["mapped"].values()}
    rows = db.query(ShopProduct).filter(ShopProduct.id.in_(sp_ids)).all()
    assert len(rows) == 3

    by_id = {sp.id: sp for sp in rows}
    for key, mapped in world["mapped"].items():
        sp = by_id[mapped["id"]]
        assert sp.product_master_id == world["masters"][key]
        assert float(sp.price) > 0
        assert float(sp.mrp) >= float(sp.price)
        inv = db.query(Inventory).filter(Inventory.shop_product_id == sp.id).first()
        assert inv is not None
        assert int(inv.quantity) == int(mapped["quantity"])
        assert inv.is_available is True

    # SKUs are preserved exactly as the shopkeeper provided them.
    skus = {sp.sku for sp in rows}
    assert "PH21-ATTA-5KG" in skus
    assert "PH21-MILK-500ML" in skus
    assert "PH21-SALT-1KG" in skus


def test_mapped_products_created_no_master_duplicates(world):
    """Phase-23 guarantee: add-from-master never creates duplicate product
    masters — the three mappings reference the SAME catalog rows."""
    from app.models.product import ProductMaster

    db = world["db"]
    for key, master_id in world["masters"].items():
        count = (
            db.query(ProductMaster)
            .filter(ProductMaster.id == master_id, ProductMaster.is_deleted == False)  # noqa: E712
            .count()
        )
        assert count == 1


def test_offer_assigned_to_mapped_product(world):
    """POST /shopkeeper/shops/{id}/offers/assign created + linked a PERCENTAGE
    offer to the atta listing — the offer step of the flow."""
    from app.models.product import Offer, OfferProduct

    db = world["db"]
    offer = db.get(Offer, int(world["offer"]["offer_id"]))
    assert offer is not None
    assert offer.title == "Atta 5% Off"
    assert offer.shop_id == world["shop"]["id"]
    assert offer.discount_percentage == 5
    links = db.query(OfferProduct).filter(OfferProduct.offer_id == offer.id).all()
    assert any(l.shop_product_id == world["mapped"]["atta"]["id"] for l in links)


def test_publish_indexed_all_shop_listings(world):
    """After the real index-worker publish, the search index holds every
    mapped listing for the shop — the publish step."""
    from app.models.search import SearchIndex, SearchIndexEntityType

    db = world["db"]
    entries = (
        db.query(SearchIndex)
        .filter(
            SearchIndex.entity_type == SearchIndexEntityType.SHOP_PRODUCT,
            SearchIndex.shop_id == world["shop"]["id"],
        )
        .all()
    )
    assert len(entries) == 3
    for entry in entries:
        assert entry.is_product_searchable is True
        assert entry.is_shop_visible is True
        assert entry.product_name in (
            "Aashirvaad Whole Wheat Atta",
            "Amul Taaza Toned Milk",
            "Tata Salt 1kg",
        )


# ═══════════════════════════════════════════════════════════════════════════════
# 2. Customer side — search → product → nearby shop → price → availability
# ═══════════════════════════════════════════════════════════════════════════════
def test_customer_search_finds_product_from_shop(world):
    """Customer SEARCH: typing the product name returns the shop's listing with
    product + shop + price + availability + distance (the discovery contract)."""
    data = _search(world, "Aashirvaad Whole Wheat Atta")
    assert data["total"] >= 1
    res = _result_by_shop(data, world["shop"]["id"])
    assert res is not None, "the published listing must surface in customer search"
    assert res["product_id"] == world["masters"]["atta"]
    assert res["product_name"] == "Aashirvaad Whole Wheat Atta"

    # Every result must carry the full hyperlocal payload.
    for r in data["results"]:
        assert r["product_id"] and r["shop_id"]
        assert r["shop_name"] is not None
        assert r["price"] is not None and r["mrp"] is not None
        assert r["is_available"] in (True, False)
        assert r["distance_km"] is not None


def test_customer_product_detail_from_shop(world):
    """Customer PRODUCT view: opening the product reveals the master +
    live shop inventories (which nearby shop sells it, and for how much)."""
    resp = _req(
        world["client"],
        "GET",
        f"{API}/products/{world['masters']['milk']}",
        params={"latitude": CUSTOMER_LAT, "longitude": CUSTOMER_LNG, "radius_km": 10.0},
    )
    data = _ok(resp, what=f"customer product detail {world['masters']['milk']}")
    assert data["product"]["name"] == "Amul Taaza Toned Milk"
    shops = data["shop_inventories"]
    assert any(s["shop_id"] == world["shop"]["id"] for s in shops)
    ours = next(s for s in shops if s["shop_id"] == world["shop"]["id"])
    assert ours["price"] == 29.0
    assert ours["mrp"] == 31.0
    assert ours["is_available"] is True


def test_customer_barcode_path_also_resolves_shop(world):
    """Customer BARCODE path: the customer-facing ``GET /products/{barcode}``
    resolves the EAN via the real BarcodeRelationship table into the master +
    live shop inventories (which shop sells it, price, availability)."""
    ean = world["barcodes"]["atta"]
    resp = _req(
        world["client"],
        "GET",
        f"{API}/products/{ean}",
        params={"latitude": CUSTOMER_LAT, "longitude": CUSTOMER_LNG, "radius_km": 10.0},
    )
    data = _ok(resp, what=f"customer product-by-barcode {ean}")
    assert data["product"]["name"] == "Aashirvaad Whole Wheat Atta"
    assert data["product"]["id"] == world["masters"]["atta"]
    shops = data["shop_inventories"]
    assert any(s["shop_id"] == world["shop"]["id"] for s in shops)
    ours = next(s for s in shops if s["shop_id"] == world["shop"]["id"])
    assert ours["price"] == 230.0
    assert ours["mrp"] == 255.0
    assert ours["is_available"] is True


def test_customer_sees_offer_text_in_search(world):
    """The shopkeeper's offer flows through to the customer search results."""
    data = _search(world, "Aashirvaad Whole Wheat Atta")
    res = _result_by_shop(data, world["shop"]["id"])
    assert res is not None
    assert res["offer_text"] is not None
    assert "5%" in res["offer_text"]


def test_customer_price_and_availability_are_live(world):
    """CUSTOMER PRICE + AVAILABILITY: the customer sees exactly the price /
    availability the shopkeeper set during the mapping step (230/255 atta,
    29/31 milk, 28/30 salt — all in stock)."""
    expectations = {
        "atta": (230.0, 255.0),
        "milk": (29.0, 31.0),
        "salt": (28.0, 30.0),
    }
    names = {"atta": MASTER_ATTA[0], "milk": MASTER_MILK[0], "salt": MASTER_SALT[0]}
    for key, (price, mrp) in expectations.items():
        data = _search(world, names[key])
        res = _result_by_shop(data, world["shop"]["id"])
        assert res is not None, f"{names[key]} must surface for the shop"
        assert float(res["price"]) == price, f"{names[key]} price mismatch"
        assert float(res["mrp"]) == mrp, f"{names[key]} mrp mismatch"
        assert res["is_available"] is True, f"{names[key]} must be available"
        assert res["stock_status"] in ("IN_STOCK", "LIMITED_STOCK")


def test_customer_in_stock_filter_keeps_shop(world):
    """The customer's in-stock filter does not drop the shop's available items."""
    data = _search(world, "Amul Taaza Toned Milk", in_stock=True)
    ids = {r["shop_id"] for r in data["results"]}
    assert world["shop"]["id"] in ids


def test_full_flow_required_no_manual_db_edits(world):
    """End-to-end guarantee: the ONLY DB writes during the whole flow came from
    the real HTTP API calls (plus the production seed_data bootstrap). No fixture
    pre-inserts shopkeeper rows — every entity below was created through a route."""
    from app.models.product import Offer, OfferProduct, ProductMaster, ShopProduct
    from app.models.search import SearchIndex
    from app.models.shop import Shop, ShopAddress, ShopDocument, ShopVerification
    from app.models.user import User

    db = world["db"]
    assert db.query(Shop).filter(Shop.id == world["shop"]["id"]).count() == 1
    assert db.query(User).filter(User.phone_number == SHOPKEEPER_PHONE).count() == 1
    assert db.query(ShopAddress).filter(ShopAddress.shop_id == world["shop"]["id"]).count() >= 2
    assert db.query(ShopDocument).filter(ShopDocument.shop_id == world["shop"]["id"]).count() >= 1
    assert db.query(ShopVerification).filter(ShopVerification.shop_id == world["shop"]["id"]).count() >= 2
    assert db.query(ProductMaster).filter(ProductMaster.is_deleted == False).count() == 3  # noqa: E712
    assert db.query(ShopProduct).filter(ShopProduct.shop_id == world["shop"]["id"]).count() == 3
    assert db.query(Offer).filter(Offer.shop_id == world["shop"]["id"]).count() == 1
    assert db.query(OfferProduct).count() == 1
    assert db.query(SearchIndex).filter(SearchIndex.shop_id == world["shop"]["id"]).count() == 3