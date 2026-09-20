import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/data/inventory_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/product_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/screens/products_screen.dart';

import 'fakes.dart';

/// PRODUCTS screen list mechanics: the result counter, search, the filter
/// sheet (category / brand / price), sort, the three empty states and the
/// availability switch.
///
/// The list filters client-side over the whole `view=list` payload, so these
/// tests drive the real predicate and the real sheet — only the repository is
/// faked.
ShopProductItem p({
  required int id,
  required String name,
  double price = 10,
  double? mrp,
  String? sku,
  String? brand,
  String? category,
  String? variant,
  int quantity = 5,
  String stockStatus = 'IN_STOCK',
  bool isAvailable = true,
  DateTime? lastUpdated,
}) =>
    ShopProductItem(
      id: id,
      name: name,
      status: 'ACTIVE',
      price: price,
      mrp: mrp,
      sku: sku,
      brand: brand,
      category: category,
      variant: variant,
      isActive: true,
      isAvailable: isAvailable,
      quantity: quantity,
      stockStatus: stockStatus,
      lastUpdated: lastUpdated,
    );

void main() {
  ({ProviderContainer container, FakeProductRepo repo}) makeHarness(
    List<ShopProductItem> items, {
    ShopProductItem? Function(int, Map<String, dynamic>)? onUpdate,
  }) {
    final repo = FakeProductRepo(items: items, onUpdate: onUpdate);
    final container = ProviderContainer(overrides: [
      productRepositoryProvider.overrideWithValue(repo),
      inventoryRepositoryProvider.overrideWithValue(repo),
      tokenStoreProvider.overrideWithValue(
          InMemoryTokenStore(accessToken: 'test-access-token')),
      selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
    ]);
    addTearDown(container.dispose);
    return (container: container, repo: repo);
  }

  /// Tall viewport so a full page of rows is on screen without scrolling.
  Future<void> pumpList(
      WidgetTester tester, ProviderContainer container) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ProductsScreen()),
    ));
    await tester.pumpAndSettle();
  }

  Finder searchBox() => find.byType(TextField).first;

  Finder sheetFields() => find.descendant(
      of: find.byType(ProductFilterSheet), matching: find.byType(TextField));

  Finder sheetPickers() => find.descendant(
      of: find.byType(ProductFilterSheet),
      matching: find.byType(DropdownButtonFormField<String?>));

  Future<void> openFilters(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.filter_alt_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Filter products'), findsOneWidget);
  }

  final milk = p(
    id: 1,
    name: 'Amul Milk',
    price: 30,
    brand: 'Amul',
    category: 'Dairy',
    sku: 'SKU-MILK',
    variant: '500ml',
  );
  final soap = p(
    id: 2,
    name: 'Zebra Soap',
    price: 20,
    brand: 'Zebra',
    category: 'Personal care',
    sku: 'SKU-SOAP',
    variant: '100g',
  );

  group('products list', () {
    testWidgets('renders a row per product with a visible/total counter',
        (tester) async {
      final harness = makeHarness([milk, soap]);
      await pumpList(tester, harness.container);

      expect(find.text('Amul Milk'), findsOneWidget);
      expect(find.text('Zebra Soap'), findsOneWidget);
      expect(find.text('2 of 2 products'), findsOneWidget);
    });

    testWidgets('search matches name, brand, SKU and variant', (tester) async {
      final harness = makeHarness([milk, soap]);
      await pumpList(tester, harness.container);

      Future<void> search(String query) async {
        await tester.enterText(searchBox(), query);
        await tester.pumpAndSettle();
      }

      // name, case-insensitively
      await search('amul');
      expect(find.text('Amul Milk'), findsOneWidget);
      expect(find.text('Zebra Soap'), findsNothing);
      expect(find.text('1 of 2 products'), findsOneWidget);

      // brand
      await search('zebra');
      expect(find.text('Zebra Soap'), findsOneWidget);
      expect(find.text('Amul Milk'), findsNothing);

      // SKU — printed on the details sheet, so it has to be searchable here
      await search('sku-milk');
      expect(find.text('Amul Milk'), findsOneWidget);
      expect(find.text('Zebra Soap'), findsNothing);

      // variant
      await search('100g');
      expect(find.text('Zebra Soap'), findsOneWidget);
      expect(find.text('Amul Milk'), findsNothing);
    });

    testWidgets('a no-match search explains itself and clears', (tester) async {
      final harness = makeHarness([milk, soap]);
      await pumpList(tester, harness.container);

      await tester.enterText(searchBox(), 'nothing-like-this');
      await tester.pumpAndSettle();

      expect(
          find.text('No products match "nothing-like-this".'), findsOneWidget);
      expect(find.textContaining('No products yet'), findsNothing);
      expect(find.text('0 of 2 products'), findsOneWidget);

      await tester.tap(find.text('Clear search'));
      await tester.pumpAndSettle();

      expect(find.text('2 of 2 products'), findsOneWidget);
      expect(find.text('Amul Milk'), findsOneWidget);
    });

    testWidgets('a filter that matches nothing never claims the shop is empty',
        (tester) async {
      final harness = makeHarness([milk, soap]);
      await pumpList(tester, harness.container);

      await tester.tap(find.text('Out of Stock'));
      await tester.pumpAndSettle();

      // The catalog is full — only the filter is empty, and the copy must say
      // so instead of telling the shopkeeper to create a first listing.
      expect(find.text('0 of 2 products'), findsOneWidget);
      expect(find.text('No products match your filters.'), findsOneWidget);
      expect(find.textContaining('No products yet'), findsNothing);
      expect(find.text('Amul Milk'), findsNothing);

      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();

      expect(find.text('2 of 2 products'), findsOneWidget);
      expect(find.text('Amul Milk'), findsOneWidget);
    });

    testWidgets('an empty catalog points at Add, not at filters',
        (tester) async {
      final harness = makeHarness([]);
      await pumpList(tester, harness.container);

      expect(
          find.text(
              'No products yet.\nTap "Add" to create your first listing.'),
          findsOneWidget);
      expect(find.text('No products match your filters.'), findsNothing);
      expect(find.text('Clear filters'), findsNothing);
      expect(find.text('0 of 0 products'), findsNothing);
    });

    testWidgets('sorting by name and price reorders the visible rows',
        (tester) async {
      final harness = makeHarness([soap, milk]);
      await pumpList(tester, harness.container);

      Future<void> sortBy(String label) async {
        await tester.tap(find.byIcon(Icons.sort));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      await sortBy('Name');
      expect(tester.getTopLeft(find.text('Amul Milk')).dy,
          lessThan(tester.getTopLeft(find.text('Zebra Soap')).dy));

      await sortBy('Price');
      expect(tester.getTopLeft(find.text('Zebra Soap')).dy,
          lessThan(tester.getTopLeft(find.text('Amul Milk')).dy));
    });
    testWidgets('the filter sheet narrows by category and Reset clears it',
        (tester) async {
      final harness = makeHarness([milk, soap]);
      await pumpList(tester, harness.container);
      await openFilters(tester);

      // The picker offers the values the catalog actually contains.
      await tester.tap(sheetPickers().at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dairy').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.text('1 of 2 products'), findsOneWidget);
      expect(find.text('Amul Milk'), findsOneWidget);
      expect(find.text('Zebra Soap'), findsNothing);

      // Reset clears the pickers *and* the list behind them, so a following
      // Apply can no longer re-send the stale selection.
      await openFilters(tester);
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.text('2 of 2 products'), findsOneWidget);
      expect(find.text('Zebra Soap'), findsOneWidget);
    });

    testWidgets('the filter sheet narrows by brand', (tester) async {
      final harness = makeHarness([milk, soap]);
      await pumpList(tester, harness.container);
      await openFilters(tester);

      await tester.tap(sheetPickers().at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zebra').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.text('1 of 2 products'), findsOneWidget);
      expect(find.text('Zebra Soap'), findsOneWidget);
      expect(find.text('Amul Milk'), findsNothing);
    });

    testWidgets('the filter sheet narrows by price range', (tester) async {
      final harness = makeHarness([milk, soap]);
      await pumpList(tester, harness.container);
      await openFilters(tester);

      await tester.enterText(sheetFields().at(0), '25');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.text('1 of 2 products'), findsOneWidget);
      expect(find.text('Amul Milk'), findsOneWidget);
      expect(find.text('Zebra Soap'), findsNothing);
    });

    testWidgets('category and brand pickers hide when no row has them',
        (tester) async {
      final harness = makeHarness([p(id: 9, name: 'Loose Rice', price: 60)]);
      await pumpList(tester, harness.container);
      await openFilters(tester);

      // A picker that could only ever match nothing is not offered at all.
      expect(sheetPickers(), findsNothing);
      expect(find.text('Availability'), findsOneWidget);
      expect(find.text('Recently updated'), findsOneWidget);
      expect(find.text('Price range'), findsOneWidget);
    });

    testWidgets('the row switch writes availability and shows the server value',
        (tester) async {
      final harness = makeHarness(
        [milk],
        onUpdate: (id, fields) => p(
          id: id,
          name: 'Amul Milk',
          isAvailable: fields['is_available'] as bool,
        ),
      );
      await pumpList(tester, harness.container);

      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(harness.repo.lastUpdatedId, 1);
      expect(harness.repo.lastUpdateFields?['is_available'], isFalse);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });
  });
}
