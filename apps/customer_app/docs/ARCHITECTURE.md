# State management

**Use the existing project state-management approach. If it is sound, KEEP it.
Do not migrate the entire app to another framework without a real architectural
reason.**

## Verdict: Riverpod is sound, and it stays

I audited before changing anything, because the rule's first instruction is not
"migrate" — it is "check whether it needs migrating". The counts:

| Approach | In `lib/` |
| --- | --- |
| **Riverpod** (`Provider`, `FutureProvider`, `StreamProvider`, `NotifierProvider`) | **100+ sites — the only framework in use** |
| `ChangeNotifier` | 0 |
| `StateProvider` | 0 |
| `provider` package | 0 |
| bloc / getX / redux / mobx | 0 |
| `ValueNotifier` / `ValueListenable` | 2 |

The two `ValueListenable` uses are **not** our state: they wrap
`MobileScannerState` from the third-party `mobile_scanner` camera API, which
exposes its own listenable. Replacing that with Riverpod would mean fighting the
package, not improving the app.

`setState` appears 65 times, and that is also correct: every one is in a
`presentation/screens/` or `presentation/widgets/` file, holding genuinely local
UI state — a text controller's contents, which tab is open, whether a tile is
expanded. That is what `setState` is for. Moving it to a provider would add
indirection and make the widget harder to read for no benefit.

**So: no migration. Riverpod remains the state layer.** The sealed state types
(`LoadState`, `PagedState`, `MutationState`) are *models used inside* Riverpod
notifiers, not a competing framework.

## The eight conceptual states

Every state the spec names, and where it lives. `state_vocabulary.dart` is the
single source of truth and `state_vocabulary_test.dart` fails if this drifts.

| Conceptual state | Implemented as | Why it is a separate state |
| --- | --- | --- |
| **Initial** | `LoadIdle`, `PageInitial`, `MutationIdle` | "we have not started" earns a different affordance than "still working" |
| **Loading** | `LoadLoading`, `PageLoading`, `PageReplacing` | First fetch; nothing on screen yet |
| **Loaded** | `LoadReady`, `PageHasMore`, `PageComplete` | The answer, with data |
| **Empty** | `LoadEmpty` | A **success** that is not a failure — "widen your search", not a scary error |
| **Refreshing** | `LoadRefreshing`, `PageLoadingMore` | In flight, but the previous value stays visible |
| **Saving** | `MutationRunning` | A write is in flight; the control must be disabled |
| **Success** | `MutationSucceeded` | The backend **confirmed** it. Never optimistic |
| **Error** | `LoadFailed`, `PageFailed`, `MutationFailed` | Retains previous content, so a failure never destroys what the customer was reading |

## Which type to use

* A single thing that loads, searches, or filters → `LoadState<T>`
* A list that pages → `PagedState<T>` + `PagePhase`
* A write (submit, save, place) → `MutationState`

They **compose** rather than merge. A search screen is typically
`LoadState<List<Product>>` plus a `MutationState` if it can save a search.
Folding them into one type is the mistake — a page that is simultaneously
`Loading`, `Empty` and `Error` is the boolean-cluster bug in a sealed costume.

## Why `Refreshing` is separate from `Loading`

Both are "a request is in flight", and both report `isLoading == true`. But they
render differently, and conflating them is the flash-of-empty bug:

* `LoadLoading` → no data exists, so a full-screen skeleton is correct.
* `LoadRefreshing` → data exists and must stay on screen, so the skeleton would
  be a regression: the customer loses what they were reading to watch a spinner.

A test asserts the two are different types, because a view genuinely cannot tell
them apart if they are the same.

## What is enforced

| Rule | Test |
| --- | --- |
| No competing state framework (bloc/get/provider/hooks_riverpod) | `view_rule_guard_test.dart` — "no competing state-management framework is introduced" |
| No feature state class with 3+ independent `bool` fields | `view_rule_guard_test.dart` — "no feature state class reintroduces the boolean-cluster antipattern" |
| All eight states are named and covered | `state_vocabulary_test.dart` |
| Each type covers at least one state | `state_vocabulary_test.dart` — "every state model covers at least one conceptual state" |

The boolean-cluster check is deliberately **narrow**: it only inspects feature
`*_state.dart` files outside `presentation/`, because a widget owning one or two
booleans is fine and flagging that would be ceremony rather than safety.

