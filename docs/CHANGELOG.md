# Hyperlocal Product Discovery Platform — Changelog

## [Unreleased]

### CI/CD & branching
- Added the `develop` (integration) branch model: `feature/*` → PR → `develop` →
  staging → E2E → PR → `main` → approval → production
- `backend-ci.yml`, `backend-cd.yml`, `backend-deploy.yml`, `flutter-*.yml` and
  `secret-scan.yml` now trigger on `develop` as well as `main`; the Flutter
  workflows gained a `pull_request` trigger (analyze + test gate)
- Staging is now an enforced release gate: `deploy-production` requires
  `deploy-staging`, `smoke-test-staging` and `e2e-staging` to succeed
  (`!cancelled() && !failure()`) and only runs from `main`
- New `e2e-staging` job + `infrastructure/scripts/cicd_contract_check.py`:
  the deployed `/openapi.json` must match `packages/api_contracts/openapi.json`
  (paths, methods, schemas, version) and `/ready` must report
  database+redis+postgis — also run against production in `verify-production`
- Job-level concurrency locks (`backend-staging-deploy`,
  `backend-production-release`) stop `develop`/`main` deploys racing on one box
- Branch-aware image tags: `:latest` on `main`, `:develop` on `develop`,
  immutable `:<sha>` always
- Flutter staging flavor builds (`APP_ENV=staging` →
  `https://staging-api.hyperlocal.in`) on `develop`; production APKs now fail
  fast when the API host secret is missing
- New docs: `docs/deployment/BRANCHING.md` (develop vs staging, gates,
  runbooks); `scripts/setup_branch_protection.ps1` applies the branch rules
  (`-Discover` uses the exact check names GitHub reports)
- Reconciled with the existing `platform-ci.yml` (PR gate for every app/package)
  and `flutter-admin.yml`: the Flutter branch gates now skip `pull_request` runs
  (platform-ci already covers them), and the admin panel publishes a staging web
  artifact on `develop` next to its production artifact on `main`
- `docs/deployment/GITHUB_CICD.md` + `DEPLOYMENT.md` updated to the enforced flow
- terraform staging preset domains aligned with the apps' staging default
  (`staging-api.hyperlocal.in`)

### Build & release (repo could not produce a binary at all)
- AUDIT found the repository shipping **literal merge-conflict markers in six
  tracked files**. Analyzer and unit tests were green throughout, so nothing in
  CI caught this — the breakage was only visible by actually building.
  - `shopkeeper_app/android/app/build.gradle.kts` — markers made the Gradle
    script unparseable; the app **could not produce an APK at all**.
  - `backend/tests/test_customer_support.py` — began with a stray `a` before
    its module docstring, so the whole module failed to import (SyntaxError).
  - `backend/tests/{test_orders_api,test_phase4_rds,test_phase26_migration_automation}.py`
    and `backend/scripts/verify_rds.py` — markers, plus revision ids hardcoded
    to `"0026"`/`"0027"`. The derived-head assertions replace the hardcoding,
    so a new migration no longer breaks them.
  - `docs/architecture/CLOUD_OWNERSHIP.md` — an *entire-file* conflict. Both
    audits are preserved rather than one being dropped: the narrative document
    stays, the capability-matrix view is kept alongside as
    `CLOUD_OWNERSHIP_MATRIX.md`, and the two cross-link.
  - `backend/tests/test_orders_api.py` also carried a **duplicate** autouse
    fixture: the newer `_pin_orders_overrides` supersedes the older
    `_install_orders_overrides`, so only the newer one is kept.
- `customer_app` could not build for three independent reasons, fixed in
  order: `compileSdk` was on `flutter.compileSdkVersion` (36) while
  `permission_handler_android` 14.x requires 37; AGP 9.1.0 caps at 36, so AGP
  moved to 9.2.1; and AGP 9.2.1 then required Gradle ≥ 9.4.1 while the wrapper
  still pinned 9.3.1. All three now match the working `shopkeeper_app`
  configuration.
- `customer_app/MainActivity.kt` called `CredentialManager.getCredential()` as
  if it returned a `Task` and chained `addOnSuccessListener` onto it. Since
  `androidx.credentials` 1.3.0 that method is **suspend**, so
  `:app:compileDebugKotlin` failed with five errors. It now runs on a
  main-dispatcher coroutine, mirroring `shopkeeper_app`'s MainActivity.
