# SHOPKEEPER APP — STRUCTURE & FLOW AUDIT
> Scope: `apps/shopkeeper_app` (Flutter 3.47 / Dart 3.13, Riverpod + go_router, clean architecture).
> Companion to `docs/database/DATABASE_PERFORMANCE_AUDIT.md` and
> `docs/architecture/CUSTOMER_APP_FLOW_AUDIT.md`. No code modified except lint fixes.

---

## 1. STRUCTURE — verified layout

```
lib/
├── main.dart                 ← Firebase init (skip in mock mode), production URL guard
├── app.dart                  ← MaterialApp.router (light/dark/system theme)
├── core/                     ← config/env, network (api_client/endpoints/providers/
│                                media_upload/token_refresh/token_store), router, theme
└── features/                 ← feature-first, each: data/ domain/ presentation/
     auth, account, barcode, dashboard, notifications, products, shell, shops
```

**Architecture verdict: GOOD.** Clean layering, Riverpod controllers, centralized
`ApiEndpoints` targeting the isolated `/shopkeeper/*` module (never customer routes),
dual `mock_*` / real repositories with `kUseMockAuth` switch, production guard.

## 2. NAVIGATION FLOW (from `app_router.dart`, verified)

```
/splash ──► redirect guard (auth state machine)
   │  initial/loading → stay on splash
   │  signed-out (unauthenticated/sessionExpired/error/otpSent) → /welcome
   └─► authenticated → /dashboard (or /shops / /shop-register if no shop)
        │
        ├─ auth routes: /welcome, /login, /otp?phone=, /register,
        │                /forgot-password, /reset-password?token=
        ├─ shop routes:  /shop-register, /shops, /shop-profile,
        │                /shop-settings, /shop-location?shopName
        └─ StatefulShellRoute.indexedStack (bottom nav, 3 branches):
             /dashboard   DashboardScreen
             /products    ProductsScreen
             /account     AccountScreen
```

**Notable:** the router is created exactly ONCE; auth changes use
`ref.listen(...) -> router.refresh()` (NOT `ref.watch`) — this deliberately avoids
the login/register-OTP bounce bug. Verified by `register_navigation_test.dart`.

## 3. AUTH FLOW (shopkeeper journey)

```
Splash → Welcome → Login ──┬─► password login → /dashboard
                           └─► OTP → /otp?phone= → verify → /dashboard
                                      ↑ no bounce (router.refresh, not recreate)
Register → /register → Firebase verify → account + shop creation → /dashboard
Forgot/Reset password → /forgot-password → /reset-password?token=
```

**Backend contract check ✔** — every endpoint in `api_endpoints.dart` maps to a
registered backend route under `/api/v1/shopkeeper/*` (auth, shops, dashboard,
inventory, products, profile, location, settings) plus `/api/v1/locations/pincode`
and `/api/v1/media/*` (S3 presigned upload). The shopkeeper app never touches
customer `/auth/*` or `/search/*` routes — clean isolation.

## 4. VERIFICATION EXECUTED (all commands run live)

| Check | Result |
|---|---|
| `flutter analyze --no-pub` (before fix) | ❌ **5 issues** (all in `place_autocomplete_service.dart`) |
| `flutter analyze --no-pub` (after fix) | ✅ **No issues found** |
| `flutter test --no-pub` (full suite) | ✅ **31 passed, 0 failed** |
| Endpoint contract (app ↔ backend routes) | ✔ all `/shopkeeper/*` routes match |

## 5. FIXES APPLIED (this session)

1. `place_autocomplete_service.dart` — 5 lint issues fixed (if-braces + redundant `!`).
2. **🟡 S1 — Barcode scanner wired into products flow**: added a barcode IconButton
   (`Icons.qr_code_scanner`) to the `ProductsScreen` AppBar that pushes `/scan-barcode`,
   and registered the route in `app_router.dart` → `BarcodeScannerScreen`. The orphaned
   screen is now reachable from the shopkeeper's product inventory.
3. **🟡 S2 — Deleted empty `lib/features/data/`** directory.

## 6. REMAINING — none (all findings resolved)
