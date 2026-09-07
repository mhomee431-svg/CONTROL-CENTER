# Phase 4 — Free Cloud PostgreSQL + PostGIS (Neon / Supabase)

**Goal:** a production-ready, **free-tier** managed PostgreSQL with PostGIS for
the Hyperlocal Customer API — `$0/month`, no RDS, no EC2 — with the approved
migration chain applied **automatically and idempotently**, the schema verified
against the approved architecture, PostGIS spatial queries validated, and real
sample hyperlocal data seeded through the project's own ORM models.

> The RDS-based design lives in [`PHASE4_RDS_POSTGRESQL_POSTGIS.md`](
> PHASE4_RDS_POSTGRESQL_POSTGIS.md). This runbook is the **$0 cloud** variant.

---

## 1. Design decisions (aligned to the approved architecture)

- **The migration chain is the source of truth** — `backend/alembic/versions/0001…0013`.
  We **never recreate the database** and **never hand-edit schema**. If
  migrations already exist (`alembic_version` present), `alembic upgrade head`
  simply applies the delta. Provisioning never drops a database.
- **PostGIS is enabled by migration `0002`** (`CREATE EXTENSION IF NOT EXISTS
  postgis`) and `pg_trgm` by `0006` — both run on the cloud DB exactly as on
  RDS. `app/database/session.enable_postgis()` is a startup backstop.
- **Geography columns** (`PostGIS Geography POINT, srid=4326`): `shops.location`,
  `customer_addresses.location`, `search_indexes.location` (+ GiST index).
- **SSL is always on.** Neon/Supabase require TLS. Two query styles exist:
  - asyncpg (app + Alembic): `?ssl=require`
  - psycopg (verifier / sync jobs): `?sslmode=require`
  All tooling converts between the two (see `scripts/provision_free_db.py`,
  `scripts/migrate_free_db.py`, `scripts/verify_rds.py`).

## 2. Provisioning (`scripts/provision_free_db.py`)

Neon (serverless PG; free = 0.5 GB storage, scale-to-zero compute):

```powershell
cd backend
python scripts/provision_free_db.py neon --api-key $env:NEON_API_KEY `
  --region aws-ap-south-1 --name hyperlocal-free --db hyperlocal
```

Supabase (free plan; 500 MB + always-on Postgres 15):

```powershell
python scripts/provision_free_db.py supabase --access-token $env:SUPABASE_ACCESS_TOKEN `
  --region ap-south-1 --name hyperlocal-free
```

Adopt an existing DB (already created in a dashboard / on RDS):

```powershell
python scripts/provision_free_db.py import `
  --url "postgresql+asyncpg://user:pass@host:5432/hyperlocal?ssl=require"
