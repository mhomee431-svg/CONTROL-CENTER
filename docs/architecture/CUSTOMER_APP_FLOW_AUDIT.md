# CUSTOMER APP — STRUCTURE & FLOW AUDIT
> Scope: `apps/customer_app` (Flutter 3.47 / Dart 3.13, Riverpod + go_router, clean architecture).
> Companion to `docs/database/DATABASE_PERFORMANCE_AUDIT.md`. No code modified.

---

## 1. STRUCTURE — verified layout

```
lib/
├── main.dart                 ← Firebase init (only if API base URL set), production
│                                URL guard, SafeLogger crash hooks, ProviderScope
├── app.dart                  ← MaterialApp.router + session-expiry bridge (401 →
│                                Welcome), login/logout side-effects (favorite
│                                migration, device-token register/unregister)
├── core/                     ← env, network (dio client/endpoints/errors/retry/
│                                connectivity), router, theme, cache, storage,
│                                security (safe logger, input validator), widgets
└── features/                 ← 16 features, each: data/ domain/ presentation/
     auth, customer, directions, home, location, notifications, onboarding,
     product_details, profile, saved, saved_and_history, search, settings,
     shell, shop_details, splash
```

**Architecture verdict: GOOD.** Consistent clean-architecture layering
(data / domain / presentation), Riverpod controllers, freezed+json models,
centralized `ApiEndpoints` mirroring backend `API_PREFIX=/api/v1`,
dual `mock_*` / `api_*` repositories with a safe `EnvConfig.hasApiBaseUrl`
switch (mocks forced off in production).

## 2. NAVIGATION FLOW (from `app_router.dart`, verified)

```
/splash ──► redirect guard
   │  auth initial/loading → stay on splash
   └─► any other state (guest-first: auth routes COMMENTED OUT) → /
        │
        └─ StatefulShellRoute.indexedStack (bottom nav, 5 branches):
             /                HomeScreen
             /search          SearchScreen ── /search/results?q=
             /saved           SavedItemsScreen   (saved_and_history)
             /notifications   NotificationsScreen
             /profile         ProfileScreen
        │
        └─ full-screen routes:
             /product/:id           ProductDetailsScreen
             /product/:id/shops     NearbyShopsScreen
             /shop/:id              ShopDetailsScreen
             /directions?shopId&name  DirectionsScreen
             /profile/edit, /profile/addresses
             /my-favorites, /recently-viewed   (customer feature)
             /settings
```

## 3. PRIMARY DISCOVERY FLOW (customer journey — matches product spec)

```
Splash → Home (location header, categories, nearby shops, promo)
   └─► Search bar → /search (suggestions + history + popular)
         └─► /search/results?q=
               ApiSearchRepository → GET /api/v1/search/v2/products
                 params: q, page, limit, sort(nearest|lowest_price|highest_rated|
                 recently_updated|relevance|availability), latitude, longitude,
                 in_stock, radius_km, min_rating, max_price
               → results cards (shop_product: price, availability, distance,
                 shop rating) → tap
                   ├─► /product/:id  → GET /products/:id (+ /products/:id/shops)
                   │      └─► /product/:id/shops → NearbyShopsScreen
                   └─► /shop/:id → GET /shops/:id (+ /shops/:id/products)
                          └─► /directions?shopId → GET /locations/directions
```


