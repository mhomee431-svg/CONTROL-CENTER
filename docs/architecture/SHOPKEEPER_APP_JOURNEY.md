# SHOPKEEPER APP — THE COMPLETE JOURNEY (verified against code)

> Scope: `apps/shopkeeper_app` (Flutter, Riverpod + go_router, clean architecture).
> Companion to `docs/architecture/SHOPKEEPER_APP_FLOW_AUDIT.md` (structure audit)
> and `docs/deployment/IOS_SETUP.md` (iOS platform setup).

This document maps the end-to-end shopkeeper journey to the exact code that
implements each stage, and records the gaps that were closed to make every
stage reachable.

---

## 1. THE JOURNEY

```
APP START
   │
   ▼
Splash / Initialization            /splash            → SplashScreen
   │
   ▼
Authentication Check               AuthController      → AuthStatus state machine
   │  initial/loading   → stay / splash
   │  signed out        → /welcome
   │  restricted        → /account-status (INACTIVE / SUSPENDED / BANNED)
   │  authenticated     → continue
   ▼
Google Sign-In                     /welcome, /login    → FirebaseAuthService
   │
   ▼
Firebase Authentication            Firebase ID token
   │
   ▼
Backend Token Verification         POST /api/v1/shopkeeper/auth/firebase-login
   │                               (Firebase Admin SDK verifyIdToken)
   ▼
Application User Check             same call — the backend auto-provisions the
   │                               shopkeeper user on first sign-in
   ▼
Shopkeeper Profile Check           AuthState.profileComplete (shops.isNotEmpty)
   │
   ├── Profile exists? YES ────────► Home  (/dashboard, ShopkeeperShell)
   │
   └── NO ──► Create Shopkeeper Profile  (/profile-create → CreateProfileScreen)
                  │
                  ▼
              Shop Setup                (/shop-register → ShopRegistrationWizard:
                  │                      name, category, location, hours, documents)
                  ▼
              Shopkeeper Home           (/dashboard)
                  │
                  ▼
              MAIN SHOPKEEPER FEATURES  (see §2)
```

Every branch above is enforced in ONE place — the `redirect` closure of
`lib/core/router/app_router.dart`:

| Guard | Condition | Destination |
|---|---|---|
| 1 | `initial \|\| isLoading \|\| sessionError` | `/splash` (auth routes exempt; `sessionError` shows Retry) |
| 2 | `unauthenticated \| sessionExpired \| error` | `/welcome` |
| 3 | `accountRestricted` | `/account-status` (only reachable screen) |
| 3b | SHOPKEEPER gate: `isShopkeeper == false` | `/account-status` ("Shopkeeper access required") |
| 4 | `!profileComplete` (no shop yet) | `/profile-create` |
| 5 | shop exists, target in `needsShop` | `/shops` (or `/dashboard` when no shop) |

The router is created exactly ONCE; auth changes call `router.refresh()` (never
`ref.watch`), which is what stops the login/register bounce. Verified by
`test/register_navigation_test.dart`.

**Startup hold (route-flicker prevention).** Flutter + Firebase initialize in `main`; the router then holds `/splash` while the session is UNKNOWN (`initial` / `loading`) — Home never renders before the account state is known. The startup chain (`AuthController.checkSession`): stored backend session (`/auth/me`) → device Firebase auth state → fresh ID token → backend exchange (`/firebase-login`) → routed by the guard chain above. A TRANSIENT failure (offline / backend 5xx) is **NOT** signed-out: it enters `sessionError`, the splash holds with a **Retry** button (plus a "Sign in instead" escape hatch that does not wipe tokens), so there is no Welcome-flicker and a stored session is never lost. A definitive 401 still lands on Welcome. Verified by `test/startup_guard_test.dart`.

---

## 2. MAIN SHOPKEEPER FEATURES — every one reachable

`/features` (AllFeaturesScreen) is the hub that mirrors this table 1:1
(`kShopkeeperFeatures`). Each tile deep-links to the screen that owns the
feature's backend data — the hub renders no numbers of its own.

