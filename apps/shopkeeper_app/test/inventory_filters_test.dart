import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/data/inventory_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/domain/inventory_scope.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/presentation/controllers/inventory_scope_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/presentation/screens/inventory_list_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/presentation/widgets/inventory_filter_sheet.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/product_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_query.dart';

import 'fakes.dart';

/// INVENTORY FILTERS — the filter half of the inventory scope screens: the
/// quick STOCK chips, the Category / Freshness sheet, and the state protocol
/// that keeps them in step.
///
/// The spec's inventory facet set is decided HERE, not by any one screen:
///   * Stock — quick chips OUTSIDE the sheet (immediate commit), hidden on the
///     slices whose own query already pins the answer;
///   * Category / Freshness — the sheet, a DRAFT until Apply;
///   * Reset re-applies the empty filter WITHOUT closing; Apply commits the
///     draft atomically; Clear never touches the scope's own slice.
///
/// The slice mechanics live in `inventory_price_state_test.dart`; THIS file
/// drives the real chips, the real sheet and the real controller.
ShopProductItem p({
  required int id,
  required String name,
  String? category,
  int quantity = 10,
  String stockStatus = 'IN_STOCK',
  String? freshnessStatus,
  DateTime? lastUpdated,
}) =>
    ShopProductItem(
      id: id,
      name: name,
      status: 'ACTIVE',
      price: 10,
      category: category,
      isActive: true,
      isAvailable: quantity > 0,
      quantity: quantity,
      stockStatus: stockStatus,
      freshnessStatus: freshnessStatus,
      lastUpdated: lastUpdated,
      source: 'MANUAL',
    );

/// A three-row catalog: one row per stock state, a category each, and a
/// fresh/stale pair — so every facet has something to match (and something
/// else it must exclude).
List<ShopProductItem> catalog() => [
      p(
        id: 1,
        name: 'Amul Milk',
        category: 'Dairy',
        freshnessStatus: 'RECENTLY_UPDATED',
        lastUpdated: DateTime(2026, 1, 10),
      ),
      p(
        id: 2,
        name: 'Basmati Rice',
        category: 'Grains',
        quantity: 4,
        stockStatus: 'LOW_STOCK',
        freshnessStatus: 'STALE',
        lastUpdated: DateTime(2024, 1, 1),
      ),
      p(
        id: 3,
        name: 'Detergent Bar',
        category: 'Household',
        quantity: 0,
        stockStatus: 'OUT_OF_STOCK',
      ),
    ];

