import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/core/ui/debounced_search_field.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/presentation/screens/low_stock_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/data/inventory_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/product_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/widgets/product_image_view.dart';

import 'fakes.dart';

/// Dedicated Low Stock Management screen.
///
/// Pins the restock contract: the warning banner appears ONLY when something
/// is at or below its own threshold, cards carry SKU + threshold + a
/// highlighted current stock, both actions exist, and a healthy inventory
/// reads "All items well stocked" instead of showing an alarm.
ShopProductItem lowItem({
  required int id,
  required String name,
  int quantity = 2,
  int threshold = 5,
  String sku = 'SKU-1',
  String? imageUrl,
}) =>
    ShopProductItem(
      id: id,
      name: name,
      status: 'ACTIVE',
      price: 100,
      sku: sku,
      imageUrl: imageUrl,
      isActive: true,
      isAvailable: quantity > 0,
      quantity: quantity,
      stockStatus: quantity == 0 ? 'OUT_OF_STOCK' : 'LOW_STOCK',
      lowStockThreshold: threshold,
    );

ShopProductItem healthyItem({
  required int id,
  required String name,
  int quantity = 40,
  int threshold = 5,
}) =>
    ShopProductItem(
      id: id,
      name: name,
      status: 'ACTIVE',
      price: 100,
      sku: 'SKU-OK-$id',
      isActive: true,
      isAvailable: true,
      quantity: quantity,
      stockStatus: 'IN_STOCK',
      lowStockThreshold: threshold,
    );


ProviderContainer makeContainer({required FakeProductRepo productRepo}) {
  return ProviderContainer(
    overrides: [
      productRepositoryProvider.overrideWithValue(productRepo),
      inventoryRepositoryProvider.overrideWithValue(productRepo),
      tokenStoreProvider.overrideWithValue(
        InMemoryTokenStore(accessToken: 'test-access-token'),
      ),
      selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
    ],
  );
}