# Single source of truth rule

**One logical source of truth per domain.** Two providers must never hold
independent copies of the same list.

## Avoid

```dart
final searchResultsA = ...;  // its own cached list
final searchResultsB = ...;  // its own cached list
final productCache1 = ...;
final shopListCopy = ...;
```

## Instead

Derive. A second reader of the same data must be a **projection** of the
owner, never a second cache:

```dart
// The owner: the only place that holds and mutates the list.
final recentSearchesNotifierProvider = AsyncNotifierProvider<...>(...);

// Readers project it. No cache, no copy, nothing to invalidate.
final recentSearchesProvider = Provider<List<String>>((ref) {
  final items = ref.watch(recentSearchesNotifierProvider).value;
  if (items == null) return const <String>[];
  return items.map((e) => e.query).toList(growable: false);
});
```

## Why this is a bug, not a style preference

The audit found a **live, user-visible divergence** in search history. Recent
searches were cached twice in memory — once in the search feature, once in the
saved-and-history notifier — and tied together by a manual version counter that
every writer had to remember to bump:

| Writer | Refreshed the search copy | Refreshed the notifier copy |
| --- | --- | --- |
| `saveRecentSearch` (search screen) | yes | **no** |
| `RecentSearchesNotifier.addQuery` (history tab) | **no** | yes |
| Settings "clear all history" | **no** | yes |

So a customer could search *colgate*, open the history tab, delete it, and the
search screen would still offer it. "Clear all history" in Settings emptied the
tab but left the search screen unchanged.

**A manual invalidation bridge is the smell, not the fix.** The counter existed
only to keep two copies in step, and every new write path had to remember to
operate it. Deleting the counter and deleting the copy removes the entire class
of bug: with one owner and derived readers, there is nothing to forget.

## What is allowed

A repository/cache layer is a deliberate second layer, not a violation, when it
is a *different* concern: an HTTP cache in front of a network source, a
`CachedResourceController` holding stale-while-revalidate entries, or a
`LocalCacheService` persisting across launches. The test is:

- Does the second holder own data, or **derive** it? Deriving is always safe.
- Do both holders accept writes? If yes, it is two sources of truth — consolidate.
- Is there a manual counter/`invalidate` call keeping them aligned? That is the
  proof they are duplicates. Remove one side.

Legacy-key migrations are not caches. A one-time copy from an old store into the
one current store is fine, and belongs next to the owner — `search_history_v1`
now migrates inside `RecentSearchesNotifier`, not in a second feature.

## Regression guard

`test/features/search/presentation/widgets/search_results_ui_test.dart`,
group `recent searches single source of truth`, pins the behaviour: a write
through the notifier is visible to the projection, and a deletion in the history
tab removes the entry from the search screen with no manual invalidation.

# Repository rule

**Repositories own:** cached application data, API data, retry, refresh, mapping,
data-source coordination.

**Create only where justified.** A repository that wraps a single `getX()` with
no cache, no retry and no mapping is a pass-through class that adds a layer
without adding a reason. This codebase has 13 repositories, and the ones that
earn their place all do at least two of the jobs above.

## Interface in `domain/`, implementation in `data/`

The single most common layering mistake found in the audit was a **contract
living in `data/` next to its implementation**. `SupportRepository` was declared
inside `support_repository.dart` alongside the Dio class, which meant:

1. A view that only needed to name a `SupportIssueCategory` had to import
   `data/`, because that is where the enum was — a View-rule violation caused
   purely by file placement.
2. The contract could not be depended on without dragging in `ApiClient`,
   `ApiEndpoints` and Dio, so a plain unit test pulled in the whole HTTP stack.

Now: `domain/` holds the interface, the enums, and the user-facing copy;
`data/` holds only the Dio wiring and re-exports the vocabulary for convenience.
`domain` stays free of IO.

Same treatment applied to `phone_utils.dart`, which was a pure string function
sitting in `auth/data/` and forcing `login_screen` and `register_screen` to
import a data layer. It moved to `auth/domain/` with **no logic change**.

## Service rule

**Services wrap external systems:** Firebase Auth, Firebase Messaging, REST API,
location plugin, maps plugin, local file/device APIs.

