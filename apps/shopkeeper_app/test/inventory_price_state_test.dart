import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/domain/inventory_scope.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/presentation/controllers/inventory_scope_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/pricing/presentation/controllers/price_list_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_page.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_query.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_search.dart';

/// INVENTORY STATE + PRICE STATE — the view states behind the five inventory
/// scope routes and the price list.
///
/// The DATA half (the catalog, its loading/error/lifecycle) is pinned in
/// `product_state_test.dart`; THIS file pins the VIEW half the inventory and
/// pricing screens are built on:
///   * every scope answers its own question (all / low / out of stock /
///     discontinued / freshness);
///   * the shopkeeper's search text and page are the scope's OWN state —
///     narrowable, clearable, paged — and independent between scopes;
///   * the price list pages and searches the catalog without re-ordering it;
///   * the page counters (`matched` / `total` / `hidden` / `hasMore` /
///     `isEmptyCatalog`) can never contradict each other, because they are
///     derived, not stored.
ShopProductItem p({
  required int id,
  required String name,
  int quantity = 5,
  String stockStatus = 'IN_STOCK',
  String status = 'ACTIVE',
  String? freshnessStatus,
  DateTime? lastUpdated,
}) => ShopProductItem(
      id: id,
      name: name,
      status: status,
      price: 10,
      isActive: true,
      isAvailable: true,
      quantity: quantity,
      stockStatus: stockStatus,
      freshnessStatus: freshnessStatus,
      lastUpdated: lastUpdated,
    );

/// A catalog with every stock state in it, in the server's order.
List<ShopProductItem> catalog() => [
      p(id: 1, name: 'Amul Milk', quantity: 20),
      p(id: 2, name: 'Basmati Rice', quantity: 4, stockStatus: 'LOW_STOCK'),
      p(id: 3, name: 'Detergent Bar', quantity: 0, stockStatus: 'OUT_OF_STOCK'),
      p(
        id: 4,
        name: 'Old Shampoo',
        quantity: 7,
        status: 'DISCONTINUED',
      ),
      p(
        id: 5,
        name: 'Stale Biscuits',
        quantity: 12,
        freshnessStatus: 'STALE',
        lastUpdated: DateTime(2024, 1, 1),
      ),
      p(
        id: 6,
        name: 'Fresh Juice',
        quantity: 9,
        lastUpdated: DateTime(2026, 1, 1),
      ),
    ];

/// A catalog too big for one window: 55 rows, so exactly [productsPageSize]
/// show and 5 hide behind the page break.
List<ShopProductItem> tallCatalog() => List.generate(
      productsPageSize + 5,
      (i) => p(id: i + 1, name: 'Item ${i + 1}'),
    );