void main() {
  ProviderContainer makeContainer(List<ShopProductItem> items) {
    final repo = FakeProductRepo(items: items);
    final container = ProviderContainer(overrides: [
      productRepositoryProvider.overrideWithValue(repo),
      inventoryRepositoryProvider.overrideWithValue(repo),
      tokenStoreProvider.overrideWithValue(
          InMemoryTokenStore(accessToken: 'test-access-token')),
      selectedShopProvider
          .overrideWith(() => SelectedShopOverride(ownerShop())),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  Future<void> pumpScope(
    WidgetTester tester,
    ProviderContainer container,
    InventoryScope scope,
  ) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: InventoryScopeScreen(scope: scope)),
    ));
    await tester.pumpAndSettle();
  }

  /// Opens the filter sheet and pins its frame (title + both actions).
  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('inventory-filters-button')));
    await tester.pumpAndSettle();
    expect(find.text('Filter inventory'), findsOneWidget);
  }

  Finder categoryPicker() => find.descendant(
        of: find.byType(InventoryFilterSheet),
        matching: find.byType(DropdownButtonFormField<String?>),
      );

  group('InventoryScopeController — predictable filter state', () {
    test('pinsStock: the three stock slices pin, list and freshness do not',
        () {
      final container = makeContainer(catalog());
      bool pins(InventoryScope scope) => container
          .read(inventoryScopeControllerProvider(scope).notifier)
          .pinsStock;

      expect(pins(InventoryScope.low), isTrue);
      expect(pins(InventoryScope.outOfStock), isTrue);
      expect(pins(InventoryScope.discontinued), isTrue);
      expect(pins(InventoryScope.all), isFalse);
      expect(pins(InventoryScope.freshness), isFalse);
    });

    test('setFilters replaces the sheet facets and keeps search + stock', () {
      final container = makeContainer(catalog());
      final view = container
          .read(inventoryScopeControllerProvider(InventoryScope.all).notifier);
      view.setSearch('milk');
      view.setStock(ProductQuery.stockInStock);

      // The sheet's own protocol: it is handed the USER query and returns it
      // with only the facets it owns replaced.
      final user = container
          .read(inventoryScopeControllerProvider(InventoryScope.all))
          .query;
      view.setFilters(user.withFilters(
        availability: user.availability,
        category: 'Dairy',
        brand: user.brand,
        minPrice: user.minPrice,
        maxPrice: user.maxPrice,
        recentlyUpdated: user.recentlyUpdated,
        freshness: ProductQuery.freshnessFresh,
      ));

      final state = container
          .read(inventoryScopeControllerProvider(InventoryScope.all))
          .query;
      expect(state.search, 'milk');
      expect(state.stock, ProductQuery.stockInStock);
      expect(state.category, 'Dairy');
      expect(state.freshness, ProductQuery.freshnessFresh);

      // And the merged question the list renders carries every one of them.
      final merged = view.query;
      expect(merged.search, 'milk');
      expect(merged.stock, ProductQuery.stockInStock);
      expect(merged.category, 'Dairy');
      expect(merged.freshness, ProductQuery.freshnessFresh);
    });

    test('a stock facet can never contradict a pinned slice', () {
      final container = makeContainer(catalog());
      final low = container
          .read(inventoryScopeControllerProvider(InventoryScope.low).notifier);

      low.setStock(ProductQuery.stockInStock);

      // A facet the scope already pins is IGNORED when merging, never
      // intersected: the list can never drift from the dashboard counter it
      // mirrors.
      expect(low.query.stock, ProductQuery.stockServerLow);
      expect(low.pageFor(catalog()).rows.map((r) => r.id), [2]);
    });
  });

  group('InventoryScopeScreen — the STOCK chips', () {
    testWidgets('they narrow the list and All restores it', (tester) async {
      final container = makeContainer(catalog());
      await pumpScope(tester, container, InventoryScope.all);

      expect(find.text('3 of 3 products'), findsOneWidget);

      await tester.tap(find.text('Low Stock'));
      await tester.pumpAndSettle();
      expect(find.text('1 of 3 products'), findsOneWidget);
      expect(find.text('Basmati Rice'), findsOneWidget);
      expect(find.text('Amul Milk'), findsNothing);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(find.text('3 of 3 products'), findsOneWidget);
    });

    testWidgets('a pinned stock slice hides the chips entirely',
        (tester) async {
      final container = makeContainer(catalog());
      await pumpScope(tester, container, InventoryScope.low);

      // The Low stock screen IS a stock answer — a second one could only
      // contradict the dashboard counter it mirrors.
      expect(find.text('1 of 3 products'), findsOneWidget);
      expect(find.text('All'), findsNothing);
      expect(find.text('In Stock'), findsNothing);
      expect(find.text('Low Stock'), findsNothing);
      expect(find.text('Out of Stock'), findsNothing);
    });
  });

  group('InventoryScopeScreen — the filter sheet', () {
    testWidgets('narrows by category; Any restores the whole slice',
        (tester) async {
      final container = makeContainer(catalog());
      await pumpScope(tester, container, InventoryScope.all);
      await openSheet(tester);

      await tester.tap(categoryPicker());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dairy').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.text('1 of 3 products'), findsOneWidget);
      expect(find.text('Amul Milk'), findsOneWidget);
      expect(find.text('Basmati Rice'), findsNothing);

      // Reopening seeds the draft from the committed query — predictable
      // state, never a silent reset to Any.
      await openSheet(tester);
      expect(find.text('Dairy'), findsOneWidget);

      await tester.tap(categoryPicker());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Any').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.text('3 of 3 products'), findsOneWidget);
    });

    testWidgets('narrows by freshness', (tester) async {
      final container = makeContainer(catalog());
      await pumpScope(tester, container, InventoryScope.all);
      await openSheet(tester);

      await tester.tap(find.text('Needs update'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // Only the STALE row survives; an unknown tier matches neither value.
      expect(find.text('1 of 3 products'), findsOneWidget);
      expect(find.text('Basmati Rice'), findsOneWidget);
      expect(find.text('Amul Milk'), findsNothing);
    });

    testWidgets('a facet that could match nothing is not offered',
        (tester) async {
      final container = makeContainer([p(id: 1, name: 'Loose Rice')]);
      await pumpScope(tester, container, InventoryScope.all);
      await openSheet(tester);

      expect(find.text('Category'), findsNothing);
      expect(find.text('Freshness'), findsOneWidget);
    });
  });

  group('InventoryScopeScreen — the Reset / Apply / Clear protocol', () {
    testWidgets(
        'Reset clears the draft AND the list behind it, without closing',
        (tester) async {
      final container = makeContainer(catalog());
      await pumpScope(tester, container, InventoryScope.all);

      await openSheet(tester);
      await tester.tap(categoryPicker());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dairy').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.text('1 of 3 products'), findsOneWidget);

      await openSheet(tester);
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();

      // The sheet is STILL open and the list behind already shows everything:
      // the two can never disagree about what is filtered.
      expect(find.text('Filter inventory'), findsOneWidget);
      expect(find.text('3 of 3 products'), findsOneWidget);

      // A following Apply commits exactly the cleared draft — no stale send.
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.text('Filter inventory'), findsNothing);
      expect(find.text('3 of 3 products'), findsOneWidget);
    });

    testWidgets(
        'a sheet facet composes with the chips; Reset leaves them alone',
        (tester) async {
      final container = makeContainer(catalog());
      await pumpScope(tester, container, InventoryScope.all);

      await tester.tap(find.text('In Stock'));
      await tester.pumpAndSettle();
      expect(find.text('1 of 3 products'), findsOneWidget);

      await openSheet(tester);
      await tester.tap(categoryPicker());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grains').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // IN_STOCK ∧ Grains: neither facet overwrote the other.
      expect(find.text('0 of 3 products'), findsOneWidget);
      expect(find.text('No products match your filters'), findsOneWidget);

      await openSheet(tester);
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();

      // The category is gone; the chip was never the sheet's to clear.
      expect(find.text('1 of 3 products'), findsOneWidget);
      expect(find.text('Amul Milk'), findsOneWidget);
    });

    testWidgets('Clear drops the facets but keeps the scope slice',
        (tester) async {
      final container = makeContainer(catalog());
      await pumpScope(tester, container, InventoryScope.low);
      expect(find.text('1 of 3 products'), findsOneWidget);

      // Narrow the pinned slice further: no LOW_STOCK row is fresh.
      await openSheet(tester);
      await tester.tap(find.text('Fresh'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.text('0 of 3 products'), findsOneWidget);
      expect(find.text('No products match your filters'), findsOneWidget);

      await tester.tap(find.byKey(const Key('inventory-clear-filters')));
      await tester.pumpAndSettle();

      // The facet is gone; the SLICE is not — the counter still measures the
      // shopkeeper's rows against the whole catalog.
      expect(find.text('1 of 3 products'), findsOneWidget);
      expect(find.text('Basmati Rice'), findsOneWidget);
      expect(find.byKey(const Key('inventory-clear-filters')), findsNothing);
    });
  });
}