**Services must not become giant business-logic containers.**

The line between a service and a repository is *what it talks to*, not *how much
code it has*:

| | Service | Repository |
| --- | --- | --- |
| Talks to | Firebase, Dio, geolocator, maps, secure storage | other repositories / a data source |
| Knows about | the plugin or transport | caching, retry, staleness, mapping |

A service that decides *which product to show* is a business-logic container
wearing a service's name. `local_cache_service.dart` is the right shape: it
wraps SharedPreferences and knows nothing about products. `fcm_notification_service`
wraps Firebase Messaging; the decision of *which* notification a customer gets
belongs above it.

## The three rules together

```
View          layout, display decisions, animation, routing
   ↓ watches
ViewModel     UI state, commands, loading/error/filter/search/pagination/mutation
   ↓ reads
Repository    cache, retry, refresh, mapping, data-source coordination
   ↓ uses
Service       one wrapper per external system
```

Each arrow points one way. A View never imports `data/`, a ViewModel never
imports `material.dart`, and a Service never decides product behaviour. The
guard test in `test/core/view/view_rule_guard_test.dart` enforces the first two
mechanically.

# The two rules this codebase is built on

These are the contract. Everything else in this document exists to satisfy them,
and `test/core/view/view_rule_guard_test.dart` enforces them on every test run.

## VIEW RULE

**Views should contain:** layout, simple display decisions, animation, basic
routing actions.

**Views should NOT contain:** database logic, backend verification logic, large
business logic, complex API transformations.

Concretely: a widget in `presentation/` may import its own `domain/models`, the
shared `core/` presentation helpers, and a ViewModel. It may **not** import a
`data/` layer. Decoding rules, permission checks, and repository calls belong
behind a ViewModel — otherwise two views decode the same record differently and
the disagreement only shows up on whichever screen happened to hit a malformed
row.

## VIEWMODEL RULE

**ViewModels manage:** UI state, commands, loading, error, filter state, search
state, pagination state, mutation state.

**Avoid conflicting boolean states. Prefer explicit state models.**

This is the rule that has the most bugs behind it, so it is worth being precise
about what "conflicting" means.

### Why booleans break

The pattern this replaces was real code in this repo:

```dart
class PaginatedState<T> {
  final List<T> items;
  final bool isLoadingInitial;
  final bool isLoadingMore;
  final bool hasMore;
  final ApiException? error;   // <-- dead code: never read, never assigned
}
```

Four independent fields describe a list that has four **mutually exclusive**
phases. Four booleans mean sixteen reachable states, twelve of which are
impossible, and nothing stops the code from being in one of them:
`isLoadingInitial: true, hasMore: false` is a list that is loading its first
page and has already decided there is no more — a screen reading that has no
correct thing to render.

The `error` field made it worse. `copyWith` assigned `error: error` instead of
`error: error ?? this.error`, so every unrelated `copyWith` call **silently
cleared the error**. A customer would see a failure, scroll, and find the retry
button gone.

### What replaces it

Sealed classes, one case per phase, so the impossible states are unrepresentable:

| Concern | Type | Cases |
| --- | --- | --- |
| Load / search / filter | `LoadState<T>` | `LoadIdle`, `LoadLoading`, `LoadRefreshing`, `LoadReady`, `LoadEmpty`, `LoadFailed` |
| Pagination | `PagedState<T>` + `PagePhase` | `PageInitial`, `PageLoading`, `PageReplacing`, `PageHasMore`, `PageLoadingMore`, `PageComplete`, `PageFailed` |
| Mutation | `MutationState` | `MutationIdle`, `MutationRunning`, `MutationSucceeded`, `MutationFailed` |

Three properties the boolean version could not offer:

1. **Exhaustive `switch`.** Adding a case fails the build at every unhandled
   site, so a new state cannot be silently ignored.
2. **Derived, not stored.** `PagedState.hasMore` is computed from `phase`, so it
   cannot contradict whether a request is in flight.
3. **Meaningful fields per case.** `LoadEmpty` has no `error`, because an empty
   result is a *success* needing different copy ("widen your search"), not a
   failure. Collapsing the two is what makes empty-state screens show a scary
   error.

