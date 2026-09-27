import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/env/env_config.dart';
import '../../../../core/network/api_error_handler.dart';
import '../../../../core/performance/debouncer.dart';
import '../../../location/presentation/controllers/location_controller.dart';
import '../../../saved_and_history/domain/saved_and_history_repository.dart';
import '../../domain/barcode_capability.dart';
import '../../domain/search_repository.dart';
import '../../domain/search_state.dart';
import '../../domain/search_event_tracker.dart';
import '../../domain/models/search_models.dart';

// --- DEBOUNCER ---
/// Single shared [Debouncer] (core/performance). Consolidated here so search
/// does not carry a second, diverging implementation.
final debouncerProvider = Provider<Debouncer>((ref) {
  final debouncer = Debouncer(delay: const Duration(milliseconds: 500));
  ref.onDispose(debouncer.dispose);
  return debouncer;
});

/// Override this provider to plug in real analytics (Phase 20+).
final searchEventTrackerProvider = Provider<SearchEventTracker>((ref) {
  return NoopSearchEventTracker();
});

// --- QUERY + STAGE STATE ---
/// Tracks the current query text and the search lifecycle stage.
///
/// [query] mirrors every keystroke for immediate UI echo (clear button,
/// idle/typing view switch). [debouncedQuery] only advances once the input
/// debounce fires and is the ONLY field suggestion fetches should watch —
/// otherwise every keystroke would fire a network request.
class SearchQueryState {
  final String query;

  /// Debounce-settled query that drives suggestion requests.
  final String debouncedQuery;
  final SearchStage stage;

  const SearchQueryState({
    this.query = '',
    this.debouncedQuery = '',
    this.stage = SearchStage.idle,
  });

  SearchQueryState copyWith({
    String? query,
    String? debouncedQuery,
    SearchStage? stage,
  }) {
    return SearchQueryState(
      query: query ?? this.query,
      debouncedQuery: debouncedQuery ?? this.debouncedQuery,
      stage: stage ?? this.stage,
    );
  }
}

final searchQueryProvider =
    NotifierProvider<SearchQueryNotifier, SearchQueryState>(
      SearchQueryNotifier.new,
    );

class SearchQueryNotifier extends Notifier<SearchQueryState> {
  @override
  SearchQueryState build() => const SearchQueryState();

  /// Called on every keystroke. Puts the flow into [SearchStage.typing]
  /// while the debounce determines whether a suggestion fetch fires.
  /// Does NOT advance [debouncedQuery].
  void onTextChanged(String value) {
    state = state.copyWith(query: value, stage: SearchStage.typing);
  }

  /// Debounced update that triggers suggestions. Called after the debounce
  /// interval so we avoid firing a request on every keystroke.
  void debouncedTextChanged(String value) {
    state = SearchQueryState(
      query: value,
      debouncedQuery: value,
      stage: value.trim().isEmpty ? SearchStage.idle : SearchStage.typing,
    );
  }

  /// Clears the query and returns to idle.
  void clear() {
    state = const SearchQueryState();
  }
}

// --- SUGGESTIONS STATE ---
/// Watches ONLY the debounce-settled query. Selecting the single string field
/// means keystrokes that merely echo text do not re-trigger this provider.
final suggestionsProvider = FutureProvider.autoDispose<List<SearchSuggestion>>((
  ref,
) async {
  final query = ref
      .watch(searchQueryProvider.select((s) => s.debouncedQuery))
      .trim();
  if (query.length < 2) return [];
  return ref.watch(searchRepositoryProvider).getSuggestions(query);
});

// --- SEARCH HISTORY (delegates to the unified saved-and-history store) ---
/// Single source of truth for search history is
/// [SavedAndHistoryRepository] (recent searches are capped at 10 and
/// de-duplicated there). This wrapper keeps the search UI API intact,
/// migrates the legacy SharedPreferences list once, and never stores a
/// second, diverging copy of the same history.
class SearchHistoryStore {
  static const String _legacyKey = 'search_history_v1';

  final SavedAndHistoryRepository _repo;
  SearchHistoryStore(this._repo);

  Future<List<String>> load() async {
    await _migrateLegacyHistory();
    final items = await _repo.getRecentSearches();
    return items.map((e) => e.query).toList();
  }

