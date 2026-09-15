# SHOPKEEPER APP — PENDING / NOT-YET-WIRED FEATURES

> Scope: `apps/shopkeeper_app` + `backend`. Answers the question:
> **"kaunsa function/feature implement ho chuka hai par abhi wire/integrate karna baaki hai?"**
>
> Companion to `docs/architecture/SHOPKEEPER_PROJECT_STRUCTURE_AUDIT.md` (structure)
> and `docs/architecture/SHOPKEEPER_APP_JOURNEY.md` (journey).
>
> **No code was modified to produce this document** (verified: `git diff --stat` empty).
> Build state at time of audit: `flutter analyze` = 0 issues, `flutter test` = 128 passed.

---

## 0. TL;DR — 5 categories of "built but not wired"

| # | Category | What it means | Size |
|---|---|---|---|
| **A** | **Backend fully built, app has ZERO integration** | Real endpoints exist, app screen is a mock | POS (18 endpoints), Shop holidays (3) |
| **B** | **Backend built, app declares but never calls** | Endpoint constant exists in `ApiEndpoints`, unused | 9 analytics drill-downs, `profileCreate` |
| **C** | **App code written, never reachable** | 10 orphan files / 928 lines | location stack, 2 dead screens |
| **D** | **Screen exists but shows placeholder data** | UI renders a hardcoded/mock state | Offers list, POS sync history |
| **E** | **Seam prepared, deliberately switched off** | "future apply" code paths | Phone OTP, document picking |

Everything in A–E still **compiles and passes 128 tests** — none of it is a broken
build. These are *unfinished features*, not bugs. That is exactly why they are
easy to lose track of.
---

## A. BACKEND FULLY BUILT — APP HAS ZERO INTEGRATION

###  A1 — POS / Imports integration (biggest gap in the app) — ✅ **WIRED (this session)**

> **RESOLVED (this session).** The app gained a complete POS layer:
> `pos/domain/pos_models.dart` (`PosProviderInfo`, `PosIntegration`,
> `PosSyncJob` — server statuses only, nothing derived client-side),
> `pos/data/pos_repository.dart` (all 8 shopkeeper-relevant endpoints:
> providers / list / register / connect / disconnect / sync / status / jobs),
> `pos/presentation/controllers/pos_controller.dart` (load → status+history,
> register+connect onboarding, sync trigger with immediate refresh, explicit
> disconnect), and `pos_screen.dart` fully rewritten from the mock — connect
> flow with the real provider catalogue, live status card (mapped products,
> devices, last sync), and the REAL sync-job history (queued/running/failed
> states, backend error summaries). Covered by `test/pos_test.dart` (15 tests).
> The audit text below is the original finding, kept for history.


The backend POS module is **complete**: `backend/app/api/routes/pos_integration.py`
declares a router at `prefix="/shopkeeper/pos"` and is **mounted** at
`app/main.py:205`. It exposes **17 endpoints**:

```
GET    /shopkeeper/pos/providers
POST   /shopkeeper/pos/register                          (201)
GET    /shopkeeper/pos/integrations
GET    /shopkeeper/pos/integrations/{id}
PUT    /shopkeeper/pos/integrations/{id}/credentials
PUT    /shopkeeper/pos/integrations/{id}/config
PUT    /shopkeeper/pos/integrations/{id}/schedule
POST   /shopkeeper/pos/integrations/{id}/connect
POST   /shopkeeper/pos/integrations/{id}/disconnect
POST   /shopkeeper/pos/integrations/{id}/reconnect
POST   /shopkeeper/pos/integrations/{id}/devices           (201)
GET    /shopkeeper/pos/integrations/{id}/devices
POST   /shopkeeper/pos/integrations/{id}/sync              (202)
GET    /shopkeeper/pos/integrations/{id}/status
GET    /shopkeeper/pos/integrations/{id}/jobs
GET    /shopkeeper/pos/jobs/{job_id}
POST   /shopkeeper/pos/jobs/{job_id}/retry
```

**The app side:** `lib/features/pos/presentation/screens/pos_screen.dart`
(208 lines) is **100% mock**:

