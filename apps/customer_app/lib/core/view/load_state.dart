/// An explicit, closed set of load states.
///
/// WHY NOT BOOLEANS
/// ----------------
/// The audit that produced this file found the antipattern the ViewModel rule
/// forbids: `isLoadingInitial` + `isLoadingMore` + `hasMore` + `error` as four
/// independent fields. Those fields can express impossible combinations —
/// `isLoadingInitial && isLoadingMore`, or `hasMore == false` while a first
/// page is still loading — and every one of those combinations is a UI bug
/// waiting to happen, because a view reading them has to reason about the
/// cross-product rather than the case.
///
/// A sealed class removes the cross-product: exactly one case is true at a time,
/// and the compiler makes a view handle each one. `switch` on a sealed type is
/// also exhaustive, so adding a case later fails the build at every unhandled
/// site instead of silently falling through.
///
/// Each case carries exactly the fields that are MEANINGFUL in that case, which
/// is the second win: [LoadEmpty] has no `error` because an empty result is not
/// a failure, and [LoadFailed] has no `items` because there are none.
sealed class LoadState<T> {
  const LoadState();

  /// Nothing requested. Distinct from [LoadLoading] because a view may show a
  /// prompt for "not started" and a skeleton for "still working".
  const factory LoadState.idle() = LoadIdle<T>;

  /// First load, with nothing to show yet.
  const factory LoadState.loading() = LoadLoading<T>;

  /// Loaded successfully, and the answer is legitimately "nothing".
  const factory LoadState.empty() = LoadEmpty<T>;

  /// The loaded value, or null when there is nothing to show.
  ///
  /// A REFRESH keeps the last good value rather than blanking it, so the
  /// customer does not lose what they were reading to a spinner.
  T? get dataOrNull => switch (this) {
    LoadReady<T>(:final value) => value,
    LoadRefreshing<T>(:final previous) => previous,
    LoadFailed<T>(:final previous) => previous,
    LoadIdle<T>() || LoadLoading<T>() || LoadEmpty<T>() => null,
  };

  /// True while a request is in flight, cold or refreshing.
  bool get isLoading => this is LoadLoading<T> || this is LoadRefreshing<T>;

  /// True when the last attempt failed.
  bool get isFailed => this is LoadFailed<T>;

  /// The error, when the last attempt failed.
  Object? get error => switch (this) {
    LoadFailed<T>(:final error) => error,
    _ => null,
  };

  /// A request is in flight and [previous] is still worth keeping on screen.
  ///
  /// Returns [LoadLoading] when there is nothing to preserve, so a view never
  /// has to handle a "refreshing with no data" variant.
  LoadState<T> refreshing([T? previous]) =>
      previous == null ? LoadLoading<T>() : LoadRefreshing<T>(previous);
}

/// A refresh is in flight, but [previous] is still on screen.
///
/// This is what removes the blank-screen flash: a pull-to-refresh must not
/// throw away content the customer is already reading. A view that cannot
/// distinguish this from a cold load shows a full-page spinner over data it
/// already has.
final class LoadRefreshing<T> extends LoadState<T> {
  final T previous;
  const LoadRefreshing(this.previous);
}

/// Nothing requested yet. Distinct from [LoadLoading] because "we have not
/// started" and "we started and are still working" are different states, and a
/// view may legitimately show a prompt for the first one.
final class LoadIdle<T> extends LoadState<T> {
  const LoadIdle();
}

/// First load, with nothing to show yet. The skeleton case.
final class LoadLoading<T> extends LoadState<T> {
  const LoadLoading();
}

/// Loaded successfully with a value.
final class LoadReady<T> extends LoadState<T> {
  final T value;
  const LoadReady(this.value);
}

/// Loaded successfully, and the answer is legitimately "nothing".
///
/// Kept separate from [LoadReady] with an empty collection because an empty
/// result is a SUCCESS that needs different copy and different recovery
/// (broaden the search) than a failure (retry). Collapsing them is what makes
/// empty-state screens show a scary error.
final class LoadEmpty<T> extends LoadState<T> {
  const LoadEmpty();
}

/// The request failed. [previous] is retained so a failed refresh degrades to
/// "old content plus a retry affordance" instead of destroying it.
final class LoadFailed<T> extends LoadState<T> {
  /// A field may override a getter when its type is a subtype, which is what
  /// makes the FIELD (not a hand-written accessor) the single source of truth.
  @override
  final Object error;
  final T? previous;
  const LoadFailed(this.error, [this.previous]);
}

/// A mutation (submit, place order, save) in one of exactly these states.
///
/// The audit also found views holding `_isSubmitting` and `_error` as two
/// separate `setState` fields, which can reach `isSubmitting == true` with a
/// stale error still set, and worse, can show "failed" and "submitting" at the
/// same time. One sealed case removes that.
sealed class MutationState {
  const MutationState();

  /// Nothing in flight, nothing has succeeded yet.
  const factory MutationState.idle() = MutationIdle;

  /// The backend confirmed success. Only this may drive a success screen.
  const factory MutationState.succeeded() = MutationSucceeded;

  /// True while the mutation is in flight. Use to disable the submit control —
  /// a double-tap that fires two requests is a real duplicate-order bug.
  bool get isRunning => this is MutationRunning;

  bool get isFailed => this is MutationFailed;

  /// The underlying error, for logging and assertions ONLY. A view must render
  /// [MutationFailed.message], which is already user-safe — raw exception text
  /// can contain backend internals the customer should never see.
  Object? get error => switch (this) {
    MutationFailed(:final error) => error,
    _ => null,
  };
}

/// No mutation in flight, and none has succeeded yet.
final class MutationIdle extends MutationState {
  const MutationIdle();
}

/// The customer has tapped submit and we are waiting.
final class MutationRunning extends MutationState {
  const MutationRunning();
}

/// The backend confirmed success. Only this may drive a success screen — never
/// an optimistic guess, or a customer can be shown "your order is placed" for a
/// request that never landed.
final class MutationSucceeded extends MutationState {
  const MutationSucceeded();
}

/// The mutation failed. [message] is already user-safe.
final class MutationFailed extends MutationState {
  /// Overrides the base getter so the field is the single source of truth.
  @override
  final Object error;

  /// Already user-safe. A view renders THIS, never [error] — raw exception text
  /// can contain backend internals the customer should never see.
  final String message;

  const MutationFailed(this.error, this.message);
}
