# SHOPKEEPER APP — PROJECT STRUCTURE AUDIT

> Scope: `apps/shopkeeper_app` (Flutter, Riverpod + go_router, feature-first clean
> architecture). **Audit only — no files were moved, renamed or deleted by this
> document.**
>
> Companion to `docs/architecture/SHOPKEEPER_APP_FLOW_AUDIT.md` (flow audit) and
> `docs/architecture/SHOPKEEPER_APP_JOURNEY.md` (journey mapping).

---

## 0. VERDICT (read this first)

**The existing structure is sound and should NOT be replaced.** It already
implements the *intent* of the recommended tree — a shared `core/` kernel plus
feature-first modules — with a discipline the generic tree would actually
destroy (every feature genuinely owns its `data/ domain/ presentation/` layers).

A blind migration to the proposed tree would be **net-negative churn**:

* Renaming `dashboard/` → `home/`, `insights/` → `reports/` + `analytics/`,
  `inventory_import/` → `imports/`, `shops/` → `business/` buys nothing and
  costs ~40 import rewrites plus every test.
* Splitting `app_theme.dart` (54 lines) into `app_colors / app_text_styles /
  app_spacing / app_radius / app_shadows` is speculative scaffolding for code
  that does not exist yet.
* Creating empty `core/errors/`, `core/logging/`, `core/connectivity/`,
  `core/permissions/`, `core/formatters/`, `core/constants/` folders produces
  the classic "empty architecture folder" smell.

**However, the audit did find 9 concrete deviations** — 4 of them real defects
(2 dead duplicate screens + **10 orphaned files totalling 928 lines**, 644 of
them an unwired location subsystem) and 5 real structural smells. Those are worth
fixing. They are listed in §4 with evidence and in §6 as a prioritized plan.
**None of them require the recommended tree.**

---

## 1. METHOD (how this was audited — reproducible)

| Step | What was measured | How |
|---|---|---|
| 1 | Full directory + file inventory (96 lib files, 13 test files) | `Get-ChildItem -Recurse` |
| 2 | **Orphan detection** — is each file imported by *any* other file? | import-path scan across all 109 `.dart` files |
| 3 | Per-feature layer conformance (`data`/`domain`/`presentation`) | directory scan |
| 4 | Loose-file detection (files at feature root, outside any layer) | directory scan |
| 5 | Route-literal duplication (24 route strings) | literal string scan |
| 6 | Location subsystem dependency graph | import graph |

Commands are recorded in §7 so the audit can be re-run.

---

## 2. ACTUAL STRUCTURE (verified)

```
lib/
├── main.dart                         45   Firebase init → dev discovery → prod guard → runApp
├── app.dart                          23   MaterialApp.router (light/dark/system)
├── firebase_options.dart             82   FlutterFire generated
│
├── core/                                  ← shared kernel (5 areas)
│   ├── auth/       firebase_auth_service.dart                 280
│   ├── config/     env_config.dart                            138
│   │               dev_backend_discovery.dart                  77
│   ├── network/    api_client.dart                            122
│   │               api_endpoints.dart                         114
│   │               api_providers.dart                          50
│   │               media_upload_service.dart                  208
│   │               token_refresh_interceptor.dart             148
│   │               token_store.dart                           176
│   ├── router/     app_router.dart                            217
│   └── theme/      app_theme.dart                              54
│
└── features/                              ← 14 modules
    ├── account/          presentation/                                    ✔ UI-only
    ├── auth/             data/ domain/ presentation/                      ✔
    ├── barcode/          data/ domain/ presentation/  + 1 loose file      ⚠
    ├── dashboard/        data/ domain/ presentation/                      ✔
    ├── insights/         data/ domain/ presentation/                      ✔
    ├── inventory_import/ data/ domain/ presentation/                      ✔
    ├── notifications/    data/ domain/ presentation/                      ✔
    ├── offers/           data/ domain/ presentation/                      ✔
    ├── pos/              presentation/                                    ✔ UI-only
    ├── products/         data/ domain/ presentation/  + 1 loose file      ⚠
    ├── shell/            2 loose files, no layers                         ⚠
    ├── shop_registration/data/ domain/ presentation/ + flat controllers/  
    ├── shops/            data/ domain/ presentation/  (11 data files)     ⚠
    └── support/          presentation/                                    ✔

test/  13 flat files (fakes.dart 823 lines, requirements_21_27_test.dart 870)
```

