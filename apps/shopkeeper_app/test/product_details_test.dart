import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/app.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/data/auth_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/dashboard/data/dashboard_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/notifications/data/notifications_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/product_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/controllers/products_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/widgets/product_details_sheet.dart';

import 'fakes.dart';

/// PRODUCTS screen inventory: the read-only **Product Details** view that every
/// list row opens, plus its write entry points (edit / stock / history) and the
/// availability toggle.
ShopProductItem product({
  int id = 42,
  String name = 'Amul Milk 500ml',
  double price = 30,
  double? mrp,
  String? sku,
  String? brand,
  String? category,
  String? variant,
  String? imageUrl,
  int quantity = 12,
  String stockStatus = 'IN_STOCK',
  String status = 'ACTIVE',
  bool isActive = true,
  bool isAvailable = true,
  String? source,
  String? updatedBy,
  DateTime? lastUpdated,
  String? freshnessStatus,
}) =>
    ShopProductItem(
      id: id,
      name: name,
      status: status,
      price: price,
      mrp: mrp,
      sku: sku,
      brand: brand,
      category: category,
      variant: variant,
      imageUrl: imageUrl,
      isActive: isActive,
      isAvailable: isAvailable,
      quantity: quantity,
      stockStatus: stockStatus,
      freshnessStatus: freshnessStatus,
      lastUpdated: lastUpdated,
      source: source,
      updatedBy: updatedBy,
    );