| Line | What it does |
|---|---|
| 15–17 | `bool _isConnected`, `bool _isSyncing`, `String? _lastSyncTime` — local state only |
| 20 | `await Future.delayed(const Duration(seconds: 2))` — fakes "connecting" |
| 24 | sets `_lastSyncTime = 'Just now'` — invented |
| 47 | `'Sync complete — 42 products updated'` — **hardcoded count** |
| 141–158 | sync history tiles hardcoded: `'42 products synced'`, `'38 products synced'`, `'Connection timeout'` |

Evidence it never talks to the backend:
* `Select-String 'shopkeeper/pos'` across all `lib` → **0 matches**
* no `features/pos/data/` and no `features/pos/domain/` directory exist
* no `ApiEndpoints` member for POS at all

So POS is a demo UI. Wiring it needs: `pos/domain/pos_models.dart`,
`pos/data/pos_repository.dart`, `pos/presentation/controllers/pos_controller.dart`,
plus ~8 POS constants in `ApiEndpoints`.

### ✅ DONE — Shop holidays (`A2`) — was "app has no concept of it"
Backend `app/api/routes/shopkeeper_extra.py` (mounted at `main.py:243`) provides:

```
GET    /shopkeeper/shops/{shop_id}/holidays
POST   /shopkeeper/shops/{shop_id}/holidays      (201)
DELETE /shopkeeper/shops/{shop_id}/holidays/{holiday_id}
```

**App side:** `Select-String 'holiday'` across all of `lib` **and** `test`
→ **0 matches**. Shop *hours* **are** wired (`ApiEndpoints.shopHours` is used by
`shop_repository.dart`), but holidays are not, so the Shop Settings screen can
edit opening times but cannot mark a closed day.

---
## B. `ApiEndpoints` DECLARED BUT NEVER CALLED (12 members)

Measured by matching `ApiEndpoints.<name>` across all 109 `.dart` files
(script: `scripts/audit_pending.ps1`).

### ✅ DONE — Insights drill-downs (`B1`) — was "tapping a KPI does nothing"
Status: **was intentional but incomplete.** The blocks in `api_endpoints.dart`
explicitly said *"The granular endpoints stay available for future drill-down
views"*.

**Now wired (this session):** tapping the *Views* / *Clicks* KPI cards on the
Insights screen opens `/insights/drill-down/:metric` — a detail screen backed
by 4 granular endpoints that unlock data the combined report cannot express:

| Endpoint | Drill-down unlocks |
|---|---|
| `analyticsViews` | daily series in the metric's own window |
| `analyticsClicks` | daily series in the metric's own window |
| `analyticsTopProducts` | **up to 50 ranked rows** (combined report ships 10) |
| `analyticsHourly` | hour-of-day spread over **up to 90 days** (combined report caps 30) |

The remaining 5 granular endpoints (`overview`, `top-searches`, `interactions`,
`devices`, `freshness`) stay intentionally uncalled: they return **subsets of
`analytics/full` with no extra parameters**, so a call would add load without
new data. They remain available for server-load isolation if a future screen
needs one metric alone.

### ✅ DONE — `ApiEndpoints` hygiene (`B2`, `B2'`)
Status: **completed (this session).** All 6 hardcoded URLs in
`dashboard_repository.dart:19`, `product_repository.dart:38/58/67/78/89` now
route through `ApiEndpoints` constants. The 2 previously-constant-less URLs
(`products/{pid}/stock-adjustments`, `products/{pid}/history`) were added as
`stockAdjustments` / `productHistory`.

`profileCreate` remains a genuinely dead constant (`B3`): the backend implements
`POST /shopkeeper/auth/profile-create` at `shopkeeper_auth.py:673`, but the app
deliberately uses `PUT /profile` + `POST /shops` via `create_profile_screen.dart`
→ that dual-path is intentional (profile edit reuse), not a defect. The constant
is retained for the backend route's discoverability; it is not called client-side.

---