**Confirmed strengths**

* 10 of 14 features are *textbook* `data/ domain/ presentation/` — this is the
  strongest structural asset in the app and matches the recommendation exactly.
* Repository → Riverpod controller → screen separation is consistent; every
  backend-facing feature has a `*_repository.dart` and a `*_controller.dart`.
* URL *building* is centralised in `ApiEndpoints`. **Correction — see
  `SHOPKEEPER_PENDING_FEATURES.md` §B2':** this is not airtight; 6 call sites
  bypass it with hardcoded `/api/v1/...` literals
  (`dashboard_repository.dart:19`, `product_repository.dart:38,58,67,78,89`).
  Two of them (`…/stock-adjustments`, `…/history`) have no constant at all.
* `EnvConfig` handles 3 environments + a prod fail-fast guard; `AppEnv` is a real
  enum, not a bool. This is *better* than the proposed `environment.dart` sketch.
---

## 3. CONFORMANCE MATRIX — recommended tree vs. reality

Legend: **KEEP** = current is fine · **ADAPT** = recommendation wins, small
justified change · **GAP** = genuinely missing · **REJECT** = applying it would
be harmful churn.

| Recommended | Actual | Verdict | Reasoning |
|---|---|---|---|
| `lib/app/app.dart` | `lib/app.dart` | **REJECT** | `lib/app.dart` + `lib/main.dart` is the Flutter/`flutter create` convention. An `app/` folder holding one file adds a hop for zero gain. |
| `app/router/app_router.dart` | `core/router/app_router.dart` | **KEEP** | Already centralised; the router is infrastructure, so `core/` is correct. |
| `app/router/route_names.dart` | *(absent — literals inline)* | **ADAPT** ⭐ | Real defect — see **F5**. 24 route strings are duplicated across 10+ files. |
| `app/router/route_guards.dart` | guards inline in `app_router.dart` (217 lines) | **ADAPT (low)** | The guard chain is ~80 lines and *is* the auth state machine; separating it is optional. See **F6**. |
| `app/theme/app_theme.dart` | `core/theme/app_theme.dart` | **KEEP** | Same role, correct place. |
| `app_theme` split into colors/text_styles/spacing/radius/shadows | single 54-line file | **REJECT** | Colours/paddings are currently inline in widgets. 5 files for 54 lines is speculative. Split only *if* a design-system pass creates them. |
| `app/config/app_config.dart` + `environment.dart` | `core/config/env_config.dart` + `dev_backend_discovery.dart` | **KEEP** | Already covers 3 envs + prod guard and encodes dev auto-discovery. Richer than the sketch. |
| `core/network/` | `core/network/` (6 files) | **KEEP** | Well scoped. Matches. |
| `core/storage/` | `token_store.dart` inside `core/network/` | **ADAPT (low)** | Token persistence is a storage concern sitting in network. See **F7**. |
| `core/auth/` | `core/auth/` | **KEEP** | Matches. |
| `core/location/` | `features/shops/data/` (11 files) | **ADAPT** ⭐ | Biggest smell in the app. See **F3**. |
| `core/errors/` | `ApiException` inside `api_client.dart` | **GAP (low)** | Only one exception type exists today. Extract when a second appears — not before. |
| `core/state/` | **`core/state/system_state.dart` + `system_state_view.dart` (ADDED)** | **ADOPTED** | The REJECT trigger below was met: 6+ features hand-rolled the same error/empty views (`PosMessageView`, `_MessageView`, `ShopModuleBody`, `_ErrorView` ×5, `_AccessDenied` ×3, empty-state widgets). One file now owns the nine system states (offline, network error, server error, permission denied, session expired, unauthorized, maintenance, generic retry, empty) — copy, icon and the ONE way out — and one reusable view renders them. Transport failures are classified once in `ApiException` (`kind`, `systemState`). Pinned by `test/system_state_test.dart`. |
| `core/ui/` | **`core/ui/lazy_list.dart` (ADDED)** | **ADOPTED** | The §3 trigger was met: the products list, the four inventory scopes and the price list all hand-rolled the same `ListView` page (eager header + rows + empty state). One lazy scroll implementation now owns it — rows are built only near the viewport (a keystroke re-filters instead of re-creating every row widget), headers/footers stay eager, and the empty state renders inside the same scroll view. The card-look variant reads its corners/border/colour from `CardTheme`, nothing hard-coded. |
| `core/logging/` | `debugPrint` + `FlutterError.onError` in `main.dart` | **GAP (low)** | `main.dart` already notes "remote reporter pending". Real gap, low urgency. |
| `core/utils/` | `features/auth/data/phone_utils.dart` | **GAP (low)** | `phone_utils.dart` is the only true cross-cutting util and it is auth-specific; feature-local is defensible. |
| `core/permissions/` `connectivity/` `constants/` `widgets/` `dialogs/` `formatters/` `validators/` | *absent* (`core/widgets/` was superseded by the narrower `core/state/` — see the row above) | **REJECT (for now)** | No consumers exist. Creating them now = empty folders. Revisit when 3+ features duplicate the same helper. |
| `features/authentication/` | `auth/` | **KEEP** | Shorter, unambiguous. Rename = churn. |
| `features/home/` | `dashboard/` | **KEEP** | "Dashboard" is the product's own word for it (used in the journey spec). |
| `features/onboarding/` `profile/` | `shop_registration/` | **KEEP** | "shop_registration" is more precise than "onboarding". |
| `features/business/` | `shops/` | **KEEP** | See **F3** — the fix is *splitting out location*, not renaming. |
| `features/products/` | `products/` | **KEEP** | Matches. |
| `features/barcode/` | `barcode/` | **KEEP** | Matches. |
| `features/pricing/` `offers/` | `offers/` | **KEEP** | Offer creation *is* pricing in this domain; one module is correct. |
| `features/imports/` | `inventory_import/` | **KEEP** | More precise; also distinguishes it from barcode intake. |
| `features/reports/` `analytics/` | `insights/` | **KEEP** | One module, one backend endpoint (`.../analytics/full`). Splitting into two features over one data source would be artificial. |
| `features/shop_profile/` `settings/` | screens inside `shops/` | **KEEP** | Both operate on the same `shop_repository`; splitting would duplicate the repository. |
| `features/account/` `notifications/` `pos/` `support/` `shell/` | same | **KEEP** | Already aligned. |
| `test/` (flat) | 13 flat files | **ADAPT (low)** | See **F8**. |
| `test/integration_test/` | *(absent)* | **GAP** | No on-device E2E harness exists. See **F8**. |
  into features.