`LoadState.refreshing()` and `LoadFailed(previous:)` exist so that a refresh
never blanks content the customer is already reading — the "flash of empty" on
every pull-to-refresh.

`MutationState` exists because views were holding `_isSubmitting` and `_error` as
two `setState` fields, which could show "submitting" and "failed" at once, and
which allowed a double-tap to fire two requests. `MutationRunning.isFailed` is
`false` by construction, and a view disables its submit control on
`isRunning`.

### A ViewModel knows nothing about widgets

`ViewModel` imports `package:flutter/foundation.dart`, **not** `material.dart`,
and never holds a `BuildContext` or calls `setState`. That is what makes it
testable with no widget pumping — you assert on state, not pixels. The guard
test fails the build if `material.dart`, `BuildContext`, or `setState` appears
anywhere under `lib/core/view/`.

### Where the rules are checked

| Check | Test |
| --- | --- |
| No view imports `data/` | `view_rule_guard_test.dart` — "no view imports a data/ layer" |
| Known violations are all still real (no stale baseline) | `view_rule_guard_test.dart` — "every known violation is still justified" |
| A ViewModel never imports material / holds context | `view_rule_guard_test.dart` — "a ViewModel never imports material.dart" |
| Exactly one phase per state | `load_state_test.dart`, `paged_state_test.dart` |

### Current violations (tracked, not ignored)

Zero views reach into `data/`. `_knownViolations` in the guard test is empty,
and the test **fails if any view starts importing `data/`** — so the baseline
cannot quietly rot:

- `help_support_screen.dart` — [RESOLVED] now renders through
  `SupportFormViewModel` (`support/application/support_form_view_model.dart`),
  which owns the `MutationState` submission lifecycle.
- `delete_account_screen.dart` — [RESOLVED] depends on `auth/domain/` and the
  storage driver, not a data layer.
- `barcode_scan_screen.dart`, `barcode_camera_gate.dart` — [RESOLVED] migrated to
  `BarcodeScannerViewModel` (`presentation/controllers/barcode_scanner_view_model.dart`),
  removing direct `data/` imports and consolidating camera permission flow state.
- `login_screen.dart`, `register_screen.dart` — [RESOLVED] import
  `auth/domain/phone_utils.dart` (pure string function, moved out of `data/`
  with no logic change).

Each is removed as its feature is migrated. New violations are not accepted.

# Feature Architecture

How data moves and how the UI rebuilds in this app, and why each layer is shaped
the way it is. Read this before adding a feature or touching a controller.

## The four problems this architecture exists to solve

These came out of an audit of the existing code, not from a preference for
architecture diagrams.

| Problem found in the code | Consequence for the customer | Fix |
| --- | --- | --- |
| `keepAlive` used **0 times** in the whole app | Navigate away and back, and everything refetches. Content they just read shows a skeleton again. | `keepHot(ref)` — a timed hot window |
| ~50 providers declared **inside screens/controllers** | State lifetime is an accident of which widget watched what. Screens can see and mutate data they should not. | Providers belong to the feature's `application` layer |
| No request deduplication | Two widgets watching the same resource = two GETs. Last response to land wins, even if it is the **stale** one. | `RequestCoalescer` |
| `AsyncValue` used for remote data | A refresh either blanks the screen or is invisible. No way to say "this is cached". | `Resource<T>` |

Numbers from the audit: 136 `ref.watch`, 0 `keepAlive`, 35 non-lazy `ListView`
against 17 lazy ones, 0 `RepaintBoundary`.

## The layers

```
presentation/     widgets only. Watches state, renders it, dispatches intents.
                 Must never call a repository or parse JSON directly.
    ↓
application/     controllers (Riverpod). Owns load/refresh/retry, and the
                 lifetime decision. The ONLY layer that talks to data.
    ↓
domain/          models and repository interfaces. Pure Dart, no Flutter, no
                 JSON. This is what tests assert against.
    ↓
data/            repository implementations. Decoding, caching, coalescing.
                 No widgets, no Riverpod state.
```

**The one rule that makes it work: dependencies point down only.** A repository
cannot import a controller, and a controller cannot import a widget. When a
screen needs new data, you add a repository method and a controller — you never

## Data flow: one path, not five

Every remote read goes through `CachedResourceController`:

```
           ┌───────────── cold open ─────────────┐
fetch ─────┤                                      ├────► ResourceData
           └───── warm open ─────────────────────┘
                     │                    ▲
              cache hit (instant)         │ background revalidate
                     ▼                    │
             ResourceCached ──────────────┘
                     │
        on failure: ResourceError(previous: <the data>)
```

That single path fixes, for every feature at once:

1. **Duplicate requests** — routed through the shared `RequestCoalescer`, so a
   screen and a badge asking for the same thing cause one GET.
2. **Blank-screen flash** — a refresh emits `ResourceRefreshing` *with* the
   previous data attached, so pull-to-refresh never blanks what the customer is
   reading.
3. **Silent staleness** — a cache hit emits `ResourceCached(cachedAt)`, so the
   UI can say "as of 2 min ago" rather than passing old stock off as live.
4. **Failure destroying content** — a failed refresh emits
   `ResourceError(previous: ...)`, so the customer keeps what they had and gains
   a retry affordance.

`fetch` must be a **pure, idempotent read**. That restriction is what makes
auto-revalidation safe, and it is why side-effecting operations (place order,
submit ticket) must not go through this controller.

### Why `Resource` instead of `AsyncValue`

`AsyncValue` cannot express "showing cached data while refreshing" — it offers
`loading` (no data) or `data` (not refreshing). That forces a choice between
blanking the screen and hiding the fact that data is stale. `Resource` is a
sealed class with a state for each, and the compiler enforces exhaustive
handling, so a new state cannot be silently unhandled by a screen.

### Cold vs warm

- `load()` — cold open: network, then cache.
- `warm()` — warm open: publish the cache **immediately** so the customer sees
  the last known data in the first frame, then revalidate behind it. A cache
  entry younger than `staleAfter` is a complete answer and is not revalidated at
  all, so a warm open can cost **zero** requests.

## Provider lifetime: an explicit decision

Lifetime is a **decision**, not an accident of which widget watched what.

```dart
class CartNotifier extends HotNotifier<Cart> {
  @override
  Cart buildOnce() => const Cart();
}
```

- **Hot** (`keepHot(ref)` / `HotNotifier`): survives losing its last listener for
  `ProviderPolicy.hotIdle` (5 min). Use for the signed-in customer, location, the
  home feed — anything a customer is likely to return to within a session.
  Navigate back = no refetch, no lost scroll position.
- **autoDispose** (`FutureProvider.autoDispose`): a single screen's short-lived
  request.
- **Session-scoped**: anything holding customer data must be released on
  sign-out. A cart that survives a sign-out shows the next customer somebody
  else's basket — that is a privacy bug, not a performance one, and it is why
  "just make everything hot" is not the answer.

A permanent `keepAlive` is deliberately not offered: it grows for the whole
session and has to be invalidated on sign-out anyway.

## Search state: what must survive leaving the screen

A search must not lose the customer's work when they tap into a product and come
back. The full set to preserve is **query, suggestions, results, filters, sort,
pagination, loading, error**.

| Piece | Where it lives | Survives a push? |
| --- | --- | --- |
| `query` | the `searchResultsProvider(query)` family key | yes — it *is* the key |
| `results`, `currentPage`, `totalResults` | `SearchPaginationState` | yes |
| `loading`, `error`, `stage` | `SearchPaginationState` | yes |
| `filters`, `sort` | `SearchQueryPreferences` | yes |
| `suggestions` | `suggestionsProvider` (`autoDispose`) | content yes, cache **no** |

Most of this is free, and it is worth knowing why. `searchResultsProvider` is a
plain `NotifierProvider.family` — **not** `autoDispose`. Its state therefore lives
in the `ProviderContainer`, not in the widget, so pushing `/product/:id` cannot
dispose it. Making it `autoDispose` would silently reset scroll position, page
number and the whole result set on every product tap. That is a regression to
avoid, not a leak to fix.

`filters` and `sort` are the exception. `build()` constructs a **fresh**
controller on re-entry, so those two values have to be remembered somewhere. That
is `searchQueryPreferencesProvider` — and it is a provider rather than a
`static` map on purpose:

### `suggestions`: correct on return, but re-fetched

Worth stating precisely, because "does suggestions survive?" has two answers and
only one of them matters.

