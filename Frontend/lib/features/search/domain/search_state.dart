import 'models/search_models.dart';

/// Lifecycle stages of the customer search experience.
///
/// - [idle]:      Empty query, ready for input.
/// - [typing]:    User is actively typing (debounce in progress).
/// - [loading]:   A search request is in flight.
/// - [results]:   Results are displayed.
/// - [empty]:     Search completed with no matching results.
/// - [error]:     Search request failed.
enum SearchStage { idle, typing, loading, results, empty, error }

/// Parameters that describe a single search request.
///
/// Kept field-based (not a widget) so business logic stays out of widgets.
/// This maps directly to the future Phase 20 search engine query contract.
class SearchParams {
  final String query;
  final int page;
  final int limit;
  final SortOption sort;
  final Map<String, dynamic>? filters;

  const SearchParams({
    required this.query,
    required this.page,
    required this.limit,
    this.sort = SortOption.nearest,
    this.filters,
  });

  SearchParams copyWith({
    String? query,
    int? page,
    int? limit,
    SortOption? sort,
    Map<String, dynamic>? filters,
    bool clearFilters = false,
  }) {
    return SearchParams(
      query: query ?? this.query,
      page: page ?? this.page,
      limit: limit ?? this.limit,
      sort: sort ?? this.sort,
      filters: clearFilters ? null : (filters ?? this.filters),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SearchParams &&
        other.query == query &&
        other.page == page &&
        other.limit == limit &&
        other.sort == sort;
  }

  @override
  int get hashCode => Object.hash(query, page, limit, sort);
}