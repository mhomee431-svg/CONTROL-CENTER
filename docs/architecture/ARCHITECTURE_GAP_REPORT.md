# Architecture Gap Report — Hyperlocal Customer App

**Date:** 2026-09-01
**Baseline:** Master Project Specification (`masterPrompt.txt`) + current repository state
(HEAD `e370862`, plus uncommitted in-progress work: migration `0014`, new models,
`DATABASE SCHEMA DESIGN.txt`).

**Method (per Master Spec §60):** inspect → understand → compare → identify
(Existing / Missing / Duplicate / Incorrect / Incomplete / Deprecated) → propose changes.



## 1. Headline verdict

The repository already implements the large majority of the Master Specification’s
database + backend surface (19 ORM modules, 15-entity migration chain, 21 routers,
customer & shopkeeper Flutter apps, Terraform/AWS topology). The current in-progress
work correctly completes their identity/customer/location/index surface (migration `0014`).

One substantive **domain gap** versus the Master Spec remains: **Transport +
Personal Transport Booking (§28-§29)**, still designed [P] in `DATABASE
SCHEMA DESIGN.txt`. **Restaurant discovery (§27)** is now **authored**:
- models `app/models/restaurant.py`; migration `0015_restaurant_discovery.py`;
- DB-free tests `tests/test_phase15_restaurant_schema.py`; verifier + HEAD-test
  bumps (`test_phase4_rds.py`, `scripts/verify_rds.py`); all uncommitted.

## 2. Existing (aligned with spec)

- **Product Master / Catalog architecture** — `product_masters`, variants, identifiers,
  barcode_relationships, attributes, images; shop-specific `shop_products` +
  `inventory` + `price_history` + `offers` correctly separates identity from price/stock.

- **Inventory pathway** — one canonical inventory model fed by MANUAL / BARCODE /
  EXCEL (`inventory_import_jobs`) / POS (`pos_integrations`, sync jobs, mappings).
- **Shops/Business + verification** — shops, owners, managers, hours, holidays,
  documents, verifications with PENDING-VERIFIED lifecycle. ✔
- **Search + geo** — `search_indexes` (GIN trgm + GiST geography), PostGIS POINT
  columns on shops/customer_addresses; service areas (POLYGON) in 0014. ✔
- **Subscriptions+Payments** — plans (admin-configurable price), subscriptions,
  payments, webhook idempotency ledger. ✔ (Payment *provider* is mock — see §5).)
- **Auth/RBAC** — OTP+JWT+refresh rotation+sessions+blacklist+roles/permissions
   (+ user_roles M2M in 0014). ✔
- **Notifications** — typed notifications, preferences, device tokens, per-device
  deliveries. ✔ (FCM dependency gap — see §5.)
- **Analytics/Audit** — unified `analytics_events` stream + daily aggregates + views/
  clicks/metrics/interactions + tamper-evident hashed `audit_logs`. ✔
- **Admin API surface** — dashboard, users, shops, products, inventory, categories,
  brands, offers, subscriptions, payments, reports, analytics, complaints, flags, audit. ✔

## 3. Missing (must-add; designs now in `DATABASE SCHEMA DESIGN.txt`)

| # | Domain | Master Spec | Proposed entities |
|---|--------|-----------|------------------|
| M1 | Restaurant discovery | §27 (Rule 4) | `restaurants` (1:1 with shops), `restaurant_menu_categories`, `restaurant_menu_items` — discovery-only; no delivery. **Authored `[W]` in `0015`** — models + migration + API layer (routes/service/schemas) |
| M2 | Transport & Personal Transport Booking | §28-§29 (Rules 5-6) | `transport_providers`, `vehicles`, `vehicle_documents`, `transport_services`, `vehicle_availability`, `transport_quotes`, `transport_bookings`, `booking_status_history`, `trip_details` — **Authored in `0016`** with full API layer |
| M3 | Reviews / ratings display content | §§19-20, 49 | `reviews` — moderated, verified-customer; supersedes raw `user_interactions.rating` for display — **Authored in `0017`** with API layer |
| M4 | Pharmacy/healthcare compliance fields | §36 | `product_masters` + `prescription_required`, `regulatory_class`, `requires_license_type`, `is_restricted`, `compliance_notes` (Rx = discovery-only) — **Authored in `0017`** |
| M5 | Shopkeeper analytics "customers' discovery activity" visibility | §§5, 32 | thin materialisation/query layer over `analytics_events`; no new table strictly required |

## 4. Duplicate / redundant (proposed cleanup)

