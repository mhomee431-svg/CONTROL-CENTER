import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/controllers/products_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/data/inventory_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/product_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/widgets/product_sheets.dart';

import 'fakes.dart';

/// The EDIT DATA FLOW, end to end, for all three surfaces the spec names.
///
/// The rule being tested is the one at the end of the spec: **do not create
/// separate disconnected copies**. A shopkeeper who edits a price in one place
/// and sees the old number elsewhere has two copies of one product, and there
/// is no way for a user to tell which one the backend will honour.
///
/// So every assertion here reads the CANONICAL state
/// ([ProductsController.items]) rather than a screen's local variable. A screen
/// that repaints itself from its own copy would pass a widget test and fail a
/// shopkeeper.
class _Env {
  _Env(this.container, this.repo);

  final ProviderContainer container;
  final FakeProductRepo repo;

  ProductsController get controller =>
      container.read(productsControllerProvider.notifier);

  /// The one true row for a product, wherever it is on screen.
  ShopProductItem canonical(int id) => container
      .read(productsControllerProvider)
      .items
      .firstWhere((i) => i.id == id);
}

void main() {
  const milk = ShopProductItem(
    id: 11,
    name: 'Amul Milk 1L',
    status: 'ACTIVE',
    price: 27,
    mrp: 30,
    isActive: true,
    isAvailable: true,
    quantity: 5,
    stockStatus: 'LOW_STOCK',
  );

  Future<_Env> env({FakeProductRepo? repo}) async {
    final r = repo ?? FakeProductRepo(items: [milk]);
    final container = ProviderContainer(
      overrides: [
        productRepositoryProvider.overrideWithValue(r),
        inventoryRepositoryProvider.overrideWithValue(r),
        tokenStoreProvider.overrideWithValue(
          InMemoryTokenStore(accessToken: 'tok'),
        ),
        selectedShopProvider.overrideWith(() => SelectedShopOverride(ownerShop())),
      ],
    );
    addTearDown(container.dispose);
    await container.read(productsControllerProvider.notifier).load();
    return _Env(container, r);
  }

  group('Products: Edit -> Save -> Backend -> Refresh', () {
    test('the edit reaches the backend and the row shows the server answer',
        () async {
      final e = await env();

      final ok = await e.controller.saveEdits(productId: 11, price: 99, mrp: 120);

      expect(ok, isTrue);
      // 1. It really went to the backend, not just to local state.
      expect(e.repo.lastUpdatedId, 11);
      expect(e.repo.lastUpdateFields?['price'], 99);
      // 2. The canonical row now holds it.
      expect(e.canonical(11).price, 99);
      expect(e.canonical(11).mrp, 120);
    });

    test('the server response wins over what the client asked for', () async {
      // A price clamped, rounded or rejected server-side must be what the
      // shopkeeper sees. Trusting the request would show a number the backend
      // never stored.
      final e = await env(
        repo: FakeProductRepo(
          items: [milk],
          onUpdate: (id, _) => milk.copyWith(price: 27),
        ),
      );

      await e.controller.saveEdits(productId: 11, price: 9999);

      expect(e.canonical(11).price, 27);
    });

    test('a rejected edit leaves the canonical row untouched', () async {
      final e = await env(
        repo: FakeProductRepo(
          items: [milk],
          // A rejected write: the transport fails, so nothing may change.
          onUpdate: (_, _) => throw const ApiException(message: 'offline'),
        ),
      );

      final ok = await e.controller.saveEdits(productId: 11, price: 99);

      expect(ok, isFalse);
      expect(e.canonical(11).price, 27);
    });

    testWidgets('Cancel closes the sheet and sends nothing', (tester) async {
      final r = FakeProductRepo(items: [milk]);
      final container = ProviderContainer(
        overrides: [
          productRepositoryProvider.overrideWithValue(r),
          inventoryRepositoryProvider.overrideWithValue(r),
          tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'tok'),
          ),
          selectedShopProvider.overrideWith(
            () => SelectedShopOverride(ownerShop()),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const ProductEditSheet(item: milk),
                ),
                child: const Text('open'),
              ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), '99');
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(ProductEditSheet), findsNothing);
      expect(r.lastUpdatedId, isNull);
    });
  });

  group('Inventory: Product -> Inventory -> Update -> Save', () {
    test('the adjustment lands on the canonical row', () async {
      final e = await env();

      final outcome =
          await e.controller.adjustStock(productId: 11, delta: 7);

      expect(outcome.ok, isTrue);
      expect(e.repo.adjustStockCalls, 1);
      expect(e.canonical(11).quantity, 12); // 5 + 7
    });

    test('the server post-update number wins over client arithmetic', () async {
      final e = await env(
        repo: FakeProductRepo(
          items: [milk],
          onAdjustStock: (shopId, productId, payload, token) =>
              StockAdjustmentResult(
            shopProductId: productId,
            previousQuantity: 5,
            quantityAdjustment: 7,
            // The server clamped it (another sale landed first).
            newQuantity: 9,
            stockStatus: 'IN_STOCK',
          ),
        ),
      );

      await e.controller.adjustStock(productId: 11, delta: 7);

      expect(e.canonical(11).quantity, 9);
    });

    test('a manual adjustment marks the row fresh, not stale', () async {
      // The shopkeeper just fixed the number by hand; the row must stop reading
      // "Stale - needs a refresh" immediately.
      final e = await env();

      await e.controller.adjustStock(productId: 11, delta: 1);

      expect(e.canonical(11).freshnessStatus, 'RECENTLY_UPDATED');
      expect(e.canonical(11).source, 'MANUAL');
    });
  });

  group('Pricing: Product -> Price -> Update -> Save', () {
    test('price and MRP go to the backend and back to the row', () async {
      final e = await env();

      final ok = await e.controller.saveEdits(
        productId: 11,
        price: 31.5,
        mrp: 35,
      );

      expect(ok, isTrue);
      expect(e.repo.lastUpdateFields?['price'], 31.5);
      expect(e.repo.lastUpdateFields?['mrp'], 35);
      expect(e.canonical(11).price, 31.5);
      expect(e.canonical(11).mrp, 35);
    });

    test('an unchanged field is not sent', () async {
      // Sending every field on every save would overwrite a change made
      // elsewhere with this screen's stale copy of it.
      final e = await env();

      await e.controller.saveEdits(productId: 11, price: 31.5);

      expect(e.repo.lastUpdateFields?.containsKey('mrp'), isFalse);
      expect(e.repo.lastUpdateFields?.containsKey('quantity'), isFalse);
    });
  });

  group('One product, one row', () {
    test('editing from two surfaces converges on the same item', () async {
      // Price then stock, through the two different entry points. If either kept
      // its own copy, the second write would resurrect the first surface's
      // value.
      final e = await env();

      await e.controller.saveEdits(productId: 11, price: 40, mrp: 45);
      await e.controller.adjustStock(productId: 11, delta: 3);

      final row = e.canonical(11);
      expect(row.price, 40); // survived the stock write
      expect(row.quantity, 8); // survived the price write
    });

    test('the list holds exactly one row per product', () async {
      final e = await env();

      await e.controller.saveEdits(productId: 11, price: 40);
      await e.controller.adjustStock(productId: 11, delta: 1);

      expect(
        e.container
            .read(productsControllerProvider)
            .items
            .where((i) => i.id == 11)
            .length,
        1,
      );
    });
  });
}
