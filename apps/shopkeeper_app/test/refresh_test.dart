import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/data/inventory_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/domain/inventory_scope.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/presentation/screens/inventory_list_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/offers/data/offers_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/offers/presentation/screens/offers_screen.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/product_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/controllers/products_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/screens/products_screen.dart';

import 'fakes.dart';

/// REFRESH (spec #97) — pull-to-refresh where it is useful, and the two rules
/// that keep it honest:
///
///   * a pull REFETCHES (exactly once) and keeps what is already on screen —
///     a short list, an empty offer bucket and a full list all behave the
///     same, because every pull-able list is ALWAYS scrollable;
///   * a mutation patches the affected rows; it never reloads the catalog.
///
/// The gesture half is driven through the REAL screens (the real
/// `RefreshIndicator`s and the real controllers); only the repository is
/// faked. The catalogs are deliberately tiny: a list shorter than the viewport
/// is exactly the case where a pull silently dies without
/// `AlwaysScrollableScrollPhysics`.
ShopProductItem p(int id, String name, {int quantity = 5}) => ShopProductItem(
      id: id,
      name: name,
      status: 'ACTIVE',
      price: 10,
      isActive: true,
      isAvailable: quantity > 0,
      quantity: quantity,
      stockStatus: quantity > 0 ? 'IN_STOCK' : 'OUT_OF_STOCK',
    );

void main() {
  ({ProviderContainer container, FakeProductRepo repo}) makeHarness(
      List<ShopProductItem> items) {
    final repo = FakeProductRepo(items: items);
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

  Future<void> pumpScreen(
    WidgetTester tester,
    ProviderContainer container,
    Widget child,
  ) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: child),
    ));
    await tester.pumpAndSettle();
  }

  /// Pulls the list down hard enough to fire the refresh.
  ///
  /// Fixed pumps, never [WidgetTester.pumpAndSettle]: the refreshes held open
  /// by a gate would make settling time out, and the in-flight frame is
  /// exactly what these tests look at.
  Future<void> pullToRefresh(WidgetTester tester) async {
    await tester.fling(
        find.byType(CustomScrollView), const Offset(0, 320), 1200);
    await tester.pump(); // the drag settles
    await tester.pump(const Duration(seconds: 1)); // onRefresh fires
  }

  group('ProductsController — refresh() is the silent path', () {
    test('it refetches and swaps the rows in without blanking', () async {
      final items = [p(1, 'Amul Milk')];
      final h = makeHarness(items);
      final controller = h.container.read(productsControllerProvider.notifier);
      await controller.load();
      expect(h.repo.overviewCalls, 1);

      // Hold the response so the in-flight window is observable.
      final gate = Completer<void>();
      h.repo.overviewGate = gate;
      final refreshing = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(h.repo.overviewCalls, 2);
      // The pull is SILENT: still ready, still showing the row, no error.
      expect(
        h.container.read(productsControllerProvider).status,
        ProductsStatus.ready,
      );
      expect(h.container.read(productsControllerProvider).items, hasLength(1));

      // The server's answer lands in place — a row added elsewhere arrives
      // (a NEW list: the app's derived lists are identity-cached).
      h.repo.items = [p(1, 'Amul Milk'), p(2, 'Basmati Rice')];
      gate.complete();
      await refreshing;
      final state = h.container.read(productsControllerProvider);
      expect(state.status, ProductsStatus.ready);
      expect(state.items.map((i) => i.name), ['Amul Milk', 'Basmati Rice']);
    });

    test('a failed refresh keeps the rows and latches nothing', () async {
      final h = makeHarness([p(1, 'Amul Milk')]);
      final controller = h.container.read(productsControllerProvider.notifier);
      await controller.load();

      h.repo.failOverview = true;
      await controller.refresh();
      final state = h.container.read(productsControllerProvider);
      expect(state.status, ProductsStatus.ready);
      expect(state.items, hasLength(1));
      expect(state.message, isNull);

      // The next pull simply tries again.
      h.repo.failOverview = false;
      await controller.refresh();
      expect(h.repo.overviewCalls, 3);
    });
  });

  group('pull-to-refresh — the gesture', () {
    testWidgets('a two-row product list still pulls, and never blanks',
        (tester) async {
      final items = [p(1, 'Amul Milk'), p(2, 'Basmati Rice')];
      final h = makeHarness(items);
      await pumpScreen(tester, h.container, const ProductsScreen());
      expect(h.repo.overviewCalls, 1);

      final gate = Completer<void>();
      h.repo.overviewGate = gate;
      await pullToRefresh(tester);

      // The gesture fired ONE refetch — on a list too short to scroll, which
      // is the AlwaysScrollableScrollPhysics contract.
      expect(h.repo.overviewCalls, 2);
      // ...and the rows never left the screen (the loud path would have
      // replaced them with a spinner).
      expect(find.text('Amul Milk'), findsOneWidget);

      // The refreshed payload lands IN PLACE — a name edited on another
      // device shows up without a reload (a NEW list: the derived rows are
      // identity-cached, and the renamed first row is the one guaranteed to
      // be built).
      h.repo.items = [p(1, 'Amul Milk 2L'), p(2, 'Basmati Rice')];
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Amul Milk 2L'), findsOneWidget);
    });

    testWidgets('an inventory scope list pulls its own slice', (tester) async {
      final items = [p(1, 'Amul Milk')];
      final h = makeHarness(items);
      await pumpScreen(
        tester,
        h.container,
        const InventoryScopeScreen(scope: InventoryScope.all),
      );
      expect(h.repo.overviewCalls, 1);

      await pullToRefresh(tester);
      expect(h.repo.overviewCalls, 2);
      expect(find.text('Amul Milk'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('an EMPTY offer bucket still pulls', (tester) async {
      final repo = FakeOffersRepo();
      final container = ProviderContainer(overrides: [
        offersRepositoryProvider.overrideWithValue(repo),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        selectedShopProvider
            .overrideWith(() => SelectedShopOverride(ownerShop())),
      ]);
      addTearDown(container.dispose);
      await pumpScreen(tester, container, const OffersScreen());
      expect(repo.fetchCalls, 1);

      // Zero rows — the empty state IS the list, so the pull still fires (a
      // fresh offer created on another device can arrive).
      await pullToRefresh(tester);
      expect(repo.fetchCalls, 2);
    });
  });

  group('after a mutation the catalog is NOT reloaded', () {
    test('setAvailability / adjustStock patch the affected rows in place',
        () async {
      final h = makeHarness([p(1, 'Amul Milk'), p(2, 'Basmati Rice')]);
      final controller = h.container.read(productsControllerProvider.notifier);
      await controller.load();
      expect(h.repo.overviewCalls, 1);

      await controller.setAvailability(1, false);
      final outcome = await controller.adjustStock(productId: 2, delta: 5);
      expect(outcome.ok, isTrue);

      final state = h.container.read(productsControllerProvider);
      // The catalog was NOT refetched: the affected rows were swapped for the
      // server's own values and the rest of the list stayed put.
      expect(h.repo.overviewCalls, 1);
      expect(h.repo.adjustStockCalls, 1);
      expect(h.repo.lastAdjustedId, 2);
      expect(state.items, hasLength(2));
      // The server's post-update numbers, not the client's arithmetic.
      expect(state.items.firstWhere((i) => i.id == 2).quantity, 10);
    });
  });
}
