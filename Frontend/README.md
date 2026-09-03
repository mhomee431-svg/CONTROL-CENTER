# Hyperlocal Customer App

Customer-facing Flutter application for hyperlocal product/shop discovery.
This document is the **final Phase 1–11 reference** for architecture, features,
environment, builds, testing, backend integration and release readiness
(validated   in Phase 12).

- Flutter 3.47 / Dart 3.13 · Riverpod 3 · go_router 17 · Dio 5
- Android applicationId: `com.hyperlocal.hyperlocal_customer_app`
- iOS bundle identifier: `com.hyperlocal.hyperlocalCustomerApp`

---

## 1. Architecture

Feature-first clean architecture with dependency inversion at every boundary:

```
lib/
├── main.dart                  # Entry point, ProviderScope
├── app.dart                   # MaterialApp.router, theme, auth-transition listeners
├── core/
│   ├── cache/                 # local_cache_service.dart (stale-while-revalidate)
│   ├── env/                   # env_config.dart (--dart-define injection, no defaults)
│   ├── error/                 # failures.dart (typed failure hierarchy)
│   ├── i18n/                  # app_strings.dart (English / हिंदी strings)
│   ├── maps/                  # map_adapter.dart (MapProvider abstraction + stub)
│   ├── network/               # api_client.dart, api_endpoints.dart,
│   │                          # api_error_handler.dart, connectivity_service.dart,
│   │                          # retry_interceptor.dart
│   ├── performance/           # debouncer.dart, paginated_state.dart
│   ├── router/                # app_router.dart (go_router, auth+location guards)
│   ├── security/              # input_validator.dart, safe_logger.dart,
│   │                          # secure_storage_driver.dart
│   ├── storage/               # local_storage_driver.dart (SharedPreferences JSON),
│   │                          # secure_storage_service.dart (flutter_secure_storage)
│   ├── theme/                 # app_theme.dart (light/dark)
│   └── widgets/               # product_card, shop_card, empty_state_view,
│                              # state_view_builder, image views
└── features/<feature>/        # auth, location, home, search, product_details,
    ├── data/                  # shop_details, directions, saved_and_history,
    ├── domain/                # notifications, profile, settings, shell, splash
    └── presentation/          # data/ (Mock+Api repos) · domain/ (interfaces+models)
                               # presentation/ (controllers, screens, widgets)
```

**Key architectural decisions**

| Concern | Decision |
|---|---|
| State management | Riverpod 3 (code-generated providers where applicable) |
| Navigation | go_router with `StatefulShellRoute.indexedStack` bottom-nav shell |
| Repository pattern | Every feature exposes a domain repository; provider selects **Mock locally**, **API-backed only when authenticated AND `API_BASE_URL` configured** |
| Offline foundation | SharedPreferences (key-value) + flutter_secure_storage (tokens); stale-while-revalidate caches for home feed / product details / shop details |
| Maps | `MapAdapter` abstraction — real **Google Maps** adapter (`google_maps_flutter`) when a `MAPS_API_KEY` is configured; deterministic stub as dev fallback |
| Push | `PushNotificationService` abstraction + `DeviceTokenCoordinator` (register on login, unregister on logout) |

---

## 2. Features (Phase 1–11 inventory)

| Phase | Feature | Status |
|---|---|---|
| 1–2 | Project foundation: theme, router, shell, storage drivers, env config, i18n | ✅ |
| 3 | Auth: welcome/login/register/OTP, session persistence, token refresh, guest mode | ✅ |
| 4 | Location: permission flow, GPS via geolocator, manual search/select, saved address book, default address sync | ✅ |
| 4 | Home: feed (categories, nearby shops, product rows, promotions), skeleton loaders, pull-to-refresh, stale-while-revalidate | ✅ |
| 5 | Search: debounced suggestions, search history (dedupe, cap 10) | ✅ |
| 5 | Search results: filter/sort bar, pagination, results/map view toggle, empty & error states | ✅ |
| 6 | Product details: gallery, offers, price comparison, save/share, recently-viewed recording | ✅ |
| 6 | Nearby shops per product (`/product/:id/shops`) | ✅ |
| 7 | Shop profile: header, product list, save, call/directions actions | ✅ |
| 8 | Directions screen with `MapAdapter` map, markers, distance, external-maps hand-off | ✅ |
| 9 | Favorites (products/shops): guest local queue, login migration (`syncPendingSaves`), logout purge of synced entries | ✅ |
| 9 | Recently viewed products/shops (cap 20, dedupe-bump) + Saved & History hub (5 tabs) | ✅ |
| 10 | Notifications: list, unread badge, mark read/all, deep links to product/shop/offer with validation + graceful degradation | ✅ |
| 10 | Profile: view/edit with validation, address book, account-state chip, delete account | ✅ |
| 10 | Settings: notification prefs (per-type/channel, rollback-on-failure), location prefs, theme/language, privacy toggles, clear history, sign out/delete | ✅ |
| 11 | Quality hardening: builder-based lists, image decode limits, connectivity monitoring, retries/timeouts, a11y semantics, overflow handling | ✅ |