* `EnvConfig` handles 3 environments + a prod fail-fast guard; `AppEnv` is a real
  enum, not a bool. This is *better* than the proposed `environment.dart` sketch.
---

## 4. FINDINGS (evidence-backed)

Severity: **F1–F3 = real defects** · **F4–F7 = structural smells** · **F8–F9 = polish.**

### 🔴 F1 — Dead duplicate screen: `ProfileCreateScreen`
`features/auth/presentation/screens/profile_create_screen.dart` (106 lines,
class `ProfileCreateScreen`) is **imported by nothing**. The router imports
`create_profile_screen.dart` (407 lines, class `CreateProfileScreen`).

Both implement "first-time profile creation". `profile_create_screen.dart` calls
`createProfile(name:, phoneNumber:)`; the live screen additionally handles shop
creation, Google prefill and the `/dashboard` landing. This is a superseded
earlier revision left in the tree — a confusing trap (`ProfileCreateScreen` vs
`CreateProfileScreen`).

### 🔴 F2 — Dead screen: `ExcelImportScreen`
`features/products/excel_import_screen.dart` (136 lines) — imported by nothing.
Its behaviour is superseded by the dedicated `features/inventory_import/` module
(repository + controller + real backend `.../inventory/import`), which the router
uses for `/inventory-import`. The leftover screen fakes progress with `_progress`
and a `Map<String,dynamic>` stub, and is unreachable. **Also a loose file (F4).**