void main() {
  group('InventoryScope — the slice IS a query', () {
    ProductSearch index() => ProductSearchCache().of(catalog());

    test('all keeps every row, in the server\'s order', () {
      final rows = InventoryScope.all.query.apply(catalog(), index());
      expect(rows.map((r) => r.id), [1, 2, 3, 4, 5, 6]);
    });

    test('low keeps only the listings the server calls LOW_STOCK', () {
      final rows = InventoryScope.low.query.apply(catalog(), index());
      expect(rows.map((r) => r.id), [2]);
    });

    test('outOfStock keeps only the listings the server calls OUT_OF_STOCK',
        () {
      final rows = InventoryScope.outOfStock.query.apply(catalog(), index());
      expect(rows.map((r) => r.id), [3]);
    });

    test('discontinued keeps only the retired listings', () {
      final rows = InventoryScope.discontinued.query.apply(catalog(), index());
      expect(rows.map((r) => r.id), [4]);
    });

    test('freshness keeps everything, stale listings first, newest last', () {
      final rows = InventoryScope.freshness.query.apply(catalog(), index());
      // Stale (5) first; the never-stamped (1..4) sort as oldest, in order;
      // the recently-updated (6) last.
      expect(rows.map((r) => r.id).first, 5);
      expect(rows.map((r) => r.id).last, 6);
      expect(rows.length, 6);
    });

    test('only the freshness route shows freshness on rows', () {
      expect(InventoryScope.freshness.showsFreshness, isTrue);
      expect(InventoryScope.all.showsFreshness, isFalse);
      expect(InventoryScope.low.showsFreshness, isFalse);
      expect(InventoryScope.outOfStock.showsFreshness, isFalse);
      expect(InventoryScope.discontinued.showsFreshness, isFalse);
    });
  });
  group('InventoryScopeController — the scope\'s OWN state', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    InventoryScopeController notifierOf(InventoryScope scope) =>
        container.read(inventoryScopeControllerProvider(scope).notifier);

    InventoryScopeState stateOf(InventoryScope scope) =>
        container.read(inventoryScopeControllerProvider(scope));

    test('each scope starts unfiltered and unpaged', () {
      for (final scope in InventoryScope.values) {
        expect(stateOf(scope).query.search, '', reason: scope.name);
        expect(
          stateOf(scope).visibleCount,
          productsPageSize,
          reason: scope.name,
        );
      }
    });

    test('pageFor cuts the slice at the page window and counts what hides',
        () {
      final rows = tallCatalog();
      final page = notifierOf(InventoryScope.all).pageFor(rows);

      expect(page.rows.length, productsPageSize);
      expect(page.matched, productsPageSize + 5);
      expect(page.total, productsPageSize + 5);
      expect(page.hasMore, isTrue);
      expect(page.hidden, 5);
    });

    test('showMore reveals the rest of the slice, then clamps', () {
      final rows = tallCatalog();
      final view = notifierOf(InventoryScope.all);

      view.showMore();
      expect(stateOf(InventoryScope.all).visibleCount, productsPageSize * 2);

      final second = view.pageFor(rows);
      expect(second.rows.length, productsPageSize + 5);
      expect(second.hasMore, isFalse);
      expect(second.hidden, 0);
    });

    test('search narrows the slice; a fresh question re-pages from the top',
        () {
      final rows = tallCatalog();
      final view = notifierOf(InventoryScope.all);

      view.showMore(); // page 2
      view.setSearch('Item 5');
      expect(stateOf(InventoryScope.all).visibleCount, productsPageSize,
          reason: 'a new question means a new result set: page from the top');

      final page = view.pageFor(rows);
      // Every 'Item 5x' matches (5, 50..55) — narrowed, first page only.
      expect(page.matched, 7);
      expect(page.rows.length, 7);
    });

    test('clear removes the search text but not the slice', () {
      final view = notifierOf(InventoryScope.low);
      view.setSearch('rice');

      view.clear();
      expect(stateOf(InventoryScope.low).query.search, '');
      // The slice itself is the screen's identity — it can never be cleared.
      expect(InventoryScope.low.query.stock, ProductQuery.stockServerLow);
    });

    test('scopes are independent: one route\'s search never leaks into another',
        () {
      final list = notifierOf(InventoryScope.all);
      final low = notifierOf(InventoryScope.low);

      list.setSearch('amul');
      expect(stateOf(InventoryScope.all).query.search, 'amul');
      expect(stateOf(InventoryScope.low).query.search, '',
          reason: 'four scope routes stay alive side by side');

      low.setSearch('rice');
      expect(stateOf(InventoryScope.all).query.search, 'amul');
      expect(stateOf(InventoryScope.low).query.search, 'rice');
    });

    test('search and the slice compose: the question stays, the text narrows',
        () {
      final rows = catalog();
      final low = notifierOf(InventoryScope.low);

      low.setSearch('basmati');
      final page = low.pageFor(rows);
      expect(page.matched, 1);
      expect(page.rows.single.id, 2);

      low.setSearch('amul');
      // 'amul' matches a row, but the LOW_STOCK slice removes it: a filter
      // miss, not an empty catalog.
      final noMatch = low.pageFor(rows);
      expect(noMatch.matched, 0);
      expect(noMatch.isEmptyCatalog, isFalse);
      expect(noMatch.isNoMatch, isTrue);
    });
  });
  group('PriceListController — the price book\'s own state', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    PriceListController controller() =>
        container.read(priceListControllerProvider.notifier);

    PriceListState state() => container.read(priceListControllerProvider);

    test('starts unfiltered, unpaged, in the server\'s order', () {
      expect(state().query.search, '');
      expect(state().visibleCount, productsPageSize);
      final page = controller().pageFor(catalog());
      expect(page.rows.map((r) => r.id), [1, 2, 3, 4, 5, 6]);
    });

    test('pages the price book exactly like every other list', () {
      final page = controller().pageFor(tallCatalog());
      expect(page.rows.length, productsPageSize);
      expect(page.hidden, 5);
      expect(page.hasMore, isTrue);

      controller().showMore();
      expect(state().visibleCount, productsPageSize * 2);
      expect(controller().pageFor(tallCatalog()).hasMore, isFalse);
    });

    test('search narrows; clearing brings the whole book back', () {
      controller().setSearch('amul');
      expect(controller().pageFor(catalog()).rows.single.id, 1);

      controller().setSearch('nothing-matches-this');
      final page = controller().pageFor(catalog());
      expect(page.matched, 0);
      expect(page.isEmptyCatalog, isFalse);

      controller().clear();
      expect(state().query.search, '');
      expect(controller().pageFor(catalog()).matched, 6);
    });
  });

  group('ProductPage — derived, so it cannot contradict itself', () {
    test('an empty catalog is the feature\'s own empty state', () {
      final page = ProductPage.of(const [], total: 0, visibleCount: 50);
      expect(page.isEmptyCatalog, isTrue);
      expect(page.isNoMatch, isFalse);
      expect(page.hasMore, isFalse);
      expect(page.hidden, 0);
    });

    test('a filter miss is NOT an empty catalog', () {
      final page = ProductPage.of(
        const <ShopProductItem>[],
        total: 6,
        visibleCount: 50,
      );
      expect(page.isEmptyCatalog, isFalse);
      expect(page.isNoMatch, isTrue);
    });

    test('an over-wide window renders exactly the rows there are', () {
      final page = ProductPage.of(catalog(), total: 6, visibleCount: 100);
      expect(page.rows.length, 6);
      expect(page.matched, 6);
      expect(page.hasMore, isFalse);
      expect(page.hidden, 0);
    });
  });
}
