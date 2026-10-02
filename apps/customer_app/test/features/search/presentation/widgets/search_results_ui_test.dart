import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyperlocal_app/core/storage/local_storage_driver.dart';
import 'package:hyperlocal_app/features/saved_and_history/presentation/controllers/saved_and_history_controllers.dart';
import 'package:hyperlocal_app/features/search/data/mock_search_repository.dart';
import 'package:hyperlocal_app/features/search/domain/models/search_models.dart';
import 'package:hyperlocal_app/features/search/domain/search_repository.dart';
import 'package:hyperlocal_app/features/search/presentation/controllers/search_controller.dart';
import 'package:hyperlocal_app/features/search/presentation/widgets/search_history_view.dart';
import 'package:hyperlocal_app/features/search/presentation/widgets/search_suggestions_list.dart';
import 'package:hyperlocal_app/features/search/presentation/widgets/shop_product_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

ShopProductResult _result({
  FreshnessLevel freshness = FreshnessLevel.fresh,
  String? offerText,
  bool? isOpenNow,
  bool? isAcceptingOrders,
  // 0 is the wire value for "unknown", so tests can exercise the absent cases.
  double distanceInKm = 1.2,
  double shopRating = 4.5,
}) {
  return ShopProductResult(
    id: 'r1',
    productId: 'p1',
    productName: 'Dove Shampoo 650ml',
    productImageUrl: '',
    shopId: 's1',
    shopName: 'Gupta Electronics',
    price: 240,
    isAvailable: true,
    distanceInKm: distanceInKm,
    shopRating: shopRating,
    lastUpdated: DateTime(2026, 1, 1),
    offerText: offerText,
    isOpenNow: isOpenNow,
    isAcceptingOrders: isAcceptingOrders,
    availability: InventoryAvailability.inStock,
    freshness: freshness,
  );
}

