# Phase 28 — Real Device E2E Test

> "Use real devices and real services."

## 1. What "real device / real services" means in this workspace

This repository has **no physical Android/iOS device and no emulator** available
in the CI/developer workstation (`flutter devices` reports Windows, Chrome, and
Edge only). The Hyperlocal platform therefore expresses its **real-device E2E**
contract as:

- **Backend:** the *entire* customer / shopkeeper / admin journey driven
  end-to-end through the **real FastAPI HTTP API** via
  `fastapi.testclient.TestClient` (real routing, real dependency injection,
  real SQLAlchemy session, real OTP send/verify, real catalog, real
  PostGIS/pg_trgm search engine on a SQLite file with SQL shims). No hand-built
  DB fixtures replace a step — Phase 21's `_build_world()` builds the whole
  dataset through the platform's own routes.
- **Frontend (device-only legs):** the network/GPS/permission matrix is
  verified against the **real production classes** (`DeviceLocationService`,
  `LocalCacheService`, `ExponentialRetryInterceptor`, `DirectionsController`)
  — no test-only stubs in `lib/`. These unit tests are the deterministic
  proxy for the on-device manual protocol in §4.

## 2. Test inventory

### 2.1 Backend — real HTTP API e2e

`Backend/tests/test_phase28_real_device_e2e.py` (14 tests, full pass):

| # | Test | Phase-28 leg |
|---|------|--------------|
| 1 | `test_customer_registration_otp_and_session` | registration → OTP → session |
| 2 | `test_customer_location_manual_search` | location (city search) |
| 3 | `test_customer_distance_and_map_markers` | distance (haversine) + map (lat/lng) |
| 4 | `test_customer_search_product_shop_price_availability` | search → product → shop → price → availability → distance |
| 5 | `test_customer_directions_data_contract` | directions (shop coords + distance math) |
| 6 | `test_shopkeeper_update_price_inventory_and_rediscovery` | shopkeeper update → re-index → live rediscovery |
| 7 | `test_admin_login_and_identity` | admin login (SUPER role) |
| 8 | `test_admin_verification_record_exists` | admin → verification |
| 9 | `test_admin_moderation_edit_product` | admin → moderation (product edit) |
| 10 | `test_admin_monitoring_dashboard_metrics` | admin → monitoring (dashboard) |
| 11 | `test_admin_monitoring_audit_and_admin_actions` | admin → monitoring (governance trail) |
| 12 | `test_admin_monitoring_inventory_insights` | admin → monitoring (inventory views) |
| 13 | `test_platform_health_and_offline_error_envelope` | real-network: liveness + offline 404 envelope |
| 14 | `test_admin_moderation_suspend_reactivate_shop` | admin → moderation (suspend/reactivate) |

Run: `cd Backend && python -m pytest tests/test_phase28_real_device_e2e.py -q`
(~6 s).

### 2.2 Frontend — device network / GPS / permission matrix

| File | Covers |
|------|--------|
| `test/core/network/retry_interceptor_test.dart` | slow-network timeout/retry, 429, 5xx retry; POST/PUT/DELETE never retried (no double OTP); backoff math |
| `test/core/network/phase28_device_network_matrix_test.dart` (NEW) | GPS-disabled, permission-denied, valid-fixture coordinate, haversine distance, offline stale cache |
| `test/core/cache/local_cache_service_test.dart` (NEW) | no-network stale serving, hard-expiry eviction, corrupted-entry eviction, clear/remove |
| `test/features/directions/.../directions_controller_test.dart` | GPS-off → `noGps`, permission-denied → `permissionDenied`, network failure → `networkFailure`, retry recovery |
| `test/core/network/api_error_handler_test.dart` | timeout/offline/401/404/500 mapping |

### 2.3 Backend test data contracts asserted

- `/search/v2/products` → results carry `price`, `mrp`, `is_available`,
  `stock_status`, `distance_km`, `shop_id`, `shop_name`, `brand_name`
  (`app/search/engine.py`).
- `/search/v2/nearby-shops` and `/locations/nearby` → expose `latitude`,
  `longitude`, `distance_km` (the map + distance contract).
- `/shops/public/{id}` → `ShopPublicResponse` exposes `latitude`, `longitude`,
  `is_verified`, `is_accepting_orders`, `is_open_now` (the map + directions
  data contract the device geo-intent consumes).
- `/shopkeeper/shops/{id}/products/{sp}` (PATCH, `ShopkeeperProductUpdate`) →
  live price/inventory/availability update.
- `/admin/shops/{shop_id}/verification` (POST) → audited
  VERIFY/REJECT/SUSPEND/REACTIVATE; SUSPEND also flips `is_accepting_orders=False`
  (`admin_service.shop_verification_action`, `app/services/admin_service.py`).