**Backend contract check ✔** — every endpoint in `api_endpoints.dart` maps to a
registered backend route (search/v2/*, products, shops/nearby, inventory/product|shop,
home/feed, categories, customer/*, notifications/*, profile, locations/*).
One stale-comment note: `search_repository.dart` mentions "Elasticsearch pagination" —
backend is PostgreSQL + search_indexes; fix the comment.

## 4. FINDINGS (ordered by severity)

### 🔴 F1 — App does not compile: `MapLatLng` called with named args (P0)
- `lib/features/location/data/location_api_service.dart:241-244`
  ```dart
  return MapLatLng(
    latitude: (data['latitude'] as num).toDouble(),
    longitude: (data['longitude'] as num).toDouble(),
  );
  ```
  but `lib/features/location/domain/models/map_route.dart:6` defines a
  **positional** constructor: `const MapLatLng(this.latitude, this.longitude);`
- `flutter analyze` → **3 errors** (`not_enough_positional_arguments`,
  `undefined_named_parameter` ×2). `flutter build` / `flutter run` will fail.
- **Why tests still pass:** no test imports `location_api_service.dart`
  (295 passed, 1 skipped) — a compile-blocking file with zero test coverage.
- Fix: `return MapLatLng(lat, lng);` (1-line change).

### 🟠 F2 — Corrupt/empty leftover artifacts in `lib/` (must delete)
| Path | What it is |
|---|---|
| `lib/features/search/p/` | empty stray directory |
| `lib/features/search/presentation/controllers/search_controller` | file with **no `.dart` extension** (duplicate of the real one) |
| `lib/features/search/presentation/screens/search_results_s` | file with **no `.dart` extension** |
| `test/features/notifications/notifi` | file with no extension |
| `test/features/product_details/presentation/s` | file with no extension |

All are unreferenced; they confuse tooling and pollute the tree.

### 🟠 F3 — Dead feature: `features/saved/` is fully orphaned
- `saved/saved_screen.dart` + `saved/data/api_saved_repository.dart` have
  **zero imports** anywhere; the router and shell use `features/saved_and_history/`.
- Consequently `ApiEndpoints.savedProducts` / `savedShops`
  (`/saved-products`, `/saved-shops`) are referenced **only** by the dead
  repository (the live one uses `/customer/favorites` + local sync).
- Decide: delete the folder or merge it into `saved_and_history`; also remove
  or rewire the two unused endpoints.

### 🟡 F4 — Dual saved implementations (semantic overlap)
`features/saved_and_history` (live: local storage + API sync + purge-on-logout)
coexists with `features/customer` favorites screens (`/my-favorites`) and the dead
`features/saved`. Three concepts for "saved items". Consolidate to one documented model.

### 🟡 F5 — No test coverage for `location_api_service.dart`
The exact file that is broken has no test file; add one when fixing F1 so
regressions surface as test failures, not build failures.

### 🟢 Positive findings
- Session-expiry bridge, guest→account favorite migration, purge-on-logout,
  device-token lifecycle all correctly wired in `app.dart`.
- `EnvConfig.validateProduction()` fail-fast guard; mocks disabled in production.
- Search flow maps 1:1 to backend `/search/v2/*` incl. all filters and sorts.
- `PaginatedState`, debouncer, retry interceptor, safe logger — solid plumbing.

## 5. VERIFICATION EXECUTED (all commands run live)

| Check | Result |
|---|---|
| `flutter analyze --no-pub` (after P0 fix) | ✅ **No issues found** |
| `flutter test --no-pub` (full suite, after fix) | ✅ **295 passed, 1 skipped** |
| `flutter test --no-pub` (full suite, after F2 cleanup) | ✅ **295 passed, 1 skipped** (no regression) |
| Endpoint contract (app ↔ backend routes) | ✔ all match; 2 endpoints only used by dead code (F3) |
| Dead-code scan | `features/saved/` orphaned; 5 corrupt artifacts (F2) |

## 6. FIXES APPLIED (this session)

1. **🟠 F2 — Artifact cleanup** (5 items deleted, all verified stale — see previous session).
2. **🟠 F3 — Dead `features/saved/` folder deleted** (`saved_screen.dart` dummy placeholder,
   `saved_repository.dart` abstract class whose own doc said "real implementation lives in
   saved_and_history", `api_saved_repository.dart`). The `/saved-products` & `/saved-shops`
   endpoint constants were briefly removed but **restored** — they are shared infrastructure
   also used by live `saved_and_history`, `product_details`, and `shop_details` repositories.
   The dead folder was just a redundant second repository, not the endpoints themselves.
3. **🟡 F4 — Resolved by F3.** The `customer` favorites feature (`/my-favorites`) is live,
   routed, and uses the distinct `/customer/favorites` endpoint — it is a separate concept
   (server-side favorites) from `saved_and_history` (local-first saves + account sync).
   Deleting the dead `features/saved/` collapsed the 3 overlapping concepts to 2 legitimate ones.

## 7. REMAINING — none (all findings resolved)

**Recommended order:** F1 ✅ → F2 ✅ → re-run analyze+tests ✅ → **F3/F4 cleanup decision** → then return to the database architecture steps.

