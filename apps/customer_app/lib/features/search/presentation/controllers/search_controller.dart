import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/env/env_config.dart';
import '../../../../core/network/api_error_handler.dart';
import '../../../../core/performance/debouncer.dart';
import '../../../location/presentation/controllers/location_controller.dart';
// The notifier is the single owner of recent searches; this file projects it
// rather than keeping a second copy.
import '../../../saved_and_history/presentation/controllers/saved_and_history_controllers.dart';
import '../../data/discovery_lexicon_provider.dart';
import '../../domain/barcode_capability.dart';
import '../../domain/discovery_query.dart';
import '../../domain/search_repository.dart';
import '../../domain/search_state.dart';
import '../../domain/semantic_reranker.dart';
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

// --- SEARCH HISTORY ---
//
// Search history has NO store in this file on purpose. It used to keep a second
// cache here, refreshed by a manual version counter, which is how the search
// screen and the Saved & History tab drifted apart. The single owner is
// `RecentSearchesNotifier`; `recentSearchesProvider` below is a projection of it.
//
// The legacy `search_history_v1` SharedPreferences migration that used to live in
// this file now runs inside the notifier, so no history is lost and there is
// only one place that knows about the old key.

/// Recent searches, as plain strings for the search UI.
///
/// DERIVED from [recentSearchesNotifierProvider] — one list, one owner. Every
/// write (search, delete, clear) goes through the notifier, so a change is
/// visible everywhere at once. Copying the list here is what previously let a
/// deleted search still appear on the search screen.
final recentSearchesProvider = Provider<List<String>>((ref) {
  final async = ref.watch(recentSearchesNotifierProvider);
  // An unresolved AsyncValue has no list to project yet, so this returns empty
  // rather than throwing. Callers render an empty chip row for one frame, which
  // is the same behaviour the previous FutureProvider produced.
  final items = async.value;
  if (items == null) return const <String>[];
  return items.map((e) => e.query).toList(growable: false);
});

