import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/data/inventory_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/product_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_query.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_search.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/controllers/products_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_page.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/controllers/products_list_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/screens/products_screen.dart';

import 'fakes.dart';

/// PRODUCT STATE — the model that has to cover the whole product surface:
/// list, pagination, search, filter, sort, detail, create, edit, deactivate,
/// loading and error.
///
/// Two states split that job, and these tests pin both halves:
///   * `ProductsState` (`productsControllerProvider`) — the DATA: the rows, the
///     server summary, the read/write lifecycle, and the detail lookup.
///   * `ProductsListState` (`productsListControllerProvider`) — the VIEW: the
///     query (search + filters + sort in ONE value) and the page window.
///
/// The list's own state must never be lost by a trip out of the screen — a
/// refresh, a rebuild, or opening Product Details and coming back — so the
/// widget tests below drive those trips for real instead of trusting a memo.
ShopProductItem p({
  required int id,
  required String name,
  double price = 10,
  String? brand,
  String? category,
  int quantity = 5,
  String stockStatus = 'IN_STOCK',
  bool isAvailable = true,
  DateTime? lastUpdated,
}) => ShopProductItem(
  id: id,
  name: name,
  status: 'ACTIVE',
  price: price,
  brand: brand,
  category: category,
  isActive: true,
  isAvailable: isAvailable,
  quantity: quantity,
  stockStatus: stockStatus,
  lastUpdated: lastUpdated,
);

