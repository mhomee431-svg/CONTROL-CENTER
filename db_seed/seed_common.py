#!/usr/bin/env python
"""seed_common.py -- shared helpers for the area-wise dummy-data seed scripts.

Everything both ``seed_data.py`` (insert) and ``cleanup_data.py`` (rollback) need:

* Database URL resolution (--url / $DATABASE_URL / Backend ``.env`` files)
* A synchronous SQLAlchemy engine + Session (psycopg3)
* A global ID allocator: EVERY dummy row gets an id above ``DUMMY_ID_BASE`` and
  each table receives one contiguous block, so cleanup can safely delete exactly
  the seeded rows (``WHERE id BETWEEN start AND start+count-1``) and can never
  touch existing real data.
"""
from __future__ import annotations

import os
import random
import re
import sys
import urllib.parse
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Iterable

# -- Paths ----------------------------------------------------------------
PROJECT_ROOT = Path(__file__).resolve().parents[1]          # hyperlocal_app/
BACKEND_DIR = PROJECT_ROOT / "backend"
SEED_DIR = Path(__file__).resolve().parent

# Allow `from app.models...` imports (the same ORM models the API uses)
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

# -- Global constants -----------------------------------------------------
DUMMY_ID_BASE = 100_000_000        # reserved ID space far above real AUTOINCREMENT ids
MANIFEST_KEY = "dummy_seed_manifest_v1"  # SystemSetting key used as rollback ledger
MANIFEST_TABLE = "system_settings"
SEED_TAG = "[SEED-DUMMY]"          # text marker used inside descriptions/logs

# -- 10 Hyperlocal areas (Mumbai region) ----------------------------------
AREAS = [
    # slug, display name, latitude, longitude, pincode, city
    ("andheri-west", "Andheri West", 19.1364, 72.8306, "400058", "Mumbai"),
    ("bandra-west", "Bandra West", 19.0543, 72.8256, "400050", "Mumbai"),
    ("dadar", "Dadar", 19.0178, 72.8478, "400014", "Mumbai"),
    ("powai", "Powai", 19.1176, 72.9044, "400076", "Mumbai"),
    ("juhu", "Juhu", 19.1075, 72.8260, "400049", "Mumbai"),
    ("chembur", "Chembur", 19.0550, 72.8990, "400071", "Mumbai"),
    ("borivali-west", "Borivali West", 19.2307, 72.8568, "400092", "Mumbai"),
    ("malad-west", "Malad West", 19.1860, 72.8488, "400064", "Mumbai"),
    ("thane-west", "Thane West", 19.2183, 72.9781, "400601", "Thane"),
    ("vashi-nm", "Vashi (Navi Mumbai)", 19.0798, 72.9977, "400703", "Navi Mumbai"),
]

FIRST_NAMES = [
    "Aarav", "Vivaan", "Aditya", "Vihaan", "Arjun", "Sai", "Rahul", "Rohan",
    "Ramesh", "Suresh", "Mahesh", "Dinesh", "Amit", "Ravi", "Vikram", "Sanjay",
    "Priya", "Anita", "Sunita", "Pooja", "Neha", "Kavita", "Meera", "Lakshmi",
    "Farhan", "Imran", "Salim", "Sameer", "Joseph", "Anthony", "Xavier",
]
LAST_NAMES = [
    "Sharma", "Verma", "Gupta", "Mehta", "Iyer", "Rao", "Reddy", "Nair",
    "Patel", "Shah", "Desai", "Joshi", "Kulkarni", "Mishra", "Singh", "Kaur",
    "Khan", "Ansari", "Shaikh", "Souza", "Fernandes", "Dias", "Chopra",
    "Malhotra", "Kapoor", "Bhatt", "Trivedi", "Pandey",
]
FAMILY_NAMES = [
    "Sharma", "Verma", "Gupta", "Mehta", "Iyer", "Patel", "Shah", "Desai",
    "Joshi", "Kulkarni", "Mishra", "Singh", "Khan", "Souza", "Fernandes",
    "Chopra", "Malhotra", "Kapoor", "Bhatt", "Trivedi", "Pandey", "Reddy",
    "Rao", "Nair", "Dias", "Lobo", "Agrawal",
]

SHOP_SUFFIX = {
    "GROCERY": ["General Store", "Kirana Bhandar", "SuperMart", "Provision Store", "Wholesale Mart"],
    "ELECTRONICS": ["Electronics Hub", "Mobile Care", "Digital Zone", "Gadget House"],
    "PHARMACY": ["Medico & Chemists", "Pharmacy Store", "Medicine Centre"],
    "HARDWARE": ["Hardware & Paints", "Tool Mart", "Electrical Hardware"],
    "FASHION": ["Fashion Studio", "Garment House", "Fabrics & Sarees"],
    "RESTAURANT": ["Biryani House", "Food Junction", "Veg Restaurant", "Tiffin Centre"],
    "BAKERY": ["Bakery & Confectionery", "Fresh Bread House", "Cake Studio"],
    "DAIRY": ["Dairy & Milk Shop", "Fresh Milk Centre"],
    "MEAT": ["Fresh Meat & Fish", "Chicken Shop", "Mutton Stall"],
    "VEGETABLES": ["Fresh Veggies & Fruits", "Sabzi Mandi", "Organic Fresh"],
    "STATIONERY": ["Book & Stationery", "School Supplies"],
    "TOYS": ["Toy & Kids Zone"],
    "BEAUTY": ["Beauty & Personal Care", "Salon Store"],
    "OTHER": ["Multi-Purpose Store", "Discount Mart", "Super Bazaar"],
}