```

Idempotent behaviour:

| Action | Repeated run |
|---|---|
| Project with the same `--name` | **reused** (found by name via provider API) |
| Database `--db` | **reused** if already present |
| `backend/.env.free` | rewritten with fresh `DATABASE_URL` / `DATABASE_URL_SYNC` |
| Anything under the database | never dropped / recreated |

Outputs: `backend/.env.free` (git-ignored, real credentials)
+ `backend/.free_cloud_db.json` (git-ignored provider metadata).
## 3. Migration workflow (`scripts/migrate_free_db.py`)

```powershell
python scripts/migrate_free_db.py --url $env:DATABASE_URL   # explicit
python scripts/migrate_free_db.py                            # reads .env.free
```

1. Resolves the **async** URL (`--url` → `$DATABASE_URL` → `backend/.env.free`).
2. Runs `alembic upgrade head` in a subprocess with `DATABASE_URL` injected
   (env var wins over `.env` / `.env.<profile>` in pydantic). Idempotent —
   a partially-migrated DB resumes from its current revision.
3. Runs `scripts/verify_rds.py` against the **sync** URL (sslmode=require) and
   exits non-zero if the architecture no longer matches.

Transaction boundaries are preserved exactly as authored: each Alembic revision
is a single transaction; the ORM seeder uses one commit per logical section.

## 4. Verification (`scripts/verify_rds.py`)

```powershell
cd backend
python scripts/verify_rds.py   # reads $DATABASE_URL / --url (sync or async)
```

Checks every Phase-4 requirement **live**:

| # | Check |
|---|---|
| 1 | Connection (`SELECT 1`) |
| 2 | PostGIS installed + `PostGIS_Version()` |
| 3 | Alembic at HEAD (`0013`) — no drift |
| 4 | **Every approved table** in the `public` schema |
| 5 | PK / FK / unique / check / index integrity surface |
| 6 | Geography columns typed `geography` (shops, customer_addresses, search_indexes) |
## 5. Entities verified (approved architecture ↔ migrations 0001–0013)

| Approved entity | Backing table(s) | Notes verified |
|---|---|---|
| **users / roles** | `users`, `roles`, `permissions`, `role_permissions` | RBAC FKs, unique `name`, `user_status` enum, soft-delete `is_deleted`/`deleted_at`, timestamps |
| **customer_profiles** | `customers` | In this codebase the profile table is named **`customers`** |
| **customer_addresses** | `customer_addresses` | FK → `users`/`customers`, **PostGIS Geography POINT**, soft delete |
| **shops / owners** | `shops`, `shop_owners`, `shop_managers`, `shop_addresses`, `shop_hours`, `shop_holidays`, `shop_documents`, `shop_verifications` | `shops.location` Geography POINT + GiST, `rating 0–5`/`review_count>=0` CHECK, `uq_shop_owner_shop_user` unique, cascades |
| **products / categories / brands** | `product_masters`, `product_variants`, `product_images`, `product_attributes`, `product_attribute_values`, `product_identifiers`, `barcode_relationships`, `categories`, `brands` | `identifier_type` enum, `uq_product_identifier_type_value`, `slug`/`name` unique, timestamps + soft delete |
| **shop_products** | `shop_products` | FK → shops/product_masters/variants, `shop_product_status`/`stock_status`/`inventory_source` enums, price/mrp NUMERIC, CHECKs |
| **inventory / movements / adjustments** | `inventory`, `inventory_movements`, `inventory_adjustments`, `inventory_import_jobs`, `inventory_import_rows` | FK `inventory→shop_products`, quantity non-negative CHECKs, source enum, audit timestamps |
| **shop_product_prices** | `price_history` | In this codebase price history table is named **`price_history`** (old/new price **and** MRP, `change_source`, `effective_from/to`) |
| **offers** | `offers`, `offer_products`, `offer_conditions` | `offer_type`/`offer_status` enums, `end_date > start_date` CHECK, `uq_offer_product_offer_shop_product` |
| **search_history / analytics** | `search_history`, `search_events`, `popular_searches`, `barcode_scans`, `search_indexes`, `search_index_sync_runs` | GIN `search_vector`, GiST location index, composite filter indexes |
| **favorites** | `saved_products`, `saved_shops` | In this codebase favorites are **`saved_products`/`saved_shops`** with `uq_*` (user, product/shop) |
| **notifications** | `notifications`, `notification_preferences`, `notification_deliveries`, `device_tokens` | `delivery_status`, dedupe key, `ix_notifications_user_read`, delivery attempts |
| **leads / interactions** | `user_interactions` | immutable `CALL_VIEW|MESSAGE|RATING`, `rating 1–5` CHECK |
| **OTP auth** | `otps` | 5-minute expiry, salted digest, indexed phone/expiry |
| **pos / admin / analytics / billing / audit** | `pos_*`, `admin_actions`, `admin_notes`, `product_approvals`, `reports`, `complaints`, `audit_logs`, `analytics_*`, `system_*`, `subscription_*`, `payments`, `payment_events` | status enums, tamper-evident `record_hash` chain on audit_logs |
| 7 | GiST spatial index on `search_indexes.location` |
| 8 | Real spatial queries: `ST_Distance`, `ST_DWithin`@5km, `ST_Within` + a **rolled-back** sample round-trip |

`EXPECTED_TABLES` now also covers the Phase-4-era additions `otps`
(Fast2SMS OTP records) and `user_interactions` (leads) from migrations 0012/0013.
## 6. Sample hyperlocal data (`scripts/seed_free_data.py`)

Seeds Mumbai-area data through the **same ORM models the API uses** (geoalchemy2
`WKTElement` for geography, native enum members, resolved FKs):

- RBAC: 4 roles, 16 permissions + link rows.
- Users: admin / shop-owner / customer / Google-OAuth user + profiles,
  Bandra address (Geography POINT), notification prefs, FCM device token.
- Catalog: 4 categories, 6 brands, 6 product_masters (+ variants, EAN
  identifiers, images).
- Shops: 5 verified/pending shops across Andheri/Juhu/Bandra/Dadar/Powai with
  owners, addresses, verifications.
- Listings: 9 `shop_products` → `inventory` (stock statuses incl. OUT_OF_STOCK),
  `inventory_movements`, `price_history`.
- Offers, search history/events/popular + `search_indexes` with geography,
  favourites (`saved_products`/`saved_shops`), notifications, `audit_logs`,
  `user_interactions` (rating/call_view), `otps`.

Idempotent (every row guarded by natural keys; `--reset` deletes **only** rows
this seeder owns, by exact keys — never the whole table).

```powershell
python scripts/seed_free_data.py --url $env:DATABASE_URL
python scripts/seed_free_data.py --reset   # clean reseed for development
```

## 7. One-command workflow

```powershell
# repo root
powershell -ExecutionPolicy Bypass -File scripts/dev/free_db.ps1 `
  -Provider neon -ApiKey "$env:NEON_API_KEY" -Region aws-ap-south-1
# provision → alembic upgrade head → verify_rds → seed (all green or exit ≠ 0)
```

Already provisioned? `-MigrateOnly`. Already seeded? `-NoSeed`.

## 8. Security posture

- Real credentials live **only** in git-ignored `backend/.env.free`; the state
  file and env template contain no secrets; APIs never print passwords.
- SSL required on every connection (`ssl=require`/`sslmode=require`).
- The seeder never deletes other data (`--reset` is scoped by natural keys).
- Neon/Supabase free tiers: choose **Mumbai (`aws-ap-south-1`)** to keep reads
  fast for the target market; Neon supports PG 14–18 (`pg_version 16` matches
  RDS), Supabase free ships PG 15.

## 9. Teardown (full stop — no auto-spend)

```powershell
# Neon
curl -X DELETE https://console.neon.tech/api/v2/projects/<project_id> `
  -H "Authorization: Bearer $env:NEON_API_KEY"
# Supabase: Dashboard → Project → Settings → Danger zone → Delete project
# then remove the local artifacts:
Remove-Item backend/.env.free, backend/.free_cloud_db.json
```

Both providers have **no upfront cost**; Neon stops charging compute at 5 min
idle (free tier scale-to-zero) and Supabase free is flat $0.