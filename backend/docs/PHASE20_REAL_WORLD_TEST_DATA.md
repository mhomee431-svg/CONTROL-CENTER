# Phase 20 — Real-World Test Data

This phase creates a **controlled, production-like test dataset** through the
platform's own APIs / admin tools / import tooling — **no random manual inserts
into production**. It then proves the live mutation → discovery loops a customer
actually experiences.

## 1. How the dataset is created (all via real HTTPS/HTTP tooling)

| Entity | Tool |
|---|---|
| Customer account | `POST /api/v1/auth/send-otp` → `/auth/register` (real OTP flow) |
| Shopkeeper account | `POST /api/v1/shopkeeper/auth/send-otp` → `/auth/register` |
| Admin account | `POST /api/v1/auth/verify-otp` (dev admin from `seed_data`) |
| Verified shops | `POST /api/v1/shopkeeper/shops` + `POST /shops/admin/shops/{id}/review` (APPROVE) |
| Categories / Brands | `POST /api/v1/admin/categories`, `/api/v1/admin/brands` |
| Master products | `POST /api/v1/shopkeeper/shops/{id}/products` (publish) |
| Variants | `POST /api/v1/catalog/products/{id}/variants` |
| Identifiers / barcodes | `POST /api/v1/catalog/products/{id}/identifiers`, `/barcodes` |
| Shop-product mapping | `POST /api/v1/shopkeeper/shops/{id}/inventory/products` (add-from-master) |
| Inventory / prices | created by the listing APIs (price + MRP asserted) |
| Offers | `POST /api/v1/shopkeeper/shops/{id}/offers/assign` |
| Locations | shop registration lat/lng + `PUT /shops/my/shops/{id}` |

Barcodes are generated with the **GS1 EAN-13 check-digit** algorithm so the real
barcode-intake validator accepts them.

## 2. The four mutation → discovery tests

1. **Shopkeeper updates inventory**
   → `PATCH /shopkeeper/shops/{id}/products/{sp}` (quantity 40 → 3)
   → DB `inventory` row changes (`IN_STOCK` → `LOW_STOCK`)
   → customer `GET /search/v2/products` now reports `LIMITED_STOCK`.
2. **Price update**
   → `PATCH` price 230 → 199
   → DB row updates + a `PriceHistory` record is written
   → customer search returns the new price (199) and MRP.
3. **Inventory becomes unavailable**
   → `PATCH` quantity → 0
   → `is_available` flips false / `OUT_OF_STOCK`
   → customer `in_stock=true` search no longer returns it; unfiltered search
     marks it unavailable.
4. **Shop changes location**
   → `PUT /shops/my/shops/{id}` lat/lng to Gaya (~90 km away)
   → shop's PostGIS point updates
   → customer `GET /search/v2/nearby-shops` drops shop_a but keeps shop_b;
     product search within radius also stops returning the relocated shop.

After every mutation the **real search indexer** (`app.search.indexer.upsert_shop_product`,
the exact body of the Celery `index_shop_product` worker) is run so discovery
reflects the change through the production search path.

## 3. Infrastructure

The suite runs on a shared SQLite *file* (no PostgreSQL/PostGIS required):

- a **synchronous** engine for the sync route graph (`/auth`, `/shopkeeper`,
  `/search`, `/shops`, `/admin`), and
- a **`sqlite+aiosqlite`** engine for the async catalog routes (`/catalog`).

Both point at the same database file. The PostGIS / `pg_trgm` SQL functions the
production search emits (`ST_GeogFromText`, `ST_Distance`, `ST_DWithin`,
`similarity`) are registered as faithful Python shims (haversine geodesics +
pg_trgm trigram similarity). The Geography columns are made SQLite-portable via
`tests.geo_compat.strip_geo_columns`.

Two small test-only compatibility shims account for SQLite's lack of native
PostGIS/`timestamptz` support (both leave the real service logic untouched and
are no-ops on PostgreSQL):

- `shop_service._get_wkt_point` emits the same `POINT(lng lat)` WKT text the real
  code serialises, instead of a `WKTElement` object SQLite cannot bind.
- `fast2sms_otp_service._latest_record` re-attaches UTC to OTP-row datetimes that
  SQLite reads back as naive (the production comparison uses aware UTC datetimes).

## 4. How to run

```bash
cd backend
python -m pytest tests/test_phase20_realworld_testdata.py -v
```

Result: **8 passed** (dataset creation + 4 mutation→discovery loops + search /
barcode / offer-text assertions). Regression: `test_search_geo` + `test_e2e_phase31`
= **57 passed**.