### 🔴 F3 — 644 lines of built-but-unreachable location code
`features/shops/` carries an entire address/location subsystem. Import-graph
result — every file below has **zero importers**:

| File | Lines | Status |
|---|---|---|
| `features/shops/presentation/screens/map_picker_screen.dart` | 139 | **orphan** |
| `features/shops/data/place_autocomplete_service.dart` | 127 | **orphan** |
| `features/shops/data/pincode_api_service.dart` | 118 | **orphan** |
| `features/shops/data/gstin_decoder.dart` | 103 | **orphan** |
| `features/shops/data/pincode_lookup.dart` | 67 | **orphan** |
| `features/shops/data/directions_service.dart` | 48 | **orphan** |
| `features/shops/data/lookup_repository.dart` | 42 | **orphan** |
| `features/shops/data/geocoding_service.dart` | 113 | reachable ✅ |
| `features/shops/data/map_providers_config.dart` | 65 | reachable ✅ |
| `features/shops/data/location_service.dart` | 388 | reachable ✅ |
| `features/shops/data/location_accuracy_config.dart` | 104 | reachable ✅ |

The **reachable** set is used by `location_capture_controller`,
`location_capture_screen` and `shop_registration_controller` — i.e. the location
step of shop setup works. The **orphan** set (map picker, place autocomplete, PIN
lookup, GSTIN decoder) is a *planned* "address autofill + drag-a-pin map" feature
that was built and never wired to a screen. The earlier flow audit even
lint-fixed `place_autocomplete_service.dart`, so it is maintained while
unreachable.

**Decision required:** wire it (add a "search address / pick on map" entry point
to the location step) **or** park it under an explicit staged path or delete it.
Leaving it as-is is the worst option: 780 lines no test touches.

### 🟡 F4 — 4 loose files sitting outside any layer
Files at a *feature root* instead of inside `presentation/`:

| File | Should be |
|---|---|
| `features/barcode/barcode_scanner_screen.dart` | `barcode/presentation/screens/` |
| `features/products/excel_import_screen.dart` | (dead — see F2) |
| `features/shell/all_features_screen.dart` | `shell/presentation/screens/` |
| `features/shell/shopkeeper_shell.dart` | `shell/presentation/widgets/` |

These are the only files in the app that break the per-feature layer convention,
which makes them exactly where a new developer will misplace future code.
### 🟡 F5 — Route strings are duplicated literals (no `route_names.dart`)
`app_router.dart` declares routes as inline literals, and 10 other files repeat
those literals when navigating. Measured duplication:

| Route | Uses | Distinct files |
|---|---|---|
| `/dashboard` | 12 | 8 (`all_features_screen`, `create_profile_screen`, `dashboard_screen`, `notifications_screen`, `shop_registration_wizard`, `shops_screen`, router, journey test) |
| `/products` | 12 | 6 (`all_features_screen`, `barcode_sheets`, `dashboard_screen`, `notifications_screen`, router, test) |
| `/shop-profile` | 7 | 6 |
| `/shop-settings` | 7 | 5 |
| `/inventory-import` | 7 | 6 |
| `/insights` | 6 | 5 |
| `/shops` | 6 | 4 |

Consequence: `context.push('/produts')` **compiles** and fails silently at
runtime (go_router logs; the user sees nothing happen). A `route_names.dart` with
`abstract final class Routes { static const products = '/products'; }` removes the
whole class of bug for ~24 constants. **Highest value-per-effort item in the audit.**

### 🟡 F6 — Guard chain embedded in the 217-line router
The 5-guard auth chain (`initial/loading` → `unauthenticated/sessionExpired/error`
→ `accountRestricted` → `!profileComplete` → `needsShop`) plus the
`alwaysOpen`/`needsShop` lists live inline in `app_router.dart`. It is
well-commented and correct, but it is *policy* (who may see what) coupled to
*routing* (which widget renders). Extracting `route_guards.dart` makes the policy
unit-testable without pumping the whole app. Optional, medium value.

