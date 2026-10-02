# Hyperlocal Product Discovery Platform — Changelog

## [Unreleased]

### Added
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