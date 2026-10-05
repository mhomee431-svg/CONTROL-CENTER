# Hyperlocal Product Discovery Platform — Changelog

## [Unreleased]

### Added
- **THE ROUTE GUARD FAILED OPEN — closed, and this was the app's single largest
  structural gap.** The redirect's shop gate ended with
  `if (!needsShop.any(target)) return null;` — allow-by-default. Counted rather
  than assumed: of **75 registered routes, 56 relied on that default**, and more
  than 30 of them were shop-scoped business screens — every inventory sub-screen,
  price list/update/history, all five offer screens, the entire Excel-import
  chain, the whole POS chain, and the insights drill-downs. A shopkeeper with
  **no shop selected** who reached one of those by deep link, a restored
  back-stack, or any future caller that forgot the guard got a shop-scoped
  screen rendering with nothing to scope it to. This is exactly the
  *"every authenticated route must be protected"* rule failing.
  - **FIX — the gate now fails CLOSED.** Every route must be deliberately placed
    in one of four buckets: `alwaysOpen` (fine with or without a shop),
    `needsShop`, `userScoped` (the account's own settings and help surfaces —
    these read no shop rows, so demanding a shop first would be wrong), or the
    auth/public set handled by earlier redirect branches. **Anything
    unclassified is denied** and sent Home, so adding a screen becomes a
    deliberate act rather than an omission someone else has to notice.
  - **PINNED — a new `page_hierarchy_test.dart` case reads the real router
    source**, slicing the actual bucket lists instead of duplicating them, and
    fails if any registered route is unclassified or lands in two buckets. I
    confirmed it genuinely bites by deleting `Routes.priceHistory` from the
    guard: the test failed and named it. A guard test that cannot fail is
    decoration.
- **PHASED-DELIVERY RULE ADOPTED — and the one phase that was actually weak,
  PERFORMANCE, is now closed.** A phase-compliance audit of the 22-phase order
  found that the app had been built with all layers in place but **without any
  measured performance work**. That phase is now done; the rest were audited
  rather than re-done, because each already has its own test coverage.
  - **THE REAL PERF FINDING — every API call paid an encrypted platform-channel
    hop.** `SecureTokenStore.readAccessToken()` is called by every repository
    before every request, and `flutter_secure_storage.read` is a MethodChannel
    into Keystore/Keychain. A screen that fires several calls at once (the
    dashboard loads alerts + notifications + products) repeated the same
    encrypted read many times per frame budget, for a value that cannot change
    between them.
  - **FIX — a read-through cache, not a shortcut.** The FIRST read still hits
    secure storage, so a cold start reads exactly what was persisted and a
    relaunched app can never invent a token; every `save*` writes through and
    `clearAll()` **evicts before deleting** (if a delete throws, memory must not
    keep serving a token the caller believes they signed out of). The security
    property is unchanged: the token was already resident in the process for the
    whole session, so nothing is held longer or less protected than before.
  - **PINNED — `test/token_store_cache_test.dart` (5), because a stale token is an
    AUTH BYPASS, not a slow read.** Re-saving replaces the cached value (the
    real mid-session token-rotation path); `clearAll()` leaves nothing readable;
    a signed-out store stays signed out across repeated reads; keys do not leak
    into each other. The `flutter_secure_storage` channel is stubbed with a real
    in-memory map, so the cache genuinely sits in front of a real
    read/write/delete pair rather than being asserted in the abstract.
  - **AUDITED AND ALREADY SOUND (no change needed):** all data-bearing lists use
    `LazyListView` (notifications, tickets, import history, products — the 32
    `ListView(children:)` sites are bounded settings/form/FAQ lists); **zero**
    synchronous file or JSON reads anywhere in `lib/`; image decoding is width-
    clamped with `gaplessPlayback`; GPS repeat-acquire does not open a second
    stream (all pinned by `memory_management_test.dart`).
