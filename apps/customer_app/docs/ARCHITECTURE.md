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

Six views still reach into `data/`. They are listed in `_knownViolations` in the
guard test with a reason each, and the test **fails if a listed file stops
violating** — so the baseline cannot quietly rot:

- `help_support_screen.dart` — calls `supportRepository.submitIssue` from the
  view and tracks `_isSubmitting` / `_error` as `setState` fields. This is the
  clearest violation: it is a mutation state machine living in a widget. It
  should be a `MutationState` in a support ViewModel.
- `delete_account_screen.dart` — calls `phoneAuthService` directly.
- `barcode_scan_screen.dart`, `barcode_camera_gate.dart` — read permission
  status directly.
- `login_screen.dart`, `register_screen.dart` — import `data/phone_utils.dart`.
  This one is a naming problem rather than a layering problem: phone
  normalisation is a pure function and belongs in `domain/`. Moving the file
  fixes it with no logic change.

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