void main() {
  /// The whole screen, wired to a fake repository: product CRUD and the
  /// catalog read both come from the same fake, exactly as in the app.
  ({ProviderContainer container, FakeProductRepo repo}) makeHarness(
    List<ShopProductItem> items,
  ) {
    final repo = FakeProductRepo(items: items);
    final container = ProviderContainer(
      overrides: [
        productRepositoryProvider.overrideWithValue(repo),
        inventoryRepositoryProvider.overrideWithValue(repo),
        tokenStoreProvider.overrideWithValue(
          InMemoryTokenStore(accessToken: 'test-access-token'),
        ),
        selectedShopProvider.overrideWith(
          () => SelectedShopOverride(ownerShop()),
        ),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, repo: repo);
  }

  /// A tall viewport, so a full page of rows is on screen without scrolling.
  Future<void> pumpScreen(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProductsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder searchBox() => find.byType(TextField).first;

  String searchText(WidgetTester tester) =>
      tester.widget<TextField>(searchBox()).controller?.text ?? '';

  final milk = p(
    id: 1,
    name: 'Amul Milk',
    brand: 'Amul',
    category: 'Dairy',
    price: 30,
    quantity: 5,
    lastUpdated: DateTime(2026, 1, 2),
  );
  final limited = p(
    id: 2,
    name: 'Amul Butter',
    brand: 'Amul',
    category: 'Dairy',
    price: 55,
    quantity: 40,
    stockStatus: 'LIMITED_STOCK',
    lastUpdated: DateTime(2026, 1, 3),
  );
  final soap = p(
    id: 3,
    name: 'Zebra Soap',
    brand: 'Zebra',
    category: 'Home',
    price: 20,
    quantity: 0,
    stockStatus: 'OUT_OF_STOCK',
    lastUpdated: DateTime(2026, 1, 1),
  );

  group('ProductQuery — search, filter and sort are ONE value', () {
    final catalog = [milk, limited, soap];

    List<ShopProductItem> rowsFor(ProductQuery query) =>
        query.apply(catalog, ProductSearch(catalog));

    List<int> idsOf(ProductQuery query) =>
        rowsFor(query).map((item) => item.id).toList();

    test('the stock scope spans the server\'s LOW and LIMITED tiers', () {
      // The default order is "recently updated": Butter (Jan 3), Milk (Jan 2),
      // Soap (Jan 1).
      expect(idsOf(const ProductQuery()), [2, 1, 3]);
      expect(idsOf(const ProductQuery(stock: ProductQuery.stockInStock)), [1]);
      expect(idsOf(const ProductQuery(stock: ProductQuery.stockLow)), [2]);
      expect(idsOf(const ProductQuery(stock: ProductQuery.stockOutOfStock)), [
        3,
      ]);
    });

    test('search, brand, category and price narrow the same catalog', () {
      expect(idsOf(const ProductQuery(search: 'amul')), [2, 1]);
      expect(idsOf(const ProductQuery(brand: 'Zebra')), [3]);
      expect(idsOf(const ProductQuery(category: 'Dairy', maxPrice: 40)), [1]);
      expect(idsOf(const ProductQuery(minPrice: 21, maxPrice: 60)), [2, 1]);
      expect(idsOf(const ProductQuery(availability: false)), isEmpty);
    });

    test('"recently updated" drops rows the server never timestamped', () {
      final untimed = p(id: 4, name: 'Loose Rice');
      final rows = const ProductQuery(recentlyUpdated: true)
          .apply([milk, untimed], ProductSearch([milk, untimed]));
      expect(rows.map((item) => item.id), [1]);
    });

    test('sort orders by name, price and stock', () {
      expect(
        rowsFor(const ProductQuery(sort: ProductSort.name)).map((i) => i.name),
        ['Amul Butter', 'Amul Milk', 'Zebra Soap'],
      );
      expect(
        rowsFor(const ProductQuery(sort: ProductSort.price))
            .map((i) => i.price),
        [20, 30, 55],
      );
      expect(idsOf(const ProductQuery(sort: ProductSort.stock)), [2, 1, 3]);
      expect(idsOf(const ProductQuery(sort: ProductSort.recentlyUpdated)), [
        2,
        1,
        3,
      ]);
    });

    test('search is reported separately from the filters', () {
      expect(const ProductQuery(search: 'amul').hasActiveFilters, isFalse);
      expect(const ProductQuery(search: 'amul').isNarrowed, isTrue);
      expect(
        const ProductQuery(stock: ProductQuery.stockLow).hasActiveFilters,
        isTrue,
      );
      expect(const ProductQuery().isNarrowed, isFalse);
    });

    test('withFilters CLEARS any facet it is handed null for', () {
      // The bug a `copyWith` would hide: null means "clear", not "keep".
      final filtered = const ProductQuery().withFilters(
        availability: false,
        category: 'Dairy',
        brand: 'Amul',
        minPrice: 10,
        maxPrice: 90,
        recentlyUpdated: true,
      );
      expect(filtered.hasActiveFilters, isTrue);

      final cleared = filtered.withFilters(
        availability: null,
        category: null,
        brand: null,
        minPrice: null,
        maxPrice: null,
        recentlyUpdated: false,
      );
      expect(cleared.hasActiveFilters, isFalse);
    });

    test('withFilters keeps the facets the sheet does not own', () {
      const live = ProductQuery(
        search: 'amul',
        stock: ProductQuery.stockLow,
        sort: ProductSort.price,
      );
      final applied = live.withFilters(
        availability: true,
        category: null,
        brand: null,
        minPrice: null,
        maxPrice: null,
        recentlyUpdated: false,
      );
      expect(applied.search, 'amul');
      expect(applied.stock, ProductQuery.stockLow);
      expect(applied.sort, ProductSort.price);
      expect(applied.availability, isTrue);
    });

    test('clearFilters keeps the search, the scope and the sort', () {
      const live = ProductQuery(
        search: 'amul',
        stock: ProductQuery.stockLow,
        sort: ProductSort.price,
        brand: 'Amul',
      );
      final cleared = live.clearFilters();
      expect(cleared.brand, isNull);
      expect(cleared.search, 'amul');
      expect(cleared.stock, ProductQuery.stockLow);
      expect(cleared.sort, ProductSort.price);
    });

    test(
      'two queries with the same content are equal (they are memo keys)',
      () {
        expect(
          const ProductQuery(search: 'a', stock: ProductQuery.stockLow),
          const ProductQuery(search: 'a', stock: ProductQuery.stockLow),
        );
        expect(
          const ProductQuery(search: 'a').hashCode,
          const ProductQuery(search: 'a').hashCode,
        );
        expect(
          const ProductQuery(search: 'a') == const ProductQuery(search: 'b'),
          isFalse,
        );
      },
    );
  });

  group('products list view state — the query and the page window', () {
    late ProviderContainer container;
    late ProductsListController view;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
      view = container.read(productsListControllerProvider.notifier);
    });

    ProductsListState state() => container.read(productsListControllerProvider);

    List<ShopProductItem> catalog({int count = 3}) => [
      for (var i = 1; i <= count; i++)
        p(
          id: i,
          name: 'Product $i',
          price: i * 10,
          lastUpdated: DateTime(2026, 1, 1).add(Duration(days: i)),
        ),
    ];

    test('starts unfiltered, on the first page', () {
      final rows = catalog();
      final page = view.pageFor(rows);
      expect(page.rows.length, 3);
      expect(page.matched, 3);
      expect(page.total, 3);
      expect(page.hasMore, isFalse);
      expect(state().visibleCount, productsPageSize);
      expect(state().query.isNarrowed, isFalse);
    });

    test('the query IS state: it narrows the page and stays readable', () {
      final rows = catalog();
      view.setSearch('Product 2');

      final page = view.pageFor(rows);
      expect(page.rows.map((item) => item.name), ['Product 2']);
      expect(page.matched, 1);
      expect(page.total, 3, reason: 'the catalog size is not the match count');
      expect(state().query.search, 'Product 2');
    });

    test('each setter keeps the facets it does not own', () {
      view.setSearch('Product');
      view.setStock(ProductQuery.stockLow);
      view.setSort(ProductSort.price);

      final query = state().query;
      expect(query.search, 'Product');
      expect(query.stock, ProductQuery.stockLow);
      expect(query.sort, ProductSort.price);
    });

    test('setting the value it already has never replaces the state', () {
      final before = state();
      view.setSearch('');
      expect(identical(state(), before), isTrue);
    });

    test('clear drops the search and the filters but keeps the sort', () {
      view.setSort(ProductSort.name);
      view.setSearch('milk');
      view.setStock(ProductQuery.stockOutOfStock);

      view.clear();

      expect(state().query.search, isEmpty);
      expect(state().query.stock, ProductQuery.stockAll);
      expect(state().query.sort, ProductSort.name);
    });

    test('"empty shop" and "nothing matched" are different states', () {
      final rows = catalog();
      view.setSearch('no such product');

      final noMatch = view.pageFor(rows);
      expect(noMatch.isNoMatch, isTrue);
      expect(noMatch.isEmptyCatalog, isFalse);

      final empty = view.pageFor(const []);
      expect(empty.isEmptyCatalog, isTrue);
      expect(empty.isNoMatch, isFalse);
      expect(empty.rows, isEmpty);
    });

    test('a catalog bigger than one page pages in, and clamps at the end', () {
      final rows = catalog(count: productsPageSize + 5);

      final first = view.pageFor(rows);
      expect(first.rows.length, productsPageSize);
      expect(first.matched, productsPageSize + 5);
      expect(first.hasMore, isTrue);
      expect(first.hidden, 5);

      view.showMore();
      final second = view.pageFor(rows);
      expect(second.rows.length, productsPageSize + 5);
      expect(second.hasMore, isFalse);
      expect(second.hidden, 0);

      // One turn too many is harmless: the window is clamped by the matches.
      view.showMore();
      expect(view.pageFor(rows).rows.length, productsPageSize + 5);
    });

    test('a new query pages from the top again', () {
      final rows = catalog(count: productsPageSize + 5);
      view.showMore();
      expect(state().visibleCount, productsPageSize * 2);

      view.setSearch('Product');
      expect(state().visibleCount, productsPageSize);
      expect(view.pageFor(rows).rows.length, productsPageSize);
    });

    test('the derivation is memoized against the (catalog, query) pair', () {
      final rows = catalog();
      final first = view.matching(rows);
      expect(
        identical(view.matching(rows), first),
        isTrue,
        reason: 'an unrelated rebuild must not re-run the predicate',
      );

      // A refresh hands over a NEW list instance...
      final refreshed = List<ShopProductItem>.of(rows);
      expect(identical(view.matching(refreshed), first), isFalse);

      // ...and a new query re-derives too.
      view.setSearch('Product 1');
      final narrowed = view.matching(refreshed);
      expect(narrowed.length, 1);
      expect(identical(view.matching(refreshed), narrowed), isTrue);
    });
  });

  group('the list state survives every trip out of the screen', () {
    testWidgets('a rebuilt screen comes back with the search and the filter', (
      tester,
    ) async {
      final harness = makeHarness([milk, soap]);
      await pumpScreen(tester, harness.container);

      await tester.enterText(searchBox(), 'amul');
      await tester.pumpAndSettle();
      expect(find.text('1 of 2 products'), findsOneWidget);

      // The screen is disposed entirely — the worst case of "left and came
      // back": a query held in widget state would be gone here.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      await tester.pumpAndSettle();

      await pumpScreen(tester, harness.container);

      expect(find.text('1 of 2 products'), findsOneWidget);
      expect(find.text('Amul Milk'), findsOneWidget);
      expect(find.text('Zebra Soap'), findsNothing);
      expect(
        searchText(tester),
        'amul',
        reason: 'the search box is seeded from the query state',
      );
    });

    testWidgets('a refresh keeps the query and the page', (tester) async {
      final harness = makeHarness([milk, soap]);
      await pumpScreen(tester, harness.container);

      await tester.enterText(searchBox(), 'amul');
      await tester.pumpAndSettle();
      harness.container
          .read(productsListControllerProvider.notifier)
          .showMore();

      await harness.container.read(productsControllerProvider.notifier).load();
      await tester.pumpAndSettle();

      expect(find.text('1 of 2 products'), findsOneWidget);
      expect(
        harness.container.read(productsListControllerProvider).query.search,
        'amul',
      );
      expect(
        harness.container.read(productsListControllerProvider).visibleCount,
        productsPageSize * 2,
        reason: 'a refresh is not a new question — the page stays put',
      );
    });

    testWidgets('opening Product Details and returning changes nothing', (
      tester,
    ) async {
      final harness = makeHarness([milk, soap]);
      await pumpScreen(tester, harness.container);

      await tester.enterText(searchBox(), 'amul');
      await tester.pumpAndSettle();
      expect(find.text('1 of 2 products'), findsOneWidget);

      await tester.tap(find.text('Amul Milk'));
      await tester.pumpAndSettle();
      // The details view is up, resolved from the SAME state (no refetch).
      expect(find.text('Pricing'), findsOneWidget);

      Navigator.of(tester.element(find.text('Pricing'))).pop();
      await tester.pumpAndSettle();

      expect(find.text('1 of 2 products'), findsOneWidget);
      expect(find.text('Amul Milk'), findsOneWidget);
      expect(find.text('Zebra Soap'), findsNothing);
      expect(searchText(tester), 'amul');
      expect(
        find.byType(Switch),
        findsOneWidget,
        reason: 'the list row is back, untouched',
      );
    });

    testWidgets('only a catalog bigger than a page offers more rows', (
      tester,
    ) async {
      final many = [
        for (var i = 1; i <= productsPageSize + 5; i++)
          p(id: i, name: 'Item $i', lastUpdated: DateTime(2026, 1, 1)),
      ];
      final harness = makeHarness(many);
      await pumpScreen(tester, harness.container);

      // Every matching row is counted, even though only one page is rendered.
      expect(
        find.text(
          '${productsPageSize + 5} of ${productsPageSize + 5} products',
        ),
        findsOneWidget,
      );

      await tester.dragUntilVisible(
        find.byKey(const Key('products-load-more')),
        find.byType(CustomScrollView),
        const Offset(0, -400),
      );
      expect(find.text('Load more (5 remaining)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('products-load-more')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('products-load-more')),
        findsNothing,
        reason: 'nothing is behind the page break any more',
      );

      final page = harness.container
          .read(productsListControllerProvider.notifier)
          .pageFor(harness.repo.items);
      expect(page.rows.length, productsPageSize + 5);
      expect(page.hasMore, isFalse);
    });

    testWidgets('a small catalog shows no page break at all', (tester) async {
      final harness = makeHarness([milk, soap]);
      await pumpScreen(tester, harness.container);
      expect(find.byKey(const Key('products-load-more')), findsNothing);
      expect(find.text('2 of 2 products'), findsOneWidget);
    });
  });
}