void main() {
  /// Product repository + container, with the token/shop base pair the repo's
  /// controller convention requires.
  ({ProviderContainer container, FakeProductRepo repo}) makeHarness({
    List<ShopProductItem> items = const [],
    ShopProductItem? Function(int, Map<String, dynamic>)? onUpdate,
  }) {
    final repo = FakeProductRepo(items: items, onUpdate: onUpdate);
    final container = ProviderContainer(overrides: [
      productRepositoryProvider.overrideWithValue(repo),
      tokenStoreProvider.overrideWithValue(
          InMemoryTokenStore(accessToken: 'test-access-token')),
      selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
    ]);
    addTearDown(container.dispose);
    return (container: container, repo: repo);
  }

  Future<void> pumpSheet(
    WidgetTester tester,
    ProviderContainer container,
    ShopProductItem item,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: ProductDetailsSheet(item: item))),
    ));
    await tester.pumpAndSettle();
  }

  group('ProductDetailsSheet', () {
    testWidgets('shows pricing, inventory and catalog details', (tester) async {
      final harness = makeHarness();
      await pumpSheet(
        tester,
        harness.container,
        product(
          mrp: 40,
          sku: 'AMUL-500',
          brand: 'Amul',
          category: 'Dairy',
          variant: '500ml',
          source: 'BARCODE_SCAN',
          updatedBy: 'Ramesh',
          freshnessStatus: 'RECENTLY_UPDATED',
          lastUpdated: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
      );

      expect(find.text('Amul Milk 500ml'), findsOneWidget);
      expect(find.text('Amul - 500ml'), findsOneWidget);
      // Pricing: 30 against an MRP of 40 is a 25% saving.
      expect(find.text('Pricing'), findsOneWidget);
      expect(find.text('Selling price'), findsOneWidget);
      expect(find.text('Rs 30.00'), findsOneWidget);
      expect(find.text('Rs 40.00'), findsOneWidget);
      expect(find.text('25% off MRP'), findsOneWidget);
      // Inventory (server-owned vocabulary mapped for display).
      expect(find.text('Inventory'), findsOneWidget);
      expect(find.text('Stock status'), findsOneWidget);
      expect(find.text('In stock'), findsOneWidget);
      expect(find.text('Barcode scan'), findsOneWidget);
      expect(find.text('Ramesh'), findsOneWidget);
      expect(find.text('Fresh'), findsOneWidget);
      // Catalog reference (read-only master data).
      expect(find.text('Catalog reference'), findsOneWidget);
      expect(find.text('AMUL-500'), findsOneWidget);
      expect(find.text('Dairy'), findsOneWidget);
      // The one write this view performs directly.
      expect(find.text('Available to customers'), findsOneWidget);
    });

    testWidgets('shows an explicit placeholder when the master has no image',
        (tester) async {
      final harness = makeHarness();
      await pumpSheet(tester, harness.container, product(imageUrl: null));

      expect(find.text('No image'), findsOneWidget);
      expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
    });

    testWidgets('flags stale inventory and missing provenance', (tester) async {
      final harness = makeHarness();
      await pumpSheet(
        tester,
        harness.container,
        product(freshnessStatus: 'STALE'),
      );

      expect(find.text('Stale - needs a refresh'), findsOneWidget);
      expect(find.text('Not updated yet'), findsOneWidget);
      // Both "Updated by" and "Source" are unknown - never fabricated.
      expect(find.text('Not recorded'), findsWidgets);
    });

    testWidgets('out-of-stock listing is flagged in the header and inventory',
        (tester) async {
      final harness = makeHarness();
      await pumpSheet(
        tester,
        harness.container,
        product(quantity: 0, stockStatus: 'OUT_OF_STOCK'),
      );

      // Status chip + the "Stock status" row.
      expect(find.text('Out of stock'), findsNWidgets(2));
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('availability toggle writes through the products controller',
        (tester) async {
      final harness = makeHarness(
        items: [product()],
        onUpdate: (id, fields) => product(
          id: id,
          isAvailable: fields['is_available'] as bool? ?? true,
        ),
      );
      await harness.container.read(productsControllerProvider.notifier).load();
      await pumpSheet(tester, harness.container, product());
      expect(
          find.text('Customers can see and buy this listing.'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(harness.repo.lastUpdatedId, 42);
      expect(harness.repo.lastUpdateFields!['is_available'], isFalse);
      // The view follows the controller's updated row.
      expect(find.text('Hidden from customers until you switch it back on.'),
          findsOneWidget);
    });

    testWidgets('Edit product opens the edit sheet for the live values',
        (tester) async {
      final harness = makeHarness(items: [product()]);
      await harness.container.read(productsControllerProvider.notifier).load();
      await pumpSheet(tester, harness.container, product());

      await tester.tap(find.text('Edit product'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Amul Milk 500ml'), findsOneWidget);
    });

    testWidgets('re-resolves the row from controller state (live refresh)',
        (tester) async {
      final harness = makeHarness(items: [product(price: 55)]);
      await harness.container.read(productsControllerProvider.notifier).load();

      // A stale snapshot from the list must never win over live state.
      await pumpSheet(tester, harness.container, product(id: 42, price: 30));

      expect(find.text('Rs 55.00'), findsOneWidget);
      expect(find.text('Rs 30.00'), findsNothing);
    });

    testWidgets('falls back to the tapped snapshot when the row is gone',
        (tester) async {
      final harness = makeHarness();
      await pumpSheet(tester, harness.container, product(price: 30));

      expect(find.text('Rs 30.00'), findsOneWidget);
    });
  });

  // The list -> details wiring: a product row is the entry point to the
  // read-only details view; every write is launched from inside it.
  group('products list -> product details', () {
    testWidgets('tapping a product row opens its details', (tester) async {
      final container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(
            FakeAuthRepository()..restoreResult = makeSession()),
        dashboardRepositoryProvider.overrideWithValue(FakeDashboardRepo()),
        notificationsRepositoryProvider
            .overrideWithValue(FakeNotificationsRepo()),
        productRepositoryProvider.overrideWithValue(
            FakeProductRepo(items: [product(name: 'Amul Milk 500ml')])),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
      ]);
      addTearDown(container.dispose);
      // Phone-sized viewport: below 900 logical px the shell uses the bottom
      // NavigationBar (wider layouts render a NavigationRail instead).
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const ShopkeeperApp(),
      ));
      await tester.pumpAndSettle();

      // Switch tabs through the shell — the dashboard also renders the word
      // "Products", so a bare text finder would be ambiguous.
      await tester.tap(find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Products'),
      ));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Amul Milk 500ml'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Amul Milk 500ml'));
      await tester.pumpAndSettle();

      expect(find.text('Pricing'), findsOneWidget);
      expect(find.text('Edit product'), findsOneWidget);
      expect(find.text('Update stock'), findsOneWidget);
      expect(find.text('View history'), findsOneWidget);
    });
  });
}