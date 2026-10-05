import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_app/features/search/data/mock_search_repository.dart';
import 'package:hyperlocal_app/features/search/domain/models/search_models.dart';
import 'package:hyperlocal_app/features/search/domain/search_repository.dart';
import 'package:hyperlocal_app/features/search/domain/search_state.dart';
import 'package:hyperlocal_app/features/search/presentation/controllers/search_controller.dart';
import 'package:hyperlocal_app/features/search/presentation/screens/search_results_screen.dart';

/// Serves one fixed result so the screen reaches the results stage.
class _StubSearchRepository implements SearchRepository {
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
    return [
      ShopProductResult(
        id: 'r1',
        productId: 'p1',
        productName: 'Dove Shampoo 650ml',
        productImageUrl: '',
        shopId: 's1',
        shopName: 'Gupta Electronics',
        price: 240,
        isAvailable: true,
        distanceInKm: 1.2,
        shopRating: 4.5,
        lastUpdated: DateTime(2026, 1, 1),
        availability: InventoryAvailability.inStock,
        freshness: FreshnessLevel.fresh,
      ),
    ];
  }

  @override
  Future<List<String>> getPopularSearches() async => const [];

  @override
  Future<List<String>> getRecentSearches() async => const [];

  @override
  Future<List<SearchSuggestion>> getSuggestions(String query) async => const [];

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
  testWidgets('shows the spec header Search Results for "<query>"', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        searchRepositoryProvider.overrideWithValue(_StubSearchRepository()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: SearchResultsScreen(query: 'Dove Shampoo'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Search Results for "Dove Shampoo"'), findsOneWidget);
    // The count line below is complementary, not a replacement.
    expect(find.text('1 results for "Dove Shampoo"'), findsOneWidget);
  });

  // Search state that must survive leaving the screen: query, suggestions,
  // results, filters, sort, pagination, loading, error.
  //
  // results/page/loading/error survive for free -- `searchResultsProvider` is a
  // plain (non-autoDispose) `NotifierProvider.family`, so its state lives in the
  // container, not the widget, and pushing to Product Details cannot dispose
  // it. Sort and filters do NOT ride along: `build()` makes a fresh controller.
  // That gap is what `SearchQueryPreferences` covers.
  group('search state preservation', () {
    ProviderContainer newContainer() => ProviderContainer(
      overrides: [
        searchRepositoryProvider.overrideWithValue(MockSearchRepository()),
      ],
    );

    /// Settles the controller's async initial fetch.
    ///
    /// `MockSearchRepository` deliberately sleeps 800ms to simulate network
    /// latency, so pumping 100ms is not enough -- the assertions would run
    /// while the screen was still loading and every result list came back empty.
    /// A real elapse past the latency, not just extra pumps.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('sort and filters survive a push to product details', (
      tester,
    ) async {
      final container = newContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: SearchResultsScreen(query: 'Dove Shampoo'),
          ),
        ),
      );
      await settle(tester);

      // The customer narrows the search, then changes the sort.
      container
          .read(searchResultsProvider('Dove Shampoo').notifier)
          .updateFilters({'in_stock': true});
      await settle(tester);
      container
          .read(searchResultsProvider('Dove Shampoo').notifier)
          .updateSort(SortOption.lowestPrice);
      await settle(tester);

      final beforePush = container.read(searchResultsProvider('Dove Shampoo'));
      expect(beforePush.sort, SortOption.lowestPrice);
      expect(beforePush.filters['in_stock'], true);

      // Simulate the push: the results screen is torn down. The container is
      // untouched, which is exactly what `context.push('/product/...')` does.
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await settle(tester);

      // ...and the customer navigates back to the results.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: SearchResultsScreen(query: 'Dove Shampoo'),
          ),
        ),
      );
      await settle(tester);

      final afterReturn = container.read(searchResultsProvider('Dove Shampoo'));
      // Sort and filters came back instead of silently reverting to default.
      expect(afterReturn.sort, SortOption.lowestPrice);
      expect(afterReturn.filters['in_stock'], true);
      // Results, pagination and stage are still there -- no re-fetch reset it.
      expect(afterReturn.results, isNotEmpty);
      expect(afterReturn.currentPage, beforePush.currentPage);
      expect(afterReturn.stage, SearchStage.results);
    });

    testWidgets(
      'the whole Search-Filter-Product-Back round trip keeps all three',
      (tester) async {
        // The three pieces of temporary state the customer set, asserted together
        // because that is the flow they actually perform. Each is covered
        // individually elsewhere; this is the one that proves the COMBINATION
        // survives, which is what "back should not lose my search" means.
        final container = newContainer();
        addTearDown(container.dispose);

        // 1. Search: the customer types and submits.
        container
            .read(searchQueryProvider.notifier)
            .debouncedTextChanged('Dove Shampoo');

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: SearchResultsScreen(query: 'Dove Shampoo'),
            ),
          ),
        );
        await settle(tester);

        // 2. Filter and sort.
        container
            .read(searchResultsProvider('Dove Shampoo').notifier)
            .updateFilters({'in_stock': true});
        await settle(tester);
        container
            .read(searchResultsProvider('Dove Shampoo').notifier)
            .updateSort(SortOption.lowestPrice);
        await settle(tester);

        // 3. Product: the results screen is torn down (what a push does).
        await tester.pumpWidget(const MaterialApp(home: Scaffold()));
        await settle(tester);

        // 4. Back: the results screen is rebuilt, as a pop does.
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: SearchResultsScreen(query: 'Dove Shampoo'),
            ),
          ),
        );
        await settle(tester);

        // The typed query...
        expect(container.read(searchQueryProvider).query, 'Dove Shampoo');
        // ...the filter...
        final state = container.read(searchResultsProvider('Dove Shampoo'));
        expect(state.filters['in_stock'], true);
        // ...and the sort all came back.
        expect(state.sort, SortOption.lowestPrice);
      },
    );

    testWidgets('a different query does not inherit the previous filters', (
      tester,
    ) async {
      final container = newContainer();
      addTearDown(container.dispose);

      container
          .read(searchResultsProvider('Dove Shampoo').notifier)
          .updateFilters({'in_stock': true});
      container
          .read(searchResultsProvider('Dove Shampoo').notifier)
          .updateSort(SortOption.lowestPrice);
      await settle(tester);

      // A new search must start from the defaults, not inherit choices made
      // while searching for something else.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SearchResultsScreen(query: 'milk')),
        ),
      );
      await settle(tester);

      final milk = container.read(searchResultsProvider('milk'));
      expect(milk.sort, kDefaultSortOption);
      expect(milk.filters, isEmpty);
    });

    testWidgets('cancelling a search forgets its retained choices', (
      tester,
    ) async {
      final container = newContainer();
      addTearDown(container.dispose);

      container
          .read(searchResultsProvider('Dove Shampoo').notifier)
          .updateSort(SortOption.lowestPrice);
      container
          .read(searchResultsProvider('Dove Shampoo').notifier)
          .updateFilters({'in_stock': true});
      await settle(tester);

      expect(
        container.read(searchQueryPreferencesProvider).retainedQueryCount,
        1,
      );

      container.read(searchResultsProvider('Dove Shampoo').notifier).cancel();
      await settle(tester);

      // Cancelling means "start over", so the choices must not come back.
      expect(
        container.read(searchQueryPreferencesProvider).retainedQueryCount,
        0,
      );
    });
  });

  // These are plain `test`s, not widget tests: they pin the LIFETIME of the
  // preferences, which is the whole reason this moved out of `static` maps.
  group('search query preferences lifetime', () {
    ProviderContainer newContainer() => ProviderContainer(
      overrides: [
        searchRepositoryProvider.overrideWithValue(MockSearchRepository()),
      ],
    );

    test('scoped to the container, not the process', () {
      // The preferences used to live in `static final` maps, which meant a fresh
      // container inherited the previous one's choices -- so this test could not
      // have been written at all -- and nothing could ever clear them.
      final first = newContainer();
      first
          .read(searchResultsProvider('Dove Shampoo').notifier)
          .updateSort(SortOption.lowestPrice);
      expect(
        first.read(searchQueryPreferencesProvider).sortFor('Dove Shampoo'),
        SortOption.lowestPrice,
      );
      first.dispose();

      final second = newContainer();
      addTearDown(second.dispose);
      expect(
        second.read(searchQueryPreferencesProvider).sortFor('Dove Shampoo'),
        kDefaultSortOption,
        reason: "a new container must not inherit another session's sort",
      );
    });

    test('clear() drops every query, for sign-out', () {
      final container = newContainer();
      addTearDown(container.dispose);

      for (final q in ['milk', 'bread', 'eggs']) {
        container
            .read(searchResultsProvider(q).notifier)
            .updateSort(SortOption.lowestPrice);
      }
      expect(
        container.read(searchQueryPreferencesProvider).retainedQueryCount,
        3,
      );

      // Called from the logout listener in app.dart.
      container.read(searchQueryPreferencesProvider).clear();

      expect(
        container.read(searchQueryPreferencesProvider).retainedQueryCount,
        0,
      );
      expect(
        container.read(searchQueryPreferencesProvider).sortFor('milk'),
        kDefaultSortOption,
      );
    });

    test('recorded filters are copied, not aliased', () {
      // Guards against a caller mutating the map it passed in and silently
      // changing what was remembered for the rest of the session.
      final container = newContainer();
      addTearDown(container.dispose);

      final filters = <String, dynamic>{'in_stock': true};
      container
          .read(searchQueryPreferencesProvider)
          .recordFilters('milk', filters);

      filters['in_stock'] = false;
      filters['brand'] = 'Dove';

      final remembered = container
          .read(searchQueryPreferencesProvider)
          .filtersFor('milk');
      expect(remembered?['in_stock'], true);
      expect(remembered, isNot(contains('brand')));
    });
  });
}