The **query** is preserved (`searchQueryProvider` is not `autoDispose`).
`suggestionsProvider` is `autoDispose` and watches the preserved
`debouncedQuery`, so on return the suggestions are **correct** — they are simply
fetched again rather than served from a cache. That is one wasted round trip, not
a lost state, so it is left as-is rather than promoted to a hot provider.

Measuring this is easy to get wrong. `container.read(suggestionsProvider)` twice
in a row reports **one** repository call, because `read` leaves no lasting
listener and nothing triggers disposal in between — which would make a broken
test look like a passing one. The honest test uses `container.listen(...)` to
stand in for the widget and `.close()` to stand in for leaving the screen;
`search_state_contract_test.dart` does exactly that and asserts the refetch.

- A `static` map outlives every container, so no `ref.invalidate` can clear it.
  Sign-out could not reset it, meaning the next customer inherited the previous
  one's filter choices — the same privacy failure as a cart surviving logout.
- Every query ever searched kept an entry forever.
- Tests shared one process-wide map, so a new `ProviderContainer` inherited the
  previous test's state and results depended on execution order.

`cancel()` calls `forget(query)` because "cancel" means start over, and the
logout listener in `app.dart` calls `clear()`.

**Regression guards** live in
`test/features/search/presentation/screens/search_results_screen_test.dart`:
the round-trip through a torn-down screen, no cross-query leakage, cancel, the
container-scoped lifetime, and `clear()`.

One trap when writing these: `MockSearchRepository` sleeps **800ms** to simulate
network latency. Pumping 100ms asserts against a still-loading screen and every
result list reads as empty. Elapse past the latency, don't just add pumps.

## Result pagination

Search results can be large, so pagination is **backend-driven**. The client
never asks for "everything" and never accumulates without bound.

- `limit: 10` per request; `page` and `limit` are sent on every call.
- The list is a `ListView.builder`, so rows are built lazily regardless of
  length.
- A 200px-from-the-bottom scroll listener triggers the next page, and
  `hasReachedMax` stops the requests once the backend returns a short page.

### Cursor vs offset

The backend contract is `page`/`limit` offset pagination. There is no cursor or
keyset support anywhere in the client today, so there is nothing to prefer yet.
Offset paging has two costs worth remembering when that contract changes:

- Deep pages get progressively slower server-side, because the backend must
  count past every skipped row.
- If the catalogue changes mid-scroll, rows can shift between pages, so an
  offset client can show a duplicate or skip an item. A `(sort_key, id)` keyset
  makes that impossible.

Adopting cursors means `SearchPaginationState.currentPage` becomes a token and
`hasReachedMax` becomes "the server sent no cursor". That is a deliberate
backend+client change, not a client-only refactor.

### Two invariants the tests pin

`test/features/search/presentation/controllers/search_pagination_test.dart`
holds both, because each was a real defect:

1. **A failed page is retried, not skipped.** `fetchNextPage` increments `_page`
   before awaiting. Without a rollback on the error path, a page-3 failure left
   `_page` at 3, so the retry asked for page 4 and page 3 was never delivered —
   a permanent gap in the list. The catch block hands the number back.
2. **The in-memory buffer is capped** at `_maxRetainedResults` (500). Because
   `searchResultsProvider` is deliberately not `autoDispose`, the list outlives
   the screen; without a ceiling, a long scroll keeps growing session-long
   state. Truncation also sets `hasReachedMax`, so the client stops asking.

### A guard that needed no fix

`fetchNextPage` opens with:

```dart
if (state.isFetchingMore || state.hasReachedMax || state.isLoading) return;
state = state.copyWith(isFetchingMore: true, ...);
```

It is tempting to read a race into that — a burst of scroll events arriving
before the flag is written. There is none: the check and the write are adjacent
with no `await` between them, and Dart is single-threaded, so the second caller
always observes the flag. A test that fired two concurrent `fetchNextPage()`
calls against a gated repository confirmed only one request goes out. The guard
was left exactly as it was.

### Shops by pin code

`fetchShopsByPincode` was the one list endpoint with **no bound at all**. It took
only a pincode and returned every match, so a dense area meant one request could
materialise an entire catalogue into a list. It now takes `page` and `limit` and
returns a `ShopsByPinPage { shops, hasMore }`; the screen requests the next page
as the customer scrolls.

