# Phase 31 — End-to-End Platform Testing

This phase executes a full-platform test of the complete ecosystem and verifies
the business journey from **shopkeeper data entry to customer discovery**.
Result: **all suites green after fixing one critical and one high-severity
production defect plus one test-isolation defect.**

---

## 1. Test suites executed

| Suite | Scope | Result |
|-------|-------|--------|
| Backend unit + integration + API + DB + search + security + performance | `Backend/tests` (full `pytest`) | **619 passed, 6 skipped** |
| ShopkeeperApp widget/unit tests | `flutter test` | **11 passed** |
| Customer Frontend widget/unit tests | `flutter test` | **242 passed, 1 skipped** |
| New Phase 31 E2E regression suite | `tests/test_e2e_phase31.py` | **7 passed** |

Phase 31 added a dedicated end-to-end test module that exercises, on an
in-memory SQLite engine with the production ORM models:

* Redis/broker-down resilience of the fire-and-forget search-index enqueue.
* Convergence of all four inventory intake sources (manual / barcode / Excel /
  POS) into the single canonical `Inventory` model + `InventoryMovement` audit.
* Shopkeeper publish → indexer → `SearchIndex` → customer-discovery visibility
  (price, availability, freshness, geo, search-text tokens).
* Shop suspension and product deactivation correctly flip discoverability.

---

## 2. Failure-scenario coverage (requested in Phase 31)

| Scenario | Verification |
---

## 3. Final bug list

### Critical — FIXED

1. **Search-index background task crashed with `NameError`**
   `app/search/indexer.py::build_shop_product_index` computed the freshness
   timestamp into a local named `last_inv_update`, but returned
   `"last_inventory_update": last_inventory_update` — a `NameError`. Because the
   `index_shop_product` Celery task (and the periodic incremental sync that
   keeps catalog fresh) invoke this on *every* shop-product publish/product
   update, listings could fail to become discoverable by customers.
   *Fix:* renamed the local to `last_inventory_update`. Regression-covered by
   `test_shopkeeper_to_customer_discovery_journey`.

2. **Redis outage could hang a request thread indefinitely**
   `app/services/inventory_service.py::_enqueue_search_index_update` called
   `celery_app.send_task(...)` inline and relied on `try/except` to bound the
   broker. When Redis is down, `send_task` blocks in the result-backend's
   pubsub reconnect loop and never returns (captured in `hang_trace.txt`), so a
   simple `except` never runs — an inventory/price write would stall the HTTP
   request. 
   *   Fix: run the publish in a short-lived daemon thread with a hard 1s
       timeout (`ignore_result=True` prevents result-backend wait), swallow
       in-thread errors, and log-and-continue. Convergence is preserved by the
       periodic Celery-beat incremental search-index sync.
   *   Covered by the three `test_redis_down_*` / `test_enqueue_publishes_*`
       resilience tests.

### High | FIXED

3. **Order-dependent backend test failure (shared metadata mutation)**
   Four SQLite test modules each ran an in-place `_strip_geo_columns()` that
   rewrote the process-global `Base.metadata` (`Geography` → `Text`). Depending
   on test ordering, `test_search_index_model_has_geo` — which asserts the
   production `SearchIndex.location` is a PostGIS `Geography` — failed.
   *Fix:* consolidated into a reversible shared helper
   `tests/geo_compat.py` (`strip_geo_columns` / `declared_type`) and made the
   asserting test inspect the pristine declared type. Green regardless of
   ordering (verified by running stripping modules + `test_search_geo` together).

### Non-blocking / already present

- `datetime.utcnow()` deprecation warnings across the test-suite (cosmetic; no
  logic impact under Python 3.14).
- No `get_db` no-op placeholder concerns; database failover relies on
  `pool_pre_ping=True` + per-request SQLAlchemy error handling already covered by
  Phase 30.

---

## 4. Community cross-checks applied

- Confirmed all four intake paths write to the **same** `ShopProduct` +
  `Inventory` canonical model via their respective services:
  `barcode_intake_service` (`InventorySource.BARCODE_SCAN`),
  `excel_import_service` (`EXCEL_UPLOAD`), `inventory_service` (`MANUAL`),
  `pos_sync_service` (`POS_INTEGRATION`, documented "POS data lands in the same
  canonical inventory system").
- Confirmed the discovery chain: inventory write → `_enqueue_search_index_update`
  → `index_shop_product` → indexer → `SearchIndex` → customer search engine
  (freshness/availability/geo/price surfaced). Also a Celery-beat incremental
  sync + hourly reconcile as a safety net.

---

## 5. Verification summary

- ✅ Full backend suite green (619 passed / 6 skipped / 0 failed).
- ✅ New Phase 31 E2E suite green (7 passed).
- ✅ Customer Frontend (242) and ShopkeeperApp (11) suites green.
- ✅ No critical or high-severity issue remains open after fixes.
- ✅ The shopkeeper→customer business journey is verified end-to-end.
|----------|--------------|
| Redis / broker unavailable | `test_redis_down_enqueue_does_not_hang_or_raise` — daemon-thread + hard 1s timeout regression for `hang_trace.txt` |
| Background job failure | `index_shop_product` task now survives a broker error (never crashes a thread) |
| Four intake sources converge | `test_all_four_intake_sources_converge_on_inventory_model` |
| Shop suspension | `test_shop_suspension_hides_listing_from_discovery` |
| Product deactivation | `test_product_deactivation_hides_listing_from_discovery` |
| Shopkeeper → customer discovery | `test_shopkeeper_to_customer_discovery_journey` |
| Stale inventory / freshness | `test_all_four_intake_sources_converge_*` asserts per-source staleness thresholds |
| Empty states, invalid input, timeouts | covered by existing backend suites (validation schemas, rate limits, pagination limits) |