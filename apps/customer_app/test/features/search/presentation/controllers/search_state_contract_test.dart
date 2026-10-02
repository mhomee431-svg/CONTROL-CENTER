import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_app/features/search/domain/models/search_models.dart';
import 'package:hyperlocal_app/features/search/domain/search_repository.dart';
import 'package:hyperlocal_app/features/search/domain/search_state.dart';
import 'package:hyperlocal_app/features/search/presentation/controllers/search_controller.dart';

/// A repository that counts calls, so a test can tell a CACHE apart from a
/// REFETCH. Both can be correct; only one of them costs a round trip.
class _CountingRepository implements SearchRepository {
  int suggestionCalls = 0;
  int productCalls = 0;

  @override
  Future<List<SearchSuggestion>> getSuggestions(String query) async {
    suggestionCalls++;
    if (query.isEmpty) return const [];
    return [
      SearchSuggestion(text: '$query 500mg'),
      SearchSuggestion(text: 'Samsung $query', isBrand: true),
    ];
  }

  @override
  Future<List<ShopProductResult>> searchProducts({
    required String query,
    required int page,
    required int limit,
    SortOption sort = SortOption.nearest,
    Map<String, dynamic>? filters,
    double? latitude,
    double? longitude,
  }) async {
    productCalls++;
    return List.generate(
      3,
      (i) => ShopProductResult(
        id: 'r_${page}_$i',
        productId: 'p_${page}_$i',
        productName: '$query row $i',
        productImageUrl: '',
        shopId: 's$page',
        shopName: 'Shop $page',
        price: 10.0 + i,
        isAvailable: true,
        distanceInKm: 1,
        shopRating: 4,
        lastUpdated: DateTime(2026, 1, 1),
        availability: InventoryAvailability.inStock,
        freshness: FreshnessLevel.fresh,
      ),
      growable: false,
    );
  }

  @override
  Future<List<String>> getPopularSearches() async => const [];

  @override
  Future<List<String>> getRecentSearches() async => const [];

  @override
  Future<List<ShopProductResult>> lookupBarcode(
    String barcode, {
    double? latitude,
    double? longitude,
    int page = 1,
    int limit = 20,
  }) async => const [];
}

void main() {
  /// The rule: search state must preserve query, suggestions, results, filters,
  /// sort, pagination, loading and error across a Product Details round trip.
  ///
  /// That round trip is a `context.push`, which does NOT dispose the
  /// `ProviderContainer`. So anything held by the container survives on its own,
  /// and only what lives in a controller's own fields is at risk. This file
  /// states which is which, so a later change that turns a preserved value into
  /// a lost one gets caught.
  group('search state contract', () {
    late _CountingRepository repo;
    late ProviderContainer container;

    setUp(() {
      repo = _CountingRepository();
      container = ProviderContainer(
        overrides: [searchRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
    });

    test('query survives', () {
      container.read(searchQueryProvider.notifier).debouncedTextChanged('dove');
      expect(container.read(searchQueryProvider).query, 'dove');
      expect(container.read(searchQueryProvider).debouncedQuery, 'dove');
    });

    test('suggestions come back, driven by the preserved query', () async {
      container.read(searchQueryProvider.notifier).debouncedTextChanged('dove');

      // A listener stands in for the suggestions widget. `listen` rather than
      // `read` matters: `read` leaves no lasting listener, so an autoDispose
      // provider is not disposed deterministically and a call count measured
      // that way says nothing about the real screen.
      final onScreen = container.listen(suggestionsProvider, (_, _) {});
      final first = await container.read(suggestionsProvider.future);
      expect(first, isNotEmpty);
      expect(first.first.text, contains('dove'));
      expect(repo.suggestionCalls, 1);

      // Leave: the widget goes away, so the autoDispose provider is torn down.
      onScreen.close();
      await Future.delayed(const Duration(milliseconds: 10));

      // Return: the query is still `dove`, and the suggestions are right again.
      final backOnScreen = container.listen(suggestionsProvider, (_, _) {});
      addTearDown(backOnScreen.close);
      final second = await container.read(suggestionsProvider.future);
      expect(second.map((s) => s.text), first.map((s) => s.text));

      // They are RE-FETCHED, not restored from a cache: autoDispose means
      // leaving the screen drops the result. Correctness is preserved because
      // the *query* is preserved and drives the fresh request. This is one
      // saved round trip, not a lost state, so it is left as-is rather than
      // promoted to a hot provider.
      expect(
        repo.suggestionCalls,
        2,
        reason: 'a round trip costs one suggestion request, not zero',
      );
    });

    test(
      'results, pagination, loading and error survive without a refetch',
      () async {
        container.read(searchResultsProvider('milk'));
        await Future.delayed(const Duration(milliseconds: 10));

        final state = container.read(searchResultsProvider('milk'));
        expect(state.results, isNotEmpty);
        expect(state.currentPage, 1);
        expect(state.isLoading, isFalse);
        expect(state.error, isNull);
        expect(state.stage, SearchStage.results);

        expect(
          identical(
            container.read(searchResultsProvider('milk')),
            container.read(searchResultsProvider('milk')),
          ),
          isTrue,
          reason: 'not autoDispose: this state lives in the container',
        );
        expect(repo.productCalls, 1, reason: 're-reading does not refetch');
      },
    );

    test('filters and sort survive', () async {
      container.read(searchResultsProvider('milk').notifier).updateFilters({
        'in_stock': true,
      });
      container
          .read(searchResultsProvider('milk').notifier)
          .updateSort(SortOption.lowestPrice);
      await Future.delayed(const Duration(milliseconds: 10));

      final state = container.read(searchResultsProvider('milk'));
      expect(state.filters['in_stock'], true);
      expect(state.sort, SortOption.lowestPrice);
    });

    test('re-running the SAME query keeps its sort', () async {
      container
          .read(searchResultsProvider('milk').notifier)
          .updateSort(SortOption.lowestPrice);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(
        container.read(searchResultsProvider('milk')).sort,
        SortOption.lowestPrice,
      );
    });

    test('a DIFFERENT query starts clean', () async {
      container
          .read(searchResultsProvider('milk').notifier)
          .updateSort(SortOption.lowestPrice);
      await Future.delayed(const Duration(milliseconds: 10));

      container.read(searchResultsProvider('bread'));
      await Future.delayed(const Duration(milliseconds: 10));

      final bread = container.read(searchResultsProvider('bread'));
      expect(bread.sort, kDefaultSortOption);
      expect(bread.filters, isEmpty);
    });
  });
}