void main() {
  group('the model rules behind distance and rating', () {
    test('a zero distance is unknown, not "you are standing in it"', () {
      expect(_result(distanceInKm: 0).hasKnownDistance, isFalse);
      expect(_result(distanceInKm: 1.2).hasKnownDistance, isTrue);
    });

    test('a zero rating means never reviewed, not rated-terrible', () {
      expect(_result(shopRating: 0).isRated, isFalse);
      expect(_result(shopRating: 4.5).isRated, isTrue);
    });
  });

  group('the card only states facts the data contains', () {
    Future<void> pumpCard(WidgetTester tester, ShopProductResult result) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ShopProductCard(result: result)),
        ),
      );
    }

    testWidgets('shows distance when it is known', (tester) async {
      await pumpCard(tester, _result(distanceInKm: 1.2));
      expect(find.text('1.2 km'), findsOneWidget);
    });

    testWidgets('prints no distance at all when it is unknown', (tester) async {
      // Regression: a confident "0.0 km" tells the customer they are standing in
      // the shop when the truth is that coordinates could not be resolved.
      await pumpCard(tester, _result(distanceInKm: 0));
      expect(find.textContaining('km'), findsNothing);
    });

    testWidgets('shows the rating when the shop has one', (tester) async {
      await pumpCard(tester, _result(shopRating: 4.5));
      expect(find.text('4.5'), findsOneWidget);
    });

    testWidgets('shows no star or 0.0 for an unrated shop', (tester) async {
      // A star beside "0.0" claims the shop was rated and scored zero. It has not
      // been rated at all.
      await pumpCard(tester, _result(shopRating: 0));
      expect(find.text('0.0'), findsNothing);
      expect(find.byIcon(Icons.star), findsNothing);
    });

    testWidgets('availability survives both being unknown', (tester) async {
      // The point of making the signals conditional: stripping distance and
      // rating must not strip the row the customer most needs.
      await pumpCard(tester, _result(distanceInKm: 0, shopRating: 0));
      expect(find.text('In Stock'), findsOneWidget);
    });
  });

  group('result card', () {
    testWidgets('View Shop is primary and does not also fire product tap', (
      tester,
    ) async {
      var shopTaps = 0;
      var productTaps = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShopProductCard(
              result: _result(),
              onTap: () => productTaps++,
              onShopTap: () => shopTaps++,
            ),
          ),
        ),
      );

      expect(find.text('View Shop'), findsOneWidget);
      expect(find.text('View Product'), findsOneWidget);

      await tester.tap(find.byKey(const Key('viewShopButton')));
      expect(shopTaps, 1);
      // Tapping the shop CTA must not also fire product navigation.
      expect(productTaps, 0);
    });

    testWidgets('omits CTAs that have no handler', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ShopProductCard(result: _result())),
        ),
      );
      expect(find.byKey(const Key('viewShopButton')), findsNothing);
      expect(find.byKey(const Key('viewProductButton')), findsNothing);
    });

    testWidgets('surfaces offer copy only when supplied', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ShopProductCard(result: _result())),
        ),
      );
      expect(find.text('20% OFF this week'), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShopProductCard(
              result: _result(offerText: '20% OFF this week'),
            ),
          ),
        ),
      );
      expect(find.text('20% OFF this week'), findsOneWidget);
    });

    testWidgets('unknown freshness is never shown as in stock', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShopProductCard(
              result: _result(freshness: FreshnessLevel.unknown),
            ),
          ),
        ),
      );
      expect(find.text('In Stock'), findsNothing);
      expect(find.text('Check availability'), findsOneWidget);
    });

    testWidgets('shows Open only when the backend reported it open', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShopProductCard(result: _result(isOpenNow: true)),
          ),
        ),
      );
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Closed'), findsNothing);
    });

    testWidgets('shows Closed when the backend reported it closed', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShopProductCard(result: _result(isOpenNow: false)),
          ),
        ),
      );
      expect(find.text('Closed'), findsOneWidget);
      expect(find.text('Open'), findsNothing);
    });

    testWidgets('never guesses open state when none was reported', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ShopProductCard(result: _result())),
        ),
      );
      // isOpenNow == null must render neither label — unknown is not "Open".
      expect(find.text('Open'), findsNothing);
      expect(find.text('Closed'), findsNothing);
    });

    testWidgets('flags an open shop that is not accepting orders', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShopProductCard(
              result: _result(isOpenNow: true, isAcceptingOrders: false),
            ),
          ),
        ),
      );
      expect(find.text('Open · No orders'), findsOneWidget);
    });
  });

  group('suggestions grouping', () {
    // NOTE: the query must be set BEFORE the tree builds. Mutating a provider
    // inside build throws "Tried to modify a provider while the widget tree was
    // building". Explicit pumps are used instead of pumpAndSettle because the
    // loading state is a CircularProgressIndicator that never settles.
    Future<void> pumpSuggestions(
      WidgetTester tester,
      SearchRepository repo,
    ) async {
      final container = ProviderContainer(
        overrides: [searchRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      container.read(searchQueryProvider.notifier).debouncedTextChanged('dove');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: SearchSuggestionsList()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('groups product, brand and category suggestions', (
      tester,
    ) async {
      await pumpSuggestions(tester, _StubSearchRepository());

      expect(find.text('Products'), findsOneWidget);
      expect(find.text('Brands'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Dove Shampoo 650ml'), findsOneWidget);
      expect(find.text('Dove'), findsOneWidget);
      expect(find.text('Beauty & Personal Care'), findsOneWidget);
    });

    testWidgets('skips the header for an empty group', (tester) async {
      await pumpSuggestions(tester, _StubSearchRepository(onlyProducts: true));

      expect(find.text('Products'), findsOneWidget);
      expect(find.text('Brands'), findsNothing);
      expect(find.text('Categories'), findsNothing);
    });

    // Recents are local (no debounce, no network), so they surface instantly
    // — even while the backend suggestion request is still in flight.
    testWidgets('shows matching recent searches while typing', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          searchRepositoryProvider.overrideWithValue(_StubSearchRepository()),
          localStorageDriverProvider.overrideWithValue(InMemoryStorageDriver()),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(recentSearchesNotifierProvider.notifier)
          .addQuery('Dove Body Wash');
      await container
          .read(recentSearchesNotifierProvider.notifier)
          .addQuery('Colgate');
      container.read(searchQueryProvider.notifier).debouncedTextChanged('dove');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: SearchSuggestionsList()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Recent Searches'), findsOneWidget);
      expect(
        find.byKey(const Key('recentSuggestion:Dove Body Wash')),
        findsOneWidget,
      );
      // Non-matching history stays hidden.
      expect(find.byKey(const Key('recentSuggestion:Colgate')), findsNothing);
    });

    testWidgets('never shows a recent the backend also suggests', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          searchRepositoryProvider.overrideWithValue(_StubSearchRepository()),
          localStorageDriverProvider.overrideWithValue(InMemoryStorageDriver()),
        ],
      );
      addTearDown(container.dispose);
      // The stub backend returns 'Dove Shampoo 650ml' as a product suggestion;
      // the same text in history must not render twice.
      await container
          .read(recentSearchesNotifierProvider.notifier)
          .addQuery('Dove Shampoo 650ml');
      container.read(searchQueryProvider.notifier).debouncedTextChanged('dove');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: SearchSuggestionsList()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Dove Shampoo 650ml'), findsOneWidget);
      // Deduped: the Recent Searches group has nothing left to show.
      expect(find.text('Recent Searches'), findsNothing);
    });
  });

  group('recent searches', () {
    testWidgets('clear one removes only that entry', (tester) async {
      // The history store performs a one-time legacy migration through
      // SharedPreferences; without a mock the plugin channel never answers and
      // the test hangs.
      SharedPreferences.setMockInitialValues({});

      // Seed BEFORE the tree builds, then use the same container for the UI.
      final container = ProviderContainer(
        overrides: [
          searchRepositoryProvider.overrideWithValue(MockSearchRepository()),
          localStorageDriverProvider.overrideWithValue(InMemoryStorageDriver()),
        ],
      );
      addTearDown(container.dispose);
      for (final q in ['Dove Shampoo', 'Colgate']) {
        await container
            .read(recentSearchesNotifierProvider.notifier)
            .addQuery(q);
      }

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: SearchHistoryView())),
        ),
      );
      // Explicit pumps: the list shows a LinearProgressIndicator while loading,
      // which never lets pumpAndSettle converge.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Dove Shampoo'), findsOneWidget);
      expect(find.text('Colgate'), findsOneWidget);
      expect(
        find.byKey(const Key('removeRecentSearch:Dove Shampoo')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('removeRecentSearch:Dove Shampoo')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Dove Shampoo'), findsNothing);
      expect(find.text('Colgate'), findsOneWidget);
    });
  });

  // Regression guard for a real, user-visible bug: search history used to be
  // held in TWO in-memory copies (the search feature's own cached list and the
  // saved-and-history notifier) tied together by a manual version counter that
  // each writer had to remember to bump. Writers refreshed only one copy, so a
  // search could be deleted in one place and still appear in the other.
  group('recent searches single source of truth', () {
    testWidgets(
      'a write through the notifier is seen by the search projection',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer(
          overrides: [
            searchRepositoryProvider.overrideWithValue(MockSearchRepository()),
            localStorageDriverProvider.overrideWithValue(
              InMemoryStorageDriver(),
            ),
          ],
        );
        addTearDown(container.dispose);

        // The search feature's provider is a projection of the notifier, so it
        // must reflect a write made through the notifier with no manual
        // invalidation step of any kind.
        await container
            .read(recentSearchesNotifierProvider.notifier)
            .addQuery('Colgate');

        expect(container.read(recentSearchesProvider), ['Colgate']);

        // And a removal through the notifier must disappear from the projection
        // too. Previously this only worked if the caller remembered to bump the
        // version counter, which is exactly how the two copies drifted apart.
        await container
            .read(recentSearchesNotifierProvider.notifier)
            .removeQuery('Colgate');

        expect(container.read(recentSearchesProvider), isEmpty);
      },
    );

    testWidgets('the search screen drops an entry deleted in the history tab', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          searchRepositoryProvider.overrideWithValue(MockSearchRepository()),
          localStorageDriverProvider.overrideWithValue(InMemoryStorageDriver()),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(recentSearchesNotifierProvider.notifier)
          .addQuery('Dove Shampoo');
      await container
          .read(recentSearchesNotifierProvider.notifier)
          .addQuery('Colgate');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: SearchHistoryView())),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Colgate'), findsOneWidget);

      // Delete 'Colgate' exactly as the history tab does.
      await tester.tap(find.byKey(const Key('removeRecentSearch:Colgate')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The search screen must not still be offering it.
      expect(find.text('Colgate'), findsNothing);

      // The projection used by the suggestions row agrees with what is on screen.
      expect(
        container.read(recentSearchesProvider),
        isNot(contains('Colgate')),
      );
    });
  });
}

/// Serves a fixed suggestion set so grouping can be asserted.
class _StubSearchRepository implements SearchRepository {
  final bool onlyProducts;
  _StubSearchRepository({this.onlyProducts = false});

  @override
  Future<List<SearchSuggestion>> getSuggestions(String query) async {
    if (onlyProducts) {
      return const [SearchSuggestion(text: 'Dove Shampoo 650ml')];
    }
    return const [
      SearchSuggestion(text: 'Dove Shampoo 650ml'),
      SearchSuggestion(text: 'Dove', isBrand: true),
      SearchSuggestion(text: 'Beauty & Personal Care', isCategory: true),
    ];
  }

  @override
  Future<List<String>> getPopularSearches() async => const [];

  @override
  Future<List<String>> getRecentSearches() async => const [];

  @override
  Future<List<ShopProductResult>> searchProducts({
    required String query,
    required int page,
    required int limit,
    SortOption sort = SortOption.nearest,
    Map<String, dynamic>? filters,
    double? latitude,
    double? longitude,
  }) async => const [];

  @override
  Future<List<ShopProductResult>> lookupBarcode(
    String barcode, {
    double? latitude,
    double? longitude,
    int page = 1,
    int limit = 20,
  }) async => const [];
}
