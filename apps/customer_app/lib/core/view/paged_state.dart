/// Explicit pagination state: what is loaded, and what the list is doing.
///
/// This replaces the older `PaginatedState`, which carried
/// `isLoadingInitial` + `isLoadingMore` + `hasMore` + `error` as four
/// independent fields. Those fields could express impossible combinations —
/// both loading flags set, or `hasMore == false` during a first-page load — and
/// each combination is a distinct UI bug. A sealed [PagePhase] makes exactly
/// one of them true.
///
/// The rule it encodes: a list that is already showing items must never blank
/// itself on refresh. Appending a page keeps the items; only a REPLACE
/// (a new query or a pull-to-refresh that changes the dataset) may clear them.
class PagedState<T> {
  final List<T> items;

  /// What the list is currently doing. Exactly one case at a time.
  final PagePhase phase;

  /// 1-based index of the last page successfully appended.
  final int page;

  /// Whether another page can be requested.
  ///
  /// Derived from [phase] rather than stored separately, so it cannot disagree
  /// with whether a request is in flight.
  bool get hasMore => phase is PageHasMore || phase is PageLoadingMore;

  PagedState({List<T>? items, this.phase = const PageInitial(), this.page = 0})
    : items = List.unmodifiable(items ?? const []);

  PagedState<T> copyWith({List<T>? items, PagePhase? phase, int? page}) {
    return PagedState<T>(
      items: items ?? this.items,
      phase: phase ?? this.phase,
      page: page ?? this.page,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PagedState<T> &&
          page == other.page &&
          phase.runtimeType == other.phase.runtimeType &&
          _listEquals<T>(items, other.items);

  @override
  int get hashCode =>
      Object.hash(page, phase.runtimeType, Object.hashAll(items));
}

/// Order-sensitive list equality.
///
/// A top-level function rather than a static method because a static member of
/// a generic class cannot reference the class's own type parameter.
bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The mutually exclusive phases of a paginated list.
sealed class PagePhase {
  const PagePhase();
}

/// Nothing has been requested.
final class PageInitial extends PagePhase {
  const PageInitial();
}

/// The FIRST page is loading, so there is nothing on screen yet.
final class PageLoading extends PagePhase {
  const PageLoading();
}

/// Loaded, and more pages may exist.
final class PageHasMore extends PagePhase {
  const PageHasMore();
}

/// A SUBSEQUENT page is loading. [PagedState.items] still holds every loaded
/// row — this is the state that keeps a scroll position from resetting while
/// the next page arrives.
final class PageLoadingMore extends PagePhase {
  const PageLoadingMore();
}

/// Every page has been loaded.
final class PageComplete extends PagePhase {
  const PageComplete();
}

/// Loading a replacement (new query, or a refresh that changes the dataset).
/// The list is expected to be empty for this phase.
final class PageReplacing extends PagePhase {
  const PageReplacing();
}

/// The request failed. [previousItems] are preserved so a failed refresh does
/// not destroy content the customer is already reading.
final class PageFailed extends PagePhase {
  final Object error;

  /// Retained so the caller can decide to keep showing the old rows.
  final List<Object?> previousItems;

  const PageFailed(this.error, this.previousItems);
}
