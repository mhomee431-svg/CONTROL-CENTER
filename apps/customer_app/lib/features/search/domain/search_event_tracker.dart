import 'models/search_models.dart';

/// Events emitted during the customer search journey.
///
/// These events are intentionally field-based and UI-agnostic so the
/// underlying analytics / tracking channel can be swapped without
/// touching presentation widgets.
sealed class SearchEvent {
  const SearchEvent();
}

/// User submitted a query (via keyboard, suggestion tap, or history tap).
class SearchSubmittedEvent extends SearchEvent {
  final String query;
  final String source; // e.g. 'keyboard', 'suggestion', 'history', 'popular'
  const SearchSubmittedEvent({required this.query, required this.source});
}

/// A suggestion was shown to the user (used for impression tracking).
class SuggestionsShownEvent extends SearchEvent {
  final List<String> suggestions;
  const SuggestionsShownEvent({required this.suggestions});
}

/// User tapped on a search suggestion.
class SuggestionSelectedEvent extends SearchEvent {
  final String query;
  final String suggestion;
  const SuggestionSelectedEvent({required this.query, required this.suggestion});
}

/// Search results were successfully returned.
class ResultsShownEvent extends SearchEvent {
  final String query;
  final int resultCount;
  final SortOption sort;
  const ResultsShownEvent({
    required this.query,
    required this.resultCount,
    required this.sort,
  });
}

/// A search request failed.
class SearchErrorEvent extends SearchEvent {
  final String query;
  final String error;
  const SearchErrorEvent({required this.query, required this.error});
}

/// User cleared the search input / cancelled the search session.
class SearchClearedEvent extends SearchEvent {
  const SearchClearedEvent();
}

/// User loaded more results (pagination).
class PaginationLoadedEvent extends SearchEvent {
  final String query;
  final int page;
  const PaginationLoadedEvent({required this.query, required this.page});
}

/// Abstract contract for tracking / logging search events.
///
/// The default [NoopSearchEventTracker] is provided so the UI works
/// out-of-the-box. A real analytics implementation can replace it via the
/// [searchEventTrackerProvider] override without restructuring the UI.
abstract class SearchEventTracker {
  void track(SearchEvent event);
}

/// No-op implementation used by default. Swap via provider override.
class NoopSearchEventTracker implements SearchEventTracker {
  @override
  void track(SearchEvent event) {
    // Intentionally no-op. Logged by real analytics in Phase 20+.
  }
}