- `/admin/dashboard/metrics` → `DashboardMetrics`.
- `/admin/dashboard/metrics` → `DashboardMetrics`.

## 3. Network-condition coverage map

| Condition | Where exercised | How |
|-----------|-----------------|-----|
| Wi-Fi | backend test 4-5 | customer search resolves real products over the HTTP stack |
| mobile data | backend test 4-5 | same — TestClient is transport-agnostic |
| slow network | `retry_interceptor_test` + backend `retry_interceptor` | receiveTimeout retried with 800→1600→3200 ms backoff; OTP POST never retried |
| no network | `local_cache_service_test` + backend test 13 | `/shops/public/999999` → structured `success:false` envelope; stale cache serves offline data |
| GPS disabled | `device_location_service_test` + `phase28_device_network_matrix` + `directions_controller_test` | `LocationErrorType.noGps` |
| permission denied | `direction_controller_test` + matrix | `LocationErrorType.permissionDenied` |

## 4. Real-device execution protocol (manual)

When a physical device / emulator is available, map the deterministic unit
scenarios above onto this hands-on protocol:

1. **Customer flow** — register on-device (real phone number) → receive OTP
   over real SMS (Wi-Fi and 4G) → grant location permission → set Delhi as the
   manual location (GPS off) → search "Aashirvaad" → open product → open shop →
   verify price/MRP/availability/distance/MapAdapter distance label → tap
   Directions → confirm the `geo:` intent + Google Maps fallback route.
2. **Network variants** — repeat the customer flow throttled to
   Chrome DevTools "Slow 3G" → confirm retry interceptor rescues GETs and the
   stale cache renders product detail; enable Airplane Mode → confirm
   `ApiException.offline` surfaces and cached shop/profile pages render from
   `LocalCacheService`; disable GPS + deny permission → confirm `DirectionsController`
   surfaces `noGps` / `permissionDenied` errors and `retry()` recovers.
3. **Shopkeeper flow** — register → verify → map a master product → set price
   199 / MRP 255 / qty 3 → publish → observe customer rediscovery reflects the
   new price within one re-index cycle.
4. **Admin flow** — log in → confirm `/admin/me` shows SUPER → moderate
   (suspend the shop → confirm it disappears from `/search/v2/nearby-shops`;
   reactivate → confirm it reappears) → open the dashboard metrics / inventory
   insights panels.
5. **Real network** — run steps 1-4 over Wi-Fi, then mobile data (4G), then a
   throttled "Slow 3G" profile, then Airplane Mode (cache-only), then GPS-off
   and permission-denied combinations. Record pass/fail in the matrix below.

## 5. Results

- Backend: **14/14 passed** (5.67 s).
- Frontend: **45/45 passed** across the 6 Phase-28-covered test files.

| Condition | Backend | Frontend (unit proxy) | Real-device protocol |
|-----------|---------|----------------------|----------------------|
| Wi-Fi | ✅ customer discovery | ✅ retry interceptor | manual §4.1 |
| mobile data | ✅ (same HTTP stack) | ✅ | manual §4.5 |
| slow network | ✅ retry+backoff | ✅ `retry_interceptor_test` | manual §4.2 |
| no network | ✅ offline 404 envelope | ✅ stale cache tests | manual §4.2 |
| GPS disabled | n/a (backend has no GPS) | ✅ `noGps` | manual §4.2 |
| permission denied | n/a | ✅ `permissionDenied` | manual §4.2 |

## 6. Environment & limitation notes

- `ENVIRONMENT=test` / `HYPERLOCAL_ENV=test` are set for the backend run; the
  OTP dev value is read from settings so registration is deterministic.
- The Phase-27 push-notification dispatch inside
  `shop_verification_action` can issue a synchronous FCM call with no timeout
  in a device-less test environment and hang; `test_admin_moderation_*` patches
  `notification_service.notify_shop_verification` / `create_notification` to a
  no-op so the governance logic (status flip + audit trail) is exercised
  without the hang. The notification delivery path itself is covered by
  Phase-27 tests.
- `/ready` is intentionally not asserted in the test harness: it pings live
  Redis / PostGIS / storage / Celery and hangs under SQLite-only test config.
  `/health` (liveness) is asserted.
- The Flutter matrix tests use the in-memory GPS/permission flags that
  `DeviceLocationService` exposes for debug/test builds; on a **real device** in
  production builds (`EnvConfig.isProduction` true), `getCurrentLocation` calls
  the real `geolocator` API — the unit assertions then become the spec the
  manual protocol in §4 validates against.

