import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/data/inventory_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/product_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/controllers/products_controller.dart';

import 'fakes.dart';

/// Spec §131 INVENTORY TEST CASES, one group per named case: stock increase,
/// stock decrease, zero, negative, large number, concurrent update response,
/// stale inventory, network failure.
///
/// Two rules the spec states for this module drive most of them:
///   * §30 "Prevent duplicate submission" — one in-flight write at a time.
///   * §31 "Backend remains authoritative" — the server's post-update quantity
///     and stock status are adopted verbatim; the client never recomputes them.
///
/// The concurrency case is the one that found a real bug: the read paths were
/// generation-guarded, but a stock write could race ITSELF.
void main() {
  /// The backend caps quantities at 999,999 (`le=999_999` on the schema) and the
  /// stock sheet mirrors that number, so the tests can use the real boundary.
  const maxQuantity = 999999;

  ShopProductItem row({int id = 1, int quantity = 10, String? freshness}) =>
      ShopProductItem(
        id: id,
        name: 'Amul Milk 500ml',
        status: 'ACTIVE',
        price: 30,
        isActive: true,
        isAvailable: quantity > 0,
        quantity: quantity,
        stockStatus: quantity == 0 ? 'OUT_OF_STOCK' : 'IN_STOCK',
        freshnessStatus: freshness,
      );

  /// A container whose catalog is already [items] (loaded, not just seeded).
  Future<({ProviderContainer container, FakeProductRepo repo})> loaded(
    List<ShopProductItem> items, {
    StockAdjustmentResult? Function(int, int, Map<String, dynamic>, String)?
        onAdjust,
  }) async {
    final repo = FakeProductRepo(items: items, onAdjustStock: onAdjust);
    final container = ProviderContainer(overrides: [
      productRepositoryProvider.overrideWithValue(repo),
      inventoryRepositoryProvider.overrideWithValue(repo),
      tokenStoreProvider.overrideWithValue(
          InMemoryTokenStore(accessToken: 'test-access-token')),
      selectedShopProvider
          .overrideWith(() => SelectedShopOverride(ownerShop(id: 10))),
    ]);
    addTearDown(container.dispose);
    await container.read(productsControllerProvider.notifier).load();
    return (container: container, repo: repo);
  }

  /// The server's answer for one adjustment.
  StockAdjustmentResult answer(
    int id,
    int previous,
    int delta,
    int next,
    String stockStatus,
  ) =>
      StockAdjustmentResult(
        shopProductId: id,
        previousQuantity: previous,
        quantityAdjustment: delta,
        newQuantity: next,
        stockStatus: stockStatus,
      );

  /// Asserts the LIVE row for [id] reports [quantity] / [stockStatus].
  void expectRow(
    ProviderContainer container,
    int id,
    int quantity,
    String stockStatus,
  ) {
    final item = container.read(productsControllerProvider).itemById(id);
    expect(item, isNotNull, reason: 'row $id left the catalog');
    expect(item!.quantity, quantity);
    expect(item.stockStatus, stockStatus);
  }

  // ── §131: stock increase / stock decrease ─────────────────────────────────
  group('stock increase and stock decrease', () {
    test('an increase adopts the server quantity and stock state', () async {
      final h = await loaded([row(quantity: 10)],
          onAdjust: (_, _, _, _) => answer(1, 10, 25, 35, 'IN_STOCK'));

      final outcome = await h.container
          .read(productsControllerProvider.notifier)
          .adjustStock(productId: 1, delta: 25);

      expect(outcome.ok, isTrue);
      expectRow(h.container, 1, 35, 'IN_STOCK');
      expect(outcome.result!.newQuantity, 35);
    });

    test('a decrease adopts the server number — the client never subtracts',
        () async {
      // §31: the server computes the new quantity, so a decrease landing on a
      // different number than 10-8 proves we adopt rather than recompute.
      final h = await loaded([row(quantity: 10)],
          onAdjust: (_, _, _, _) => answer(1, 10, -8, 2, 'LOW_STOCK'));

      final outcome = await h.container
          .read(productsControllerProvider.notifier)
          .adjustStock(productId: 1, delta: -8);

      expect(outcome.ok, isTrue);
      expectRow(h.container, 1, 2, 'LOW_STOCK');
    });

    test('a decrease to zero flips the row out of stock and unavailable',
        () async {
      final h = await loaded([row(quantity: 3)],
          onAdjust: (_, _, _, _) => answer(1, 3, -3, 0, 'OUT_OF_STOCK'));

      final outcome = await h.container
          .read(productsControllerProvider.notifier)
          .adjustStock(productId: 1, delta: -3);

      expect(outcome.ok, isTrue);
      expectRow(h.container, 1, 0, 'OUT_OF_STOCK');
      // Zero units on the shelf means nothing to buy.
      expect(
        h.container.read(productsControllerProvider).itemById(1)!.isAvailable,
        isFalse,
      );
    });

    test('a negative delta is a legitimate decrease, not a client rejection',
        () async {
      final h = await loaded([row(quantity: 10)],
          onAdjust: (_, _, _, _) => answer(1, 10, -4, 6, 'IN_STOCK'));

      await h.container
          .read(productsControllerProvider.notifier)
          .adjustStock(productId: 1, delta: -4);

      expect(h.repo.lastAdjustPayload!['quantity_adjustment'], -4);
    });
  });

  // ── §131: zero ────────────────────────────────────────────────────────────
  group('zero', () {
    test('a zero change never reaches the network', () async {
      final h = await loaded([row(quantity: 10)]);

      final outcome = await h.container
          .read(productsControllerProvider.notifier)
          .adjustStock(productId: 1, delta: 0);

      expect(outcome.ok, isFalse);
      expect(outcome.error, 'Quantity change cannot be zero');
      // The backend rejects a zero adjustment too, so asking would only burn a
      // round-trip to learn something already known.
      expect(h.repo.adjustStockCalls, 0);
      expectRow(h.container, 1, 10, 'IN_STOCK');
    });

    test('setting stock TO zero is a legal -N delta, not a no-op', () async {
      final h = await loaded([row(quantity: 10)],
          onAdjust: (_, _, _, _) => answer(1, 10, -10, 0, 'OUT_OF_STOCK'));

      final outcome = await h.container
          .read(productsControllerProvider.notifier)
          .adjustStock(productId: 1, delta: -10);

      expect(outcome.ok, isTrue);
      expectRow(h.container, 1, 0, 'OUT_OF_STOCK');
    });
  });

  // ── §131: negative ────────────────────────────────────────────────────────
  group('negative', () {
    test('a "result would go negative" refusal is shown verbatim', () async {
      // §31: the server owns the floor, so the app surfaces ITS wording rather
      // than inventing "stock cannot be negative" of its own.
      const refusal = 'Resulting quantity cannot be negative';
      final h = await loaded([row(quantity: 2)],
          onAdjust: (_, _, _, _) =>
              throw const ApiException(statusCode: 400, message: refusal));

      final outcome = await h.container
          .read(productsControllerProvider.notifier)
          .adjustStock(productId: 1, delta: -5);

      expect(outcome.ok, isFalse);
      expect(outcome.error, refusal);
      expectRow(h.container, 1, 2, 'IN_STOCK');
    });

    test('a 404 says the product left the inventory, not a generic failure',
        () async {
      final h = await loaded([row(quantity: 2)],
          onAdjust: (_, _, _, _) =>
              throw const ApiException(statusCode: 404, message: 'Not found'));

      final outcome = await h.container
          .read(productsControllerProvider.notifier)
          .adjustStock(productId: 1, delta: 5);

      expect(outcome.ok, isFalse);
      expect(outcome.error, 'This product is no longer in your inventory.');
    });
  });

  // ── §131: large number ────────────────────────────────────────────────────
  group('large number', () {
    test('the server quantity is adopted verbatim, however large', () async {
      // §31 "overflowing quantities": the cap is the server's, and the client
      // renders whatever it answers without clamping.
      final h = await loaded([row(quantity: 10)],
          onAdjust: (_, _, _, _) =>
              answer(1, 10, 999989, 999999, 'IN_STOCK'));

      final outcome = await h.container
          .read(productsControllerProvider.notifier)
          .adjustStock(productId: 1, delta: 999989);

      expect(outcome.ok, isTrue);
      expectRow(h.container, 1, maxQuantity, 'IN_STOCK');
    });

    test('a delta past the backend cap is refused with the server message',
        () async {
      const refusal = 'quantity_adjustment must be <= 999999';
      final h = await loaded([row(quantity: 10)],
          onAdjust: (_, _, _, _) =>
              throw const ApiException(statusCode: 422, message: refusal));

      final outcome = await h.container
          .read(productsControllerProvider.notifier)
          .adjustStock(productId: 1, delta: 5000000);

      expect(outcome.ok, isFalse);
      expect(outcome.error, refusal);
      // A refused oversized write must not corrupt the row.
      expectRow(h.container, 1, 10, 'IN_STOCK');
    });
  });

  // ── §131: concurrent update response ──────────────────────────────────────
  group('concurrent update response', () {
    test('a slower first write cannot roll the row back over a newer one',
        () async {
      // The bug this pins: two saves in flight, the SECOND answers first, then
      // the superseded first one lands and used to repaint the row with its own
      // older quantity — silently undoing the shopkeeper's second edit.
      final first = Completer<void>();
      final h = await loaded([row(quantity: 10)],
          // 10 + 5 = 15, the answer that arrives LAST and is already stale.
          onAdjust: (_, _, payload, _) => (payload['quantity_adjustment'] == 5)
              ? answer(1, 10, 5, 15, 'IN_STOCK')
              : answer(1, 15, 3, 18, 'IN_STOCK'));
      h.repo.adjustStockGates.addAll([first, null]);

      final controller = h.container.read(productsControllerProvider.notifier);

      // First save: +5, its response is withheld.
      final firstCall = controller.adjustStock(productId: 1, delta: 5);
      await Future<void>.delayed(Duration.zero);

      // Second save: +3, answers straight away.
      final secondOutcome = await controller.adjustStock(productId: 1, delta: 3);
      expect(secondOutcome.ok, isTrue);
      expectRow(h.container, 1, 18, 'IN_STOCK');

      // The superseded first response finally lands, carrying its older
      // arithmetic (10 + 5 = 15).
      first.complete();
      final firstOutcome = await firstCall;

      // It genuinely succeeded on the server, so it must NOT be reported as a
      // failure...
      expect(firstOutcome.ok, isTrue);
      // ...but it must not repaint the row either: 18 is the newest truth.
      expectRow(h.container, 1, 18, 'IN_STOCK');
      expect(h.repo.adjustStockCalls, 2);
    });

    test('a superseded failure cannot paint its error over a newer success',
        () async {
      final first = Completer<void>();
      final h = await loaded([row(quantity: 10)], onAdjust: (_, _, payload, _) {
        // Only the FIRST write (delta 5) is rejected; the newer one succeeds.
        if (payload['quantity_adjustment'] == 5) {
          throw const ApiException(message: 'first write rejected');
        }
        return answer(1, 10, 3, 13, 'IN_STOCK');
      });
      h.repo.adjustStockGates.addAll([first, null]);

      final controller = h.container.read(productsControllerProvider.notifier);
      final firstCall = controller.adjustStock(productId: 1, delta: 5);
      await Future<void>.delayed(Duration.zero);

      await controller.adjustStock(productId: 1, delta: 3);
      expectRow(h.container, 1, 13, 'IN_STOCK');

      first.complete();
      await firstCall;

      // The row is the newer success and carries NO stale error banner.
      final state = h.container.read(productsControllerProvider);
      expect(state.itemById(1)!.quantity, 13);
      expect(state.message, isNull);
    });
  });

  // ── §131: stale inventory ─────────────────────────────────────────────────
  group('stale inventory', () {
    test('a manual write clears the stale tier the server reported', () async {
      // The listing arrives flagged STALE (e.g. last touched by a POS sync); a
      // manual adjustment is the freshest source there is, so the flag must go.
      final h = await loaded([row(quantity: 10, freshness: 'STALE')]);
      expect(
        h.container.read(productsControllerProvider).itemById(1)!.isStale,
        isTrue,
      );

      await h.container
          .read(productsControllerProvider.notifier)
          .adjustStock(productId: 1, delta: 4);

      final item = h.container.read(productsControllerProvider).itemById(1)!;
      expect(item.quantity, 14);
      expect(item.isStale, isFalse,
          reason: 'a manual write is the freshest source there is');
      expect(item.source, 'MANUAL');
    });

    test('a row the server never timestamped is not invented to be fresh',
        () async {
      final h = await loaded([row(quantity: 10)]);
      final item = h.container.read(productsControllerProvider).itemById(1)!;

      // No freshness tier from the server means "unknown", not "fresh".
      expect(item.hasFreshness, isFalse);
      expect(item.isFresh, isFalse);
    });
  });

  // ── §131: network failure ─────────────────────────────────────────────────
  group('network failure', () {
    test('an offline write keeps the row and explains itself', () async {
      const offline = 'You appear to be offline. Please check your connection.';
      final h = await loaded([row(quantity: 10)],
          onAdjust: (_, _, _, _) =>
              throw const ApiException(statusCode: null, message: offline));

      final outcome = await h.container
          .read(productsControllerProvider.notifier)
          .adjustStock(productId: 1, delta: 5);

      expect(outcome.ok, isFalse);
      expect(outcome.error, offline);
      // The whole point: the shopkeeper's numbers are NOT lost behind a failure.
      expectRow(h.container, 1, 10, 'IN_STOCK');
      expect(h.container.read(productsControllerProvider).message, offline);
    });

    test('an unexpected error never lands as a fake success', () async {
      final h = await loaded([row(quantity: 10)],
          onAdjust: (_, _, _, _) => throw StateError('boom'));

      final outcome = await h.container
          .read(productsControllerProvider.notifier)
          .adjustStock(productId: 1, delta: 5);

      expect(outcome.ok, isFalse);
      expect(outcome.error, 'Could not update stock. Please retry.');
      expectRow(h.container, 1, 10, 'IN_STOCK');
    });

    test('a write is refused before the network when no shop is selected',
        () async {
      final repo = FakeProductRepo(items: [row(quantity: 10)]);
      final container = ProviderContainer(overrides: [
        productRepositoryProvider.overrideWithValue(repo),
        inventoryRepositoryProvider.overrideWithValue(repo),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        selectedShopProvider.overrideWith(() => SelectedShopOverride(null)),
      ]);
      addTearDown(container.dispose);

      final outcome = await container
          .read(productsControllerProvider.notifier)
          .adjustStock(productId: 1, delta: 5);

      expect(outcome.ok, isFalse);
      expect(repo.adjustStockCalls, 0);
    });
  });
}