## 3. Environment setup

No secrets live in the repo (`.env` is gitignored). Configuration is injected at build time:

```bash
# Development (mock repositories — no backend needed, or real local backend)
flutter run

# Development against a real local backend (scheme + host only — the client
# prepends the /api/v1 version prefix centrally)
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:8000 \
  --dart-define=MAPS_API_KEY=<your-key>

# Staging
flutter run --release \
  --dart-define=API_BASE_URL=https://staging-api.hyperlocal.in \
  --dart-define=APP_ENV=staging \
  --dart-define=MAPS_API_KEY=<your-key>

# Production (default for release builds; always HTTPS)
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.hyperlocal.in \
  --dart-define=APP_ENV=production \
  --dart-define=MAPS_API_KEY=<your-key>
```

| Variable | Required | Purpose |
|---|---|---|
| `API_BASE_URL` | No* | Scheme + host of the real backend. *Required for staging/production; dev falls back to mocks when omitted. |
| `APP_ENV` | No | `development` \| `staging` \| `production`. Release builds default to `production`; debug/test to `development`. |
| `MAPS_API_KEY` | No (stub map shown if empty) | Map provider key via `EnvConfig.mapsApiKey` |

Rules enforced by design:
- Production/staging base URLs **must be HTTPS**; an `http://` production
  override fails fast in `main()` (`EnvConfig.validateProduction`).
- `API_BASE_URL` is **scheme + host only** — `/api/v1` is appended centrally
  (`ApiEndpoints.apiPath`); a stray trailing `/v1`/`/api/v1` is stripped.
- Release mode is detected via `dart.vm.product`; debug logging suppressed accordingly.
- Tokens are stored only in flutter_secure_storage; `SafeLogger` redacts sensitive keys.
- Mocks are dev-only: notifications/profile/auth resolve to the live API in
  staging/production, and the directions GPS + manual location search use real
  device/backend data in production.
- Maps resolve to the real Google Maps SDK when `MAPS_API_KEY` is injected at
  build time (`--dart-define=MAPS_API_KEY=...`). The key is **never committed**:
  Android resolves the manifest placeholder from `MAPS_API_KEY` (environment /
  gitignored `android/local.properties`); iOS reads the `GMSApiKey` Info.plist
  entry backed by the `MAPS_API_KEY` build setting.

## 3.1 Google Maps / Location (Phase 15)

- **Location** — `geolocator` (permission + GPS) via `DeviceLocationRepository`
  and `DeviceLocationService`; `LocationController` owns the permission/GPS
  lifecycle and persists the selected location in secure storage.
- **Map** — `GoogleMapAdapter` (`google_maps_flutter`) renders:
  - customer marker ("Your location") + shop/destination markers,
  - a dashed directions polyline between the two,
  - a camera fitted to all markers (re-framed once the map viewport is known),
  - the SDK "my location" button/blue dot.
  Without a key the app falls back to `StubMapAdapter` (dev/test only).
- **Shop coordinates** — `GET /shops/nearby`, `GET /locations/nearby`, and
  `GET /home/feed` return `latitude`/`longitude` + `distance_km` computed
  server-side (haversine).
- **Customer coordinates** — device GPS, validated before use; approximate or
  out-of-range fixes are surfaced as errors.
- **Directions** — on-map route hint + one-tap hand-off to the native maps app
  (`geo:` intent → Google Maps), no server-only credential required.

### Securing the Maps API key

| Platform | Mechanism |
| --- | --- |
| Android | `android/app/build.gradle.kts` reads `MAPS_API_KEY` (env var preferred, then gitignored `android/local.properties`) and injects it into `AndroidManifest.xml` via the `${MAPS_API_KEY}` placeholder. Restrict the key to **Maps SDK for Android** with the app package + SHA-1. |
| iOS | `GMSApiKey` Info.plist entry (`$(MAPS_API_KEY)` build setting) consumed by `AppDelegate.swift` → `GMSServices.provideAPIKey`. Create `ios/Flutter/MapsAPIKey.xcconfig` locally (copy `MapsAPIKey.xcconfig.example`); CI passes `MAPS_API_KEY=...` to `xcodebuild`. Restrict the key to **Maps SDK for iOS**. |
| Server-only keys | Never embed Directions/Geocoding/Places web-service keys in the app — anything server-only must stay on the backend.

## 4. Build instructions