`hasMore` is derived from a short page (`shops.length < limit`) because the
response carries no total count. That is the only end-of-list signal available
until the endpoint reports one.

`autoDispose` is kept here deliberately. The search results list is hot because a
customer is likely to bounce back into it; a pin-code browse is a bounded,
one-way trip, so re-fetching on return is cheaper than retaining a growing list.

`test/features/home/data/api_home_repository_pagination_test.dart` pins the
contract: every request carries a `limit`, pages do not overlap, the pages
together cover every shop exactly once, and a short page ends the list.

### Barcode lookup: bounded too, and ordered in SQL

`lookupBarcode(barcode)` was the last search list with no bound at all. One GS1
code can be stocked by an arbitrary number of shops, so `GET
/search/v2/barcodes/{barcode}` now takes `page` (1-based) and `limit` (default
20, max 50), and the client interface mirrors it:
`lookupBarcode(barcode, {latitude, longitude, page = 1, limit = 20})`. The
defaults preserve the old one-shot shape for the common scan, where a code
resolves to a handful of nearby shops.

Ordering moved into SQL *before* the slice — distance, then `shop_product_id` as
the tiebreak, or `shop_product_id` alone when there are no coordinates. Sorting
in Python after `limit` is only nearest-first *within that page*, so page 2 could
repeat a shop page 1 already showed, or skip one, depending on whatever the
database happened to return first. `test_search_geo.py` drives two pages through a
fake query and asserts the requested `offset`/`limit` actually reach the database,
because a pagination parameter that is silently ignored still returns a plausible
looking list.

What is still open: the scan results sheet has no load-more affordance, so a
barcode stocked by more nearby shops than `limit` shows the first page. There is
no total count in the response, so the end-of-list signal is the same short-page
heuristic as `ShopsByPinPage` (`results.length < limit`), and wiring it into
`barcodeLookupProvider` is the remaining step. Truncating client-side is not the
answer — hiding matches the server did send is worse for a scan flow than a long
list, which is exactly why this endpoint stayed unbounded until it grew real
paging.

## UI: cut rebuilds, then cut paints

Two different problems, two tools, in this order:

1. **Stop the build** — watch a projection, not a whole state object:

   ```dart
   WatchSelected<CartState, int>(
     provider: cartProvider,
     selector: (s) => s.itemCount,   // a count tick must not rebuild the title
     builder: (context, count, ref) => Badge(count),
   )
   ```

   A whole-object watch means a badge tick rebuilds every sibling, and on a list
   screen that compounds into scroll jank. The selector must be `==`-comparable
   — returning a fresh list every call defeats the mechanism entirely.

2. **Stop the paint** — wrap expensive, self-contained subtrees in
   `RepaintIsolated`. This stops rasterization propagating (a header counter
   repainting a 30-tile grid) but does **not** stop the build phase. Keep scroll
   offset separately, with a `PageStorageKey` and a controller whose `State`
   outlives the rebuild.

Lists must be lazy: `ListView.builder` / `GridView.builder`, never
`ListView(children: [...])` for anything that can grow.

## Adding a feature

1. `domain/models/` — plain models, `==` by value so change detection works.
2. `domain/<feature>_repository.dart` — the interface.
3. `data/` — implement it. Decode with `JsonMap` (tolerates missing/null/renamed
   fields and unknown enums instead of throwing), route reads through
   `CachedResourceController`.
4. `application/` — the controller. Providers go here, with an explicit lifetime
   decision.
5. `presentation/` — watch, render, dispatch. No repository calls, no JSON.

## Rules worth enforcing

- Presentation never imports `data/`. If it needs data, add a controller method.
- No `Map<String, dynamic>` crosses into presentation. `JsonMap` stops at `data/`.
- Unknown enum values never crash a screen. They render as an explicit unknown
  state, never as a confident wrong value.
- A failed refresh never clears visible content.
- Cached data is never presented as live. Disclose the age.
- Every provider is declared in `application/` and exported — never inside a
  widget file.

reach around the layer.

### Where providers live

Every provider is declared in the feature's `application/` (or `core/` for
cross-cutting concerns) and **exported** to presentation. A screen only ever
imports providers; it never defines one. This is what makes the dependency arrow
enforceable rather than aspirational.