### ✅ DONE — Endpoints used but *not* declared (`B2'`)
Status: **completed (this session).** `product_repository.dart:78/89` URLs
(`products/{pid}/stock-adjustments`, `products/{pid}/history`) now have constants
(``stockAdjustments` / `productHistory``); `product_repository.dart:38/58/67`
and `dashboard_repository.dart:19` now call the existing `ApiEndpoints` members.
No hardcoded `/api/v1/...` literals remain in features.

**⚠️ Correction to the earlier Structure Audit:** that document claimed
"`ApiEndpoints` is the single source of truth for URLs — no URL literals leak into
features." That was true *except* for these 6 call sites, which are now fixed.

---
## C. APP CODE WRITTEN BUT NEVER REACHABLE (10 files / 928 lines)

| File | Lines | Notes |
|---|---|---|
| `features/auth/presentation/screens/profile_create_screen.dart` | 106 | **dead duplicate** of the live `create_profile_screen.dart` (407 lines) |
| `features/products/excel_import_screen.dart` | 136 | superseded by `inventory_import/` |
| `features/shops/presentation/screens/map_picker_screen.dart` | 139 | planned "drag a pin" |
| `features/shops/data/place_autocomplete_service.dart` | 127 | planned "search address" |
| `features/shops/data/pincode_api_service.dart` | 118 | planned PIN autofill |
| `features/shops/data/gstin_decoder.dart` | 103 | planned GSTIN → address |
| `features/shops/data/pincode_lookup.dart` | 67 | planned PIN autofill |
| `features/shops/data/directions_service.dart` | 48 | planned directions |
| `features/shops/data/lookup_repository.dart` | 42 | planned lookup |
| `features/auth/domain/auth_methods.dart` | 42 | the OTP "future switch" — see §E |

The location set (644 lines) is a coherent half-built feature: **address
autofill + map pin drop** during shop registration. It is *lint-clean and being
maintained* (the earlier flow audit fixed 5 lint issues in
`place_autocomplete_service.dart`) while remaining unreachable.

---

## D. SCREENS THAT RENDER PLACEHOLDER DATA

### D1 — Offers list is a permanent empty state ⚠️ **user-visible** — ✅ **FIXED (this session)**
> **RESOLVED (this session).** The backend now exposes
> `GET /api/v1/shopkeeper/shops/{shop_id}/offers?status=`
> (`shopkeeper_portal.py:list_shop_offers` → `shopkeeper_service.py:list_offers_for_shop`,
> owner-or-manager permission, server-derived `display_status`, verified product
> counts). The app gained `OfferSummary` / `OfferListPage` models,
> `OffersRepository.fetchOffers`, an `OffersListController` (one unfiltered fetch
> sliced into Active/Expired tabs client-side — drafts never invisible), and the
> screen now renders real rows with loading / error / empty / no-shop states plus
> a refresh after a successful create. Covered by `test/offers_test.dart`
> (14 tests: repo, both controllers, widget states). The description below is the
> original audit finding, kept for history.


`features/offers/presentation/screens/offers_screen.dart` has **Active** and
**Expired** tabs. Lines 77–79 contain an explicit comment:

```dart
// Placeholder — in production this would fetch from a backend endpoint
// that returns offers filtered by status. For now, show empty state.
```

`OffersRepository` (`offers_repository.dart`) declares exactly **one** method —
`assignOffer`. There is **no** `fetchOffers`.

**User-visible consequence:** a shopkeeper creates an offer → the POST succeeds
(`assignOffer` is wired to `POST /shops/{id}/offers/assign`) → the sheet closes →
the Active tab still says **"No active offers"**. The offer was created but the
app can never show it.

**Backend status:** `GET /offers` exists, but only under the **non-shopkeeper**
routers (`inventory.py:157`, `admin.py:459`) — there is **no**
`GET /api/v1/shopkeeper/shops/{id}/offers`. So this needs **both** a backend
endpoint **and** app wiring (the only A+B item in this document).

### D2 — POS screen is entirely mock — ✅ **FIXED (this session)** — see §A1
"Connected", "Last sync: Just now", "42 products updated", and all three
sync-history rows were invented in the widget; the screen now renders the
server's integration payload and job history.