  /// One-time migration of the old SharedPreferences-based history so no
  /// entries are lost or duplicated when switching to the unified store.
  Future<void> _migrateLegacyHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getStringList(_legacyKey);
      if (legacy == null || legacy.isEmpty) return;
      for (final query in legacy) {
        await _repo.addRecentSearch(query);
      }
      await prefs.remove(_legacyKey);
    } catch (_) {
      // Migration is best-effort; never block loading history.
    }
  }

  Future<void> add(String query) => _repo.addRecentSearch(query);

  Future<void> remove(String query) => _repo.removeRecentSearch(query);

  Future<void> clear() => _repo.clearRecentSearches();
}

final searchHistoryStoreProvider = Provider<SearchHistoryStore>((ref) {
  return SearchHistoryStore(ref.watch(savedAndHistoryRepositoryProvider));
});

/// Version counter used to invalidate the cached [recentSearchesProvider].
class RecentSearchesVersion extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final recentSearchesVersionProvider =
    NotifierProvider<RecentSearchesVersion, int>(RecentSearchesVersion.new);

/// Loads persisted recent searches. Re-runs whenever the version bumps.
final recentSearchesProvider = FutureProvider.autoDispose<List<String>>((
  ref,
) async {
  ref.watch(recentSearchesVersionProvider);
  return ref.watch(searchHistoryStoreProvider).load();
});

/// Convenience helper to persist a query and bump the version so the
/// UI re-fetches the latest history.
Future<void> saveRecentSearch(WidgetRef ref, String query) async {
  await ref.read(searchHistoryStoreProvider).add(query);
  ref.read(recentSearchesVersionProvider.notifier).bump();
}

// --- BARCODE LOOKUP ---
/// Looks up the shops selling a scanned/entered barcode.
///
/// Passes the customer's coordinates when known so the backend can rank hits
/// by proximity. An unknown barcode resolves to an empty list (a real "not
/// found"), never a placeholder product.
// --- BARCODE CAPABILITY ---
/// What the app currently knows about the backend's barcode route.
///
/// Lives in its own notifier rather than inside [barcodeLookupProvider]
/// because it must OUTLIVE a single lookup: `barcodeLookupProvider` is
/// `autoDispose` (each scanned barcode is a different family key), so if the
/// "no such route" verdict lived there the search screen would forget it the
/// moment the customer went back and the scan icon would reappear.
final barcodeSupportProvider =
    NotifierProvider<BarcodeSupportNotifier, BarcodeSupport>(
      BarcodeSupportNotifier.new,
    );

class BarcodeSupportNotifier extends Notifier<BarcodeSupport> {
  @override
  BarcodeSupport build() => BarcodeSupport.unknown;

  /// Records a verdict. A successful lookup is the only thing that can restore
  /// the entry point after a false negative (e.g. a manual entry made from a
  /// build that still showed it).
  void mark(BarcodeSupport support) {
    if (state != support) state = support;
  }
}

/// True when the barcode entry point may be offered at all: the operator has
/// not disabled it AND the backend has not been seen to lack the route.
///
/// Single source for this decision so the search screen, the scanner screen and
/// any future entry point agree on when barcode search exists.
bool barcodeEntryPointAvailable(WidgetRef ref) =>
    EnvConfig.barcodeLookupEnabled &&
    !ref.watch(barcodeSupportProvider).isHidden;

// --- BARCODE LOOKUP ---
/// Looks up the shops selling a scanned/entered barcode.
///
/// Passes the customer's coordinates when known so the backend can rank hits
/// by proximity. An unknown barcode resolves to an empty list (a real "not
/// found"), never a placeholder product.
///
/// Failures that mean "this server has no barcode route" are recorded on
/// [barcodeSupportProvider] and rethrown with copy that says exactly that —
/// otherwise the customer blames the barcode on their shelf for what is a
/// missing feature on the server. Every other failure propagates untouched so
/// the sheet/scanner can still offer a retry.
final barcodeLookupProvider = FutureProvider.autoDispose
    .family<List<ShopProductResult>, String>((ref, barcode) async {
      final trimmed = barcode.trim();
      if (trimmed.isEmpty) return const [];

      final location = ref.watch(locationControllerProvider).location;
      final hasCoords = location != null && location.hasValidCoordinates;
      try {
        final results = await ref
            .watch(searchRepositoryProvider)
            .lookupBarcode(
              trimmed,
              latitude: hasCoords ? location.latitude : null,
              longitude: hasCoords ? location.longitude : null,
            );
        ref.read(barcodeSupportProvider.notifier).mark(BarcodeSupport.supported);
        return results;
      } catch (error) {
        if (isMissingBarcodeRoute(error)) {
          ref
              .read(barcodeSupportProvider.notifier)
              .mark(BarcodeSupport.unsupported);
          throw ApiException(
            type: ApiErrorType.notFound,
            statusCode: (error as ApiException).statusCode,
            message: kBarcodeUnsupportedMessage,
          );
        }
        rethrow;
      }
    });