# 31-position shop-category mix (deterministic variety per area)
SHOP_CATEGORY_MIX = (
    ["GROCERY"] * 6 + ["VEGETABLES"] * 3 + ["DAIRY"] * 2 + ["PHARMACY"] * 2
    + ["ELECTRONICS"] * 2 + ["HARDWARE"] * 2 + ["STATIONERY"] * 2 + ["BAKERY"] * 2
    + ["FASHION", "MEAT", "BEAUTY", "RESTAURANT", "TOYS", "OTHER"]
)
def _now() -> datetime:
    return datetime.now(timezone.utc)


def _days_ago(n: int) -> datetime:
    return _now() - timedelta(days=n)


def slugify(text: str) -> str:
    text = text.lower().strip()
    text = re.sub(r"[^a-z0-9]+", "-", text)
    return text.strip("-")


# -- DB URL resolution ----------------------------------------------------
def normalize_url(url: str) -> str:
    """Convert any app-flavoured URL to a sync psycopg URL usable by SQLAlchemy."""
    url = url.strip()
    for prefix in ("postgresql+asyncpg://", "postgres+asyncpg://"):
        if url.startswith(prefix):
            url = "postgresql+psycopg://" + url[len(prefix):]
            break
    if url.startswith(("postgres://", "postgresql://")):
        url = "postgresql+psycopg://" + url.split("://", 1)[1]

    parts = urllib.parse.urlsplit(url)
    query = dict(urllib.parse.parse_qsl(parts.query))
    if "ssl" in query and query["ssl"].lower() in ("require", "true", "1"):
        query.pop("ssl")
        query["sslmode"] = "require"
    return urllib.parse.urlunsplit(
        (parts.scheme, parts.netloc, parts.path, urllib.parse.urlencode(query), parts.fragment)
    )


def resolve_db_url(explicit: str | None) -> str | None:
    """Credential resolution order:
    1. --url flag
    2. $DATABASE_URL / $DATABASE_URL_SYNC
    3. backend/.env, backend/.env.free, db_seed/.env, backend/.env.staging
    """
    candidates = [
        PROJECT_ROOT / "backend/.env",
        PROJECT_ROOT / "backend/.env.free",
        SEED_DIR / ".env",
        PROJECT_ROOT / "backend/.env.staging",
    ]
    try:
        from dotenv import load_dotenv
        for p in candidates:
            if p.exists():
                load_dotenv(p, override=False)
    except ImportError:
        pass

    raw = (
        explicit
        or os.environ.get("DATABASE_URL")
        or os.environ.get("DATABASE_URL_SYNC")
    )
    if not raw:
        return None
    return normalize_url(raw)


def make_engine(url: str):
    from sqlalchemy.pool import NullPool
    return create_engine(url, poolclass=NullPool, pool_pre_ping=True, echo=False)


def make_session(engine):
    return sessionmaker(bind=engine, expire_on_commit=False)()


def mask_url(url: str) -> str:
    """Print a URL with the password hidden (safe for logs)."""
    parts = urllib.parse.urlsplit(url)
    host = parts.hostname or ""
    port = f":{parts.port}" if parts.port else ""
    return f"{parts.scheme}://****:****@{host}{port}{parts.path}"


# -- ID allocator (contiguous, reserved, deterministic) -------------------
class Allocator:
    def __init__(self, base: int = DUMMY_ID_BASE):
        self.base = base
        self.next_id = base
        self.blocks: dict[str, dict] = {}

    def allocate(self, table: str, count: int) -> tuple[int, int]:
        start, end = self.next_id, self.next_id + int(count)
        self.next_id = end
        self.blocks[table] = {"start": start, "count": int(count)}
        return start, int(count)

    def block(self, table: str) -> tuple[int, int] | None:
        b = self.blocks.get(table)
        return (b["start"], b["count"]) if b else None

    def ids(self, table: str) -> Iterable[int]:
        b = self.blocks[table]
        return range(b["start"], b["start"] + b["count"])


# -- Deterministic PRNG (same values on every run) ------------------------
_RNG = random.Random(20260901)


def _jitter(base: float, span: float = 0.008) -> float:
    return round(base + _RNG.uniform(-span, span), 6)


def make_point(lon: float, lat: float):
    from geoalchemy2 import WKTElement
    return WKTElement(f"POINT({lon:.6f} {lat:.6f})", srid=4326)


# -- Deterministic plan structures ----------------------------------------
SHOPS_PER_AREA = 25


def build_area_shops() -> list[dict]:
    """Deterministic list of shop specs across the 10 areas (25 shops each)."""
    shops: list[dict] = []
    idx = 0
    for area_idx, area in enumerate(AREAS):
        area_slug, area_name, lat, lon, pincode, city = area
        for s in range(SHOPS_PER_AREA):
            category = SHOP_CATEGORY_MIX[(area_idx * 31 + s * 7) % len(SHOP_CATEGORY_MIX)]
            family = FAMILY_NAMES[(area_idx * 29 + s * 11) % len(FAMILY_NAMES)]
            suffix = SHOP_SUFFIX[category][(area_idx + s * 3) % len(SHOP_SUFFIX[category])]
            shops.append({
                "idx": idx,
                "area_idx": area_idx,
                "area_slug": area_slug,
                "area_name": area_name,
                "city": city,
                "pincode": pincode,
                "lat": _jitter(lat),
                "lon": _jitter(lon),
                "slug": f"dummy-shop-{area_slug}-{s:03d}",
                "name": f"{family} {suffix}",
                "category": category,
                "num_listings": 30 + ((area_idx * 3 + s * 7) % 31),   # 30..60 per shop
            })
            idx += 1
    return shops


def count_shop_products(shops: list[dict]) -> int:
    return sum(sh["num_listings"] for sh in shops)