import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/api_client.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/data/inventory_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/product_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/controllers/products_controller.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/widgets/product_details_sheet.dart';

import 'fakes.dart';

/// DEACTIVATE / REACTIVATE — the one destructive write the products module
/// offers (spec §74 destructive actions, §75 delete-vs-deactivate).
///
/// The backend approves exactly one semantic: `PATCH
/// /shops/{id}/products/{pid}` with `{"status": ...}`. There is no delete, and
/// there must not be one here — `ShopProduct` carries a `SoftDeleteMixin`, so
/// deactivating withdraws a listing while its price/inventory history stays
/// queryable for reports.
///
/// The tests below pin the three rules that make that honest:
///   1. the shopkeeper is asked first, and cancelling really writes nothing;
///   2. a refused write carries the backend's own wording and is NEVER
///      announced as a success;
///   3. `status` and `is_active` are reconciled in ONE place, so a deactivated
///      listing cannot render as "Active" while the Discontinued slice calls it
///      discontinued.
void main() {
  const offlineMessage =
      "You're offline — changes can't be saved until you're back online.";

  const deactivateKey = Key('product-deactivate');
  const reactivateKey = Key('product-reactivate');
  const confirmKey = Key('confirm_deactivate_product');

  ShopProductItem product({
    int id = 42,
    String name = 'Amul Milk 500ml',
    String status = 'ACTIVE',
    bool isActive = true,
    bool isAvailable = true,
    String stockStatus = 'IN_STOCK',
  }) =>
      ShopProductItem(
        id: id,
        name: name,
        status: status,
        price: 30,
        isActive: isActive,
        isAvailable: isAvailable,
        quantity: 12,
        stockStatus: stockStatus,
      );

  /// The row the REAL backend returns after `{"status": "DISCONTINUED"}`:
  /// the status changes while `is_active` keeps its previous value. Modelling
  /// that faithfully is the whole point — a fake that flipped both would hide
  /// the very bug these tests exist to catch.
  ShopProductItem discontinuedResponse(int id, String name) =>
      product(id: id, name: name, status: 'DISCONTINUED', isActive: true);

  ({ProviderContainer container, FakeProductRepo repo}) makeHarness({
    List<ShopProductItem> items = const [],
    ShopProductItem? Function(int, Map<String, dynamic>)? onUpdate,
  }) {
    final repo = FakeProductRepo(items: items, onUpdate: onUpdate);
    final container = ProviderContainer(overrides: [
      productRepositoryProvider.overrideWithValue(repo),
      inventoryRepositoryProvider.overrideWithValue(repo),
      tokenStoreProvider.overrideWithValue(
          InMemoryTokenStore(accessToken: 'test-access-token')),
      selectedShopProvider
          .overrideWith(() => SelectedShopOverride(ownerShop(id: 10))),
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
      child:
          MaterialApp(home: Scaffold(body: ProductDetailsSheet(item: item))),
    ));
    await tester.pumpAndSettle();
  }
// ── The reconciliation, in isolation ──────────────────────────────────────
  group('ListingStateView — two server fields, one rendered state', () {
    test('a discontinued status outranks a still-true is_active', () {
      // The exact combination the server produces after a deactivate PATCH.
      final item = product(status: 'DISCONTINUED', isActive: true);

      expect(item.listingState, ListingStateView.discontinued);
      expect(item.listingState.isDiscontinued, isTrue);
      expect(item.listingState.isActive, isFalse);
      expect(item.isWithdrawn, isTrue);
    });

    test('is_active alone still reads as Inactive, not as a stock state', () {
      final item = product(status: 'ACTIVE', isActive: false);

      expect(item.listingState, ListingStateView.inactive);
      expect(item.isWithdrawn, isTrue);
      // Lifecycle is not stock: a switched-off listing with stock left on the
      // shelf must not be counted as "In stock".
      expect(item.stockState.isInStock, isTrue);
    });

    test('a future server status degrades to a label instead of throwing', () {
      // §126 — the client never re-declares the backend's enum.
      final view = ListingStateView.of('LIQUIDATION_PENDING');

      expect(view.value, 'LIQUIDATION_PENDING');
      // Same humaniser the stock-state view uses, so an unknown lifecycle
      // status reads exactly like an unknown stock status.
      expect(view.label, 'Liquidation Pending');
    });

    test('copyWith carries the lifecycle instead of hard-copying it', () {
      final dead = product(status: 'DISCONTINUED', isActive: true);

      // An unrelated edit (the stock path calls copyWith) must not resurrect a
      // withdrawn listing as an active one.
      final edited = dead.copyWith(quantity: 3);

      expect(edited.status, 'DISCONTINUED');
      expect(edited.listingState.isDiscontinued, isTrue);
      expect(edited.quantity, 3);
    });
  });

  // ── The write ─────────────────────────────────────────────────────────────
  group('ProductsController.setListingStatus', () {
    test('sends the backend status and swaps the server row in place', () async {
      final harness = makeHarness(
        items: [product()],
        onUpdate: (id, fields) => discontinuedResponse(id, 'Amul Milk 500ml'),
      );
      await harness.container.read(productsControllerProvider.notifier).load();

      final ok = await harness.container
          .read(productsControllerProvider.notifier)
          .setListingStatus(42, ListingStateView.discontinued);

      expect(ok, isTrue);
      expect(harness.repo.lastShopId, 10);
      expect(harness.repo.lastUpdatedId, 42);
      expect(harness.repo.lastUpdateFields!['status'], 'DISCONTINUED');
      // Single source of truth: the server's row REPLACED the old one, it was
      // not appended beside it.
      final state = harness.container.read(productsControllerProvider);
      expect(state.items, hasLength(1));
      expect(state.itemById(42)!.status, 'DISCONTINUED');
      expect(state.itemById(42)!.isDiscontinued, isTrue);
    });

    test('never bundles the availability switch into the lifecycle write',
        () async {
      // Deactivating is a lifecycle decision behind a confirmation; silently
      // flipping customer visibility alongside it would make one reversible
      // action perform two.
      final harness = makeHarness(
        items: [product()],
        onUpdate: (id, fields) => discontinuedResponse(id, 'Amul Milk 500ml'),
      );
      await harness.container.read(productsControllerProvider.notifier).load();

      await harness.container
          .read(productsControllerProvider.notifier)
          .setListingStatus(42, ListingStateView.discontinued);

      expect(harness.repo.lastUpdateFields!.containsKey('is_available'), isFalse);
    });

    test('a refused write keeps the catalog and carries the reason', () async {
      final harness = makeHarness(
        items: [product()],
        onUpdate: (_, _) => throw const ApiException(message: offlineMessage),
      );
      await harness.container.read(productsControllerProvider.notifier).load();

      final ok = await harness.container
          .read(productsControllerProvider.notifier)
          .setListingStatus(42, ListingStateView.discontinued);

      expect(ok, isFalse);
      final state = harness.container.read(productsControllerProvider);
      // The row is untouched — a failed deactivation must not leave the shop
      // looking at a listing that is half-changed.
      expect(state.itemById(42)!.status, 'ACTIVE');
      expect(state.message, offlineMessage);
    });
  });

  // ── §74: confirm before a destructive action ──────────────────────────────
  group('ProductDetailsSheet — deactivating a listing', () {
    testWidgets('an active listing offers Deactivate and asks before writing',
        (tester) async {
      final harness = makeHarness(
        items: [product()],
        onUpdate: (id, fields) => discontinuedResponse(id, 'Amul Milk 500ml'),
      );
      await harness.container.read(productsControllerProvider.notifier).load();
      await pumpSheet(tester, harness.container, product());

      expect(find.byKey(deactivateKey), findsOneWidget);
      expect(find.byKey(reactivateKey), findsNothing);

      await tester.tap(find.byKey(deactivateKey));
      await tester.pumpAndSettle();

      // The confirmation names the product and explains the impact.
      expect(find.text('Deactivate this product?'), findsOneWidget);
      expect(find.textContaining('Amul Milk 500ml'), findsWidgets);
      expect(find.textContaining('Nothing is deleted'), findsOneWidget);

      // Nothing has been written merely by ASKING.
      expect(harness.repo.lastUpdateFields, isNull);
    });

    testWidgets('cancelling writes nothing at all', (tester) async {
      final harness = makeHarness(
        items: [product()],
        onUpdate: (id, fields) => discontinuedResponse(id, 'Amul Milk 500ml'),
      );
      await harness.container.read(productsControllerProvider.notifier).load();
      await pumpSheet(tester, harness.container, product());

      await tester.tap(find.byKey(deactivateKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(harness.repo.lastUpdateFields, isNull);
      expect(
        harness.container.read(productsControllerProvider).itemById(42)!.status,
        'ACTIVE',
      );
      // The sheet is untouched and still offering the action.
      expect(find.byKey(deactivateKey), findsOneWidget);
    });

    testWidgets('confirming deactivates and reports the listing as Discontinued',
        (tester) async {
      final harness = makeHarness(
        items: [product()],
        onUpdate: (id, fields) => discontinuedResponse(id, 'Amul Milk 500ml'),
      );
      await harness.container.read(productsControllerProvider.notifier).load();
      await pumpSheet(tester, harness.container, product());

      await tester.tap(find.byKey(deactivateKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(confirmKey));
      await tester.pumpAndSettle();

      expect(harness.repo.lastUpdateFields!['status'], 'DISCONTINUED');
      expect(find.text('Product deactivated'), findsOneWidget);

      // The server left `is_active` true, yet the screen must not read "Active"
      // — this is the regression that motivated reconciling the two fields.
      expect(find.textContaining('Discontinued - hidden from customers'),
          findsOneWidget);
      expect(
        find.text('Published - customers can find this listing in your shop.'),
        findsNothing,
      );

      // The action flips to its opposite, and only one of them is ever offered.
      expect(find.byKey(reactivateKey), findsOneWidget);
      expect(find.byKey(deactivateKey), findsNothing);
    });

    testWidgets('a refused deactivation is never announced as saved',
        (tester) async {
      final harness = makeHarness(
        items: [product()],
        onUpdate: (_, _) => throw const ApiException(message: offlineMessage),
      );
      await harness.container.read(productsControllerProvider.notifier).load();
      await pumpSheet(tester, harness.container, product());

      await tester.tap(find.byKey(deactivateKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(confirmKey));
      await tester.pumpAndSettle();

      // The backend's own wording reaches the shopkeeper verbatim.
      expect(find.text(offlineMessage), findsOneWidget);
      expect(find.text('Product deactivated'), findsNothing);

      // And the listing is still live, so the action is still on offer — the
      // sheet never claimed a change that did not land.
      expect(find.byKey(deactivateKey), findsOneWidget);
      expect(find.byKey(reactivateKey), findsNothing);
    });

    testWidgets('reactivate needs no confirmation — it is not destructive',
        (tester) async {
      final harness = makeHarness(
        items: [product(status: 'DISCONTINUED')],
        onUpdate: (id, _) => product(id: id, status: 'ACTIVE'),
      );
      await harness.container.read(productsControllerProvider.notifier).load();
      await pumpSheet(tester, harness.container, product(status: 'DISCONTINUED'));

      expect(find.byKey(reactivateKey), findsOneWidget);

      await tester.tap(find.byKey(reactivateKey));
      await tester.pumpAndSettle();

      // No dialog: asking again would only train the shopkeeper to tap
      // through the confirmation that matters.
      expect(find.text('Deactivate this product?'), findsNothing);
      expect(harness.repo.lastUpdateFields!['status'], 'ACTIVE');
      expect(find.text('Product reactivated'), findsOneWidget);
      expect(find.byKey(deactivateKey), findsOneWidget);
    });
  });
}