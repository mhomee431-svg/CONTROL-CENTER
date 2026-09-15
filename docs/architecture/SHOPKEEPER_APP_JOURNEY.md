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
| 1 | `status == initial \|\| isLoading` | `/splash` (auth routes exempt) |
| 2 | `unauthenticated \| sessionExpired \| error` | `/welcome` |
| 3 | `accountRestricted` | `/account-status` (only reachable screen) |
| 4 | `!profileComplete` (no shop yet) | `/profile-create` |
| 5 | shop exists, target in `needsShop` | `/shops` (or `/dashboard` when no shop) |

The router is created exactly ONCE; auth changes call `router.refresh()` (never
`ref.watch`), which is what stops the login/register bounce. Verified by
`test/register_navigation_test.dart`.

---

## 2. MAIN SHOPKEEPER FEATURES — every one reachable

`/features` (AllFeaturesScreen) is the hub that mirrors this table 1:1
(`kShopkeeperFeatures`). Each tile deep-links to the screen that owns the
feature's backend data — the hub renders no numbers of its own.

| # | Feature | Route | Screen | Backend | Entry points |
|---|---|---|---|---|---|
| 1 | Dashboard | `/dashboard` | `DashboardScreen` | `GET .../shops/{id}/dashboard` | bottom nav branch 1 |
| 2 | Products | `/products` | `ProductsScreen` | `.../products`, `.../inventory` | bottom nav branch 2, Home *Add Product* / *Inventory* |
| 3 | Inventory | `/products` | `ProductsScreen` (inventory views, stock sheets) | `.../inventory`, `.../stock-adjustments`, `.../history` | Home *Inventory*, hub tile |
| 4 | Pricing & Offers | `/offers` | `OffersScreen` (+ `OfferCreateSheet`) | `POST .../offers/assign` | **Home *Pricing & Offers*, hub tile** |
| 5 | Imports / POS | `/inventory-import`, `/pos` | `InventoryImportScreen`, `PosScreen` | `.../inventory-imports`, `.../confirm` | Products toolbar, Home, hub tiles |
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
  hub at `/features` (11 tiles covering the journey's 10 features; Imports / POS
  is two screens). Tiles carry stable keys (`feature-tile-<id>`).
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

---

## 4. VERIFICATION (executed)

| Check | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze lib test` | ✅ No issues found |
| Full test suite | `flutter test` | ✅ **128 passed, 0 failed** |
| Journey suite | `flutter test test/app_journey_test.dart` | ✅ 19 passed |
| Analytics contract | app `ApiEndpoints.analyticsFull` ↔ backend `@router.get("/shops/{shop_id}/analytics/full")` | ✔ path, `days` query and permission (`dashboard:read`) match |

`test/app_journey_test.dart` covers:

1. **Gate chain** — signed out → Welcome; signed in without a shop → Create
   Shopkeeper Profile; signed in with a shop → Home; restricted account → gate.
2. **Feature reachability** — the feature map covers every journey destination;
   Home renders all six quick actions; the hub lists all 11 tiles; *Pricing &
   Offers*, *Reports / Insights*, *Imports*, *POS*, *Support* and *Settings* are
   actually opened (not just registered).
3. **Reports / Insights** — payload parsing (KPIs, deltas, series, top products
   with the no-SKU fallback, searches, interactions, device shares, peak hour,
   freshness), window switching (`days=7` refetch), 403 → access-denied, network
   failure → error (never fake numbers), no shop → `noShop`, `reset()` clears
   cache, empty activity → honest empty state, failure → retry state.

---

## 5. REMAINING (not blocking the journey)

| Item | Why it is still open |
|---|---|
| POS integration backend | `PosScreen` is UI-only today (connect/sync are local simulations); the journey exposes it, but a real connector needs backend work. |
| Offers list endpoint | `OffersScreen` lists are placeholders — creation is real (`POST .../offers/assign`), but there is no `GET .../offers` in the backend yet. |
| Phone-OTP UI | The service seam exists (`FirebasePhoneOtpService`, `AuthRepository.loginWithPhoneOtp`); UI stays gated by `kEnabledAuthMethods` (Google only in the MVP). |
| iOS console steps | Register the iOS app in Firebase for bundle id `com.hyperlocal.app`, drop in `GoogleService-Info.plist`, and replace the placeholder `AppFirebaseOptions.iOS.appId` — see `docs/deployment/IOS_SETUP.md`. |
| macOS-only checks | `flutter build ios --no-codesign`, `pod install`, real-device Google Sign-In. |
| Real Google Maps iOS key | Map picker needs a production iOS key before release. |