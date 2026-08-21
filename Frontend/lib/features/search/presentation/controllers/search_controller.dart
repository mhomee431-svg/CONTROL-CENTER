import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/search_repository.dart';
import '../../domain/models/search_models.dart';

// --- DEBOUNCER ---
class Debouncer {
  final int milliseconds;
  Timer? _timer;

  Debouncer({required this.milliseconds});

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: milliseconds), action);
  }

  void dispose() {
    _timer?.cancel();
  }
}

final debouncerProvider = Provider<Debouncer>((ref) {
  final debouncer = Debouncer(milliseconds: 500);
  ref.onDispose(debouncer.dispose);
  return debouncer;
});

// --- SUGGESTIONS STATE ---
final queryProvider = NotifierProvider<QueryNotifier, String>(QueryNotifier.new);

class QueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void update(String value) => state = value;
}

final suggestionsProvider = FutureProvider.autoDispose<List<SearchSuggestion>>((ref) async {
  final query = ref.watch(queryProvider);
  if (query.length < 2) return [];
  return ref.watch(searchRepositoryProvider).getSuggestions(query);
});

// --- RECENT & POPULAR SEARCHES ---
final recentSearchesProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  return ref.watch(searchRepositoryProvider).getRecentSearches();
});

final popularSearchesProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  return ref.watch(searchRepositoryProvider).getPopularSearches();
});

// --- RESULTS PAGINATION STATE ---
class SearchPaginationState {
  final List<ShopProductResult> results;
  final bool isLoading;
  final bool isFetchingMore;
  final bool hasReachedMax;
  final String? error;

  const SearchPaginationState({
    this.results = const [],
    this.isLoading = false,
    this.isFetchingMore = false,
    this.hasReachedMax = false,
    this.error,
  });

  SearchPaginationState copyWith({
    List<ShopProductResult>? results,
    bool? isLoading,
    bool? isFetchingMore,
    bool? hasReachedMax,
    String? error,
    bool clearError = false,
  }) {
    return SearchPaginationState(
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      isFetchingMore: isFetchingMore ?? this.isFetchingMore,
      hasReachedMax: hasReachedMax ?? this.hasReachedMax,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final searchResultsProvider = NotifierProvider.family<SearchResultsController, SearchPaginationState, String>(
  SearchResultsController.new,
);

class SearchResultsController extends Notifier<SearchPaginationState> {
  SearchResultsController(this.query);

  final String query;
  int _page = 1;
  static const int _limit = 10;
  SortOption _currentSort = SortOption.nearest;
  Map<String, dynamic>? _currentFilters;

  @override
  SearchPaginationState build() {
    _fetchInitial();
    return const SearchPaginationState();
  }

  SearchRepository get _repo => ref.read(searchRepositoryProvider);

  Future<void> _fetchInitial() async {
    state = const SearchPaginationState(isLoading: true);
    try {
      final results = await _repo.searchProducts(
        query: query,
        page: _page,
        limit: _limit,
        sort: _currentSort,
        filters: _currentFilters,
      );
      state = SearchPaginationState(
        results: results,
        hasReachedMax: results.length < _limit,
      );
    } catch (e) {
      state = SearchPaginationState(error: e.toString());
    }
  }

  Future<void> fetchNextPage() async {
    if (state.isFetchingMore || state.hasReachedMax || state.isLoading) return;

    state = state.copyWith(isFetchingMore: true, clearError: true);
    try {
      _page++;
      final moreResults = await _repo.searchProducts(
        query: query,
        page: _page,
        limit: _limit,
        sort: _currentSort,
        filters: _currentFilters,
      );
      state = SearchPaginationState(
        results: [...state.results, ...moreResults],
        hasReachedMax: moreResults.length < _limit,
      );
    } catch (e) {
      // Revert fetching state but keep results, allow retry
      state = state.copyWith(isFetchingMore: false, error: e.toString());
    }
  }

  void updateSort(SortOption sort) {
    if (_currentSort == sort) return;
    _currentSort = sort;
    _page = 1;
    _fetchInitial();
  }

  void updateFilters(Map<String, dynamic> filters) {
    _currentFilters = filters;
    _page = 1;
    _fetchInitial();
  }

  void retry() {
    _page = 1;
    _fetchInitial();
  }
}