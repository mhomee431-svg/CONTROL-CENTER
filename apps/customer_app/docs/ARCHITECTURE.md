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