| # | Feature | Route | Screen | Backend | Entry points |
|---|---|---|---|---|---|
| 1 | Dashboard | `/dashboard` | `DashboardScreen` | `GET .../shops/{id}/dashboard` | bottom nav branch 1 |
| 2 | Products | `/products` | `ProductsScreen` | `.../products`, `.../inventory` | bottom nav branch 2, Home *Add Product* / *Inventory* |
| 3 | Inventory | `/inventory-dashboard` (+ `/inventory-list`, `/low-stock`, `/out-of-stock`, `/inventory-freshness`, `/inventory-sync-status`, `/update-stock`, `/stock-history`) | `InventoryDashboardScreen`, `InventoryScopeScreen` (all / low / out / freshness), `UpdateStockScreen`, `StockHistoryScreen`, `InventorySyncStatusScreen` | `.../inventory`, `.../stock-adjustments`, `.../history` | **Home *Inventory*, hub tile** |
| 4 | Pricing & Offers | `/offers`, `/price-list`, `/update-price`, `/price-history`, `/create-offer`, `/active-offers`, `/expired-offers`, `/offer-details` | `OffersScreen`, `PriceListScreen`, `UpdatePriceScreen`, `PriceHistoryScreen`, `CreateOfferScreen`, `ActiveOffersScreen`, `ExpiredOffersScreen`, `OfferDetailsScreen` | `.../products/{id}` (price / MRP PATCH), `.../offers`, `POST .../offers/assign` | **Home *Pricing & Offers*, hub tiles** |
| 5 | Imports / POS | `/inventory-import`, `/import-center`, `/import-upload`, `/import-preview`, `/import-processing`, `/import-history`, `/pos` (+ `/pos-connection-setup`, `/pos-sync`, `/pos-sync-progress`, `/pos-sync-result`, `/pos-sync-history`, `/pos-error`) | `InventoryImportScreen` (*Import from Excel*), `ImportCenterScreen` + the whole guided flow, `PosScreen` (hub) + `PosConnectionSetupScreen`, `PosSyncScreen`, `PosSyncProgressScreen`, `PosSyncResultScreen`, `PosSyncHistoryScreen`, `PosErrorScreen` | `.../inventory-imports` (+ `/sample`, `/confirm`), POS connector endpoints (`/pos/providers`, `/register`, `/integrations`, `/credentials`, `/connect`, `/reconnect`, `/disconnect`, `/sync`, `/status`, `/jobs`) | Products toolbar, hub tiles |
| 6 | Reports / Insights | `/insights` | `InsightsScreen` | **`GET .../analytics/full`** | **Home *Reports & Insights*, hub tile, Account** |
| 7 | Shop Profile | `/shop-profile` | `ShopProfileScreen` | `GET/PUT .../shops/{id}/profile` | Home *Shop Profile*, Account |
| 8 | Notifications | `/notifications` | `NotificationsScreen` | `GET .../shops/{id}/notifications` | bottom nav branch 3 ("Alerts"), hub tile |
| 9 | Settings | `/shop-settings` | `ShopSettingsScreen` | `PUT .../shops/{id}/settings` | dashboard AppBar, Account, hub tile |
| 10 | Support | `/support` | `SupportScreen` | — (static help centre) | **Home → *All Features*, Account *Help & support*** |

---

## 3. GAPS CLOSED IN THIS PASS

### 3.1 Reports / Insights — was missing entirely
The backend analytics module (`backend/app/api/routes/shopkeeper_analytics.py`,
service `app/services/shopkeeper_analytics.py`) was complete but **never
called by the app**; the dashboard showed a dead *"Reports are coming soon"*
snackbar. Now:

* `lib/features/insights/domain/insights_models.dart` — full payload model
  (overview KPIs, view/click time series, top products, top searches,
  interactions, device shares, hourly distribution, inventory freshness) with
  tolerant parsing. A missing section degrades to an empty/zero model so the UI
  shows an honest empty state instead of inventing numbers.
* `lib/features/insights/data/insights_repository.dart` — one call to
  `GET /api/v1/shopkeeper/shops/{id}/analytics/full?days=N` (the backend
  requires the `dashboard:read` permission; 403 → distinct access-denied state).
* `lib/features/insights/presentation/controllers/insights_controller.dart` —
  `InsightsStatus { loading, ready, noShop, accessDenied, error }`, 7/30/90-day
  window switching, `reset()` wired into `AuthController.logout()`.
* `lib/features/insights/presentation/screens/insights_screen.dart` —
  "Reports & insights": window selector, KPI cards with backend-computed deltas,
  weekly totals, top products, searches, interactions, device shares, peak-hours
  bars, freshness score, honest empty state, error + retry.
* Route `/insights` registered and guarded (`needsShop`).

### 3.2 Orphaned features — routes existed, nothing linked to them
`/offers`, `/pos` and `/support` were registered in the router with **zero**
entry points anywhere in the app (unreachable screens). `/insights` was new.
Closed by:

* `lib/features/shell/all_features_screen.dart` — the "Main Shopkeeper Features"
  hub at `/features` (12 tiles covering the journey's 10 features: Inventory has
  its own destination and Imports / POS is three screens — *Import from Excel*,
  *Import Center*, POS). Tiles carry stable keys (`feature-tile-<id>`).
* Dashboard quick actions now deep-link for real: *Pricing & Offers* → `/offers`,
  *Reports & Insights* → `/insights`, *All Features* → `/features`.
* Account screen gained *Reports & insights*, *All features*, *Help & support*.

### 3.3 Docs / tests updated with the change
* `test/app_journey_test.dart` — journeys 1–3 (gate chain, feature reachability,
  insights data layer + screen states).
* `test/fakes.dart` — `insightsJson()` fixture (mirrors the real payload) and
  `FakeInsightsRepo`.
* `test/dashboard_test.dart` — Home assertions updated to the spec labels
  (*Pricing & Offers*, *Reports & Insights*, *All Features*).