// --- POPULAR SEARCHES ---
final popularSearchesProvider = FutureProvider.autoDispose<List<String>>((
  ref,
) async {
  return ref.watch(searchRepositoryProvider).getPopularSearches();
});

// --- RESULTS PAGINATION STATE ---
class SearchPaginationState {
  final SearchStage stage;
  final List<ShopProductResult> results;
  final bool isLoading;
  final bool isFetchingMore;
  final bool hasReachedMax;
  final String? error;
  final SortOption sort;
  final int currentPage;
  final int totalResults;
  final Map<String, dynamic> filters;

  const SearchPaginationState({
    this.stage = SearchStage.idle,
    this.results = const [],
    this.isLoading = false,
    this.isFetchingMore = false,
    this.hasReachedMax = false,
    this.error,
    this.sort = kDefaultSortOption,
    this.currentPage = 1,
    this.totalResults = 0,
    this.filters = const {},
  });

  SearchPaginationState copyWith({
    SearchStage? stage,
    List<ShopProductResult>? results,
    bool? isLoading,
    bool? isFetchingMore,
    bool? hasReachedMax,
    String? error,
    bool clearError = false,
    SortOption? sort,
    int? currentPage,
    int? totalResults,
    Map<String, dynamic>? filters,
  }) {
    return SearchPaginationState(
      stage: stage ?? this.stage,
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      isFetchingMore: isFetchingMore ?? this.isFetchingMore,
      hasReachedMax: hasReachedMax ?? this.hasReachedMax,
      error: clearError ? null : (error ?? this.error),
      sort: sort ?? this.sort,
      currentPage: currentPage ?? this.currentPage,
      totalResults: totalResults ?? this.totalResults,
      filters: filters ?? this.filters,
    );
  }

  /// Whether the current applied filters are anything other than defaults.
  bool get hasActiveFilters =>
      _isFilterActive('in_stock') ||
      _isFilterActive('offers_only') ||
      _isFilterActive('open_now') ||
      (_isFilterActive('max_distance') && maxDistance != 10.0) ||
      minPrice > 0 ||
      (_isFilterActive('max_price') && maxPrice < 5000.0) ||
      _getFilterDouble('min_rating', 0) > 0 ||
      _getFilterString('category') != null ||
      _getFilterString('brand') != null;

  bool get inStockOnly => _getFilterBool('in_stock', false);

  bool get offersOnly => _getFilterBool('offers_only', false);

  bool get openNow => _getFilterBool('open_now', false);

  double get maxDistance => _getFilterDouble('max_distance', 10.0);

  double get minPrice => _getFilterDouble('min_price', 0.0);

  double get maxPrice => _getFilterDouble('max_price', 5000.0);

  double get minRating => _getFilterDouble('min_rating', 0);

  String? get categoryFilter => _getFilterString('category');

  String? get brandFilter => _getFilterString('brand');

  bool _isFilterActive(String key) {
    final value = filters[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    return false;
  }

  bool _getFilterBool(String key, bool fallback) {
    final value = filters[key];
    return value is bool ? value : fallback;
  }

  double _getFilterDouble(String key, double fallback) {
    final value = filters[key];
    return value is num ? value.toDouble() : fallback;
  }

  String? _getFilterString(String key) {
    final value = filters[key];
    return value is String && value.isNotEmpty ? value : null;
  }
}

final searchResultsProvider =
    NotifierProvider.family<
      SearchResultsController,
      SearchPaginationState,
      String
    >(SearchResultsController.new);

class SearchResultsController extends Notifier<SearchPaginationState> {
  SearchResultsController(this.query);

  final String query;
  int _page = 1;
  static const int _limit = 10;
  SortOption _currentSort = kDefaultSortOption;
  Map<String, dynamic>? _currentFilters;

