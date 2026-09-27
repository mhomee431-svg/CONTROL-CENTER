/// A named, typed load state for anything the UI renders from remote data.
///
/// WHY NOT `AsyncValue`
/// -------------------
/// `AsyncValue` cannot express the one state that matters most in a
/// stale-while-revalidate app: **"showing cached data while refreshing"**. It
/// offers `loading` (no data) or `data` (not refreshing), so a refresh either
/// blanks the screen (bad UX) or is invisible (the customer cannot tell the
/// data is old).
///
/// [ResourceCached] carries the data AND says it is stale, which is what lets
/// the UI show content immediately and still disclose its age — the same
/// provenance rule the product-details screen already depends on.
sealed class Resource<T> {
  const Resource();

  /// The data, when there is any — including while refreshing or after a
  /// failure, so the UI never has nothing to draw.
  T? get dataOrNull => switch (this) {
    ResourceData<T>(:final value) => value,
    ResourceRefreshing<T>(:final previous) => previous,
    ResourceCached<T>(:final value) => value,
    ResourceError<T>(:final previous) => previous,
    ResourceIdle<T>() || ResourceLoading<T>() => null,
  };

  /// True while a request is in flight, whether or not there is data to show.
  bool get isLoading => switch (this) {
    ResourceLoading<T>() || ResourceRefreshing<T>() => true,
    _ => false,
  };

  /// True when [dataOrNull] came from a cache rather than a fresh response.
  bool get isStale => this is ResourceCached<T>;

  /// True when the last attempt failed.
  bool get hasError => this is ResourceError<T>;

  /// The error, when the last attempt failed.
  Object? get error => switch (this) {
    ResourceError<T>(:final error) => error,
    _ => null,
  };

  /// The "a request is in flight" form of this state, KEEPING [previous] if
  /// there is any.
  ///
  /// This is the transition that removes the blank-screen flash. If the customer
  /// is already looking at data, a refresh becomes [ResourceRefreshing] and they
  /// keep reading it; only a genuinely cold open becomes [ResourceLoading].
  Resource<T> toLoading([T? previous]) {
    final existing = dataOrNull ?? previous;
    if (existing == null) return ResourceLoading<T>();
    return ResourceRefreshing(existing);
  }
}

/// Nothing requested yet. Lets a screen distinguish "we have not started" from
/// "we started and are still working" — a real difference for a skeleton.
final class ResourceIdle<T> extends Resource<T> {
  const ResourceIdle();
}

/// First load, with nothing to show yet.
final class ResourceLoading<T> extends Resource<T> {
  const ResourceLoading();
}

/// Loaded, and this IS the current answer.
final class ResourceData<T> extends Resource<T> {
  final T value;
  const ResourceData(this.value);
}

/// A refresh is in flight, but [previous] is still on screen.
///
/// The state that removes the "flash of empty" on every pull-to-refresh.
final class ResourceRefreshing<T> extends Resource<T> {
  final T previous;
  const ResourceRefreshing(this.previous);
}

/// Loaded from cache at [cachedAt], and not yet revalidated.
///
/// The UI MUST disclose this rather than presenting it as live.
final class ResourceCached<T> extends Resource<T> {
  final T value;
  final DateTime cachedAt;
  const ResourceCached(this.value, this.cachedAt);
}

/// The last attempt failed. [previous] is kept so a failed refresh degrades to
/// "showing old data plus a retry affordance" instead of blanking the screen.
final class ResourceError<T> extends Resource<T> {
  @override
  final Object error;
  final T? previous;
  const ResourceError(this.error, [this.previous]);
}
