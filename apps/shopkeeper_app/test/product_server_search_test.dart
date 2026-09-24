// Server search — the products list's stale-catalog recovery path.
//
// Local search filters the LOADED catalog on every settled query (debounced by
// DebouncedSearchField, memoized by ProductQueryCache). When that catalog
// cannot answer a settled query — zero local matches — the screen asks the
// backend ONCE (`GET /inventory?view=list&search=`) for rows the payload may
// be missing entirely (created on another device, or after the last load).
// The backend matches name/sku, a subset of the local fields, so a server hit
// can only ADD rows. These tests pin the contract:
//   * a locally-answered query never reaches the server;
//   * an unanswered settled query fires EXACTLY ONE call (debounce +
//     per-query dedupe = no API call per keystroke);
//   * server rows merge into the catalog and the counter counts them;
//   * a failed round-trip keeps the local no-result state (fail-soft);
//   * blank / single-character drafts never reach the server;
//   * an answer that lands after a reload is dropped (no stale merge).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/data/inventory_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/product_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/controllers/products_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/screens/products_screen.dart';

import 'fakes.dart';

ShopProductItem p({
  required int id,
  required String name,
  double price = 10,
  String? sku,
  String? brand,
  int quantity = 5,
  String stockStatus = 'IN_STOCK',
}) =>
    ShopProductItem(
      id: id,
      name: name,
      status: 'ACTIVE',
      price: price,
      sku: sku,
      brand: brand,
      isActive: true,
      isAvailable: true,
      quantity: quantity,
      stockStatus: stockStatus,
    );

void main() {
  final milk = p(id: 1, name: 'Amul Milk', price: 27, brand: 'Amul');

  ({ProviderContainer container, FakeProductRepo repo}) makeHarness({
    List<ShopProductItem> items = const [],
    List<ShopProductItem> serverOnly = const [],
    Future<List<ShopProductItem>> Function(String query)? onSearch,
  }) {
    final repo = FakeProductRepo(
      items: items,
      serverOnly: serverOnly,
      onSearch: onSearch,
    );
    final container = ProviderContainer(overrides: [
      productRepositoryProvider.overrideWithValue(repo),
      inventoryRepositoryProvider.overrideWithValue(repo),
      tokenStoreProvider.overrideWithValue(
          InMemoryTokenStore(accessToken: 'test-access-token')),
      selectedShopProvider
          .overrideWith(() => SelectedShopOverride(ownerShop())),
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

  /// Types [text] and waits out the field's 300ms debounce, then settles the
  /// frames/microtasks the server-search path may have scheduled.
  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(searchBox(), text);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  group('products server search', () {
    testWidgets('a query the local catalog matches never reaches the server',
        (tester) async {
      final harness = makeHarness(items: [milk]);
      await pumpList(tester, harness.container);

      await search(tester, 'amul');

      expect(find.text('Amul Milk'), findsOneWidget);
      expect(find.text('1 of 1 products'), findsOneWidget);
      expect(harness.repo.searchCalls, 0,
          reason: 'local search answered it — no round-trip needed');
    });

    testWidgets(
        'an unanswered settled query fires ONE server search and shows the '
        'row the payload was missing', (tester) async {
      final harness = makeHarness(
        items: [milk],
        // The stale-catalog fixture: a listing the loaded payload lacks.
        serverOnly: [p(id: 9, name: 'Basmati Rice', price: 120)],
      );
      await pumpList(tester, harness.container);

      await search(tester, 'basmati');

      expect(harness.repo.searchCalls, 1);
      expect(harness.repo.lastSearchQuery, 'basmati');
      expect(find.text('Basmati Rice'), findsOneWidget);
      expect(find.text('Amul Milk'), findsNothing);
      // The merged row IS a catalog row: the counter counts it.
      expect(find.text('1 of 2 products'), findsOneWidget);
    });

    testWidgets('keystrokes coalesce through the debounce into one server call',
        (tester) async {
      final harness = makeHarness(
        items: [milk],
        serverOnly: [p(id: 9, name: 'Basmati Rice')],
      );
      await pumpList(tester, harness.container);

      for (final text in ['b', 'ba', 'bas', 'basm', 'basma', 'basmati']) {
        await tester.enterText(searchBox(), text);
        await tester.pump(const Duration(milliseconds: 50));
        expect(harness.repo.searchCalls, 0,
            reason: 'no call while still typing "$text"');
      }

      // The last keystroke's debounce delivers the settled query; exactly one
      // round-trip follows, no matter how many glyphs preceded it.
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(harness.repo.searchCalls, 1);
      expect(harness.repo.lastSearchQuery, 'basmati');
      expect(find.text('Basmati Rice'), findsOneWidget);
    });

    testWidgets('a failed server search keeps the local no-result state',
        (tester) async {
      final harness = makeHarness(
        items: [milk],
        onSearch: (query) async => throw Exception('offline'),
      );
      await pumpList(tester, harness.container);

      await search(tester, 'zz');

      expect(harness.repo.searchCalls, 1);
      // Fail-soft: the honest local result stays, nothing crashes, and the
      // clear affordance still works.
      expect(find.text('No products match "zz".'), findsOneWidget);
      expect(find.text('0 of 1 products'), findsOneWidget);

      await tester.tap(find.text('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('Amul Milk'), findsOneWidget);
    });

    testWidgets('blank and single-character drafts never reach the server',
        (tester) async {
      final harness = makeHarness(items: [milk]);
      await pumpList(tester, harness.container);

      await search(tester, 'q');
      expect(harness.repo.searchCalls, 0,
          reason: 'a single letter is a draft, not a server query');

      await search(tester, '');
      expect(harness.repo.searchCalls, 0);
      expect(find.text('Amul Milk'), findsOneWidget);
    });

    testWidgets('a server answer that lands after a reload never merges',
        (tester) async {
      var invocations = 0;
      final gate = Completer<List<ShopProductItem>>();
      final harness = makeHarness(
        items: [milk],
        onSearch: (query) {
          invocations++;
          // The FIRST call parks; later calls answer "nothing". The late row
          // can therefore only appear if the parked first answer leaked
          // through the reload's generation guard.
          return invocations == 1
              ? gate.future
              : Future.value(const <ShopProductItem>[]);
        },
      );
      await pumpList(tester, harness.container);

      await tester.enterText(searchBox(), 'zz');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(harness.repo.searchCalls, 1,
          reason: 'the first search is parked on the gate');

      // Reload while that answer is still in flight (pull-to-refresh, shop
      // re-entry): the new generation must reject the old answer.
      await harness.container
          .read(productsControllerProvider.notifier)
          .load();
      await tester.pumpAndSettle();

      gate.complete([p(id: 9, name: 'Late Row')]);
      await tester.pumpAndSettle();

      expect(find.text('Late Row'), findsNothing,
          reason: 'a pre-reload answer must not merge into the fresh catalog');
      // The query SURVIVES a reload by design (list view state is separate
      // from the catalog data), so the local no-result still stands...
      expect(find.text('No products match "zz".'), findsOneWidget);

      // ...and clearing it reveals the refreshed catalog untouched: one row,
      // not the dropped late answer's two.
      await tester.tap(find.text('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('Amul Milk'), findsOneWidget);
      expect(find.text('1 of 1 products'), findsOneWidget);
      expect(find.text('Late Row'), findsNothing);
    });
  });
}