- Verified end to end: `flutter analyze` clean on all three apps, **748 + 929 +
  1 tests pass**, `python -m compileall app tests scripts` exits 0, and real
  builds succeed — `customer_app/app-debug.apk`, `shopkeeper_app/app-debug.apk`
  and the `admin_panel` web bundle.

### Customer app
- AUDIT SWEEP (line-by-line, whole `lib/` + `test/`): 47 analyzer issues → 0
  and **one hard compile error fixed**. Verified: `flutter analyze` reports
  "No issues found" and **748 tests pass**.
  - **Fixed — the app did not compile.** `login_screen.dart` and
    `register_screen.dart` imported `../../data/phone_utils.dart`, but the file
    actually lives in `domain/` (`data/phone_utils.dart` does not exist), so
    both auth screens had an unresolvable import.
  - **Fixed — a test that failed at the end of every month.**
    `inventory_pricing_import_screens_test.dart` ("create offer validates, then
    assigns with selected products") set the start date to today and the end
    date to day **28 of the current month**. `OfferValidators.period` requires
    `end.isAfter(start)` *strictly*, so from the 28th onwards the offer failed
    its own validation and the test saw 0 assign calls. It now steps to the next
    month and picks the 1st, which is after "today" on every day of the year.
  - **Cleaned — the remaining analyzer issues**: dead imports, `const` hoists,
    and documented `// ignore:` directives where the code is deliberate.
  - **Preserved, not deleted (reserved for future work):** the `EnumCodec`
    decoder, the seeded `Random` in `MockOrderRepository`, the
    `_asNullableInt`/`_asDouble`/`_asDateTime` JSON-coercion helpers, and the
    `/coming-soon` route + `ComingSoonScreen` (Home's "no nearby shops" state).
    Each is either already linked or intentionally reserved, and now carries a
    comment saying so.

### Shopkeeper app
- AUDIT SWEEP (line-by-line, whole `lib/`): verified and fixed the real
  defects, preserved every unlinked seam. Findings:
  - **Fixed — error classification (`shop_settings_screen.dart`).** The
    "Not signed in" guard threw a raw `Exception`, the only one of 36 such
    sites not using `ApiException`. A raw throw carries no `statusCode` /
    `errorCode` / `kind`, so `ApiException.systemState` could not classify it
    and the screen collapsed a recoverable session problem into the generic
    "Could not load settings." Now the app-wide `const ApiException` idiom.
  - **Fixed — indentation (`api_endpoints.dart`).** `mediaDirectUpload` was
    indented 4 spaces out of alignment with every other member.
  - **Verified clean, no change needed:** zero orphaned files in `lib/` (the
    audit's "orphan" list is test entry points, which is correct); zero
    duplicate provider names across the whole tree (single source of truth
    holds); zero hardcoded `/api/v1` literals outside `env_config`'s
    base-URL normalizer and doc comments; all 80 route constants registered
    in `app_router.dart` and all navigation going through `Routes` (no raw
    route strings); every `TextEditingController` in a `StatefulWidget` with
    `dispose()`; the POS poll timer, the debounce timer and the connectivity
    subscription all cancelled/unsubscribed (§111); no `FutureBuilder`; no
    enum `.firstWhere` without an `orElse` (§126).
  - **Endpoint contract re-verified against `packages/api_contracts/
    openapi.json` + the live FastAPI routes.** 10 app paths are absent from
    the committed `openapi.json` snapshot but ALL exist in the backend:
    `auth/sessions` (`shopkeeper_auth.py:913`), `auth/profile-create` (`:673`),
    `auth/google-profile` (`:994`), `shops/{id}/insights`
    (`shopkeeper_portal.py:238`), `businesses/categories`
    (`merchant_onboarding.py:47`), `notifications/read-all`
    (`notifications.py:134`), `shops/{id}/offers` + `.../offers/{id}/status`
    (`shopkeeper_portal.py:580/607`), `pos/jobs`
    (`pos_integration.py:368/384`) and `support/tickets`
    (`shopkeeper_support.py:49/87`). The snapshot is stale, the app is
    correct — no app change.
  - **Preserved, not deleted (§115 / this task's rule):** the 7
    `ApiEndpoints` constants with no call site (`profileCreate`, `pincode`,
    `analyticsOverview`, `analyticsTopSearches`, `analyticsInteractions`,
    `analyticsDevices`, `analyticsFreshness`) — documented future seams
    whose routes all exist server-side; `mock_auth_repository.dart` and its
    `Future.delayed` calls (the deliberate `kUseMockAuth` seam); and
    `test/_debug_dio_test.dart`. Nothing unlinked was removed.
- PERFORMANCE (spec §110) — the Low Stock restock workbench was the last
  catalog-backed list still doing per-keystroke and per-rebuild work. Three
  defects, one screen (`features/inventory/.../low_stock_screen.dart`):
  - **Debounced search.** Its raw `TextField` filtered the restock slice on
    every glyph, while the products list, inventory scopes and price list all
    use the shared `DebouncedSearchField` (300ms). It now uses the shared field
    too, so the workbench is debounced like its three siblings and picks up the
    shared recent-searches history (submit / focus-loss `record()`, dropdown
    select + remove) instead of keeping a private one.
  - **Derivation out of `build()`.** `_restock()` sorted the WHOLE catalog
    (O(n log n)) on every rebuild — a snackbar, an availability flip, a page
    turn, or the text field's own rebuilds. It is now memoized on the
    (catalog, query) pair, the same rule `ProductQueryCache` already applies to
    the other three lists, so an unrelated rebuild costs nothing.
  - **Image optimization.** Its thumbnail was the one `Image.network` in the app
    that bypassed `ProductImageView`: it decoded at the SOURCE resolution into
    a 48px box, had no loading state (a slow image was an empty grey box,
    indistinguishable from "no image"), and rendered a raw framework error box
    when a presigned URL expired. It now goes through the shared widget at
    `cacheWidth: 96` (~2x) with the same placeholder/error icon as the products
    list.
  No behavior the shopkeeper relies on changed. Tests: `low_stock_screen_test.dart`
  +4 (12 total) pinning the shared field, the typed filter, the memoized
  slice across an unrelated rebuild, and the optimized thumbnail.
- Product search (spec §95) gained SERVER search — the missing checklist item.
  The loaded catalog still answers every settled query locally first (300ms
  `DebouncedSearchField` debounce + memoized `ProductQueryCache`, zero API
  calls while typing); only a settled query the local predicate matches
  NOTHING fires ONE `GET /inventory?view=list&search=` (2..120 chars,
  per-query dedupe — "no API call for every keystroke" holds). Server rows
  (backend matches name/sku ⊂ local fields, so only genuinely missing rows
  come back) merge into the catalog by id: counter/filters/sort keep working;
  failures are fail-soft (local no-result state stays); a reload/shop switch
  bumps a generation counter that drops any in-flight answer. Repository:
  `InventoryRepository.searchInventoryList` (deliberately no snapshot
  fallback — the call exists to escape staleness). Tests:
  `test/product_server_search_test.dart` (6) incl. keystroke coalescing and
  the stale-answer race.
- Recent-searches controller serializes every load/mutation on one internal
  queue: an in-flight `load()` can no longer wipe a just-submitted term
  (the cold-start race that made the first search vanish from the dropdown),
  `record()` always merges against the state its preceding load applied
  (no store-history loss), and the no-shop path no longer reads `state`
  while `build()` is still running ("uninitialized provider" crash).
  `recent_searches_test.dart`: 11/11 green; dropped an unused import so
  `flutter analyze` stays clean
- The two pre-existing logout failures are FIXED: `AuthController.logout()`
  now treats the recent-searches wipe as best-effort (2s timeout + catch —
  a keystore that never answers must not trap the shopkeeper inside the
  account), and the `dashboard_test` / `settings_support_test` logout tests
  override `recentSearchesStoreProvider` with the in-memory store (the secure
  store's platform channel never completes under the widget test's FakeAsync
  zone, so sign-out hung and `pumpAndSettle` timed out). Result:
  `dashboard_test` 16/16, `settings_support_test` 31/31,
  `recent_searches_test` 11/11, `flutter analyze` clean
- FILTER / SORT spec section implemented as ONE shared filter vocabulary —
  new `lib/core/ui/filter_ui.dart` with three primitives and a single state
  protocol: `FilterChipBar` (quick single-select chips, selected state exposed
  to assistive tech, 44dp touch targets), `FilterSection` + `FilterDropdown`
  (sheet facets; every dropdown carries an explicit "Any" so clearing is one
  tap, never a hidden gesture) and `FilterSheet` (the frame owning Reset /
  Apply — **Reset** clears the draft AND re-applies the empty filter WITHOUT
  closing, so the list behind updates immediately and sheet + list can never
  disagree; **Apply** commits the draft atomically and pops). Applied per
  module:
  - Products list: the stock chips and the filter sheet (Availability,
    Category, Brand, Price range, Recently updated) now build on the shared
    vocabulary; the sheet is handed the live `ProductQuery` and returns it
    via `withFilters` (every facet required — `null` CLEARS, unlike a
    `copyWith`), so search and sort survive untouched.
  - Inventory scopes: quick STOCK chips outside the sheet (hidden on the
    slices that already pin stock — low / out-of-stock / discontinued, via
    the controller's `pinsStock`) + new `InventoryFilterSheet`
    (Category / Freshness; a picker that could match nothing is not offered).
    `InventoryScopeController.setFilters` merges the sheet's facets with the
    scope's identity query; Clear drops only what the shopkeeper applied —
    the slice can never be cleared.
  - Offers: Active / Scheduled / Expired (+ Disabled) buckets as
    `FilterChipBar` chips replacing the tab controller — `OfferFilter` lives
    in the list state, ONE unfiltered fetch serves every bucket, and the four
    predicates partition the rows exactly (nothing duplicated, nothing lost).
  Tests: new `test/inventory_filters_test.dart` (11 — chip slicing, sheet
  facets, Reset/Apply/Clear protocol, pinned-slice guards); `offers_test.dart`
  extended for the scheduled/disabled buckets; `product_state_test.dart`
  call sites moved to `withFilters`. Full suite green (818), `flutter analyze`
  clean.
- REFRESH (spec §97) â€” pull-to-refresh where it is useful, and the two rules
  that keep it honest:
  - Pull-to-refresh added to the server-fed surfaces that lacked it: the five
    inventory scope lists, the inventory dashboard / sync status, the low-stock
    restock workbench, the price list, the import history (rows AND empty
    state), the POS sync history, the insights drill-down, the support ticket
    detail and the offer buckets. All of them are ALWAYS scrollable
    (`AlwaysScrollableScrollPhysics`), which is what makes the gesture fire on
    a list shorter than the viewport â€” previously a short or empty list
    silently swallowed the pull. The pulls that already existed (products,
    dashboard, insights, notifications, sessions, shops, shop profile,
    tickets) got the same physics fix.
  - A pull never blanks what is on screen: new `ProductsController.refresh()`
    (silent, re-entrancy-guarded, generation-bumping, fail-soft â€” the same
    contract as `DashboardController.refresh` / `ShopsController.refresh`)
    serves every catalog pull (products list, inventory scopes / dashboard /
    sync status, low stock, price list), and the dashboard + shops pulls now
    use their existing silent `refresh()` instead of the loud `load()`. Retry
    buttons and the app-bar refresh icons keep the loud path (spinner, error
    state) â€” the pull indicator is the feedback for a gesture.
  - "Do not refresh unnecessarily" holds by construction: automatic refreshes
    stay behind the lifecycle staleness window / reconnect throttle, the
    lifecycle batch refreshes only the Dashboard + Shops providers, and the
    single `ref.invalidate` in the app is the access token.
  - After a mutation the affected rows are patched in place â€” `createProduct`
    prepends the server's row, `_patch` / `adjustStock` swap the one row for
    the server's own numbers; the catalog is never reloaded end-to-end.
    `ProductsAsyncBody` / `PricingAsyncBody` gained an optional `onRefresh`
    (ready body only, so a spinner or an error view can never be pulled), and
    the offers list and buckets render rows AND empty state through ONE
    `LazyListView`. Tests: new `test/refresh_test.dart` (6 â€” the silent
    in-flight refresh, a failed refresh that keeps the rows, short-list pulls
    driven through the real Products / Inventory screens, an EMPTY offers
    bucket that still pulls, and a mutation that leaves the fetch count at
    one).

### Security
- Replaced HMAC-SHA256 password hashing with bcrypt (work factor 12)
- Added `.pem` and `.key` files to `.gitignore`
- Removed mock product repository with hardcoded data
- Created proper async ProductRepository with SQLAlchemy

### Backend
- Created async ProductRepository with full CRUD operations
- Added search, barcode lookup, and category/brand listing methods
- Fixed `.gitignore` to properly exclude sensitive files
- Enhanced BaseService with pagination, exists, get_or_404 methods
- Created standardized API response utilities
- Created API middleware for request context and security headers
- Enhanced validation error formatting
- Created API versioning middleware and version info endpoint
- Added API version headers and deprecation support
- Created API security middleware (input sanitization, size limits, content-type validation)
- Added SQL injection and XSS detection
- Created input validation utilities for Pydantic schemas
- Created image processing module (optimization, thumbnails, metadata stripping)
- Created virus scanning hooks (ClamAV, external API)
- Created upload audit logging service
- Created notification templates for all channels (push, email, SMS)
- Enhanced notification system with template-based messaging
- Created Razorpay payment provider adapter
- Enhanced payment system with India-specific gateway support
- Verified analytics system (comprehensive event tracking)
- Verified audit service (tamper-evident hash chaining)
- Created CloudWatch integration module (logs, metrics, alarms)
- Verified observability system (metrics, alerting, health checks)
- Created CloudTrail integration (API audit, security event detection)
- Added AWS infrastructure audit trail support
- Created backup monitoring service (RDS + S3 health checks)
- Verified backup system (RDS snapshots, PITR, S3 lifecycle)
- Created unified monitoring dashboard service
- Verified health checks, metrics, and alerting system
- Created environment validator (dev/staging/prod configuration checks)
- Verified environment separation (env files, GitHub protection rules)
- Created Flutter production build scripts (customer + shopkeeper apps)
- Verified Flutter environment configuration (dev/staging/prod)
- Created barcode scanner screen for ShopkeeperApp
- Created Excel import screen for ShopkeeperApp
- Created notifications screen for ShopkeeperApp
- Created search performance optimization module (caching, analytics, suggestions)
- Verified search engine (text + geo + barcode + ranking)
- Created performance benchmarking module (targets, tracking, load test config)
- Defined measurable performance targets (API p95 < 300ms, search < 500ms)
- Created fraud detection service (brute force, API abuse, shop fraud)
- Verified admin platform (dashboard, users, shops, products, audit)
- Created platform configuration service (system settings, feature flags)
- Verified admin control (fraud detection, reports, complaints, platform config)
- Created AWS resource tagging module (Tagging.tf + resource_tags.py)
- Verified consistent tagging (Project, Environment, Owner, ManagedBy, CostCenter)
- Created automated security audit module (IAM, SG, S3, secrets, CORS, JWT, backups)
- Added test suite for security audit, performance, platform config, and tags
- Added end-to-end flow tests (customer search, shopkeeper permissions, location) (23 tests)
- Created realistic seed data for all 11 business domains (129 products, 10 cities, brands, shops)
- Added 17 seed-data validation tests (domain coverage, price sanity, geo, no-grocery rule)
- Added observability metrics (DB latency, cache hit/miss, search latency) + 11 tests
- Instrumented cache layer with hit/miss telemetry and search engine with latency
- Created Production Release guide (15-step pipeline, 24-item checklist, rollback matrix)
- BUGFIX: password_service.reset_password naive/aware datetime crash on SQLite rows
- BUGFIX: customer.py circular FK (customer_addresses<->customers) caused SAWarning + sort failure
- BUGFIX: barcode_relationships duplicate index (column index=True + explicit Index same name)
- CLEANUP: geo_compat.py shared make_timestamp_defaults_portable helper + removed edit corruption
- CLEANUP: 41 datetime.utcnow() calls replaced with datetime.now(timezone.utc) (Python 3.14 compat)
- CLEANUP: pytest.ini added — suppresses slowapi/starlette/sqlalchemy deprecation warnings (955→0)
- VERIFIED: 248 tests passing across 11 suites, 0 warnings, app boots 39 routes, security audit 22 checks 0 errors

### Documentation
- Created ARCHITECTURE.md — System architecture overview
- Created API_CONTRACT.md — API endpoint documentation
- Created SECURITY.md — Security measures and checklist
- Created DEPLOYMENT.md — Deployment procedures
- Created ENVIRONMENT.md — Environment configuration
- Created DATABASE_ARCHITECTURE.md — Database schema and indexing
- Created AWS_ARCHITECTURE.md — AWS infrastructure details
- Created RUNBOOK.md — Operations and troubleshooting
- Created DISASTER_RECOVERY.md — DR procedures
- Created COST_GUIDE.md — Cost optimization guide

### Flutter Apps
- Created TokenRefreshInterceptor for ShopkeeperApp
- Added automatic token refresh on 401 responses

## [1.0.0] — 2026-09-07

### Added
- Initial repository audit completed
- Complete backend with FastAPI + SQLAlchemy
- Customer Flutter app with search, products, shops
- Shopkeeper Flutter app with auth, shop management
- Terraform infrastructure for AWS free-tier
- GitHub Actions CI/CD pipelines
- 18 Alembic database migrations
- PostGIS integration for geospatial queries
- Custom search engine with pg_trgm
- JWT authentication with refresh token rotation
- OTP authentication (Fast2SMS + Firebase)
- Redis caching with circuit breaker
- Celery task queue for background jobs
- S3 object storage integration
- Rate limiting and security headers