### 3.4 Home notifications strip + Product Details (this session)
* **Home → Dashboard notifications.** `_RecentNotificationsStrip` on
  `/dashboard` shows the 3 newest notifications with the unread count and a
  *View all* link. It reads `notificationsControllerProvider` — the same single
  source of truth as the Alerts tab — so the strip and the Alerts badge can
  never disagree. Fail-soft (empty or errored → the strip removes itself) and
  skeleton-backed while loading. Verified by the `home dashboard notifications
  strip` group in `test/dashboard_test.dart` (5 tests).
* **Products → Product Details.** A product row now opens the read-only
  `ProductDetailsSheet` (pricing / inventory / catalog reference / status
  chips); *Edit product*, *Update stock* and *View history* are launched from
  there, and the availability switch writes through `ProductsController`. The
  sheet re-resolves the row by id, so it refreshes after an edit.
* **Layout fix.** The product row's trailing price/MRP/availability column
  overflowed `ListTile`'s trailing slot by 10px — now
  `FittedBox(fit: BoxFit.scaleDown)` with a shrink-wrap switch.
* **Shared label.** `notificationTimeLabel()` (in
  `notifications/domain/notification_models.dart`) is rendered by both the
  Alerts tab and the Home strip, with an injectable `now` for tests.
* **Products list pass.** The empty state is now three-way (empty catalog vs
  filters vs search) instead of telling the shopkeeper to create a first listing
  while a filter is what emptied the list; the Category and Brand filters are
  reachable from `ProductFilterSheet` (the predicate honoured them but the sheet
  never set them) and *Reset* clears the widgets and the list together; one
  search field covers name / brand / variant / SKU; images show a loading
  spinner while they decode; and the "N of M products" counter hides for an
  empty shop. Verified by `test/products_list_test.dart` (11).
* **Barcode scanner pass.** Manual barcode entry now accepts every length the
  camera and the backend accept — EAN-13 was silently rejected, which is the
  most common retail barcode and the field's own example — and strips the
  separators printed on packaging; the scan frame and its instruction no longer
  draw themselves over the camera-permission / unsupported error view; the
  "already in your inventory" conflict escape returns to the Products tab
  instead of stacking a second Products page; the camera is never restarted on
  a scanner that is closing; and the confirm button cannot be left spinning
  after a successful save. Verified by `test/barcode_scanner_test.dart` (12).

* **Re-verified:** `flutter analyze` = No issues found · `flutter test` =
  **242 passed, 0 failed**.

---

## 4. VERIFICATION (executed)

| Check | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze lib test` | ✅ No issues found |
| Full test suite | `flutter test` | ✅ **242 passed, 0 failed** |
| Journey suite | `flutter test test/app_journey_test.dart` | ✅ 19 passed |
| Analytics contract | app `ApiEndpoints.analyticsFull` ↔ backend `@router.get("/shops/{shop_id}/analytics/full")` | ✔ path, `days` query and permission (`dashboard:read`) match |

`test/app_journey_test.dart` covers:

1. **Gate chain** — signed out → Welcome; signed in without a shop → Create
   Shopkeeper Profile; signed in with a shop → Home; restricted account → gate.
2. **Feature reachability** — the feature map covers every journey destination;
   Home renders all six quick actions; the hub lists all 12 tiles; *Pricing &
   Offers*, *Reports / Insights*, *Imports*, *Import Center*, *POS*, *Support*
   and *Settings* are actually opened (not just registered).
3. **Reports / Insights** — payload parsing (KPIs, deltas, series, top products
   with the no-SKU fallback, searches, interactions, device shares, peak hour,
   freshness), window switching (`days=7` refetch), 403 → access-denied, network
   failure → error (never fake numbers), no shop → `noShop`, `reset()` clears
   cache, empty activity → honest empty state, failure → retry state.

---

## 5. REMAINING (not blocking the journey)

| Item | Why it is still open |
|---|---|
| POS integration backend | ✅ **WIRED.** The mock was replaced by the real connector flow: `pos_models.dart` / `pos_repository.dart` (server vocabulary only) + `pos_controller.dart` (load → status+history, onboarding, sync trigger, disconnect). Seven screens: hub, connection setup (register / reconnect + credential rotation), sync (FULL / INCREMENTAL), progress (server counters + poll cap), result, history (filters + row detail) and the diagnostics screen. Covered by `test/pos_test.dart` (15) + `test/pos_screens_test.dart` (14). |
| Offers list endpoint | `OffersScreen` lists are placeholders — creation is real (`POST .../offers/assign`), but there is no `GET .../offers` in the backend yet. |
| Phone-OTP UI | The service seam exists (`FirebasePhoneOtpService`, `AuthRepository.loginWithPhoneOtp`); UI stays gated by `kEnabledAuthMethods` (Google only in the MVP). |
| iOS console steps | Register the iOS app in Firebase for bundle id `com.hyperlocal.app`, drop in `GoogleService-Info.plist`, and replace the placeholder `AppFirebaseOptions.iOS.appId` — see `docs/deployment/IOS_SETUP.md`. |
| macOS-only checks | `flutter build ios --no-codesign`, `pod install`, real-device Google Sign-In. |
| Real Google Maps iOS key | Map picker needs a production iOS key before release. |
