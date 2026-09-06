# Phase 21 — Shopkeeper Real-World Flow

This phase proves the **complete shopkeeper journey works end-to-end through the
platform's own APIs** — from a brand-new phone number to a live, published shop
that customers can discover — **with no manual database editing required for any
normal shopkeeper operation**.

## 1. The flow (what is tested)

```
Shopkeeper registration
→ verification (account OTP)
→ shop creation
→ shop address
→ product lookup
→ barcode lookup
→ product mapping
→ price
→ inventory
→ availability
→ offer
→ publish

Then verify customer:
Search
→ product
→ nearby shop
→ price
→ availability
```

### Shopkeeper leg (all real HTTP routes)

| Step | Endpoint |
|---|---|
| Registration | `POST /api/v1/shopkeeper/auth/send-otp` → `/auth/register` |
| Shop creation | `POST /api/v1/shopkeeper/shops` (address embedded) |
| Shop address | `POST /api/v1/shops/my/shops/{id}/addresses` + `PUT /shops/my/shops/addresses/{address_id}` |
| Verification | `POST /shops/my/shops/{id}/documents` → `/submit-verification` → `POST /shops/admin/shops/{id}/review` (APPROVE) |
| Product lookup | `GET /api/v1/shopkeeper/shops/{id}/catalog/search` |
| Barcode lookup | `GET /api/v1/shopkeeper/barcodes/{barcode}/resolve` |
| Product mapping + price + inventory + availability | `POST /api/v1/shopkeeper/shops/{id}/inventory/products` |
| Offer | `POST /api/v1/shopkeeper/shops/{id}/offers/assign` |
| Publish | the search-index worker (Celery `index_shop_product` body) — `app.search.indexer.upsert_shop_product` |

### Customer leg (all real HTTP routes)

| Step | Endpoint |
|---|---|
| Search | `GET /api/v1/search/v2/products` |
| Product | `GET /api/v1/products/{id}` (master + live shop inventories) |
| Nearby shop | `GET /api/v1/search/v2/nearby-shops` |
| Price | result `price` + `mrp` |
| Availability | result `is_available` + `stock_status` |

## 2. Platform catalog (built through platform tooling, not the shopkeeper)

The shared product-master catalog is created with the same tooling operators
use — never by random manual inserts:

- `POST /api/v1/admin/categories` and `/admin/brands`
- `POST /api/v1/catalog/products` (master + EAN identifier + variant in one payload)
- `POST /api/v1/catalog/products/{id}/barcodes`
- `POST /api/v1/catalog/approvals` → `/approvals/{id}/review` (APPROVED)

The shopkeeper then **searches / scans** the catalog and **maps** products into
their shop with shop-level price, MRP, quantity and availability.

## 3. Bug fixed during this phase

`POST /api/v1/catalog/products` (and `PUT /api/v1/catalog/products/{id}`) were
**completely broken**: `catalog_service.create_product` passed
`created_by=created_by` to the `ProductMaster(...)` constructor, but the
`product_masters` table (migration `0002` + ORM model) has **no**
`created_by`/`updated_by` columns. Every catalog creation returned
`400 'created_by' is an invalid keyword argument for ProductMaster`.

The fix removes the two unsupported kwargs (`created_by` from the constructor,
`product.updated_by = updated_by` from `update_product`). The service signatures
are unchanged; the audit trail for catalog edits continues to be recorded by the
admin audit-log pipeline (`admin_service.record_audit_log`). This unblocks the
platform's own catalog tooling so the Phase-21 flow needs zero manual DB edits.

## 4. Infrastructure

The suite runs on a shared SQLite **file** (no PostgreSQL/PostGIS required):

- a **synchronous** engine for the sync route graph (`/auth`, `/shopkeeper`,
  `/search`, `/shops`, `/admin`, `/products`), and
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

## 5. How to run

```bash
cd Backend
python -m pytest tests/test_phase21_shopkeeper_realworld_flow.py -v
```

Result: **16 passed** — the complete shopkeeper flow + the customer-side
verification (search / product / nearby shop / price / availability), plus the
"no manual DB edits" guarantee test.

Regression: `test_phase20_realworld_testdata` + `test_search_geo` +
`test_e2e_phase31` + `test_product_catalog` = **89 passed**.