- **API CONTRACT — the integration gap no unit test could catch, now closed
  (`test/api_contract_test.dart`, 4).** Every existing suite exercises behaviour
  through a **fake repository**, and a fake returns whatever it likes. The app
  could therefore be entirely green while calling endpoints the backend does not
  serve — a broken integration that surfaces only as a timeout on a real device.
  This reads the backend's committed `packages/api_contracts/openapi.json` and
  holds the app to it **without a live server**.
  - Every app endpoint must exist in the contract. The 48 literals in
    `ApiEndpoints` are normalised (`$shopId` and `{shop_id}` both collapse to
    `{}`, query strings dropped) and matched. The one non-route found —
    `/api/v1/shopkeeper/pos/jobs` — is a **base prefix** used only to build
    `posJobDetail` / `posJobRetry` (both valid); it is now a declared prefix, so
    an UNLISTED phantom route would still fail.
  - **The `/shopkeeper/*` namespace rule is now enforced, not just asserted.**
    `api_endpoints.dart` claims the app "exclusively consumes the isolated
    /shopkeeper/* module". The 8 cross-namespace paths (`/profile`,
    `/categories`, `/locations/pincode`, `/media/*`) are enumerated **with their
    justification**, so a new one has to be argued for in review instead of
    drifting in silently. A test also pins that the app never calls the
    **customer** `/api/v1/auth/*` module directly.
  - The four auth routes the whole DATA CONTRACT rests on (`firebase-login`,
    `me`, `refresh`, `logout`) are asserted present — the ownership chain is
    only as real as the routes behind it.
  - **Note on the regex:** Dart interpolation inside a string literal needs the
    `$` escaped, and a raw string plus a character class turned out to be the
    trap here; the working form builds the pattern from a `const dollar = '\$'`.
- **FINAL QUALITY GATE — the 30-point checklist audited item by item; one real
  navigation dead end found and fixed, one honest gap recorded.**
  - **THE FINDING — `/expired-offers` was an unreachable screen.**
    `ExpiredOffersScreen` was fully built and registered on its own route, but
    **nothing in the app ever navigated to it**. The shopkeeper could create an
    offer, watch its window close, and have no way to look at the history — a
    route existed, the doorway did not. This is precisely the "it compiles, so
    it's done" failure the gate exists to catch: the screen was reachable in a
    deep link and in nothing a user touches. `OfferBucketScreen` now renders an
    "Expired offers" AppBar action on the ACTIVE bucket only (omitted on the
    expired bucket so the two cannot loop), and `page_hierarchy_test.dart` gained
    **"no registered route is a dead end"**, which counts a route reachable in
    any of the three legitimate ways — an in-app `push/go`, the router's
    `initialLocation` (`splash`), or a router redirect (`profile-create`,
    `account-status`, `reset-password`, `shop-location`).
  - **VERIFIED CLEAN, WITH THE EVIDENCE:**
    | Item | Result |
    |---|---|
    | Analyzer passes | ✅ No issues found |
    | Tests pass | ✅ **1150/1150** |
    | No direct database access | ✅ no sqflite / SQL / Prisma / Mongo driver — zero hits |
    | No unnecessary AWS in Flutter | ✅ no AWS SDK, credential, or request-signing; every hit is a *comment* stating credentials never reach the client (presigned-policy upload) |
    | No hardcoded secrets | ✅ only the Firebase **client** apiKey — a public identifier by Google design, package/signature restricted, already allowlisted in `.gitleaks.toml`; the Maps key is a disabled `REPLACE_WITH_YOUR_KEY` sentinel |
    | No auth bypass | ✅ no token write outside `TokenStore`; production store is `FlutterSecureStorage` (encrypted), never plaintext |
    | No duplicate services/models/providers | ✅ **0 duplicate public types.** 12 same-named types exist, all `_`-prefixed and file-private (`_JobTile`, `_ErrorView`…) — legal Dart, not duplication |
    | No broken imports | ✅ analyzer resolves everything |
    | No major UI overflow | ✅ 320×568 (iPhone SE) viewport pinned in `ui_testing_test`; Flutter's overflow check does the asserting |
  - **WHAT I CANNOT CLAIM AS VERIFIED.** The gate is explicit that compiling is not
    completion, and roughly half its items are *runtime* claims against a live
    backend and a real device. Google Sign-In with a real Google account, the
    Firebase session round-trip, backend auth exchange, POS/Notifications where
    the backend exists, and camera/barcode on hardware are **not proven by a
    widget test** — a fake repository can return whatever it likes. What IS
    proven is the behaviour on both sides of the seam (the app sends the right
    call, parses the real envelope, and never presents a failure as success),
    but an end-to-end run against a live API on a physical device is still
    required before anyone calls this complete.
- **SCOPE BOUNDARY — `apps/customer_app` is explicitly out of scope, now
  enforced rather than assumed.** Product direction: do NOT rebuild, redesign or
  change Customer screens, and do NOT duplicate Customer features inside the
  Shopkeeper app. Only shared, technically required, backward-compatible changes
  may cross that line.
  - **VERIFIED: the Customer app has NOT been touched.** Zero changes under
    `apps/customer_app` across this whole session — every edit landed in
    `apps/shopkeeper_app` (45 files) or `docs/` (3). No Customer screen was
    redesigned, rebuilt or duplicated.
  - **THE ONE REAL COUPLING, CHECKED RATHER THAN ASSUMED.** Both apps depend on
    `path: ../../packages/shared_models`. It is **untouched** — this session
    changed nothing under `packages/`. The Shopkeeper app does not currently
    import it at all; Customer app imports its own copy of the envelope types.
    So there was no technical reason to touch the shared package, and none was
    touched.
  - **WHY A GUARD, NOT JUST A PROMISE.** The contract suites added for the
    DESIGN / BUTTON / STATE / DATA contracts are all source scans rooted
    cwd-relative to `apps/shopkeeper_app`. A scan is not an edit, but letting one
    walk `../..` would make it read Customer code and start failing builds
    there — which then tempts someone to "fix" the wrong app. `page_hierarchy_test`
    now asserts the boundary: no scan may run from inside the Customer app, and
    no scan root may be a parent path or mention `customer`.
- **BUTTON / STATE / DATA CONTRACTS — the three rules that were documented but
  unpinned, now enforced.**
  - **BUTTON CONTRACT (`test/button_contract_test.dart`, 4).** Every primary must
    have normal / pressed / disabled / loading / error-safe behaviour. Pinned
    behaviourally rather than structurally — the 79 `FilledButton`s do NOT all
    funnel through `PrimaryCtaBar`, so the contract is expressed as rules:
    `loading` swaps the label for progress copy AND disables the press, and a
    second tap can never fire a second operation. The file also reproduces the
    **violating shape** as a control (spinner that changes the label but leaves
    the button enabled, firing twice) beside the honest one (fires once), so a
    reviewer meeting that shape in production recognises it.
    **AUDIT RESULT: 48 spinner sites checked, 0 violations** — every one either
    disables `onPressed` on its busy flag or is an in-body status indicator, not
    a button. The sampled suspicious cases (`inventory_import_screen` download,
    `create_profile`, `edit_shop`, `offer_create_sheet`, `notification_preferences`,
    `pos_hub_sheets`, `sessions_screen`, `ticket_detail`) all disable correctly.
  - **STATE CONTRACT (`test/state_contract_test.dart`, 2).** INITIAL/LOADING/
    SUCCESS/EMPTY/ERROR plus SAVING/SUCCESS/FAILURE. `SystemStateView` already
    renders every state and `system_state_test.dart` already pins copy + icon +
    the one action that fixes each; what was missing was the glue rule that
    makes the vocabulary APPLY — a failed WRITE must not end in silence. The
    scan requires every controller `catch` to latch readable copy, rethrow, or
    log, with three **explicitly recognised and justified** deliberate shapes
    (best-effort teardown, optional secondary signals, documented-ignore).
    **AUDIT RESULT: 24 flagged, all 24 verified correct on reading** — logout
    teardown, `capabilities` fail-soft, alerts soft-fail, recent-searches
    best-effort. **A real bug was found in the scan itself** (not the app): the
    first version reported every handler because `} catch (_) {` closes the
    try on the SAME line, so the body reader stopped before reading anything;
    fixed to start one line deeper and to skip the closing line. That is why
    the final scan is trustworthy rather than merely green.
  - **DATA CONTRACT (`test/data_contract_test.dart`, 3).** The frontend is not
    the source of truth for authorization / inventory / price / verification /
    profile ownership. Pinned as: writes send INTENT (`quantity_adjustment: 5`),
    never client arithmetic; renders use the SERVER echo; snapshot data keeps
    its provenance. **AUDIT RESULT: 0 payload violations** — `adjustStock`
    already ships a delta and renders the server's `newQuantity`, and every
    `fromJson` read is a server echo. The first scan draft was over-broad
    (flagged 8 legitimate `fromJson`/display-string lines) and was narrowed to
    write payloads only.
  - **DESIGN CONTRACT: the last real violation found and fixed.**
    `import_processing_screen.dart` stacked TWO full-width `FilledButton`s
    ("View Results" above "Done") whenever an import produced rows — the same
    competing-CTA shape fixed on the POS screen. `Done` is now the single filled
    primary; "View Results" is an outline beside "View Errors"/"History". Pinned
    by rendered-type assertions (exactly one `FilledButton`).
  - **DESIGN CONTRACT: a DISABLED primary is still a competing CTA.**
    `pos_sync_screen.dart` rendered the bottom bar in EVERY state. With no
    connector the body already shows a filled "Go to connection setup", and the
    bar added a second filled "Start sync" — permanently disabled, because there
    is nothing to sync. Two primaries, one of them a lie: it implies an action
    the user can never take. The bar is now omitted entirely when
    `integration == null`, which is what "Primary CTA **where necessary**"
    actually requires; the existing "no connector disables the start action"
    test was rewritten as "no connector offers ONE primary" and now also asserts
    exactly one `FilledButton` on screen.
- **FULL-REPO AUDIT — every incomplete-marker, orphan, endpoint and route
  checked; real findings fixed, future-use code preserved, not deleted.**
  - **NO TODO/FIXME/HACK/UnimplementedError anywhere in `lib/`** except one
    legitimate Firebase-console note in the generated `firebase_options.dart`.
    **No skipped tests.**
  - **COMPETING CTA (real) — `import_processing_screen.dart`.** Its done state
    stacked TWO full-width `FilledButton`s ("View Results" above "Done") when an
    import produced rows. Same violating shape as the POS case. `Done` stays the
    single filled primary (it renders in every done state); `View Results` is now
    an outline alongside "View Errors"/"History". Keys and navigation unchanged.
    Pinned by rendered-type assertions in
    `inventory_pricing_import_screens_test.dart` (the partial-results test now
    requires exactly ONE `FilledButton` and an outlined "View Results").
  - **CREDENTIAL IN LOGS (real) — `auth_controller.dart`.** One `debugPrint`
    printed the first 30 characters of a live Firebase ID token, and `debugPrint`
    still runs in RELEASE builds. The rest of the chain already used
    "length only"; now this line does too. Pinned by a source scan in
    `data_ownership_test.dart` (`no log line prints a fragment of a live
    credential`), which passes over the whole fixed `lib/` and fails if any
    future log interpolates a token value.
  - **ENDPOINT CONTRACT VERIFIED — 0 real mismatches.** All 47 path literals in
    `ApiEndpoints` match `packages/api_contracts/openapi.json` (`{}`-normalised).
    The only apparent gaps were a base-prefix constant and query-string literals.
    All 79 post-exchange API calls pass a `token:`; exactly 5 omit it and all 5
    are the pre-auth set (register/login/forgot/reset/firebase-exchange), which
    must be unauthenticated by design.
  - **PRESERVED, NOT DELETED.** `lib/core/errors/api_failure_text.dart` (the one
    file nothing imports) stays intact for future render-time localization;
    `createProfile`'s whole unused vertical slice (endpoint + repo + controller)
    stays; the 5 unused granular `analytics*` endpoints and `profileCreate` /
    `pincode` stay as declared future surface. `shellTabPaths` in
    `route_names.dart` was kept but its doc comment referenced a `ShellTab`
    class that does not exist — comment corrected to reality.
  - **43 RADIUS TOKENS now tokens** (not 18 — the full count after this pass's
    POS/pricing shops fixes), every `bottomNavigationBar:` is a `PrimaryCtaBar`,
    74/74 screens wired to the router with zero raw-path `context.push/go` and
    zero `GoRoute(path: '/…')` literals, `filledButtonTheme` on both brightnesses.
- **CURRENT AUTHENTICATION UI OVERRIDE — the Sign-in screen leaked a password
  form the MVP does not offer.** The rule was *Current: Continue with Google /
  Future: Phone OTP*, enforced through one chokepoint,
  `kEnabledAuthMethods` (`googleFirebase` only), which every surface consults via
  `isAuthMethodEnabledProvider`.
  - **THE GAP.** The *links* were gated correctly — Welcome offered neither the
    phone button nor the password entry in the MVP — but `LoginScreen` itself
    was not. It rendered its identifier field, password field, Sign in button,
    "Forgot password" and "Create a new account" **unconditionally**. Since the
    `/sign-in` route stays registered on purpose (so the future re-enable is a
    one-line change), a deep link, a stale bookmark or the registration screen's
    "phone already registered" redirect could still land the shopkeeper on a
    password form the current UI does not offer — precisely the "older example
    content" the technical rules override.
  - **THE FIX — same chokepoint, nothing deleted.** `LoginScreen` now reads the
    same `isAuthMethodEnabledProvider(AuthMethod.password)` the Welcome screen
    reads, and its password block renders only while the method is enabled. With
    `googleFirebase` on, the MVP screen is Google alone. A third state is handled
    honestly rather than left as a blank screen: if *no* method is enabled it
    says so instead of rendering a dead form. Route, screen, controller, service
    seam, repository contract and all l10n strings stay intact.
  - **TESTS FIXED, NOT DELETED.** Four `LoginScreen password sign-in` tests in
    `phone_otp_login_test.dart` were asserting against the ungated form. They
    now build their container through a new `makePasswordContainer` that enables
    `AuthMethod.password` — so they test the future seam under the future
    conditions instead of failing against correct MVP behaviour.
  - **PINNED — `test/auth_otp_visibility_test.dart` (+2).** New group asserts the
    MVP Sign-in screen renders **no** password field / identifier field / submit
    / forgot link (and not even the word "Password"), and that flipping the SSOT
    restores the entire form with no widget edit — the same "prove both sides of
    the switch" pattern already used for the OTP timeline row.
- **SHOPKEEPER VISUAL REFERENCE — the primary button was styled for a widget the
  app does not use.**
  - **THE DEFECT (found by probing what actually renders, not by reading the
    theme).** `AppTheme` set `elevatedButtonTheme` to the brand style, but the
    codebase renders `FilledButton` in **79** places and `ElevatedButton` in
    **zero** — and no `filledButtonTheme` existed. So the brand style was applied
    to a button nobody renders, while every real CTA silently fell back to the
    Material 3 default: a 48dp **stadium/pill** shape at full width, not the 12dp
    rounded rectangle the contract calls for.
  - **THE FIX.** `AppButtonStyles.filled` is now the token set the app's actual
    primary uses (royal blue, 46dp, `AppRadius.mdBorder`, 15/600), wired into
    `filledButtonTheme` in **both** light and dark. `elevated` is kept for the
    rare raised surface but is no longer the primary's home.
  - **RADIUS TOKENS NOW ACTUALLY TOKENS.** 18 sites across 14 files used raw
    `BorderRadius.circular(2|6|10|14|20)` — off-scale values that made the same
    rounded rectangle look 12dp in one place and 14dp in the next. All now read
    `AppRadius.{xs,sm,md,circle}Border`, so "rounded cards" is one decision.
  - `PrimaryCtaBar` and the POS/pricing/logout migrations from the entry above
    are unchanged and still green.
- **SHOPKEEPER DESIGN CONTRACT — Top / Body / Bottom, one primary CTA, now
  enforced rather than documented.**
  - **NEW SSOT `lib/core/ui/primary_cta_bar.dart`.** A shared `PrimaryCtaBar` whose
    API cannot express a competing action: `primaryLabel`/`onPrimary` are
    **required** (a bar cannot be built with no CTA), the secondary is a
    **nullable** `OutlinedButton` (demoted by construction, never a second
    fill), `loading` disables **both** so one tap cannot start two operations
    and swaps in progress copy, and `destructive` restyles the single primary.
    There is deliberately **no `List<Widget>` slot** — a button list is exactly
    how competing primaries get back in.
  - **MIGRATED — logout confirmation, POS connection setup, POS sync, create
    offer.** Each bottom action was previously a bespoke
    `Material` + `SafeArea` + `Padding` + `FilledButton` footer hand-rolled per
    screen. The logout confirm/cancel pair additionally floated *inside the
    scrolling body*, so on a long page the actions could scroll out of reach.
  - **THE REAL VIOLATION FOUND — `pos_connection_setup_screen.dart`.** Its
    connected state stacked **two full-width `FilledButton`s** ("Sync now" and
    "back to integration") one above the other. Both read as primary, with no
    winner. Now one primary ("Sync now") + one demoted outline; the exit stays
    fully available, just not competing. Its `_syncNow` moved up to the State so
    the SAME bar owns the form's submit in one phase and sync in the other —
    the primary never moves position as the screen advances.
  - **AppBar audit.** Every `_screen.dart` rendering a `Scaffold` declares an
    AppBar, with three deliberate full-bleed exceptions: `splash_screen.dart`
    (launch surface, pre-chrome), `welcome_screen.dart` (approved auth entry),
    `account_status_screen.dart` (dead-end gate — Back would be a lie and its
    headline *is* the title).
  - **PINNED BY TESTS — `test/page_hierarchy_test.dart` (8 + 2 new adoption
    guards).** The layer scan, the `PrimaryCtaBar` single-primary guarantees
    (including "loading disables BOTH" asserted by tapping each), the API shape,
    **and now a repo-wide guard that every screen's `bottomNavigationBar:` is a
    `PrimaryCtaBar` and never hand-rolled** (`shopkeeper_shell.dart` exempt: its
    bottom layer is the tab bar, navigation not CTA). A source scan asserting
    "no `FilledButton(`/`OutlinedButton(` in these screens" backs it up. The
    scans carry a **non-empty-screen guard** so they cannot pass vacuously.
  - **POS behavior pinned, not just style** — `pos_screens_test.dart` asserts
    the connected state renders **exactly one `FilledButton` and one
    `OutlinedButton`**, that the outline is enabled, and that connecting alone
    still queues no sync — so the contract cannot be met by deleting an action.
- **CURRENT DATA OWNERSHIP — verified end-to-end and pinned by tests.** The
  declared chain is literal in the code, so this pass *confirmed* rather than
  rewrote it: Firebase proves identity → the backend verifies the ID token once
  and returns its OWN application user (access + refresh pair) → a shopkeeper
  profile → ONE business/shop, and every API call after that carries ONLY the
  backend bearer token plus the id of the one shop.
  - **WHAT WAS ACTUALLY CHECKED.** (1) The Firebase ID token is never used as
    API authorization: `ApiAuthRepository` exchanges it at
    `/shopkeeper/auth/firebase-login` and persists the *backend* pair;
    `restoreSession` re-reads `/me` with the stored backend token.
    (2) No bearer token ⇒ no call: the products and dashboard controllers throw
    the localized "not signed in" failure before touching a repository.
    (3) Every shop-scoped call names the selected business
    (`selectedShopProvider.id` → `fetchInventoryOverview(shopId…)`,
    `fetchDashboard(shopId…)`), and a selection change carries the NEW id on the
    next load — no cached id is reused.
    (4) All traffic funnels through `ApiClient`, whose `_options()` attaches
    `Authorization: Bearer <backend token>` and whose `TokenRefreshInterceptor`
    rotates it on 401 — the only two hand-rolled `'Authorization'` headers in
    `lib/features` are inside the audited multipart import repository, which is
    deliberately allow-listed.
  - **PINNED BY TESTS — `test/data_ownership_test.dart` (10).** Four layers:
    identity exchanged once (the restore path never calls Firebase), no token ⇒
    no repository call (products AND dashboard), every shop call names the
    selected id (including a re-scope to a new id and a refusal when the
    selection is cleared), and a source scan that fails the build on any new
    raw `'Authorization'` header outside the two sanctioned channels. The scan
    was verified to actually match (it reports the allow-listed import-repo
    hits), so its empty-offenders assertion is not a false pass.
  - **NO PRODUCTION CODE CHANGED.** The ownership model was already correct;
    the finding worth recording is that it was *unverified* — nothing failed the
    build if a future screen dropped the bearer token or hard-coded a shop id.
    It does now.
- **CURRENT SINGLE PROFILE OVERRIDE — one shopkeeper sees exactly one
  business.**
  - **THE SURFACES.** Under the single-shop state model the app still offered
    three multi-business affordances in the CURRENT visible flow: (a) a "Switch
    shop" button on every 403 / permission-denied state (`SystemStateView`,
    reached from the Dashboard and Products screens); (b) an Account-tab "My
    business" entry that opened the business list; and (c) the `/shops` screen
    itself, which rendered a tap-to-switch list with a selected checkmark — and
    which the router even used as a *landing* page for shop-bearing accounts
    without a selection.
  - **THE FIX — same chokepoint doctrine as the auth switch.** New SSOT
    `features/shops/domain/profile_scope.dart`: `kMultiShopEnabled = false` +
    `multiShopEnabledProvider`. Dashboard/Products gate `onSwitchShop` on it
    (their 403 stays recoverable — Products keeps Retry, Dashboard *gains* it);
    the Account tile hides behind it (the read-only `_BusinessCard` already
    shows the business; Shop profile + Shop settings own management); the
    router fallback for an unselected-but-shop-bearing account lands on
    Dashboard/Home instead of the picker; and `ShopsScreen` itself renders the
    ONE current business with no tap, no selection indicator and no
    "add another" — its setup CTA renders only when the account genuinely has
    no business (the FIRST shop, i.e. Shop Setup). NOTHING deleted: route,
    picker, controller, `listMyShops` and `SelectedShopNotifier` stay intact
    for the future one-line re-enable.
  - **SAFE UNDER THE FULL SUITE.** `SystemStateView` itself was NOT changed — its
    switch-shop capability stays for the future and for the direct widget test
    that pins it (`system_state_test.dart`); only the Dashboard/Products
    callers stop supplying the callback, which is exactly why that test and
    the suite had zero churn beyond the 7 new tests.
  - **PINNED BY TESTS — `test/single_profile_scope_test.dart` (7).** Asserts
    the switch defaults OFF, the Account "My business" entry is gone while Shop
    profile/Settings stay, `/shops` shows the one business without a switcher,
    and the full picker list-and-select (including tap → select ID 20 + router
    landing) returns when the switch is overridden ON.
- **AUTHENTICATION UI OVERRIDE — "Continue with Google" is the whole current
  sign-in surface; Phone OTP is future-only.**
  - **THE LEAK.** The auth screens were already Google-only, but the *last*
    surface that still showed OTP in the CURRENT visible flow was the
    shop-registration success screen: its "Verification Timeline" rendered an
    **"OTP Verification"** row (`commonOTPVerification`), fed by the backend
    category requirement `phone_otp`. Nothing in the app can perform OTP
    verification yet (the backend says so itself: *"No OTP UI/API/SMS exists in
    this implementation"*), so the row advertised — and, via `done: true`, even
    appeared to **complete** — a step the product cannot honour.
  - **THE FIX — same single chokepoint, no second switch.** The row is now gated
    on `isAuthMethodEnabledProvider(AuthMethod.phoneOtp)` — exactly the provider
    the Welcome / Sign-in screens already consult — and the flag is passed into
    `_SuccessStep` as `showPhoneOtpStep` (default `false`). Removing OTP from
    `kEnabledAuthMethods` therefore removes its entry point *and* its timeline
    row; adding it back restores both, with no widget edits and nothing deleted.
  - **DELIBERATE TRADE-OFF, STATED.** The backend still returns
    `phone_otp: true` for most categories; the app no longer renders it while
    the method is disabled. This is the app honouring the MVP scope, and it is
    self-reverting the moment the method is re-enabled — recorded here so the
    suppression is never mistaken for a lost contract.
  - **PINNED BY TESTS — `test/auth_otp_visibility_test.dart` (3).** Pumps the
    wizard parked on its final step and asserts (a) no "OTP Verification" row in
    the MVP, (b) the rest of the timeline (Document Verification, Approval, the
    section header) still renders — one row was hidden, not the section, and
    (c) re-enabling `phoneOtp` brings the row back. Assertion (c) is what makes
    (a) trustworthy: the harness demonstrably *can* render the row.
  - **STALE DOCS CORRECTED.** `SHOPKEEPER_PENDING_FEATURES.md` (E1) still listed
    `kEnabledAuthMethods` as `(googleFirebase, phoneOtp, password)` and
    `SHOPKEEPER_PROJECT_STRUCTURE_AUDIT.md` (F9) still called `auth_methods.dart`
    "orphaned" and un-imported. Both now describe the Google-only MVP and the
    four wiring sites (Welcome, Sign-in, `auth_widgets`, registration timeline).
  - Type-only import added (`auth_models.dart`) where the new gate needs the
    `AuthMethod` enum — `auth_methods.dart` does not re-export it.
- **Visual-reference conformance pass — the reference now wins where it was
  violated, technical rules untouched elsewhere.**
  - **AUTH — OTP and password hidden in the MVP.** `kEnabledAuthMethods` listed
    Google + phone OTP + password, so the Welcome and Sign-in screens rendered
    entry points for two methods that are *future* scope (OTP) and a *future
    profile method* (password). The reference flow surfaces Google only: the
    list now contains Google alone, and the two old tests that asserted the
    wider set — plus the "every enabled method gets an entry point" widget test
    — were rewritten to prove (a) the MVP shows Google only, and (b) the hidden
    seams still open their screens when explicitly re-enabled. Nothing was
    deleted: route, screen, service, controller, repository, session model and
    the enable-switch itself stay intact for the future one-line re-enable.
    Follow-up in this session: the two stale doc comments on `WelcomeScreen`
    ("all reachable from here") and `LoginScreen` ("with Google and Phone OTP
    offered") were corrected to say Google-only, since they described the
    pre-fix behavior.
  - **BRAND TOKENS — `tertiary`/orange wired into the theme, overlay colors
    centralized.** `scheme.tertiary` (Reports tile) had no mapping in
    `ColorScheme`, so it fell back to the Material default instead of the
    HyperLocal orange warning-highlight; `AppColors.tertiary`/`onTertiary` now
    back it in both light and dark themes. The last four raw `Colors.*`
    literals outside `core/theme/` (`Colors.black54`/`Colors.white` scrims in
    `ProductImageView`) now read `AppColors.overlayBackdrop`/`onOverlay` — the
    codebase is back to zero hardcoded colors outside the token files.
  - **SHOP CATEGORIES — static `GROCERY` literal doctrined out of scope.**
    `kShopCategories` is referenced by nothing in `lib/` — but a bare
    "choices for forms" comment invited binding a dropdown to it, which would
    ship Grocery (excluded) and hardcode codes the backend already owns. It now
    carries an explicit do-not-use warning pointing at the backend-driven
    `MerchantCategoryOption` path.
- **§118 PHASE 19 PERFORMANCE — two real image-path defects fixed.**
  - **CORRECTION to the previous audit.** It reported that the two
    `Image.network` sites were "not in a list row", so the missing disk cache was
    low impact. That was **wrong**: `ProductImageView` is rendered as the `leading`
    of every product tile (`products_screen.dart`, 48×48) and in the low-stock
    list, so network thumbnails *are* on the app's main scrolling screen. The
    consequence is that the decode fix below matters far more than first stated.
  - **BUGFIX — network images decoded at FULL source resolution.**
    The local-file branch already fell back to
    `cacheWidth ?? _decodeWidthFor(context)`, but the **network** branch passed a
    bare `cacheWidth` through. Callers that omit it (3 of 6 — including the
    product list and the details sheet) therefore decoded a server photo — up to
    2000px wide — at source resolution for a 48dp thumbnail, and that bitmap then
    occupied the image cache for the life of the screen. Both branches now share
    one rule.
  - **BUGFIX — thumbnails blanked out on every refresh (`gaplessPlayback`).**
    Used **0 times** in the codebase. Because the backend serves **presigned
    URLs**, the URL string rotates on each response even though the picture is
    unchanged; Flutter treats a changed provider as a brand-new image, so every
    pull-to-refresh dropped the decoded frame and flashed the loading placeholder
    across the whole product list. `gaplessPlayback: true` now keeps the last
    frame on both the network and file branches.
  - Deliberately **not** applied to `barcode_sheets.dart`: there each scan is a
    *different* product, so holding the previous frame would show product A's
    photo while product B loads — worse than a momentary blank.
  - **On adding `cached_network_image`: rejected, with reason.** A URL-keyed disk
    cache cannot help here — presigned URLs change per response, so every lookup
    would miss while cached entries accumulated under ever-changing keys. Disk
    caching would need a stable object-key as the cache key, which is a backend
    contract question, not a client dependency to bolt on.
  - Both fixes are pinned by tests that were verified to **fail before** the
    change (`Actual: NetworkImage`; `Actual: <false>`) and pass after. The decode
    assertion derives its expected width from the binding's device pixel ratio
    rather than hardcoding it, so it does not encode the test environment's DPR.
- **§138 NO BROKEN FLOW RULE — one undefined flow found, resolved architecturally,
  then pinned by tests.** `test/flow_contract_test.dart` (12).
  - **THE FINDING — back press had NO defined answer anywhere in the codebase.**
    A precise search for back-navigation tests returned nothing: every earlier
    match for "back" was the word "falls back", a different thing. The shell used
    `StatefulShellRoute` with **no `PopScope`**, so pressing back on the Products,
    Alerts or Account tab popped the whole shell and **exited the app** — the
    shopkeeper lost their place, silently, mid-task.
  - Per the rule, the architecture was resolved *before* any test was written:
    `ShopkeeperShell._withBackContract` now wraps the shell in a `PopScope` with
    `canPop: currentIndex == 0`, giving three defined answers — a pushed route
    pops normally, a **non-first tab returns to the first tab**, and the first
    tab exits. It sits on the *shell*, so a future tab inherits the behaviour
    instead of re-deciding it. Verified against a real `GoRouter`, not a double.
  - The write contract is pinned end-to-end on "adjust stock", the app's most
    frequent write: the API receives the real shop id and token (**Q2**); success
    shows the **server's** post-update quantity, not the client's arithmetic —
    12, not the locally computed 15 (**Q4**); a failure keeps the backend's
    wording so a 422 still names the field (**Q5**); a network failure cannot
    leave a lying row, because the row is only ever swapped on success (**Q7**);
    a 403 becomes its own `accessDenied` state rather than a retry loop (**Q8**);
    a repeat cannot duplicate the write (**Q9**); and **after a restart** the
    failed write does not survive as "saved" — the quantity is the server's
    (**Q10**). **Q1** is enforced structurally: no screen may navigate with a
    hard-coded path literal, which is a route that rots silently.
- **§137 SECURITY TESTING — one real credential leak removed, and six
  prohibitions turned into build-failing guards.**
  `test/security_testing_test.dart` (21). Five of the six rules are assertions
  about an **absence**, and an absence is not something a behavioural test can
  prove — a fake repository returns whatever it likes. So the suite is built on
  a **comment-stripped scan of `lib/`** plus behavioural tests for the two
  "trusts" items. Comment stripping is what makes it trustworthy: the codebase
  *documents* where to obtain a Google key and the backend is full of AWS code,
  so raw-text matching would drown in false positives.
  - **BUGFIX (security) — `mapplsClientSecret` was compiled into the app.** A
    Mappls OAuth *client secret* was declared in `map_providers_config.dart` as a
    `--dart-define` constant and then read **nowhere** in `lib/` or `test/`. A
    secret shipped inside an APK/IPA is not a secret — it is extracted by anyone
    who unzips the build. Removed, together with its unused `client_id` half,
    and replaced with a comment explaining why the token exchange belongs on the
    backend. No build script passed either define, so nothing broke.
  - Guards added for: no AWS credential/SDK symbol and no client-side request
    signing; no Firebase **Admin** SDK or service-account credential (the *client*
    SDK is allowed and is what the app uses); no database driver, DSN, wire
    protocol or raw socket; and an **outbound-host allowlist** so an exfiltration
    endpoint cannot be added by accident.
  - **The scans were deliberately narrowed after they proved too blunt.** A
    first pass flagged three things that are all correct, and a rule that cries
    wolf gets ignored: the POS connector's `apiSecret` is a *transit* field
    forwarded to the backend, never persisted (now pinned as such); the
    `AIzaSyD-REPLACE_WITH_YOUR_KEY` sentinel is a placeholder that *disables* the
    Maps provider (now asserted to); and `user?.role != null` decides whether to
    **draw** a role badge, which grants nothing. The rule now forbids only a role
    compared against a *privilege* string, and only `isOwner`/`isManager` used as
    a capability gate — `permissions.contains(...)` stays the single sanctioned
    gate, and an empty permission list fails closed even for an `owner`.
- **§136 NETWORK TESTING — the eleven conditions, at the behaviour layer.**
  `test/network_testing_test.dart` (13). `SystemStateSpec.classify` already maps
  every status correctly, and `system_state_test` pins that mapping — so this file
  deliberately does NOT re-assert it in isolation. What was genuinely untested is
  what a real screen-level read *does* with each answer, and what latency does:
  - **Fast** — a prompt response lands as data with no error and no spinner.
  - **Slow** — *a slow-but-successful response stays `loading` and is never
    mistaken for a failure.* This is the whole point of the case: showing an
    error (or, worse, an empty list) while the request is still in flight tells
    the shopkeeper their inventory is gone. A silent pull-to-refresh likewise
    keeps the existing rows on screen instead of blanking them.
  - **Offline / reconnect** — the app's own copy, never Dio-speak, and never a
    fabricated empty catalog; a failure is transient state, so the same read
    succeeding again clears it along with the stale message.
  - **500 / 401 / 403 / 404 / 409 / 422** — each reaches its own state with its
    own fix. Server-explained failures keep the backend's wording (a 422 that
    names `price` is useless if the field is stripped); **403 is the one status
    that changes the state enum** rather than only the message, because "you may
    not see this shop" is not retryable.
  - **Timeout** — classified as a timeout and explicitly *not* as offline: "turn
    on Wi-Fi" and "the server is slow, retry" are different instructions.
  - A closing invariant across all eleven: **no failure may ever present as a
    successful empty catalog.**
  - The 401 and timeout cases build their exceptions through
    `ApiException.fromDioError` — the path production actually takes — since a
    hand-built `ApiException` keeps whatever message it was given and would make
    the sanitisation assertions pass for the wrong reason.
- `FakeProductRepo.overviewError` — thrown verbatim by `fetchInventoryOverview`,
  following the same convention as `uploadError` / `confirmError` / `listError`.
- **§135 UI TESTING — two real overflow bugs found, and one architectural finding.**
  `test/ui_testing_test.dart` (13) verifies the checks that were genuinely
  uncovered. Overflow, clipping and small-device compatibility are the cheapest
  things to leave untested, because nothing fails until a phone is narrower than
  the test viewport — and every existing suite pins 1080×2400 or 1200×2400. These
  pin **320×568** (iPhone SE) and let Flutter's own overflow check do the
  asserting: a RenderFlex that does not fit THROWS, so a regression fails the
  test rather than shipping yellow-and-black stripes.
  - **BUGFIX — the product row overflowed a 320dp phone by 13px.** The stock
    line's `Text`s (the stock word plus the stale/fresh badge) had no
    `overflow: TextOverflow.ellipsis` and no `Flexible`, so the `Row` claimed
    their full intrinsic width. Every neighbouring text in the same tile —
    name, brand, variant — already had `maxLines: 1` + ellipsis; this row was the
    one that did not. Both labels are now flexible and ellipsise.
  - **BUGFIX — the quick-actions row overflowed by a further 9px.** "Stock",
    "History" and a "by \<user\>" attribution were laid out in a `Row` with a
    `Spacer`. A `Row` cannot give ground, so the attribution had nowhere to go on
    a narrow phone. It is now a `Wrap`, which flows onto the next line instead —
    and it also ellipsises a long user name.
  - Dark mode is wired (`theme`/`darkTheme`/`themeMode` plus a settings picker),
    so §135's "dark/light behavior only if implemented" is IN scope: the products
    list is rendered in both, and `AppTheme.dark()` is asserted to be a genuinely
    different theme rather than `light()` renamed.
  - **FINDING (reported, not changed): the app's typography has a RUNTIME NETWORK
    DEPENDENCY.** `AppTypography.base = GoogleFonts.interTextTheme()` and Inter
    is NOT declared under `fonts:` in `pubspec.yaml`, so google_fonts downloads
    it from Google's CDN on first use. Consequences: (a) no widget test can
    render the app's real theme — the failure is fatal, which is why every other
    suite pumps a bare `MaterialApp`; (b) on a first launch with no connectivity,
    or wherever `fonts.gstatic.com` is unreachable, the app falls back to the
    platform font. Bundling the TTFs is a product decision (size/licensing), not
    a test change, so the layout tests here render with the platform theme and
    carry that caveat explicitly.
  - Also covered: the software keyboard (a `viewInsets` the test raises over the
    bottom half — a keyboard layout nobody has ever rendered otherwise), loaders
    that always resolve (a `pumpAndSettle` that returns is itself the assertion,
    plus bounded Dio timeouts), and an impatient double-tap on Save producing
    exactly ONE adjustment.

### Added
- **§134 PERMISSION TESTS — the cross-cutting invariant, which had no coverage.**
  `test/permission_test_cases_test.dart` (12) walks the five named cases — camera
  denied, camera permanently denied, location denied, location unavailable,
  notification denied — and, more usefully, asserts the section's actual rule on
  each one: *"Every permission denial must have a usable alternative where
  possible."*
  Each named case was already covered by its own module's suite
  (`permission_flows_test`, `location_permission_flow_test`,
  `notification_permission_test`). What was NOT covered is the invariant across
  gates, and that is the part that rots: a screen can quietly drop its
  manual-entry button and every existing test still passes, because each one
  only ever inspected its own screen. These assert the same contract on a
  different gate each time — manual barcode entry (denied AND permanently
  denied), map-pin + manual address (denied, permanently denied, and GPS radio
  off), and the always-on in-app Alerts tab (notifications denied and blocked).
  Beyond presence, the alternatives are asserted to WORK: tapping "Choose
  Location on Map" reaches a confirmable, GPS-free pin that claims no invented
  accuracy, and "Check Again" picks up a grant made in the system settings.
  Also pinned while auditing: a permanent denial never re-asks the OS (it can
  only ever be refused again), a policy `restricted` state is handled as a
  permanent denial and never prompts at all, and an unreadable platform status
  is reported as "Unknown" rather than "Not allowed" — otherwise a desktop/web
  build would nag for a grant it can never obtain.
  **No production change was needed:** all five cases were already correct.

### Added
- **§133 IMPORT TEST CASES — dedicated suite, and three real bugs it found.**
  `test/import_test_cases_test.dart` (24) covers every case the spec names:
  valid file, invalid file, cancelled picker, empty file, large file, duplicate
  barcode, invalid category, invalid price, partial success, server failure,
  retry. Three of them were broken, and the first is the worst bug this audit
  has found:
  - **BUGFIX — the import preview showed NO ROWS at all in production.** The
    row array arrives under a different key per endpoint:
    `create_import` (POST) returns it as `"preview"`, `get_import_preview` (GET)
    returns it as `"rows"`. Only the GET shape was parsed. Since the shopkeeper
    lands on the preview via the POST, `preview.rows` was always empty, the
    screen fell back to the job counters and rendered **"No rows found in this
    file"** while the counters beside it said otherwise. That silently erased
    the entire per-row surface spec §41/§42 require. Both shapes are now read.
  - **BUGFIX — re-uploading the same file imported the PREVIOUS job's rows.**
    The backend deduplicates on file content and returns the earlier job with
    `idempotent_replay: true` (`excel_import_service.create_import`). The app
    ignored the flag completely, so a shopkeeper who corrected a workbook and
    re-uploaded it was shown the old job's rows as though they were the file just
    picked — and "Apply valid rows" applied the old staged rows. The preview now
    parses the flag and says plainly that these are the earlier import's rows.
  - **BUGFIX — `error_field` was dropped, so no error named a cell.** The
    backend sends which column was rejected (`barcode`, `price`, `mrp`, `row`),
    and spec §42 requires "Row number / Field / Error". The field was parsed
    nowhere, so a shopkeeper saw a bare code (`NEGATIVE_PRICE`) with nothing
    pointing at the cell to fix. It now leads the row's error text.
  - **§41's "Duplicate Rows" count was missing.** The backend already tags
    repeated lines `DUPLICATE_ROW`, which makes the fourth number computable; it
    is now shown as its own chip. It is a *breakdown* of the error count, not an
    extra bucket, and it is omitted entirely when the payload carries no row
    detail — a summarised large import must not display a "0 duplicates" the app
    cannot vouch for.
  - The remaining cases were already correct and are now pinned: the file-level
    rejections (wrong extension, non-`.xlsx` magic header, `EMPTY_FILE`, the
    10 MB cap) are enforced by the backend and their reasons reach the shopkeeper
    verbatim instead of a flattened "Upload failed"; cancelling the picker is
    silent and idle, and never disturbs a preview already on screen; an upload
    never applies rows on its own (§40); a partial result keeps its failed count
    (§43); and a failed confirm keeps the staged job so Retry re-applies without
    re-picking the file. `fakes.dart` gained mutable `uploadError` / `confirmError`
    so a test can fail one call and let the other succeed — the retry shape.
  - **Reported, not faked:** "invalid category" cannot be implemented on this
    side. The backend's import pipeline has no category column at all — no
    column mapping, no validation, no category in `_preview_row` — so a category
    can never be invalid and §41's Category column has nothing to read. Adding
    it is a backend change (column mapping, row validation, sample workbook).
    Rather than invent a client-side category check the server cannot honour,
    this is flagged rather than faked.

### Added
- **§132 PRICE TEST CASES — dedicated suite, and three real bugs it found.**
  `test/price_test_cases_test.dart` (22) covers every case the spec names, one
  group each: valid price, zero, invalid negative price, decimal handling,
  price conflict, offer validation. Two rules the tests exposed:
  - **BUGFIX — Update Price rejected a price of zero.** The screen kept a
    private copy of the validation and used `price <= 0` / `mrp <= 0`, while
    §36 says "Selling Price >= 0 / MRP >= 0", the backend schema says `ge=0`,
    and the app's own shared `ProductFormRules.price` allows zero. So a product
    that could be CREATED at ₹0 could never be edited back to ₹0 — the two
    screens disagreed about the same product. The screen now delegates to the
    shared rules + `productFormErrorText`, which also deleted the duplicated
    copy and routed three hardcoded English error strings through the catalog.
  - **BUGFIX — a typed negative price was silently saved as positive.** The
    price/MRP fields here used the sign-free `NumericInput.decimal()`, while the
    create sheet deliberately uses `decimal(allowSign: true)` with a comment
    explaining that the field must be able to *hold* `-5` so the validator can
    explain the rejection. On Update Price the minus was swallowed instead:
    typing `-50` showed `50` and saved **+50**. Both fields now match the
    create sheet, and the shared rule reports "Price cannot be negative".
  - **Dead branch — `OfferValidators.discount` never reported a negative flat
    discount.** `value <= 0` returned "is required" first, so the following
    `value < 0` check was unreachable and a shopkeeper who typed `-50` was told
    they had simply not filled the field in. The two are different mistakes, so
    they now say different things (a ₹0 discount is still treated as "not
    filled in", since it saves the customer nothing).
  - The remaining cases were already correct and are now pinned rather than
    assumed: a fractional price round-trips intact, money is capped at two
    decimals at the keystroke, `trimNumber`/`moneyLabel` render without
    float noise (29.90 reads as "29.9"), the implied discount is rounded rather
    than repeating, an MRP *equal* to the selling price is not a conflict (only
    undercutting is), a server-side conflict reaches the shopkeeper verbatim, and
    offer validation (percentage ≤ 100, positive flat/promo values, both dates
    present with the end after the start) is wired into both entry points.

### Added
- **§131 INVENTORY TEST CASES — dedicated suite, and two real bugs it found.**
  `test/inventory_test_cases_test.dart` (17) covers every case the spec names,
  one group each: stock increase, stock decrease, zero, negative, large number,
  **concurrent update response**, stale inventory, network failure. Two of them
  were broken:
  - **BUGFIX — a stock write could race itself and roll the row backwards.**
    The read paths were carefully generation-guarded (`_generation`, plus
    `if (shopId != _shopId) return;` on refresh), but `adjustStock` guarded
    nothing. Two saves in flight — the shopkeeper taps Save on +5, then on +3 —
    and if the second response landed first, the superseded first one then
    repainted the row with its own older arithmetic, silently undoing the
    second edit. A per-product write sequence (`_writeSeq` / `_latestWrite`,
    mirroring the existing read guard) now means a superseded response is
    dropped. The same guard covers the shop-switch case, and `reset()` clears
    the slots so a pre-logout write cannot patch the next account's catalog. A
    superseded response still reports `ok: true` — the write *did* succeed, it
    is only stale, and calling it a failure would be a lie. A superseded
    *failure* is equally prevented from painting its error over a newer success.
  - **BUGFIX — a manual stock update left the row flagged STALE.** The
    `copyWith` after a successful adjustment never touched `freshnessStatus`,
    so a listing the server had marked stale kept reading "Stale - needs a
    refresh" immediately after the shopkeeper fixed it by hand. The server
    reaches the right tier (`compute_freshness(now, MANUAL)` →
    `RECENTLY_UPDATED`) but does not send `freshness_status` on that response,
    and the client is not guessing: it just performed the write itself, which is
    the freshest data the platform holds.
  - The remaining cases were already correct and are now pinned rather than
    assumed: the server's post-update quantity/status is adopted verbatim and
    never recomputed client-side (§31 "backend remains authoritative"); a zero
    delta never reaches the network; a negative *delta* is a legal decrease
    while the *result* floor is the server's; the 999,999 cap matches the
    backend's `le=999_999` and an oversized write is refused with the server's
    message without corrupting the row; and every failure keeps the row and the
    shopkeeper's numbers intact.
  - `fakes.dart` gained `adjustStockGates`, a per-CALL gate indexed by call
    order. The existing single `overviewGate` could only stall every call at
    once, which cannot express one response overtaking another — the exact
    shape the concurrency case needs.

### Added
- **Deactivate / reactivate a product — the spec's one destructive write that
  did not exist.** §74 lists "deactivate product" among the actions that must
  confirm and explain their impact, and §75 requires Deactivate/Archive
  (never a hard delete) when history must survive — but nothing in the app could
  write it. The read side was already complete (`isDiscontinued`,
  `StockStateView.discontinued`, `ProductQuery.stockDiscontinued` and the
  Discontinued inventory slice) and so was the backend
  (`PATCH /shops/{id}/products/{pid}` with `{"status": ...}`, against a
  `ShopProduct` that carries a `SoftDeleteMixin`), so the gap was a missing
  client write, not a missing capability.
  - `ProductsController.setListingStatus` performs the write through the
    existing `_patch` path, so the server's own row is swapped into the catalog
    in place (one source of truth — never appended beside the old row) and a
    refusal leaves the catalog untouched with the backend's wording in
    `ProductsState.message`. It deliberately does **not** bundle
    `is_available`: availability is a free visibility switch, while this is the
    lifecycle decision the confirmation is asking about.
  - The action lives on the Product Details sheet behind an `AlertDialog` that
    names the product and states that price/stock history is kept and nothing is
    deleted. Cancel writes nothing at all. Reactivate asks nothing — it is not
    destructive, and re-prompting would only train tap-through on the
    confirmation that matters. A refused write shows the backend's own sentence
    and is never announced as a success (§74 + the never-lose-an-update rule).
- **§74 applied to the two destructive actions that skipped it.** The spec
  lists "remove offer" alongside "deactivate product", and requires every
  destructive action to "show confirmation. Explain impact clearly" — but only
  logout (a dedicated screen) and disconnect POS (an `AlertDialog`) actually
  did. The other two acted on a single tap:
  - **Disabling an offer** fired `PATCH .../offers/{id}/status` immediately,
    pulling a live discount out from under a customer with no undo. It now
    confirms first, naming the offer and stating that the linked products stay
    and the offer is not deleted. Re-activation still asks nothing — it is not
    destructive, and re-prompting would only train tap-through on the
    confirmation that matters.
  - **Removing a holiday** issued a real `DELETE` on the first tap, from a
    dense list where a stray finger lands easily, and it changes what CUSTOMERS
    see (the date stops counting as a closure day and the shop is advertised as
    open instead). The confirmation says exactly that, and names the date,
    because two holidays can share a label like "Every year".
  Tests: `offers_test.dart` (+2, and the two existing disable tests updated to
  confirm), `holidays_test.dart` (+3) — each pins that asking writes nothing
  and cancelling leaves the row in place.
- **BUGFIX — a deactivated listing rendered as "Active".** `ShopProduct.status`
  and the `is_active` boolean are two server fields describing one thing, and a
  deactivate PATCH leaves them disagreeing: the backend sets `status` and never
  touches `is_active`. Both the details-sheet chip and its "Listing status" row
  read `is_active` alone, so a listing the Discontinued slice was calling
  discontinued simultaneously claimed to be Active. New `ListingStateView` +
  `ShopProductItem.listingState` reconcile them in ONE place — the same shape
  as the existing `stockState`, which already merges `stock_status` and
  `status` — and an unknown future status humanises instead of throwing (§126).
- **BUGFIX — `ShopProductItem.copyWith` hard-copied the listing lifecycle.**
  `status` and `isActive` were passed straight through while every other field
  used `?? this.x`, so the stock path's `copyWith` could silently resurrect a
  discontinued listing as an active one. Both are now nullable parameters
  (alongside `mrp`, which had the same bug and ignored any override).
  Tests: new `test/product_deactivate_test.dart` (12) — field reconciliation,
  forward-compatible unknown statuses, the copy guard, the controller write
  (payload, no availability bundling, refusal handling), and the full
  confirm / cancel / refuse / reactivate sheet contract.

### Added
- **CAPABILITY ENTITLEMENTS COULD BE SERVED FOR THE WRONG SHOP.** The one
  controller every screen gates off — POS, Excel import, offers, reports — wrote
  its result unconditionally. Two real failure modes, both invisible until they
  happened:
  - **A stale read won.** Switching shops mid-refresh is ordinary, and the two
    `GET .../capabilities` requests can land out of order. The older shop's
    answer was written last, so the shopkeeper kept seeing the previous shop's
    plan. Worse than a cosmetic bug: a shop WITHOUT the offers entitlement could
    be shown the entitled shop's flags, and the reverse locks a paying shop out
    of features they bought. Only the most recent read may publish now.
  - **Logout did not cancel an in-flight read.** Signing out cleared the flags,
    but a request that was already resolving could write them back afterwards —
    the previous account's entitlements surviving into the next session, which
    is precisely what `reset()` exists to prevent. `reset()` now forgets the
    in-flight read too.
  - **Duplicate round trips removed.** Resume, reconnect and pull-to-refresh all
    fired this concurrently — each an identical request whose answer was already
    pending. The guard keys on the **shop id** rather than a plain bool, so a
    genuine shop switch is never dropped.
  - **PINNED — `test/capabilities_controller_test.dart` (4).** The fake client
    can `hold()` a response and `release()` it later, which is what turns an
    out-of-order completion from a flaky race into something reproducible.
    Confirmed both guards bite: removing either one fails the suite. The logout
    test deliberately establishes a NON-default state before `reset()`, because
    the permissive default is `true` and asserting only after reset would pass
    even if the guard were gone.
  - **A trap worth naming:** these flags default to `true` (permissive, so an
    absent block never locks a shopkeeper out), which means a fixture using the
    wrong key case would read as "fully entitled" and pass for the wrong reason.
    The keys are camelCase, confirmed against both `openapi.json` and
    `entitlements.py`, and the fixture says so.
- **BUSINESS CATEGORY: ONE SOURCE OF TRUTH, PINNED TO THE BACKEND REGISTRY.**
  The spec is explicit that the eleven approved categories must come from a
  single source, must not be re-typed into registration / shop profile / product
  forms / filters / dashboard / reports, and that Grocery / General Food / Food
  Delivery must not appear. The app was doing none of that: the create-profile
  picker and the dashboard label switch each carried their own private copy of
  all eleven names — while the backend's own contract for that screen states
  *"The wizard renders exactly what this returns — no category codes are
  hardcoded in the Flutter app."*
  - **Both duplicate lists removed.** `BusinessCategory` +
    `kBusinessCategoryFallback` + `kBusinessTypes` + `businessCategoryLabel()`
    now live in `shops/domain/shop_models.dart`, and the two screens delegate to
    them. `humanizeCode` was deliberately KEPT — it is a generic enum-value
    formatter still used for verification status and membership — and
    `businessCategoryLabel` layers the canonical names on top, so a category
    renders as `Pharmacy & Healthcare` rather than `Pharmacy healthcare`.
  - **A copied list cannot enforce the rule by itself — it only fails once
    somebody notices.** `test/business_category_test.dart` (11) reads
    `backend/app/models/merchant_category.py` from disk and compares: the app
    list must be exactly the registry (no extra code, which would offer a
    category the server rejects; no missing one, which would block a legitimate
    business), every display name must match verbatim, sort order must be dense,
    no grocery/food/delivery code may appear, the submitted value must be the
    CODE rather than the label, and **no file in `lib/` outside
    `shop_models.dart` may contain a category-code literal at all**.
    Mutation-checked: adding `GROCERY` to the backend registry fails the suite,
    so the two cannot drift.
  - **Business category and product category remain separate concepts**, which
    the taxonomy already modelled: business category is the merchant registry,
    while product taxonomy is the parent/child tree from
    `GET /api/v1/categories` (`category_taxonomy.dart`). Neither is inferred
    from the other.

### Added
- **CATEGORY CAPABILITY MODEL — the rule that was missing entirely, now owned
  by the backend and mirrored (not invented) by the app.** The spec requires
  Category → Business Type → Capabilities → Fields → Validation, with the
  frontend never inventing a category rule the backend does not support. There
  was no such model: `/shops/{id}/capabilities` exposed four booleans
  (`canUsePos`, `canUploadExcel`, `canCreateOffers`, `canViewReports`), which
  is a subscription gate, not a data-entry capability set.
  - **Backend (`app/models/merchant_category.py`).** A `CategoryCapability`
    enum (the fourteen named capabilities), a per-category table, and
    `resolve_capabilities(category, business_type)` beside the existing codes and
    names — so the rule lives with the registry rather than in a second place.
    A restaurant is not a product catalogue with a food SKU: it gets
    `SERVICES`/`BOOKING`/`CATEGORY_SPECIFIC_DATA` and **no `INVENTORY`**, while a
    pharmacy keeps its stock ledger. A `Service` business type narrows away only
    the stock-shaped capabilities, and `CONTACT`/`LOCATION` are re-applied
    afterwards — the safety invariant that a business is always contactable and
    findable, whatever its trade.
  - **Served over the existing endpoints.** Each category now ships its
    capabilities with `GET /businesses/categories` (alongside the business-type
    vocabulary), and `GET /businesses/categories/{code}/capabilities` answers
    the real question the forms ask — this category AND this business type.
    Both live in the same router, so there is still one contract, not two.
  - **Unknown category is 404, not an empty list.** An empty capability set
    would render a blank form that looks valid; a 404 tells the client the
    category genuinely does not exist.
  - **THE CROSS-LANGUAGE CONTRACT IS A GENERATED ARTIFACT.** Dart cannot import
    a Python enum, and regex-parsing a Python *source file* is fragile — a
    formatting change breaks the check silently instead of failing it (which is
    exactly how it went wrong twice here). So
    `backend/scripts/export_category_capabilities.py` writes
    `packages/api_contracts/category_capabilities.json`, and both sides read
    that file: `test_capability_artifact.py` asserts it still matches the live
    registry, and `capability_contract_test.dart` asserts the Dart table matches
    it. Either side drifting fails the build with no parsing in the way.
  - **Tests: 23 registry + 7 endpoint + 5 artifact + 15 app.** The strongest is a
    set of pre-computed `category × {Retail, Service}` **resolution samples** in
    the artifact — the Dart resolver must reproduce exactly what the backend
    resolved, which catches narrowing drift a table comparison would miss.
    Both directions are mutation-checked (drifting the artifact, and renaming a
    category code in the registry, each fail the suite).
  - **A real bug the app-side test caught in its own new code:** the resolver's
    `if (servingOnly) ... else ...base` inside a set literal compiled but silently
    contributed nothing from the base list, so *every* category resolved to
    CONTACT + LOCATION only. It is now an explicit loop. Worth noting because it
    passed the analyzer and the table-comparison tests — only comparing actual
    RESOLVED output against the backend's caught it.

### Added
- **CAPABILITY-DRIVEN FORM — the UI half of the data-entry principle.** The
  capability model decided *which* capabilities apply; nothing yet rendered a
  form from them, so a shopkeeper still saw the same fixed set of inputs
  regardless of what their business actually is.
  - **`CapabilityFieldsView` is ONE shared renderer**, not a per-screen form.
    That is the point: the field set changes, the look does not. It uses the
    app's existing conventions — `AppSpacing.md` for the gap, `OutlineInputBorder`
    with a leading icon, the shared `NumericInput` formatter and dropdown — so a
    category-driven form cannot quietly grow its own visual language.
  - **Two responsibilities kept deliberately apart.** `CategoryCapabilitySet`
    decides WHETHER a field appears, and that comes from the backend. The field
    specs decide only what an input is CALLED and how it is validated. So a
    capability the backend grants but this build has no field for renders
    nothing rather than an invented input, and a field never appears for a
    capability that was not granted.
  - **A capability that owns no shop-level input contributes nothing.** A
    restaurant is asked for services, bookings and hours; a pharmacy is asked for
    its GST number; neither is asked for the other's fields. Capabilities that
    govern other screens (products, offers, POS, import) add no input here —
    those screens render themselves, and duplicating them would put a stray
    field on the registration form.
  - **Only non-blank values are submitted, and only for granted fields.** A
    stale value left in form state is dropped rather than smuggled to the
    backend, and a blank optional field is sent as "not provided" rather than an
    empty string the server would have to guess about.
  - **Tests: 14 domain + 13 widget.** The widget tests pin the consistency half
    explicitly — every field is outlined, icon-led, spaced by the *shared*
    constant, and a restaurant and a stock category are asserted to look
    identical. The spacing assertion measures the distance between two
    consecutive fields rather than scanning every `SizedBox` in the tree, because
    a dropdown renders its own and a blanket scan fails for an unrelated reason;
    it is compared against `AppSpacing.md` rather than a literal so a form that
    hardcoded its own spacing cannot pass while drifting. Mutation-checked by
    changing the gap constant.

### Fixed
- **PINNED — `test/firebase_cache_regression.py` (7).** The claims guard now
    scans **all of `app/`**, not one router, so a *new* route cannot repeat the
    mistake. I proved it reaches beyond the file it was written for by injecting
    `firebase_uid, phone = verify_firebase_id_token_claims(token)` into
    `app/api/routes/auth.py` — a file the guard had never been pointed at — and
    the test failed naming that exact line. It also carries a self-check
    (`saw_a_real_use`) so the detector cannot silently stop matching and pass
    vacuously.
- **A DEBUG PROBE OF MINE SHIPPED IN THE REPO, AND MY OWN GATES COULD NOT SEE
  IT.** While investigating the Pylance findings I wrote a throwaway
  `probe_test.dart` into `apps/shopkeeper_app/` and left it there — untyped
  stubs and `print()` calls, reported as three `avoid_print` warnings.
  - **Why nothing caught it:** every gate I ran was scoped to `lib/` and
    `test/` (`flutter analyze lib test`, `flutter test`). A file at an **app
    root** is in neither, so "analyzer clean, 1169/1169 green" was true while
    the file sat in the working tree. The same escape is available to a
    `_probe_*.py` under `backend/`.
  - **Fixed, and pinned** by `test_no_debug_or_probe_scripts_were_left_behind`,
    which asks git directly. Its candidate set is
    `git status --untracked-files=all`, which is exactly right: it excludes
    tracked files (`_debug_dio_test.dart` is committed and named that way on
    purpose — flagging that would be second-guessing a prior decision) and
    excludes anything `.gitignore` covers (`storage/chrome_run.log.err` cannot
    ship anyway). What is left is precisely "a new file that would be
    committed". Mutation-checked by re-creating both a `probe_test.dart` and a
    `.err` leftover and watching it fail. **Running the sweep then surfaced four
    more leftovers of mine** (`backend/e1.txt`, `e3.txt`, `pc.out`, `pc.err`),
    which were removed — the guard is broader than the single file that
    prompted it.
- **THE THREE "UNUSED" WARNINGS WERE INTENTIONAL — now marked as such for
  Pylance, not silenced.** `Role` (an import-for-side-effect that registers the
  table on `Base.metadata`), `_normalize_phone` and `client_ip` all carried
  `# noqa` for flake8/ruff, which Pylance does not honour — so they were
  reported indefinitely. Each now carries `# pyright: ignore[...]` **with the
  reason inline**. `reportUnusedImport/Function/Variable` stay **ON**, so real
  dead code is still reported; the rule was never switched off to quiet them.
- **THE LINT CONFIG WAS BURYING THE TWO CHECKS THAT FIND REAL DEFECTS.**
  `pyrightconfig.json` sets `typeCheckingMode: "strict"` over a four-file
  include list, but VS Code applies the mode **workspace-wide**, so opening
  `shopkeeper_auth.py` produced ~60 diagnostics on its own. Almost all were the
  `reportUnknown*` family — ergonomics hints, not defects: they fire on
  `dict.get()` returning `Unknown`, on SQLAlchemy `filter()` criteria, and on
  bare `dict` annotations. None of them ever identified a bug in this codebase.
  - **Silenced only that family**, with the reasoning recorded in the file —
    because "make the panel clean" and "hide the useful signal" look identical
    from the outside, and only one of them is worth having.
  - **Kept two rules deliberately ON**, since between them they found the two
    release-blocking bugs above: `reportMissingImports` (the `slugify` import)
    and `reportAttributeAccessIssue` (`LocationStatus.PENDING`). Turning the
    whole report off would have hidden exactly the two defects that made the app
    unusable after first sign-in.
  - `shopkeeper_auth.py` added to the tracked include list so those checks
    actually run on it, and a test pins the split: it fails if either valuable
    rule is silenced or if `strict` is quietly downgraded. Mutation-checked by
    switching `reportAttributeAccessIssue` off — the test failed as intended.
- **`POST /shopkeeper/auth/profile-create` COULD NEVER SUCCEED — two separate
  hard failures, both invisible to a green 1481-test suite.** This is the
  endpoint every first-time shopkeeper must pass through, so on any clean
  environment the app was unusable immediately after Google sign-in. Pylance had
  been reporting both for a while; neither had been acted on.
  - **1. `python-slugify` was imported but never declared.** The handler does
    `from slugify import slugify` to build `Shop.slug`, yet the package was in
    neither the environment nor `requirements.txt` — so a fresh install (CI, the
    container image, the Lambda zip) raised `ModuleNotFoundError` → **500**.
    Verified by probe, then installed **and declared**, so the failure cannot
    return on a new machine.
  - **2. Three enum members that do not exist.** The same handler set
    `LocationStatus.PENDING`, `LocationSource.UNKNOWN` and
    `LocationType.UNKNOWN` — none exist. `LocationStatus` has
    CAPTURED / CONFIRMED / CORRECTED / STALE, and the other two have no
    `UNKNOWN` at all. Every call raised `AttributeError` → **500**. Replaced with
    the values the `Shop` model itself declares as those columns' defaults,
    which also read honestly for a shop created with no coordinates and
    `location_verified=False`.
  - **WHY THE SUITE NEVER CAUGHT EITHER.** No test built a `Shop` through this
    handler, and a lazily-imported dependency is invisible to module import.
    Both classes are now pinned by `tests/test_dependency_declarations.py` (3):
    every mapped third-party import must appear in `requirements.txt` (imports
    read with `ast`, so a name in a comment cannot fake it), and every
    `Enum.member` referenced anywhere in `app/` must really exist — resolved
    against the real enums, across all 37. Both are mutation-checked: dropping
    the `requirements.txt` line, or restoring `LocationStatus.PENDING`, fails
    naming the exact line.
- **THE TOKEN CACHE COULD REPORT A SESSION THAT WAS NEVER PERSISTED.** The
  read-through cache (which removes an encrypted Keystore hop from every API
  call) updated memory **before** the storage write. If that write threw — full
  disk, corrupted keystore, a locked keychain — the caller saw the exception
  but every later read still returned that token from memory. The app then ran
  the rest of the session authenticated on a credential that does not exist on
  disk, and the next cold start dropped the user out with no explanation.
  **Storage is now written first, memory second**, which makes the cache a
  strict subset of what is persisted: the worst case is one redundant read,
  never a phantom session. Pinned by a new `token_store_cache_test.dart` case
  that makes the storage write fail and asserts the cache neither keeps the
  un-persisted token nor loses the previous valid one — verified to fail against
  the old ordering.
- **THREE LIVE AUTH ENDPOINTS WERE BROKEN — and the test suite was GREEN while
  they were.** `verify_firebase_id_token_claims()` returns the full claims
  **dict**. Three call sites in `shopkeeper_auth.py` treated it as something
  else, all on the Firebase sign-in path the Shopkeeper app depends on:
  | Endpoint | Bug | Real-world effect |
  |---|---|---|
  | `POST /auth/verify-phone` | `firebase_uid, phone = verify_...(...)` unpacks the **dict into its KEYS** | `ValueError: too many values to unpack` — not a `FirebaseVerificationError`, so it escaped the handler as an **opaque 500 on every call** |
  | `POST /auth/verify-otp` | `phone = verify_...(...)` bound the whole **dict** to `phone` | `User.phone_number == phone` compared a string column against a dict — could never match, so every real caller got **ACCOUNT_NOT_FOUND** |
  | token cache | published a `(None, exp_ts)` placeholder **before** building claims | a token verifying without a `sub` claim raised *while the placeholder was cached*, so every later request for that token was served `None` → `TypeError`, a **401 silently degraded into a 500** |

  All three are fixed: the two routes read `verified["uid"]` / `["phone"]`, and
  the placeholder is gone — claims are now published **atomically, once, after
  validation completes**. The cache's size cap moved with it so memory is still
  bounded. The placeholder never bought anything anyway: the lock is released
  immediately, so it never prevented a concurrent verify; it could only leave
  debris behind.
  - **WHY 1477 TESTS NEVER CAUGHT THIS — and the fix that stops it repeating.**
    Two of the three call sites had tests, and both **mocked the function to
    return a tuple** (`lambda token: ("fb-uid-...", "+91...")`) while the real
    function returns a dict. The mock was shaped to match the BUG, so the suite
    validated the bug. Six such mocks are corrected to return real dicts, and
    `tests/test_firebase_cache_regression.py` (7) now pins the contract at
    **every** call site: it flags any place that binds the claims dict to a name
    and never indexes it. I confirmed both guards bite by reintroducing each bug
    — the tests failed naming the exact line, then passed again once reverted.
    This is the same lesson as the app's fake-repository suites: a fake returns
    whatever the code under test wants, so it cannot catch a contract mismatch.
  - **DEPLOYED ARTIFACT REGENERATED, not hand-edited.**
    `infrastructure/lambda_staging/app/` is a *generated copy* of `backend/app`
    (`shutil.copytree` in `build_media_lambda_staging.py`) and it carried all
    three bugs — so a deploy from the stale directory would have shipped them.
    Editing it by hand would have been overwritten on the next build, so the
    build script was run instead; both fixes are confirmed present there now.
- **27 COMMITTED BUILD LOGS — 1.5 MB of tool output tracked as if it were
  source.** The repo root carried `analyze_full.txt`, `rq_sk_test.txt`,
  `ruff_fmt.txt` and 24 siblings: analyzer and pytest transcripts `git add`ed at
  some point and never removed. They change on every local run, so they appear
  in diffs, bloat history, and would eventually conflict on merge. **They are
  UNTRACKED, not deleted** — every file is still on disk byte-for-byte — and
  `.gitignore` now covers the patterns (`analyze_*.txt`, `rq_*.txt`,
  `ruff_fmt*.txt`, …) so they cannot return. Verified: 27 files still present,
  0 tracked.
- **TWO FINISHED FEATURES WERE UNLINKED *AND* UNTESTED — now pinned.** Every
  `*_repository.dart` method was audited against every screen and controller.
  Six methods have no caller; two (`_persist`, `_token`) are private helpers and
  are correct. The other four are **complete, working API calls parked for a
  future screen** — and two of those had **zero coverage anywhere**:
  | Method | Found as |
  |---|---|
  | `InventoryRepository.fetchStockAdjustments` | unlinked, already tested |
  | `InventoryRepository.updateLowStockThreshold` | unlinked, already tested |
  | `MediaRepository.readUrl` | unlinked, **0 tests** |
  | `PosRepository.getIntegration` | unlinked, **0 tests** |

  Parked-but-untested is how working code breaks quietly: the backend renames a
  field, the model stops parsing, and nothing notices until the screen finally
  appears — months later, with the regression blamed on the new work. **Per the
  "preserve unlinked code" rule, nothing was deleted.**
  `test/unlinked_capability_test.dart` (4) now exercises them through the REAL
  `ApiMediaRepository` / `ApiPosRepository` rather than a fake, so what is
  pinned is the actual request path and envelope parsing. It also pins the
  **auth seam**: with no token the repository must refuse *before* a request
  leaves the app, rather than spend a round trip learning what it knows.
  - Writing them surfaced a real detail: the media repo's
    `ApiException.localized` carries its code in **`messageCode`**, while
    `errorCode` holds the *server's* code and is null for a client-side
    refusal. The test asserts the right field and comments why, so the next
    person does not "fix" it backwards.
- **Firebase ID-token fragments removed from debug logs.** Logging any part of an
  ID token puts a credential in logcat, which survives on a rooted device and in
  any bug report a user is asked to send.

### Performance
- Insights drill-down no longer scans the daily series once **per rendered row**.
  The chart maximum was folded inside every row's arguments, so a 90-day window
  visited the list ~8,100 times per build instead of 90, and the peak-hours card
  re-sorted the whole hourly spread once per row — all re-run on every rebuild.
  Both derivations now live on `DrillDownState` (`peakSeriesValue`,
  `busiestHours()`, alongside the existing `peakHour`/`total`) and are read once
  in `build()`. A regression guard counts element accesses and fails if the
  series is scanned quadratically again (~16.8k accesses vs ~550 at 90 days).

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

### Startup performance, duplication & legacy-code audit
- **Startup (§113).** Audited the whole startup path for all three apps and the
  backend lifespan hook. Already correct: neither splash loads data (each fires
  only an auth-session check), `main()` loads nothing but Firebase + config +
  bounded image-cache settings, customer home uses `autoDispose` providers, the
  backend lifespan only runs security checks and `enable_postgis`. The
  notification controllers are never read at startup.
  - **Fixed — one real violation.** The shopkeeper dashboard's "needs
    attention" card wanted ONE number (how many listings are `STALE`) and got
    it from `fetchInventoryOverview`, which returns **every listing in the
    shop** — a full-catalogue download on the first screen after login, purely
    to count rows the server already owns, growing with the catalogue.
    - Backend: new `view=summary` on `GET /shops/{id}/inventory` returns
      `{"summary": {...}}` and never builds or serialises an item row, so the
      body is the same size for a shop with 5 listings and one with 50,000.
      Inventories are read in ONE batched query (1:1 via
      `uq_inventory_shop_product`), which also removes the per-listing N+1.
    - `_product_counts` derives `stale` from `Inventory.freshness_status`, and
      takes `include_attention=False` for counts-only callers so the summary
      reports `needs_attention_count` (a size) instead of up to ten rows.
    - App: `InventorySummary` gains `stale`; `InventoryRepository` gains
      `fetchInventorySummary`; the dashboard alert uses it. Screens that
      genuinely render listings keep the full view.
    - Guarded by tests in both layers: a backend suite pins "no items", the
      stale tally, empty-shop zero-fill and that every number agrees with the
      full view; a dashboard test asserts `summaryCalls == 1` and
      `overviewCalls == 0`, so a regression to the full download fails a test
      instead of quietly shipping.
- **Duplication (§114).** No `AuthServiceV2` / `ProductRepositoryNew` /
  `ApiClientNew` / `ProfileProvider2` style versioning exists, and no two
  service / client / validator / store / repository classes share a name in
  either app. The repeated names that do exist (`TokenStore` +
  `SecureTokenStore` + `InMemoryTokenStore`, and the Permission/Storage
  equivalents) are the correct interface + production + test-double seam.
  - **Fixed — five private copies of one widget.** Five customer screens each
    carried a private `_SectionLabel` whose type styling was byte-identical
    (12 / w700 / 1.1 tracking / muted, uppercased); only the padding differed.
    One design change meant five edits and a missed one silently drifted. A
    single `SectionLabel` now lives beside `SectionHeader` in the existing
    `core/widgets/section_header.dart` — the file that already owns section
    typography, so no new file was introduced — with `SectionLabel.tight` /
    `.dense` preserving each screen's exact spacing. A before/after class
    diff confirms `_SectionLabel` is the only class removed from those files.
  - Deliberately NOT merged: the three private `_SummaryChip` copies
    (`import_preview`, `inventory_import`, `products`) differ in value type,
    padding, corner radius, border and weight. Merging them would need ~6 knobs
    and change pixels on shipping screens — duplication of *look*, not of code.
- **Legacy code (§115).** Nothing deleted. A whole-repo reference sweep found
  no orphan screens, no unreferenced screen/widget files, and no dead imports
  (analyzer is clean).
  - `core/widgets/rebuild_scoping.dart` was the single file nothing referenced
    — and nothing tested. Kept, and given a real suite: `WatchSelected` must
    render the selected value, rebuild exactly once when the selection changes,
    and — the actual contract — NOT rebuild when an unrelated field of the same
    provider changes; `RepaintIsolated` must render a real `RepaintBoundary`.
  - **Fixed — the backend suite could not be collected at all.**
    `tests/test_customer_support.py` raised `NameError` on import: a
    `@pytest.mark.parametrize` decorator referenced `self.CUSTOMER_CODES`, and
    `self` is not bound while a class body is evaluated. The codes are now a
    module-level `frozenset` (the class name is not bound there either).
### Screen reusability & deep linking
- **Screen reusability — the import status vocabulary is now ONE component.**
  Two surfaces each owned a private status→(icon, colour) mapping, and they had
  already drifted: the history row drew a **green tick** for the legacy
  `VALIDATED` status while the chip beside it read "Validating" in amber,
  because `ImportJobStatusValue.label` treats that status as still-validating.
  `ImportStatusView` + `importStatusTone()` (in the existing import `widgets/`
  folder) now own the icon and colour for every state, and both
  `import_processing_screen` and `import_history_screen` read from it — so one
  component covers Processing / Queued / Success / Partial / Failed and a row
  can no longer contradict its own label. The COPY stays with each surface (a
  history row wants the short label, the result screen wants the full
  sentence); only the visuals are shared.
  - The confirm result now derives its status **once** and uses it for the
    headline, the icon AND the report-sheet header, so those three can no
    longer describe different outcomes. Zero rows applied is treated as a
    FAILURE even when the payload also reports zero failures — nothing was
    imported, and "Completed" would be a lie.
  - An unrecognised future backend status degrades to a neutral icon instead of
    throwing, matching how the label helper already degrades.
- **Deep linking — a notification can now open the exact import job.**
  The backend already sent everything needed: `deep_link:
  hyperlocal://shopkeeper/imports/{job_id}` plus a `job_id` payload. The app
  ignored it and sent the shopkeeper to the whole history list — the existing
  tests even said "Import Failed → Import Result" while asserting
  `Routes.importHistory`, i.e. the intent was documented and the implementation
  lagged it.
  - New `Routes.importResult` + `ImportResultScreen`, which renders the job
    through the SAME `ImportStatusView` as the post-confirm result, so a job
    reached from a notification looks exactly like the one watched finishing.
  - The job is **fetched, never taken from the notification** — a push payload
    can be stale, forged, or name a job that no longer exists.
  - `ShopkeeperNotification.payloadInt` (a validated positive-int accessor that
    existed with **no caller**) is now the gate. A payload that cannot name a
    real job — missing, zero, negative, a string, a fractional number — falls
    back to Import history rather than requesting a fabricated id. The router
    re-validates the `extra` and falls back too, so no path can construct
    "job 0".
  - A deleted job / expired session / offline device renders an explained state
    with a way out, not a blank screen; Retry re-issues the request.