  static final Map<String, Map<String, dynamic>> _retainedFilters = {};
  static final Map<String, SortOption> _retainedSorts = {};

  @override
  SearchPaginationState build() {
    _currentSort = _retainedSorts[query] ?? kDefaultSortOption;
    _currentFilters = _retainedFilters[query];
    _fetchInitial();
    return SearchPaginationState(
      stage: SearchStage.loading,
      sort: _currentSort,
      filters: _currentFilters ?? const {},
    );
  }

  SearchRepository get _repo => ref.read(searchRepositoryProvider);
  SearchEventTracker get _tracker => ref.read(searchEventTrackerProvider);

  /// Best-effort user coordinates for geo-ranked results. Absent when the
  /// customer has not granted/selected a location yet — the backend then
  /// ranks by relevance alone.
  ({double latitude, double longitude})? get _coords {
    final location = ref.read(locationControllerProvider).location;
    if (location == null || !location.hasValidCoordinates) return null;
    return (latitude: location.latitude, longitude: location.longitude);
  }

  Future<void> _fetchInitial() async {
    state = SearchPaginationState(
      stage: SearchStage.loading,
      sort: _currentSort,
      filters: _currentFilters ?? const {},
    );
    try {
      final coords = _coords;
      final results = await _repo.searchProducts(
        query: query,
        page: _page,
        limit: _limit,
        sort: _currentSort,
        filters: _currentFilters,
        latitude: coords?.latitude,
        longitude: coords?.longitude,
      );
      final stage = results.isEmpty ? SearchStage.empty : SearchStage.results;
      state = SearchPaginationState(
        stage: stage,
        results: results,
        hasReachedMax: results.length < _limit,
        sort: _currentSort,
        currentPage: _page,
        totalResults: results.length,
        filters: _currentFilters ?? const {},
      );
      _tracker.track(
        ResultsShownEvent(
          query: query,
          resultCount: results.length,
          sort: _currentSort,
        ),
      );
    } catch (e) {
      state = SearchPaginationState(
        stage: SearchStage.error,
        sort: _currentSort,
        filters: _currentFilters ?? const {},
        // User-safe copy; raw exception text never reaches the UI.
        error: friendlyErrorMessage(e),
      );
      _tracker.track(SearchErrorEvent(query: query, error: e.toString()));
    }
  }

  Future<void> fetchNextPage() async {
    if (state.isFetchingMore || state.hasReachedMax || state.isLoading) return;

    state = state.copyWith(isFetchingMore: true, clearError: true);
    try {
      _page++;
      final coords = _coords;
      final moreResults = await _repo.searchProducts(
        query: query,
        page: _page,
        limit: _limit,
        sort: _currentSort,
        filters: _currentFilters,
        latitude: coords?.latitude,
        longitude: coords?.longitude,
      );
      final allResults = [...state.results, ...moreResults];
      state = SearchPaginationState(
        stage: allResults.isEmpty ? SearchStage.empty : SearchStage.results,
        results: allResults,
        hasReachedMax: moreResults.length < _limit,
        sort: _currentSort,
        currentPage: _page,
        totalResults: allResults.length,
        filters: _currentFilters ?? const {},
      );
      _tracker.track(PaginationLoadedEvent(query: query, page: _page));
    } catch (e) {
      state = state.copyWith(
        isFetchingMore: false,
        // User-safe copy; raw exception text never reaches the UI.
        error: friendlyErrorMessage(e),
      );
    }
  }

  void updateSort(SortOption sort) {
    if (_currentSort == sort) return;
    _currentSort = sort;
    _retainedSorts[query] = sort;
    _page = 1;
    _fetchInitial();
  }

  void updateFilters(Map<String, dynamic> filters) {
    _currentFilters = Map<String, dynamic>.from(filters);
    _retainedFilters[query] = _currentFilters!;
    _page = 1;
    _fetchInitial();
  }

  void retry() {
    _page = 1;
    _fetchInitial();
  }

  /// Cancel a pending search in the UI (e.g., user pressed back/escape).
  void cancel() {
    ref.read(searchQueryProvider.notifier).clear();
    _page = 1;
    _currentSort = kDefaultSortOption;
    _currentFilters = null;
    _retainedSorts.remove(query);
    _retainedFilters.remove(query);
    state = const SearchPaginationState(stage: SearchStage.idle);
  }
}