```bash
cd Frontend
flutter pub get

# Debug APK
flutter build apk --debug          # → build/app/outputs/flutter-apk/app-debug.apk

# Release APK (see release checklist re: signing)
flutter build apk --release        # → build/app/outputs/flutter-apk/app-release.apk

# iOS (macOS required)
flutter build ios --release
```

## 5. Testing instructions

```bash
cd Frontend
flutter analyze                    # static analysis (0 issues as of Phase 12)
flutter test                       # full suite: 241 passed, 1 skipped (intentional)
```

Coverage by type: unit (models/controllers/repositories/security/network),
widget (screens: home, search, results, product, shop, notifications, profile,
settings, saved), navigation/router-guard tests, state-transition tests,
validation tests (InputValidator), network-failure tests (ApiErrorHandler,
retry interceptor, offline fallbacks). Performance-related unit tests exist for
Debouncer/PaginatedState; real-device profiling remains a release task.

Known skip: `productDetailsControllerTest > productDetailsProvider error`
(`skip: true`) — Riverpod AsyncError timing flake; equivalent error coverage
exists at screen level.

## 6. Backend integration points (Phase 21)

All endpoints are centralized in `lib/core/network/api_endpoints.dart` and
expect the `{success, message, data}` envelope handled by `ApiClient`:

- Auth: `/auth/send-otp`, `/auth/verify-otp`, `/auth/register`, `/auth/refresh`,
  `/auth/logout`, `/auth/sessions[/:id]`, `/auth/account-status`
- User/profile: `/users/me`, `/profile`
- Home/catalog: `/home/feed`, `/categories`, `/products/:id`,
  `/products/:id/shops`, `/shops/nearby`, `/shops/:id`, `/shops/:id/products`,
  `/inventory/product/:id`, `/inventory/shop/:id`
- Search: `/search/products`, `/search/suggestions`
- Saved: `/saved-products[/:id]`, `/saved-shops[/:id]`
- Notifications (§21 contract): `/notifications`, `/notifications/:id/read`,
  `/notifications/read-all`, `/notifications/preferences`,
  `/notifications/device-token[/:token]`
- Locations: `/locations/nearby`, `/locations/manual-search`

Integration is switched on per-feature by configuring `API_BASE_URL` +
authentication — no code changes required. The definitive wiring/validation
happens in Phase 21.

## 7. Known limitations

1. `features/saved/` contains dead legacy files superseded by
   `features/saved_and_history/` (no imports reference them) — cleanup candidate.
2. Platform deep links (custom URL scheme / App Links + `CFBundleURLTypes`)
   are **not configured**; in-app notification deep links via go_router work today.
3. Android release build signs with debug keys (placeholder in
   `android/app/build.gradle.kts`) — must be replaced before store upload.
4. App icon/splash are Flutter defaults; branding assets pending.
5. Map is a real Google Maps adapter when `MAPS_API_KEY` is configured; the
   deterministic stub remains the dev/test fallback when no key is present.
6. One intentionally skipped test (see §5).
7. iOS build verified at configuration level only (Windows host; no Xcode).

## 8. Release checklist

Phase 27 — Production Flutter Build: COMPLETE ✅

- [x] Signed Android release APK (`app-release.apk`, ~56 MB universal build; per-ABI splits available via `--split-per-abi`)
- [x] Package ID: `com.hyperlocal.hyperlocal_customer_app`
- [x] App name: `Hyperlocal Customer App` (all locales)
- [x] App icon: mipmap-*/adaptive icon (ic_stat, ic_foreground)
- [x] Splash screen: `launch_background` theme + `drawable/splash.xml`
- [x] Permissions: INTERNET, ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION, ACCESS_NETWORK_STATE (declared in manifest)
- [x] Production API: `https://api.hyperlocal.in` (in `.env`, embedded in `libapp.so`)
- [x] HTTPS enforced (cleartext traffic disabled — no `usesCleartextTraffic`)
- [x] Signing: release keystore configured via `key.properties` (gitignored); CI env-var support built in
- [x] Version: `1.0.0+1` (versionCode=1)
- [x] Privacy: location permissions only; no test credentials or mock data in release build
- [x] Release configuration: R8 minify + shrinkResources + ProGuard rules
- [x] Debug logs removed (SafeLogger gates on `EnvConfig.isProduction`)
- [x] No localhost/development URLs (verified via APK static scan)
- [x] No mock data or test credentials (verified via APK static scan)

Pending:
- [ ] Device-matrix smoke test (no physical Android device available in this environment; APK verified via static analysis)
- [ ] Store listing metadata (iOS display name already set: "Hyperlocal Customer App")
- [ ] Crash reporting/Sentry production wiring (foundation exists via SafeLogger + EnvConfig.isProduction)

---