### 🟡 F7 — `shops/` mixes two bounded contexts
`features/shops/` owns **shop identity** (models, repository, controller, screen,
profile, settings, verification badge) *and* **location** (11 files: GPS
accuracy, geocoding, pincode, map config). Location is infrastructure with no
knowledge of "shop", and it is already consumed by `shop_registration/` too —
which is the tell that it is not really `shops/`-local. Belongs in
`core/location/`.

### 🟢 F8 — `test/` is flat and phase-named; no `integration_test/`
13 flat files. Two are large mixed bags: `fakes.dart` (823 lines, every fake) and
`requirements_21_27_test.dart` (870 lines, named by requirement numbers rather
than feature). No `integration_test/` directory exists, so there is no on-device
E2E harness — everything is widget/unit level (which is why `flutter test` is
fast and green, but nothing exercises real Firebase/Google Sign-In, a real device
GPS fix, or a real camera scan). `docs/testing/PHASE28_REAL_DEVICE_E2E_TEST.md`
already tracks the manual equivalent.

### 🟢 F9 — Small misfilings
* `features/auth/domain/auth_methods.dart` (42 lines) is **orphaned**. It is a
  deliberate "future apply switch" (`kEnabledAuthMethods`,
  `enabledAuthMethodsProvider`, `isAuthMethodEnabledProvider`) that **no screen
  imports** — its only references outside the file are *doc comments* in
  `phone_otp.dart` and `firebase_phone_otp_service.dart`. Those comments claim
  "the UI simply becomes visible" when the method is enabled, but the login
  screen never consults the provider, so flipping the constant today would
  surface no OTP UI. Either wire the login screen to
  `isAuthMethodEnabledProvider` or correct the comments.
* `core/network/token_store.dart` is a storage concern inside `network/` (F7's
  sibling smell).
* `main.dart` installs `FlutterError.onError` with an inline `debugPrint`; there
  is no `core/logging/`.

---

## 5. TARGET STRUCTURE (adapted — this is what I recommend, NOT the generic tree)

Keep every existing name. Apply only the fixes the evidence justifies.

```
lib/
├── main.dart                       unchanged
├── app.dart                        unchanged  (do NOT add lib/app/)
├── firebase_options.dart           unchanged (generated)
│
├── core/
│   ├── auth/                       unchanged
│   ├── config/                     unchanged
│   ├── network/                    unchanged − token_store.dart (F7)
│   ├── storage/                    ← NEW, receives token_store.dart (F7)
│   ├── logging/                    ← NEW, when the remote reporter lands (F9)
│   ├── router/
│   │   ├── app_router.dart         routes reference Routes.* constants
│   │   ├── route_names.dart         ← NEW (F5)  ⭐
│   │   └── route_guards.dart         ← NEW, optional (F6)
│   └── theme/app_theme.dart        unchanged (do NOT split into 5 files)
│
└── features/
    ├── auth/            ... + presentation/screens/  (drop dead duplicate, F1)
    │                    + domain/auth_methods.dart wired or comments corrected (F9)
    ├── barcode/         presentation/screens/barcode_scanner_screen.dart   ← moved (F4)
    ├── dashboard/       unchanged
    ├── insights/        unchanged
    ├── inventory_import/ unchanged
    ├── notifications/   unchanged
    ├── offers/          unchanged
    ├── pos/             unchanged (UI-only, documented)
    ├── products/        (dead excel_import_screen.dart removed, F2)
    ├── shell/           presentation/screens/all_features_screen.dart     ← moved (F4)
    │                    presentation/widgets/shopkeeper_shell.dart        ← moved (F4)
    ├── shop_registration/ presentation/controllers/…  ← controllers/ flattened in (F4)
    ├── shops/           ← location stack extracted out (F3/F7)
    └── support/         unchanged
```

**Deliberately NOT created:** `lib/app/`, `theme/` split, `core/errors/`,
`core/utils/`, `core/constants/`, `core/dialogs/`,
`core/formatters/`, `core/validators/`, `core/connectivity/`,
`core/permissions/`. Each has zero current consumers; adding them now would be
scaffolding that rots. The trigger for each is stated in §3.