Future<void> pumpScreen(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: LowStockScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('LowStockScreen — warning banner', () {
    testWidgets('shows the banner with the count when items need restocking',
        (tester) async {
      final container = makeContainer(
        productRepo: FakeProductRepo(items: [
          lowItem(id: 1, name: 'Oil 1L', quantity: 2, threshold: 5),
          lowItem(id: 2, name: 'Bread', quantity: 0, threshold: 4),
          healthyItem(id: 3, name: 'Rice 5kg', quantity: 40),
        ]),
      );
      addTearDown(container.dispose);

      await pumpScreen(tester, container);

      expect(find.byKey(const Key('low-stock-banner')), findsOneWidget);
      expect(find.text('2 items require immediate restocking'), findsOneWidget);
    });

    testWidgets('hides the banner entirely when nothing is low',
        (tester) async {
      final container = makeContainer(
        productRepo: FakeProductRepo(
          items: [healthyItem(id: 1, name: 'Rice 5kg')],
        ),
      );
      addTearDown(container.dispose);

      await pumpScreen(tester, container);

      expect(find.byKey(const Key('low-stock-banner')), findsNothing);
    });
  });

  group('LowStockScreen — restock cards', () {
    testWidgets('shows SKU, highlighted stock and the threshold',
        (tester) async {
      final container = makeContainer(
        productRepo: FakeProductRepo(items: [
          lowItem(
            id: 7,
            name: 'Oil 1L',
            quantity: 2,
            threshold: 5,
            sku: 'OIL-1L',
          ),
        ]),
      );
      addTearDown(container.dispose);

      await pumpScreen(tester, container);

      expect(find.byKey(const Key('low-stock-card-7')), findsOneWidget);
      expect(find.text('Oil 1L'), findsOneWidget);
      expect(find.text('SKU: OIL-1L'), findsOneWidget);
      expect(find.byKey(const Key('low-stock-qty-7')), findsOneWidget);
      expect(find.text('2 units left'), findsOneWidget);
      expect(find.text('Threshold: 5 units'), findsOneWidget);
    });

    testWidgets('offers both actions on every card', (tester) async {
      final container = makeContainer(
        productRepo: FakeProductRepo(items: [
          lowItem(id: 7, name: 'Oil 1L', quantity: 2, threshold: 5),
        ]),
      );
      addTearDown(container.dispose);

      await pumpScreen(tester, container);

      expect(find.byKey(const Key('low-stock-update-7')), findsOneWidget);
      expect(find.byKey(const Key('low-stock-open-7')), findsOneWidget);
    });

    testWidgets('Update Stock opens the quick stock sheet, no page reload',
        (tester) async {
      final container = makeContainer(
        productRepo: FakeProductRepo(items: [
          lowItem(id: 7, name: 'Oil 1L', quantity: 2, threshold: 5),
        ]),
      );
      addTearDown(container.dispose);

      await pumpScreen(tester, container);

      await tester
          .tap(find.byKey(const Key('low-stock-update-7')));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Oil 1L'), findsWidgets);
    });

    testWidgets('Open Product opens the full product details',
        (tester) async {
      final container = makeContainer(
        productRepo: FakeProductRepo(items: [
          lowItem(id: 7, name: 'Oil 1L', quantity: 2, threshold: 5),
        ]),
      );
      addTearDown(container.dispose);

      await pumpScreen(tester, container);

      await tester.tap(find.byKey(const Key('low-stock-open-7')));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
    });
  });

  group('LowStockScreen — empty state', () {
    testWidgets('reads "All items well stocked" when the shelf is full',
        (tester) async {
      final container = makeContainer(
        productRepo: FakeProductRepo(items: [
          healthyItem(id: 1, name: 'Rice 5kg'),
          healthyItem(id: 2, name: 'Dal 1kg'),
        ]),
      );
      addTearDown(container.dispose);

      await pumpScreen(tester, container);

      expect(find.byKey(const Key('low-stock-empty')), findsOneWidget);
      expect(find.text('All items well stocked'), findsOneWidget);
    });

    testWidgets('treats a listing exactly at its threshold as low',
        (tester) async {
      final container = makeContainer(
        productRepo: FakeProductRepo(
          items: [lowItem(id: 9, name: 'Soap', quantity: 5, threshold: 5)],
        ),
      );
      addTearDown(container.dispose);

      await pumpScreen(tester, container);

      // `quantity <= threshold`, so 5/5 still needs restocking.
      expect(find.byKey(const Key('low-stock-banner')), findsOneWidget);
      expect(find.text('1 item requires immediate restocking'), findsOneWidget);
    });
  });

  group('LowStockScreen — PERFORMANCE (§110)', () {
    testWidgets('uses the shared debounced search field, not a raw TextField',
        (tester) async {
      // §110 "debounced search" + the no-duplication rule: the restock slice is
      // derived from the whole catalog, so filtering it on every glyph would
      // re-run a full pass per keystroke. The shared field debounces that and
      // gives this list the same search history as the other catalog lists.
      final container = makeContainer(
        productRepo: FakeProductRepo(
          items: [lowItem(id: 7, name: 'Oil 1L', quantity: 2, threshold: 5)],
        ),
      );
      addTearDown(container.dispose);

      await pumpScreen(tester, container);

      expect(
        find.byWidgetPredicate(
          (w) => w is DebouncedSearchField && w.key == const Key('low-stock-search-field'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('filters the restock slice by the typed name', (tester) async {
      final container = makeContainer(
        productRepo: FakeProductRepo(
          items: [
            lowItem(id: 7, name: 'Oil 1L', quantity: 2, threshold: 5),
            lowItem(id: 8, name: 'Bread', quantity: 1, threshold: 5),
          ],
        ),
      );
      addTearDown(container.dispose);

      await pumpScreen(tester, container);
      expect(find.byKey(const Key('low-stock-card-7')), findsOneWidget);
      expect(find.byKey(const Key('low-stock-card-8')), findsOneWidget);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('low-stock-search-field')),
          matching: find.byType(TextField),
        ),
        'oil',
      );
      // Past the field's 300ms debounce, so the filter has actually run.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('low-stock-card-7')), findsOneWidget);
      expect(find.byKey(const Key('low-stock-card-8')), findsNothing);
    });

    testWidgets('a rebuild with unchanged data keeps the derived slice stable',
        (tester) async {
      // The derivation is memoized on (catalog, query). Opening the stock sheet
      // rebuilds this screen with the SAME catalog and the SAME query; without
      // the memo that would re-sort the whole catalog for a change the
      // shopkeeper never made. The rows must be identical afterwards, still in
      // urgency order (fewest units first).
      final container = makeContainer(
        productRepo: FakeProductRepo(
          items: [
            lowItem(id: 7, name: 'Oil 1L', quantity: 2, threshold: 5),
            lowItem(id: 8, name: 'Bread', quantity: 1, threshold: 5),
          ],
        ),
      );
      addTearDown(container.dispose);

      await pumpScreen(tester, container);
      expect(find.byKey(const Key('low-stock-card-8')), findsOneWidget);
      expect(find.text('1 units left'), findsOneWidget);

      // Open and dismiss the stock sheet — a rebuild with no data change.
      await tester.tap(find.byKey(const Key('low-stock-update-8')));
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('low-stock-card-8')), findsOneWidget);
      expect(find.byKey(const Key('low-stock-card-7')), findsOneWidget);
      expect(find.text('1 units left'), findsOneWidget);
    });

    testWidgets('the thumbnail goes through the shared optimized image widget',
        (tester) async {
      // §110 "image optimization": the row thumbnail must decode at ~2x its
      // 48px box rather than the source resolution, and must be decorative
      // (the card already names the product).
      final container = makeContainer(
        productRepo: FakeProductRepo(
          items: [
            lowItem(
              id: 7,
              name: 'Oil 1L',
              quantity: 2,
              threshold: 5,
              imageUrl: 'https://cdn.example.com/oil.jpg',
            ),
          ],
        ),
      );
      addTearDown(container.dispose);

      await pumpScreen(tester, container);

      final image =
          tester.widget<ProductImageView>(find.byType(ProductImageView));
      expect(image.imageUrl, 'https://cdn.example.com/oil.jpg');
      expect(image.cacheWidth, 96);
      expect(image.excludeFromSemantics, isTrue);
    });
  });

}