/// Persists a query and refreshes the one list that backs every reader.
Future<void> saveRecentSearch(WidgetRef ref, String query) async {
  await ref.read(recentSearchesNotifierProvider.notifier).addQuery(query);
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
        ref
            .read(barcodeSupportProvider.notifier)
            .mark(BarcodeSupport.supported);
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

/// Per-query sort and filter choices, kept so returning to a search restores it.
///
/// WHY THIS EXISTS
/// ---------------
/// A customer sets a sort order or narrows filters, taps into a product, then
/// hits back. The results provider is a plain (non-autoDispose)
/// `NotifierProvider.family`, so its `SearchPaginationState` — results, page,
/// loading, error — outlives the widget and comes back intact on its own. But
/// `build()` constructs a FRESH controller, and the sort/filter the customer had
/// chosen lived only in the old controller's fields. Without this store, going
/// back would silently reset the sort to `nearest` and drop the filters, while
/// the results list looked like it had been "preserved" — a confusing, wrong
/// screen. The retained choices are the part that does NOT ride along for free.
///
/// WHY IT IS A PROVIDER, NOT A `static` MAP
/// ----------------------------------------
/// This was previously two `static final` maps on [SearchResultsController].
/// That was a process-lifetime cache hidden from Riverpod:
///
///   * unbounded growth — every distinct query ever searched kept an entry,
///     and only `cancel()` ever removed one;
///   * uninvalidatable — no `ref.invalidate` can clear a static, so a sign-out
///     or "clear my data" left the previous customer's filters in memory;
///   * shared across containers — a `ProviderContainer` in a test inherited
///     whatever the previous test had left behind, making tests order-dependent;
///   * stale by design — re-running the query "milk" months later silently
///     reused that old filter set.
///
/// Holding it in a provider makes the lifetime explicit and scoped: it is
/// disposed with its container, clearable with `ref.invalidate`, and isolated
/// per test.
final searchQueryPreferencesProvider = Provider<SearchQueryPreferences>((ref) {
  return SearchQueryPreferences();
});

/// The customer's per-query sort and filter choices.
class SearchQueryPreferences {
  final Map<String, SortOption> _sorts = {};
  final Map<String, Map<String, dynamic>> _filters = {};

  SortOption sortFor(String query) => _sorts[query] ?? kDefaultSortOption;

  Map<String, dynamic>? filtersFor(String query) => _filters[query];

  void recordSort(String query, SortOption sort) => _sorts[query] = sort;

  /// Defensive copy on the way in and on the way out, so a caller mutating the
  /// map it passed in cannot retroactively change what was remembered.
  void recordFilters(String query, Map<String, dynamic> filters) {
    _filters[query] = Map<String, dynamic>.from(filters);
  }

  /// Forgets one query, e.g. when the customer cancels this search.
  void forget(String query) {
    _sorts.remove(query);
    _filters.remove(query);
  }

  /// Forgets everything. Called on sign-out so the next customer never inherits
  /// the previous one's filter choices.
  void clear() {
    _sorts.clear();
    _filters.clear();
  }

  /// Number of queries with remembered choices. Exposed for the leak test: a
  /// long session must not grow this without bound.
  @visibleForTesting
  int get retainedQueryCount => _sorts.length;
}

class SearchResultsController extends Notifier<SearchPaginationState> {
  SearchResultsController(this.query);

  final String query;
  int _page = 1;
  static const int _limit = 10;

  /// Hard ceiling on results held in memory for one search.
  ///
  /// 500 rows is far more than anyone scrolls through, and each row is a full
  /// `ShopProductResult` held in a Riverpod state object that -- because
  /// `searchResultsProvider` is deliberately NOT autoDispose -- lives for the
  /// whole session. Without a ceiling, a customer holding a fling on a broad
  /// query could keep the list (and its memory) growing for as long as the
  /// backend has rows to give.
  static const int _maxRetainedResults = 500;

  SortOption _currentSort = kDefaultSortOption;
  Map<String, dynamic>? _currentFilters;

  /// Monotonic token identifying the newest in-flight results request.
  ///
  /// WHY THIS EXISTS
  /// ---------------
  /// `updateSort`, `updateFilters`, `retry` and pull-to-refresh each restart the
  /// search from page 1, and any of them can fire while an earlier fetch is
  /// still open. Without a token the older response is free to arrive LAST and
  /// write itself over the newer state: the customer picks "price: low to
  /// high", the previous relevance-sorted request is still in flight, and its
  /// rows land on top of the sorted ones. The list then shows results that do
  /// not match the control the customer just used, and no amount of tapping
  /// fixes it because the state is already "settled".
  ///
  /// A token, rather than an `isLoading` flag, is required because the hazard is
  /// not two requests at once -- it is two requests whose completion order is
  /// the reverse of the order they were started in. A flag cannot see that.
  int _requestSeq = 0;

  /// True while [seq] is still the newest request and this notifier is alive.
  bool _isCurrent(int seq) => ref.mounted && seq == _requestSeq;

  SearchQueryPreferences get _prefs => ref.read(searchQueryPreferencesProvider);

  @override
  SearchPaginationState build() {
    _currentSort = _prefs.sortFor(query);
    _currentFilters = _prefs.filtersFor(query);
    _fetchInitial();
    return SearchPaginationState(
      stage: SearchStage.loading,
      sort: _currentSort,
      filters: _currentFilters ?? const {},
    );
  }

  SearchRepository get _repo => ref.read(searchRepositoryProvider);
  SearchEventTracker get _tracker => ref.read(searchEventTrackerProvider);

  /// The optional semantic layer, built over whatever reranker is installed.
  ///
  /// Reading it here is what makes the seam real: overriding
  /// [semanticRerankerProvider] changes search ordering without touching this
  /// file. The shipped reranker is a no-op, so today this costs one completed
  /// future per search and changes nothing.
  ProductDiscoveryPipeline get _discoveryPipeline =>
      ProductDiscoveryPipeline(ref.read(semanticRerankerProvider));

  /// What kind of thing the customer typed, used to pick the right route.
  ///
  /// This is what makes a hand-typed barcode work. Previously every keystroke
  /// went to `searchProducts`, so 13 digits were treated as free text and the
  /// full-text index returned nothing -- the platform already has an exact
  /// lookup for that identifier and simply was not being asked. The classifier
  /// is pure and local, so reading it costs no request.
  ///
  /// Classified directly rather than through a family provider: classification
  /// is a handful of string checks, and a family would cache one entry per
  /// distinct query for the whole session, which is not worth the memory.
  DiscoveryQuery get _intent =>
      classifyDiscovery(query, lexicon: ref.read(discoveryLexiconProvider));

  /// Filters the classifier has PROVEN, merged under the customer's own.
  ///
  /// The backend already accepts `brand` and `category` as "ID or name"
  /// (`GET /search/v2/products`), and `api_search_repository` already forwards
  /// them — but nothing ever set them, so a brand query only ever reached the
  /// free-text index. This is where discovery's verdict finally gets used.
  ///
  /// ONLY a [DiscoveryConfidence.certain] verdict narrows the result set. A
  /// narrower filter is a one-way door: getting it wrong HIDES real products,
  /// which is far worse than showing a few extra ones. A "Dove shampoo" style
  /// `likely` brand match is therefore left to the text search, which already
  /// ranks that brand's products first without being able to exclude anything.
  Map<String, dynamic>? get _inferredFilters {
    final intent = _intent;
    if (intent.confidence != DiscoveryConfidence.certain) return null;
    return switch (intent.mode) {
      DiscoveryMode.brand => {'brand': intent.normalized},
      DiscoveryMode.category => {'category': intent.normalized},
      DiscoveryMode.productName ||
      DiscoveryMode.variant ||
      DiscoveryMode.barcode => null,
    };
  }

  /// The customer's filters, with proven inferred ones applied underneath.
  ///
  /// The customer's own choices win on a key clash: a filter the customer set
  /// deliberately is never overwritten by a guess the app made.
  Map<String, dynamic>? get _effectiveFilters {
    final inferred = _inferredFilters;
    // Bound to a local first: `_currentFilters` is a mutable field, so Dart
    // will not promote it to non-null across the null check.
    final current = _currentFilters;
    if (inferred == null) return current;
    if (current == null) return inferred;
    return {...inferred, ...current};
  }

  /// Best-effort user coordinates for geo-ranked results. Absent when the
  /// customer has not granted/selected a location yet — the backend then
  /// ranks by relevance alone.
  ({double latitude, double longitude})? get _coords {
    final location = ref.read(locationControllerProvider).location;
    if (location == null || !location.hasValidCoordinates) return null;
    return (latitude: location.latitude, longitude: location.longitude);
  }

  /// Fetches one page of results using the route the query's intent calls for.
  ///
  /// A barcode goes to the exact lookup; everything else goes to the text
  /// search. Both share the same bounded pagination contract (`page` 1-based,
  /// `limit` required), so a product stocked by many shops still pages the same
  /// way whichever route answered -- and a barcode can never materialise an
  /// unbounded catalogue into one response.
  Future<List<ShopProductResult>> _fetchPage(int page) {
    final coords = _coords;
    final intent = _intent;
    if (intent.requiresBarcodeLookup) {
      return _repo.lookupBarcode(
        intent.normalized,
        latitude: coords?.latitude,
        longitude: coords?.longitude,
        page: page,
        limit: _limit,
      );
    }
    return _repo.searchProducts(
      query: query,
      page: page,
      limit: _limit,
      sort: _currentSort,
      filters: _effectiveFilters,
      latitude: coords?.latitude,
      longitude: coords?.longitude,
    );
  }

  Future<void> _fetchInitial() async {
    // Claim a token BEFORE the first await so a later restart of the search
    // (sort change, filter change, pull-to-refresh) can mark this one stale.
    final requestSeq = ++_requestSeq;
    state = SearchPaginationState(
      stage: SearchStage.loading,
      sort: _currentSort,
      filters: _currentFilters ?? const {},
    );
    try {
      final fetched = await _fetchPage(_page);
      // A newer request owns the state now; this response is history.
      if (!_isCurrent(requestSeq)) return;
      // The optional semantic layer may only reorder this page. It runs after
      // the staleness check so a superseded search never pays for it, and
      // before the state write so the customer sees one settled order rather
      // than a visible reshuffle.
      //
      // Only page 1: appending later pages keeps their backend order, because
      // re-sorting rows the customer has already scrolled past would make the
      // list jump under their thumb.
      final results = await _discoveryPipeline.run(query, fetched);
      if (!_isCurrent(requestSeq)) return;
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
      // Same rule on the failure path: an error from a superseded request must
      // not replace the newer results with an error screen, and must not be
      // tracked as the outcome of the search the customer is actually looking
      // at.
      if (!_isCurrent(requestSeq)) return;
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
    // Claim the fetch SYNCHRONOUSLY, before the first `await`.
    //
    // `_onScroll` fires on every scroll event once the customer is within 200px
    // of the bottom, and a fling can fire several in a row. Guarding on
    // `state.isFetchingMore` alone was not enough: the old code checked the
    // state and only THEN set the flag, so every caller reaching the check
    // before that write saw `false`. Two callers both passed, both ran
    // `_page++`, and the list fetched pages 2 and 3 -- meaning page 2's rows
    // The check and the flag set below are adjacent with no `await` between
    // them, so this guard is sound: Dart is single-threaded, and a second
    // caller arriving before the first suspends sees `isFetchingMore == true`.
    //
    // An earlier version of this comment claimed a race here, reasoning that a
    // burst of scroll events could slip past the check before the flag was
    // written. Deleting the guard and re-running proved otherwise -- both calls
    // still collapsed into a single request. The false claim is gone; the
    // original guard stays, because it is already doing its job.
    if (state.isFetchingMore || state.hasReachedMax || state.isLoading) return;

    // A full buffer stops us pulling more pages at all.
    // See [_maxRetainedResults].
    if (state.results.length >= _maxRetainedResults) {
      state = state.copyWith(hasReachedMax: true, isFetchingMore: false);
      return;
    }

    state = state.copyWith(isFetchingMore: true, clearError: true);
    // Pin the token this page belongs to. If a sort change, filter change or
    // refresh restarts the search while this page is in flight, the rows coming
    // back belong to a result set that no longer exists and must not be
    // appended to the new one.
    final requestSeq = _requestSeq;
    try {
      final page = ++_page;
      final moreResults = await _fetchPage(page);

      if (!_isCurrent(requestSeq)) return;

      final merged = [...state.results, ...moreResults];
      // Cap what we keep in memory. A long scroll must not grow the list
      // without bound: the first [_maxRetainedResults] rows stay available for
      // scrolling back and the tail is dropped instead of held forever.
      // `_page` keeps advancing regardless, so this is a memory ceiling, not a
      // change to the paging contract with the backend.
      final truncated = merged.length > _maxRetainedResults
          ? merged.length - _maxRetainedResults
          : 0;
      final retained = truncated > 0
          ? merged.sublist(0, _maxRetainedResults)
          : merged;

      state = SearchPaginationState(
        stage: retained.isEmpty ? SearchStage.empty : SearchStage.results,
        results: retained,
        // Short page means the backend is exhausted; truncation means WE stop.
        hasReachedMax: moreResults.length < _limit || truncated > 0,
        sort: _currentSort,
        currentPage: page,
        totalResults: retained.length,
        filters: _currentFilters ?? const {},
      );
      _tracker.track(PaginationLoadedEvent(query: query, page: page));
    } catch (e) {
      // A superseded page must not report an error either -- the search it
      // belonged to is no longer on screen.
      if (!_isCurrent(requestSeq)) return;
      // Hand the page number back. The request failed, so those rows were never
      // delivered; leaving `_page` incremented would make the next attempt ask
      // for the page AFTER the one that failed, permanently skipping it and
      // leaving a gap the customer can never fill.
      _page--;
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
    _prefs.recordSort(query, sort);
    _page = 1;
    _fetchInitial();
  }

  void updateFilters(Map<String, dynamic> filters) {
    _currentFilters = Map<String, dynamic>.from(filters);
    _prefs.recordFilters(query, _currentFilters!);
    _page = 1;
    _fetchInitial();
  }

  void retry() {
    _page = 1;
    _fetchInitial();
  }

  /// Pull-to-refresh: re-runs the current search from page 1.
  ///
  /// Refresh means "give me this search again", not "start over", so the query,
  /// sort and filters are deliberately left alone. Clearing them would silently
  /// change what the customer is looking at -- they asked for the same search
  /// with fresher stock data, not for the default search.
  ///
  /// It awaits the fetch rather than firing and forgetting so `RefreshIndicator`
  /// holds the spinner until fresh rows have actually replaced the stale ones;
  /// returning immediately makes the gesture feel like it did nothing.
  ///
  /// A refresh already in flight is superseded by the next one, and any page
  /// request that was open when this started is discarded, so the customer can
  /// pull repeatedly without a backlog of stale responses landing in order.
  Future<void> refresh() async {
    _page = 1;
    await _fetchInitial();
  }

  /// Cancel a pending search in the UI (e.g., user pressed back/escape).
  void cancel() {
    // Invalidate anything still in flight. Without this, a page or initial fetch
    // the customer walked away from still owns the state and lands after the
    // reset below, repopulating a search screen they have already left.
    _requestSeq++;
    ref.read(searchQueryProvider.notifier).clear();
    _page = 1;
    _currentSort = kDefaultSortOption;
    _currentFilters = null;
    _prefs.forget(query);
    state = const SearchPaginationState(stage: SearchStage.idle);
  }
}