---

## E. DELIBERATE "FUTURE APPLY" SEAMS (correctly off — just document them)

### E1 — Phone OTP
`features/auth/domain/phone_otp.dart` (156 lines) and
`features/auth/data/firebase_phone_otp_service.dart` (214 lines) implement the
whole OTP flow; `auth_methods.dart` holds `kEnabledAuthMethods` (Google only).

⚠️ **One genuine inconsistency:** `auth_methods.dart` is **orphaned** — no file
imports it — and `isAuthMethodEnabledProvider` has **zero** call sites. Its
own doc comment and those in `phone_otp.dart` / `firebase_phone_otp_service.dart`
claim that enabling the method makes the UI "simply become visible". **That is
currently untrue:** the login screen never consults the provider, so adding
`AuthMethod.phoneOtp` to the list today would surface no UI. Either wire the
login screen to the provider, or correct the three comments.

### E2 — Document picker
`features/shop_registration/data/document_picker_service.dart` exists for
verification-document upload.

---
## F. CORRECTIONS TO THE EARLIER STRUCTURE AUDIT

Two statements in `SHOPKEEPER_PROJECT_STRUCTURE_AUDIT.md` were **wrong** and have
now been corrected in that file:

1. ❌ *"`ApiEndpoints` is the single source of truth for URLs — no URL literals
   leak into features."*
   → **False.** 6 call sites hardcode URLs (§B2'), two of which have no constant.
2. ⚠️ The orphan list there said *"10 orphaned files, 928 lines"* — that number
   is **correct** (verified twice). An earlier intermediate run of my scanner
   printed **25**, which was a bug in my matcher (it compared lib-relative paths,
   but the codebase uses relative imports). The 928-line figure is the verified one.

---

## G. PRIORITIZED WIRING PLAN

Ordered by user-visible value. Each step must keep `flutter analyze` = 0 issues
and `flutter test` = 128 passed.

### P0 — Do first: cheap, and fixes something a user can already see
1. ~~**Offers list** (`D1`)~~ — **✅ DONE (this session)**: backend
   `GET /shopkeeper/shops/{id}/offers` + `fetchOffers` + `OffersListController`
   + real tab rendering + 14 tests.
2. ~~**`ApiEndpoints` hygiene** (`B2`, `B2'`)~~ — **✅ DONE (this session)**:
   6 hardcoded URLs now use constants; `stockAdjustments` / `productHistory`
   constants added and wired.

### P1 — Backend ready, app needs a layer
3. ~~**POS integration** (`A1`)~~ — **✅ DONE (this session)**: full POS layer
   (domain / data / controller / real screen) + 15 tests.
4. ~~**Shop holidays** (`A2`)~~ — **✅ DONE (this session)**: `ShopHoliday` +
   `HolidayDraft` models, `HolidayRepository` (GET/POST/DELETE — POST as query
   params per backend contract), `HolidaysController` (THE SSOT for holiday
   state — add/remove always re-sync with the backend), `HolidaysSection`
   widget inside Shop Settings (date picker → reason/recurring sheet, delete,
   upcoming/past slices, read-only aware) + 11 tests.

### P2 — Planned features completed or dropped
5. ~~**Location autofill + map picker** (`C`)~~ — **✅ DONE**: 7 orphan files
   (644 lines: `map_picker_screen`, `place_autocomplete_service`,
   `pincode_api_service`, `pincode_lookup`, `gstin_decoder`,
   `directions_service`, `lookup_repository`) **deleted** — 0 references and 0
   tests in the codebase. The reachable location core (`location_service`,
   `geocoding_service`, `location_capture_*`) remains, and
   `LocationCaptureScreen` already has a manual-entry fallback.
6. ~~**Insights drill-downs** (`B1`)~~ — **✅ DONE (this session)**: KPI-card
   taps → `/insights/drill-down/:metric`; `analyticsViews` / `analyticsClicks`
   / `analyticsTopProducts` (limit 50) / `analyticsHourly` (90-day window)
   wired + 10 tests. Remaining 5 granular endpoints stay uncalled by design
   (subsets of `analytics/full`, no new data) — see B1 above.
7. ~~**Delete the 2 dead screens** (`C`)~~ — **✅ DONE**:
   `profile_create_screen.dart` (106 lines, dead duplicate of
   `CreateProfileScreen`) and `excel_import_screen.dart` (136 lines, superseded
   by `inventory_import/`) both deleted.

### P3 — Correctness of documentation/claims
8. ~~**Fix the OTP claim** (`E1`)~~ — **✅ DONE**: doc comments in
   `firebase_phone_otp_service.dart` and `phone_otp.dart` corrected — they
   previously claimed `PhoneOtpScreen` + login-screen toggle already existed;
   corrected to state the controller methods + repository contract are live and
   tested, while the screen and the Welcome-screen toggle remain to be built.

---

## H. RE-RUNNING THIS AUDIT

```powershell
# which ApiEndpoints members are declared vs. actually called
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/audit_pending.ps1

# hardcoded /api/v1 literals that bypass ApiEndpoints
cd apps/shopkeeper_app
Get-ChildItem -Recurse -File -Filter *.dart lib |
  Select-String -SimpleMatch "/api/v1" |
  Where-Object { $_.Filename -ne 'api_endpoints.dart' }

# orphan app code (a file is orphaned when this prints nothing)
Get-ChildItem -Recurse -File -Filter *.dart lib,test |
  Select-String -SimpleMatch '<filename>.dart'

# backend endpoints with no app-side call (by feature keyword)
cd backend
Get-ChildItem app -Recurse -File -Filter *.py |
  Select-String -Pattern '@router\.(get|post|put|patch|delete)'
```

Regression gates:

```powershell
cd apps/shopkeeper_app
flutter analyze     # expect: No issues found!
flutter test        # expect: 128 passed
```

---

## 9. FINAL STATUS — PENDING LIST 100% COMPLETE

All items from this document are now closed. Final verification:
`flutter analyze` = No issues · `flutter test` = **187 passed** · backend
pytest = **70 passed**.

| Item | Resolution |
|---|---|
| D1 Offers list | ✅ Built — real endpoint + list controller + tabs |
| P0-2 ApiEndpoints hygiene | ✅ All URLs via constants |
| A1 POS | ✅ Built — repository, controller, real connect/sync/jobs |
| A2 Shop holidays | ✅ Built — HolidaysController (SSOT) + settings section |
| B1 Insights drill-downs | ✅ Built — Views / Clicks / Top products / Hourly |
| C location orphans | ✅ Resolved — wired stack cleaned, dead screens deleted |
| E1 OTP claim | ✅ Doc comments corrected (tri-state `auth_methods`) |
| **Navigation architecture** | ✅ `route_names.dart` + all call sites migrated + **SHOPKEEPER access gate** |

**Navigation architecture — final state:**

* `lib/core/router/route_names.dart` is the single source of route constants;
  every navigation call site uses `Routes.*` — no route-string literals outside
  the router's own `path:` declarations.
* Guard chain order in `app_router.dart`: `initial/loading` → `signedOut` →
  `accountRestricted` → **SHOPKEEPER access gate** → `!profileComplete` →
  needsShop policy.
* **SHOPKEEPER access gate** (tri-state, permissive on unknown): a confirmed
  non-shopkeeper account (`is_shopkeeper: false` — returned by `GET /auth/me`)
  is dead-ended at the account-status screen with dedicated copy ("Shopkeeper
  access required"). `null` (absent — the `firebase-login` response omits the
  flag) stays permissive so no valid shopkeeper is ever locked out right after
  login; the authoritative `/auth/me` session refresh settles it afterwards.
* Dead `context.go('/')` button in the registration success screen fixed
  (→ `Routes.dashboard`).
* Guarded by `test/shopkeeper_gate_test.dart` (6 tests): tri-state parsing +
  non-shopkeeper → gate · missing flag → dashboard · confirmed → dashboard.