| # | Item | Notes |
|---|------|-------|
| D1 | `saved_products` + `saved_shops` vs new `customer_favorites` | Both kept now (API contract needs saved_*); consider favourite unification later; keep one authoritative concept per spec §24 |
| D2 | `user.role_id` + `user_roles` M2M | Both exist; clarify precedence (M2M is the general RBAC path; `role_id` is a denormalised default role) |
| D3 | `search_history` vs `search_events` vs `popular_searches` | Three overlapping query logs; keep `search_events` as analytics truth, `search_history` for customer UI, `popular_searches` for suggestions — document the ownership boundary |
| D4 | `MockProductRepository` still present (`repositories/product_repository.py`) | get_product_repository() returns mock but live routes bypass it — prune |
| D5 | `dispatch_email` / `dispatch_sms` Celery stubs vs real services | Two layers not connected — wire or delete |
| D6 | `shops.category` legacy enum (GROCERY/BAKERY/DAIRY/MEAT/VEGETABLES) | Conflicts with Rule 13 policy; keep values for compat but enforce taxonomy at `categories` level; plan enum cleanup |
| D7 | `get_redis()` vs `Cache` wrapper | Prefer one accessor |

## 5. Incorrect / incomplete (from PRODUCTION_READINESS_REPORT, still valid)

| Severity | Item |
|----------|------|
| CRITICAL | Real secrets were once committed to git history (`backend/.env*`, `apps/customer_app/.env`); now untracked — rotate/purge (B1) |
| CRITICAL | `firebase-admin` missing from `backend/requirements.txt` while `push_service.py` imports it — FCM push breaks (B2) |
| HIGH | Payments are mock-only (`MockPaymentProvider`) — no production gateway (B3) |
| HIGH | OTP store in-memory + rate-limit `memory://` — breaks multi-instance auth/limits (B4/B7) |
| HIGH | CI swallows test failures (`\|\| true`) and migrations not gated on deploy (B5/B6) |
| MED | Terraform S3 backend commented out; state is local (B4) |
| MED | `CORS_ORIGINS` wildcard + `allow_credentials` (verify ECS sets explicit origins) |
| MED | `MockPOSProvider` / mock SMS/email/push providers — fine for dev, must be gated off in prod |
| LOW | Admin sub-role permissions (`require_admin_permission`) not uniformly applied across route modules |
| LOW | Customer app `apiBaseUrl` empty — selects `MockAuthRepository`; safe only because CI injects; add fail-fast |

## 6. Missing infrastructure/testing niceties (accepted risk or backlog)

- Dedicated search cluster (ES/OpenSearch/Meilisearch) — Postgres-only acceptable at launch (§§9, 46 allow).
- APM / crash reporter (Sentry/Crashlytics)— documented accepted risk.
- Admin web dashboard — API headless exists; no admin UI in repo (future.)
- Server-side image optimisation (CDN transforms offset).
- Contract tests Flutter ↔ frozen `API_CONTRACT.md`; real-provider smoke tests.



## 7. Proposed change backlog (ordered per Master Spec development order)

1. **Land migration `0014`** — commit the current in-progress schema-completion work
     (user_roles, password_resets, auth_sessions/token_blacklist, customer_favorites,
      customer_recent_products, service_areas, shop_addresses.location, indexes) after
      validating the migration chain against a fresh PostGIS database.

2. **Restaurant domain (`0015`)** - *AUTHORED (2026-09-05)*: models + migration + tests + full API layer:
     `app/models/restaurant.py`, `alembic/versions/0015_restaurant_discovery.py`,
     `app/api/routes/restaurant.py`, `app/services/restaurant_service.py`,
     `app/schemas/restaurant.py`, `tests/test_phase15_restaurant_schema.py`,
     `tests/test_phase15b_restaurant_api.py`.
     Discovery-only - no menu-stock/delivery semantics (Rule 4).

3. **Transport + Personal Transport Booking (`0016`)** - *AUTHORED (2026-09-05)*: §Domain 15; provider
     files: `alembic/versions/0016_transport_booking.py`, `app/models/transport.py`,
     `app/api/routes/transport.py`, `app/services/transport_service.py`,
     `app/schemas/transport.py`, `tests/test_phase16_transport_schema.py`.
     Onboarding/verification, vehicles, availability calendar, quote/accept flow,
     booking status machine (PENDING-CONFIRMED-IN_PROGRESS-COMPLETED|CANCELLED).
 4. **Reviews + pharma compliance (`0017`)** - *AUTHORED (2026-09-05)*: moderated reviews;
      `prescription_required` etc. gating Rx discovery-only flows.
      Files: `alembic/versions/0017_reviews_pharma_compliance.py`, `app/models/review.py`,
      `app/api/routes/reviews.py`, `app/services/review_service.py`, `app/schemas/review.py`,
      `tests/test_phase17_reviews_pharma_schema.py`.
 5. **Backend hardening** — add `firebase-admin`; real payment gateway; OTP/rate-limit
      → Redis; fail-on-error CI; migration gate on deploy; remote Terraform state; explicit CORS.
 6. **Prune duplicates** - §4 D4-D7 (deprecate mock repositories in prod).

## 8. Relationship to `DATABASE SCHEMA DESIGN.txt`

The companion design document (repo root) now contains:
- the complete, codebase-accurate table catalog for every committed/in-progress entity,
- M1-M4 (Restaurant/Transport/Reviews/Pharma) now all authored with full API layers,
- data-consistency rules + indexing strategy + migration map (0001-0017, linear head 0017).
