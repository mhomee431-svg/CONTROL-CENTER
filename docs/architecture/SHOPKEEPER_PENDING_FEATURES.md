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
| **A** | **Backend fully built, app has ZERO integration** | Real endpoints exist, app screen is a mock | Shop holidays (3) — POS ✅ wired |
| **B** | **Backend built, app declares but never calls** | Endpoint constant exists in `ApiEndpoints`, unused | 9 analytics drill-downs, `profileCreate` |
| **C** | **App code written, never reachable** | 10 orphan files / 928 lines | location stack, 2 dead screens |
| **D** | **Screen exists but shows placeholder data** | UI renders a hardcoded/mock state | Offers list (POS screens ✅ real) |
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
>
> **Completed (screen inventory).** The module now carries its own seven
> screens — `pos_screen.dart` (hub, from the mock),
> `pos_connection_setup_screen.dart` (register **or** reconnect + optional
> credential rotation; a credential refusal is reported as such),
> `pos_sync_screen.dart` (FULL / INCREMENTAL scope, the server's vocabulary),
> `pos_sync_progress_screen.dart` (server counters + poll cap),
> `pos_sync_result_screen.dart`, `pos_sync_history_screen.dart` (status filters
> + row-level detail sheet) and `pos_error_screen.dart` (diagnostics, every way
> out) — plus the shared `widgets/pos_shared.dart`. Covered by
> `test/pos_test.dart` (15 tests) + `test/pos_screens_test.dart` (14 tests).
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
flutter test        # expect: 242 passed
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

---

## 10. HOME (DASHBOARD) + PRODUCTS SCREEN INVENTORY (this session)

### HOME

| Element | Implementation |
|---|---|
| Shopkeeper Dashboard | `dashboard_screen.dart` — `_HomeHeader` (greeting + shop summary: name / category / profile status), Overview stat grid, subscription card, recent updates, `_PriorityCard` "Needs attention" |
| **Dashboard Notifications** | **NEW** `_RecentNotificationsStrip` — the 3 newest notifications, unread count and *View all*. Reads `notificationsControllerProvider` (the SAME controller the Alerts tab uses), so Home and the Alerts badge can never disagree. Tapping a row marks it read through that controller, then opens the Alerts tab. |
| Quick Actions | 6 tiles: Add Product (method chooser), Inventory, Pricing & Offers, Reports & Insights, Shop Profile, All Features |

Design notes:

* The strip is **fail-soft** — nothing to report, or a failed load, removes it
  rather than adding an error to Home ("Needs attention" owns alerting).
* A `_NotificationsSkeleton` (`_NotificationsSkeleton.skeletonKey`) covers the
  loading window so Home never jumps from nothing to a full card.
* `notificationTimeLabel()` lives in
  `notifications/domain/notification_models.dart` and is rendered by BOTH the
  Alerts tab and the Home strip (`now` injectable → deterministic tests).

### PRODUCTS

| Element | Implementation |
|---|---|
| Product List | `products_screen.dart` `_ProductTile` rows, sort menu (name / price / stock / recently updated), and an "N of M products" counter that tracks the active filters (hidden for an empty shop) |
| Product Search | one field over name / brand / variant / SKU, case-insensitive, with a clear affordance |
| Product Filters | `ProductFilterSheet` (availability / category / brand / price range / recently-updated) + quick stock chips; the Category and Brand pickers are built from values present in the catalog and hide when no row has them |
| Add Product | `ProductAddMethodSheet` → manual / barcode / bulk Excel → `ProductCreateSheet` |
| Edit Product | `ProductEditSheet` (price / MRP / stock) |
| **Product Details** | **NEW** `product_details_sheet.dart` — read-only pricing / inventory / catalog reference + status chips, with *Edit product* / *Update stock* / *View history* and the availability toggle |
| Product Availability | row switch + details `SwitchListTile` → `ProductsController.setAvailability` |
| Product Image state | master image with a loading spinner, broken-image fallback and 2x decode; explicit "No image" placeholder in details; upload + local preview in create / edit |
| Empty Product State | three-way copy — empty catalog: "No products yet. Tap \"Add\" to create your first listing."; filter-only: "No products match your filters." + *Clear filters*; search: "No products match \"q\"." + *Clear search* |

### BARCODE (this session)

| State | Implementation |
|---|---|
| Barcode Permission | `CAMERA` in `android/app/src/main/AndroidManifest.xml` + `NSCameraUsageDescription` in `ios/Runner/Info.plist` (asserted by `test/ios_support_test.dart`). `_ScannerErrorView` splits *permission denied* (fix it in system Settings, then Retry) from *unsupported device* (no Retry — it cannot help) and any other init failure; manual entry is offered in every branch, so the flow never dead-ends |
| Barcode Scanner | `barcode_scanner_screen.dart` — full-screen `MobileScanner` limited to retail formats (EAN-13 / EAN-8 / UPC-A / UPC-E / Code128), scan frame + instruction card, and a duplicate-detection guard (`_isProcessing` + `stop()`) so one physical code cannot fire the resolve twice |
| Barcode Found | first detection → `BarcodeController.resolve` → `FOUND` → `BarcodeConfirmSheet` for the single match |
| Product Found | the confirm sheet: name, brand, image, `Barcode … · EAN-13`, catalog-availability badge, variant picker, price / MRP / quantity / publish → `POST /shops/{id}/products/from-barcode` |
| Product Not Found | `BarcodeNotFoundSheet` — says "Product not found", echoes the digits (a mis-scan is the usual cause) and offers *Try Again* (rescan) or *Enter Manually*; nothing is invented for a code the catalog does not know |
| Barcode Conflict | two flavours, both wired: `MULTIPLE_MATCHES` (HTTP 300 — several catalog masters share the code) → an explicit pick list; `409` (already in this shop's inventory) → "This product is already in your inventory" + *View products* |
| Manual Add after Scan | NOT_FOUND / INVALID / 503 / camera failure all offer manual entry — the AppBar keyboard affordance, the error view, the snackbar action and the not-found sheet → `ProductCreateSheet`. The create form has no barcode field on purpose (`ShopkeeperProductCreate` declares none; barcodes only enter through the scanner flow) |

### Barcode bugs fixed

1. **Manual entry rejected every EAN-13.** The pattern `^\d{8}(\d{4}(\d{2})?)?$`
   matched 8 / 12 / 14 digits and *never 13* — the most common retail barcode in
   India, the length the camera scans, the length the backend accepts
   (`VALID_BARCODE_LENGTHS = {8, 12, 13, 14}`) and the length of the field's own
   hint example (`8901234567890`), while the error copy claimed 13 was fine.
   The existing test had encoded the bug, asserting a 13-digit code was
   rejected as a "bad check digit" — the form never had check-digit logic. The
   pattern now matches the backend and the test asserts a genuinely invalid
   length. Separators printed on packaging (`890-1234 567890`) are stripped
   first, mirroring the backend's `normalize_barcode`.
2. **The scan frame was drawn over the camera-failure view.** The frame and
   "Position a product barcode inside the frame — it is detected automatically"
   were unconditional `Stack` children, so a permission-denied shopkeeper saw a
   green frame and an impossible instruction on top of "Camera permission
   needed". The overlay is now driven by the controller's error state
   (`ValueListenableBuilder`) and hidden whenever the camera failed.
3. **The 409 escape stacked a second Products page.** "View products" did
   `pop() · pop()` (sheet + scanner) then `context.push(Routes.products)` — but
   the scanner is launched *from* Products (AppBar icon and Add-method sheet)
   and from the dashboard, so the shopkeeper landed on a duplicate Products
   page (and back returned to Products again). It now closes the barcode flow
   and reselects the Products tab with `context.go`, the same call the Alerts
   deep-link uses for that destination.
4. **The camera could be restarted while the screen was closing.** The result
   sheets' teardown (`whenComplete(_resumeScanning)`) races the save/conflict
   pop, and `MobileScannerController.start()` *throws* `controllerDisposed`
   from that unawaited future. Resume is skipped when the scanner is no longer
   the top route, and the restart swallows the disposed-controller error.
5. **The confirm button stayed mid-save forever.** After a successful save the
   sheet relied entirely on the caller popping it; a caller that did not would
   leave a spinning, disabled button. It now resets its saving state before
   reporting success.

### Bugs fixed while wiring the inventory

1. **Row → Edit jumped straight into editing.** A product row now opens
   **Product Details**; every write is launched from there (view → edit).
2. **`_ProductTile` trailing overflow.** The stacked price / MRP / availability
   column exceeded `ListTile`'s 56px trailing slot by 10px — a latent layout bug
   no test had ever exercised. Fixed with `FittedBox(fit: BoxFit.scaleDown)` plus
   a shrink-wrap switch.
3. **`ProfileEditController` disposal crash.** `build()` fires an async load and a
   save can outlive the screen; writing `state` afterwards threw *"Cannot use the
   Ref ... after it has been disposed"*. Every `await` is now followed by a
   `ref.mounted` guard (in `_load` and `save`).
4. **`shop_registration_test` pipeline walk.** The test entered only a shop name
   before expecting `nextFromBusinessInfo()` to advance, but that validator also
   requires category + business type — the test now fills the required fields.

5. **Empty state blamed the shop for an empty filter.** A stock chip (or a
   price range) that matched nothing printed *"No products yet. Tap \"Add\" to
   create your first listing."* while the catalog was full. The copy is now
   chosen from what actually emptied the list, with the action that clears
   exactly that (*Clear filters* / *Clear search*). The "N of M products"
   counter is hidden when the shop has no listings at all.
6. **Category / Brand filters were unreachable.** `ProductFilterApplied`
   carried `category` / `brand` and the list predicate honoured them, but
   `ProductFilterSheet` never set them — the filter could not be applied from
   the UI. Its *Reset* also cleared the applied filter while leaving the pickers
   showing the old selections, so the next *Apply* silently re-sent them. Both
   pickers are now real (built from the catalog, hidden when empty) and *Reset*
   clears the widgets and the list in one step.
7. **Search missed SKU and variant.** Both are printed in Product Details
   (`Catalog reference`), so typing them returned nothing. One field now covers
   name / brand / variant / SKU.
8. **Image loading was invisible.** `Image.network` had no `loadingBuilder`, so
   a slow image was an empty grey box — indistinguishable from "no image". The
   row thumbnail and the details header now show a progress indicator while
   loading and decode at ~2x their box (`cacheWidth`).

### Tests added

* `test/product_details_test.dart` (9) — details rendering, no-image / stale /
  out-of-stock states, availability write path, edit entry, live re-resolution
  by id, snapshot fallback, and list → details wiring.
* `test/dashboard_test.dart` — `home dashboard notifications strip` group (5).
* `test/notifications_test.dart` — `notificationTimeLabel` (2).
* `test/fakes.dart` — `notificationFixture(...)`.
* `test/barcode_scanner_test.dart` (12) — manual entry accepts EAN-8 / UPC-A /
  EAN-13 / GTIN-14 and strips packaging separators, while a non-retail length
  or non-numeric input never reaches the backend; the not-found sheet's
  contract (echoes the code, *Try Again* + *Enter Manually*, nothing invented);
  the 409 conflict escape, price validation and the save payload.
* `test/requirements_21_27_test.dart` — the manual-entry test had asserted the
  EAN-13 rejection (labelled "bad check digit"); it now asserts a genuinely
  invalid length plus non-numeric input.
* `test/products_list_test.dart` (11) — visible/total counter; search over
  name / brand / SKU / variant; the no-match copy + *Clear search*; a filter
  that matches nothing never claiming the shop is empty; the empty-catalog copy;
  sort by name / price; Category & Brand pickers (incl. *Reset*) and the price
  range; pickers hidden when no row has them; the availability switch writing
  `is_available` and rendering the server value.

**Verification:** `flutter analyze` = **No issues found** · `flutter test` =
**242 passed, 0 failed** (single run) · backend pytest unchanged.
---

## 11. INVENTORY + PRICING + IMPORT SCREEN INVENTORY (this session)

### INVENTORY

| Screen | Implementation |
|---|---|
| Inventory Dashboard | `inventory/inventory_dashboard_screen.dart` — server stock-health summary (`stat-total-products`, `stat-total-units`, `stat-low-stock`, `stat-out-of-stock`, `stat-stale` "Needs update") plus 12 navigable hub tiles in three sections: *Stock views*, *Actions*, *Pricing & imports* |
| Inventory List | `inventory_list_screen.dart` — `InventoryScopeScreen(scope: InventoryScope.all)` |
| Low Stock | same screen, `InventoryScope.low` (rows the server marks `LOW_STOCK`) |
| Out of Stock | `InventoryScope.outOfStock` (`OUT_OF_STOCK`) |
| Inventory Freshness | `InventoryScope.freshness` — stale listings with a "Needs update" label |
| Update Stock | `update_stock_screen.dart` — **delta** adjustments via `POST /shops/{id}/products/{pid}/stock-adjustments`; +1/+5/+10/-1/-5/-10 bump chips, adjustment type (`CORRECTION` / `RESTOCK` / `RETURN` / `DAMAGE` / `SPOILAGE`) and an optional note; the confirmation panel renders the **server's** before → after quantity |
| Stock History | `stock_history_screen.dart` — `GET .../products/{pid}/history`, rendering movements, adjustments and price changes from one audit trail |
| Inventory Sync Status | `inventory_sync_status_screen.dart` — products grouped by the server `source` (`Excel import`, `Barcode scan`, `POS sync`, `Updated in app`, …) with last-update stamps |

### PRICING

| Screen | Implementation |
|---|---|
| Price List | `pricing/price_list_screen.dart` — every product with price, MRP and the implied discount; search over name / brand / SKU; app-bar entries to Price History and Create Offer |
| Update Price | `update_price_screen.dart` — opened with a product or with a picker; validates selling price / MRP (MRP can never be below the price) and PATCHes through the products controller so the list stays consistent |
| Price History | `price_history_screen.dart` — only `price_change` entries, old → new price and old → new MRP |
| Create Offer | `create_offer_screen.dart` — title, offer type, discount, validity window and the product multi-select, submitted as ONE atomic create + link (`POST /shops/{id}/offers/assign`) |
| Active Offers | `offer_list_screens.dart` — `ActiveOffersScreen` |
| Expired Offers | `offer_list_screens.dart` — `ExpiredOffersScreen`; ONE fetch feeds both tabs, sliced locally, so the two lists can never disagree |
| Offer Details | `offer_details_screen.dart` — read-only summary of one offer |

### IMPORT

| Screen | Implementation |
|---|---|
| Import Center | `inventory_import/import_center_screen.dart` — Download sample · Start new import · Import history + the recent-jobs strip |
| Download Sample | `SampleDownloadController` → `GET .../inventory-imports/sample` (raw `.xlsx`) handed to the platform save dialog |
| File Picker | `PlatformWorkbookPicker` (`file_picker`, SAF on Android — no storage permission), `.xlsx` only |
| Upload Progress | `import_upload_screen.dart` — pick → upload with in-flight progress |
| Import Preview | `import_preview_screen.dart` — summary chips (total / valid / errors) and the row-level outcomes |
| Validation Errors | the preview's error rows (`error_code — error_message`) plus the *Show only validation errors* toggle |
| Import Processing | `import_processing_screen.dart` — fires `confirm()` once and renders the outcome |
| Import Success | `import-result-success` — "N products imported." |
| Partial Success | `import-result-partial` — "N products imported, M could not be applied." |
| Import Failed | `import-result-failed` — readable reason + Retry / Back |
| Import History | `import_history_screen.dart` — past jobs and their row-level report sheet |
| Import from Excel | `inventory_import_screen.dart` retained at `/inventory-import` (single-screen pick → preview → confirm) and reachable from the hub |

### Bugs fixed (this session)

1. **Half the Inventory hub was unreachable.** The dashboard was a lazy `ListView`,
   so tiles past the viewport were never built and could not be addressed by key.
   It is now a `SingleChildScrollView` + `Column`, so every tile exists regardless
   of scroll position.
2. **The price list exaggerated every discount.** `discountPercentOff(120, 90)`
   returns `25.0`, and `'$discount% off'` printed **`25.0% off`**. It now goes
   through the shared `trimNumber()`, so whole percentages print as `25% off`
   while fractional ones keep their decimal.
3. **Update Price lost its confirmation.** The screen showed a SnackBar and then
   `Navigator.pop()`-ed, tearing down the very Scaffold the SnackBar rendered in.
   The confirmation is now an inline `update-price-success` panel that stays on
   screen (the SnackBar remains as a courtesy), so the shopkeeper keeps context
   and can keep editing.
4. **Create Offer's submit was unreachable.** The action sat at the end of a
   scrolling `ListView`, so the longer the catalogue the further it drifted — and
   a button below the fold cannot be tapped (a hit test outside the viewport
   never reaches it). The form is now a non-lazy scroll view with the primary
   action pinned in the Scaffold's `bottomNavigationBar`. The post-success
   hand-off uses `GoRouter.maybeOf(context)?.go(...)`, so the screen also renders
   standalone (previews / widget tests) instead of throwing
   *"No GoRouter found in context"*.
5. **Import Confirm was disabled for summarised jobs.** `ImportPreview.validCount`
   counted only `rows`, so a staged job that reported counters without a
   `report.rows` array looked empty and the confirm button was greyed out. Both
   `validCount` and `errorCount` now fall back to the job's own `valid_rows` /
   `error_rows`.
6. **The feature map dropped `/inventory-import`.** The hub tile had been
   re-pointed at the new Import Center, which broke the journey contract that
   "Imports / POS" reaches the *Import from Excel* screen. The hub now carries
   both destinations — `Import from Excel` (`/inventory-import`) and
   `Import Center` (`/import-center`) — so nothing is lost either way.

### Tests added

* `test/inventory_pricing_import_screens_test.dart` (22) — dashboard stats + all
  12 hub tiles; the four inventory scopes (counts, filtering, freshness labels);
  the delta adjustment and its rejection; stock-history rendering; sync grouping;
  price rows with MRP / implied discount; the price PATCH payload and success
  panel; MRP-below-price rejection; price history; the offer list / details;
  Create Offer validation-then-assign; the whole Import flow
  (pick → preview → errors-only → success, partial and queued outcomes) and
  Import History with its row-level report.
* `test/app_journey_test.dart` — the feature-map contract restored
  (`/inventory-import`) and the hub walk (POS → support → Import from Excel).

**Verification:** `flutter analyze` = **No issues found** · `flutter test` =
**270 passed, 0 failed** (single run).