**Created since this audit** (the §3 trigger — "3+ features duplicate the same
helper" — was met): `core/state/` — the nine system states as one vocabulary
(`system_state.dart`) and one reusable view (`system_state_view.dart`). Feature
screens keep their own `*Status` enums and simply translate them; there is still
no screen per state, only two shared components inside feature screens.

The same trigger was later met for list screens: `core/ui/lazy_list.dart` — one
lazy scroll implementation (eager header/footer, viewport-built rows, shared
empty-state slot) used by the products list, the four inventory scopes and the
price list. Its search predicate is shared too:
`features/products/domain/product_search.dart` indexes each row's
name/brand/SKU/variant once per catalog, so every screen's search means the same
thing and a keystroke costs one `contains` per row instead of four lower-cased
strings.

---

## 6. PRIORITIZED PLAN

Ordered so each step is independently verifiable (`flutter analyze` +
`flutter test` must stay at **0 issues / 128 passed** after every step).

### P0 — No action
Nothing is broken: `flutter analyze` = *No issues found*, `flutter test` =
*128 passed*, backend = *70 passed*. The app ships today. This audit is about
structure quality, not corrections to a broken build.

### P1 — Mechanical cleanup, zero behaviour change (F1, F2, F4)
* Delete `features/auth/presentation/screens/profile_create_screen.dart` (dead
  duplicate; F1).
* Delete `features/products/excel_import_screen.dart` (dead; F2).
* Move 3 live loose files into their layers (F4):
  `barcode/barcode_scanner_screen.dart` → `barcode/presentation/screens/`,
  `shell/all_features_screen.dart` → `shell/presentation/screens/`,
  `shell/shopkeeper_shell.dart` → `shell/presentation/widgets/`.
* Move `shop_registration/controllers/shop_registration_controller.dart` →
  `shop_registration/presentation/controllers/` (F4).
* Rewrite the ~8 affected import paths.
* **Risk: low.** Purely path/import changes; the test suite proves it.

### P2 — `route_names.dart` (F5) ⭐ highest value
Add `core/router/route_names.dart` with 24 `static const` paths, then replace
every literal in `app_router.dart`, `dashboard_screen`, `account_screen`,
`all_features_screen`, `notifications_screen`, `products_screen`,
`product_sheets`, `barcode_sheets`, `create_profile_screen`, `shops_screen`,
`shop_registration_wizard`, `register_screen`, `reset_password_screen`.
* **Risk: low, mechanical.** Benefit: typo-proof navigation (a broken route
  currently fails silently at runtime).

### P3 — Location subsystem extraction (F3, F7)
* Move `location_service`, `location_accuracy_config`, `geocoding_service`,
  `map_providers_config`, `directions_service`, `place_autocomplete_service`,
  `pincode_api_service`, `pincode_lookup`, `gstin_decoder`,
  `lookup_repository` → `core/location/`; keep `location_capture_*` in
  `features/shops/presentation/`.
* **Then decide the orphans:** wire `map_picker_screen` +
  `place_autocomplete_service` + `pincode_*` + `gstin_decoder` into the location
  step (**recommended** — the code is already written and lint-clean), or delete
  them.

### P4 — Test layout + optional extras (F6, F8)
* Split `fakes.dart` (823) and `requirements_21_27_test.dart` (870) by feature;
  consider `test/unit/`, `test/widget/`, `test/support/`.
* Add `integration_test/` scaffold for real-device Google Sign-In / GPS / scan.
* Optional: extract `route_guards.dart` (F6); extract `core/errors/` once a
  second exception type exists.

---

## 7. RE-RUNNING THIS AUDIT

```powershell
# inventory + per-feature layer conformance + loose files
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/audit_structure.ps1

# location subsystem import graph + route-literal duplication
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/audit_routes.ps1

# a file is orphaned when this prints nothing:
Get-ChildItem -Recurse -File -Filter *.dart lib,test |
  Select-String -SimpleMatch '<path/fragment>.dart'
```

Regression gates after any change:

```powershell
cd apps/shopkeeper_app
flutter analyze          # expect: No issues found!
flutter test             # expect: 128 passed
```
