import 'load_state.dart';
import 'paged_state.dart';

/// The project's conceptual state vocabulary, and where each state actually
/// lives in code.
///
/// ## Why this file exists
///
/// The state-management rule says to KEEP the existing approach — Riverpod —
/// and not to migrate the app to a new framework without a real architectural
/// reason. The audit confirmed Riverpod is the ONLY approach in use
/// (0 `ChangeNotifier`, 0 `StateProvider`, 0 get/bloc/provider), so it stays.
///
/// That leaves a different, smaller question: when a feature needs a state
/// model, does the vocabulary cover every state the spec names? This file
/// answers it in one table, and `state_vocabulary_test.dart` fails if a state is
/// ever added to the spec list without an implementation — or implemented
/// without being reachable.
///
/// ## The eight conceptual states
///
/// | Conceptual state | Implemented as | Exists because |
/// | --- | --- | --- |
/// | Initial    | `LoadIdle`, `PageInitial`, `MutationIdle` | "we have not started" is a real state: it gets a different affordance than "still working" |
/// | Loading    | `LoadLoading`, `PageLoading`, `PageReplacing` | First fetch, nothing on screen yet |
/// | Loaded     | `LoadReady`, `PageHasMore`/`PageComplete` | The answer, with data |
/// | Empty      | `LoadEmpty` | A SUCCESS that is not a failure — needs "widen your search", not a scary error |
/// | Refreshing | `LoadRefreshing`, `PageLoadingMore` | A request is in flight but the previous value stays visible |
/// | Saving     | `MutationRunning` | A write is in flight; the control must be disabled |
/// | Success    | `MutationSucceeded` | The backend CONFIRMED it. Never optimistic |
/// | Error      | `LoadFailed`, `PageFailed`, `MutationFailed` | Retains the previous value so a failure never destroys content |
///
/// ## Which type to reach for
///
/// * A single thing that loads, searches, or filters → [LoadState]
/// * A list that pages → [PagedState] with a [PagePhase]
/// * A write (submit, save, place) → [MutationState]
///
/// They compose. A search screen is typically `LoadState<List<Product>>` for
/// the results plus a `MutationState` if it has a "save this search" action.
/// Overlapping them in ONE type is the mistake: a page that is both `Loading`
/// and `Empty` and `Error` is the boolean-cluster bug wearing a sealed costume.
enum ConceptualState {
  initial,
  loading,
  loaded,
  empty,
  refreshing,
  saving,
  success,
  error,
}

/// The conceptual states each concrete type can represent.
///
/// [StateVocabulary.coverage] is asserted by the test, so this table cannot
/// drift from the types.
const Map<String, Set<ConceptualState>> _coverage = {
  'LoadState': {
    ConceptualState.initial,
    ConceptualState.loading,
    ConceptualState.loaded,
    ConceptualState.empty,
    ConceptualState.refreshing,
    ConceptualState.error,
  },
  'PagedState': {
    ConceptualState.initial,
    ConceptualState.loading,
    ConceptualState.loaded,
    ConceptualState.refreshing,
    ConceptualState.error,
  },
  'MutationState': {
    ConceptualState.initial,
    ConceptualState.saving,
    ConceptualState.success,
    ConceptualState.error,
  },
};

/// Read-only view of the vocabulary, for tests and for a `switch` that must be
/// exhaustive if a state is ever added.
abstract final class StateVocabulary {
  /// Every conceptual state named by the spec.
  ///
  /// A getter, not a `const` field, because `Set` literals of enum values are
  /// not const-constructible in Dart 3 and `values.toSet()` is a runtime call.
  static Set<ConceptualState> get all => ConceptualState.values.toSet();

  /// Which states each state-model type can represent.
  static Set<ConceptualState> coverageOf(String type) =>
      _coverage[type] ?? const {};

  /// Types that cover nothing — the signal that a new type was declared but
  /// never wired into the vocabulary.
  static Iterable<String> get uncovered =>
      _coverage.keys.where((k) => (coverageOf(k).isEmpty));
}
