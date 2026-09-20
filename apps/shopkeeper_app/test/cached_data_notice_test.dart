import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_shopkeeper_app/core/network/token_store.dart';
import 'package:hyperlocal_shopkeeper_app/core/ui/cached_data_notice.dart';
import 'package:hyperlocal_shopkeeper_app/features/auth/presentation/controllers/selected_shop.dart';
import 'package:hyperlocal_shopkeeper_app/features/inventory/data/inventory_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/data/product_repository.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/domain/product_models.dart';
import 'package:hyperlocal_shopkeeper_app/features/products/presentation/screens/products_screen.dart';

import 'fakes.dart';

/// A list rebuilt from the device's offline snapshot must SAY SO.
///
/// Offline read-only access is only safe if the shopkeeper knows the quantity
/// or price in front of them is the last synced copy: acting on a stale number
/// that looks live is worse than seeing no number at all.
class _SnapshotRepo extends FakeProductRepo {
  _SnapshotRepo({required this.cached, super.items});

  /// When true, the overview comes back flagged exactly as the real
  /// repository flags it on the `ProductsSnapshotStore` fallback.
  final bool cached;

  @override
  Future<InventoryOverview> fetchInventoryOverview(
    int shopId,
    String token,
  ) async {
    final live = await super.fetchInventoryOverview(shopId, token);
    if (!cached) return live;
    return InventoryOverview(
      items: live.items,
      summary: live.summary,
      fromCache: true,
    );
  }
}

void main() {
  const defaultCopy =
      'Showing your last synced list — reconnect to refresh it.';

  ShopProductItem milk() => const ShopProductItem(
        id: 1,
        name: 'Amul Milk 1L',
        status: 'ACTIVE',
        price: 27,
        isActive: true,
        isAvailable: true,
        quantity: 5,
        stockStatus: 'LOW_STOCK',
      );

  group('CachedDataNotice', () {
    testWidgets('states that the data is the last synced copy',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: CachedDataNotice()),
      ));

      expect(find.byKey(const Key('cached-data-notice')), findsOneWidget);
      expect(find.text(defaultCopy), findsOneWidget);
    });

    testWidgets('a feature can name its own data', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: CachedDataNotice(message: 'Showing your last synced prices.'),
        ),
      ));

      expect(find.text('Showing your last synced prices.'), findsOneWidget);
      expect(find.text(defaultCopy), findsNothing);
    });
  });

  group('ProductsScreen provenance', () {
    Future<void> pump(WidgetTester tester, {required bool cached}) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(overrides: [
        productRepositoryProvider
            .overrideWithValue(_SnapshotRepo(cached: cached, items: [milk()])),
        inventoryRepositoryProvider
            .overrideWithValue(_SnapshotRepo(cached: cached, items: [milk()])),
        tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(accessToken: 'test-access-token')),
        selectedShopProvider
            .overrideWith(() => SelectedShopOverride(ownerShop())),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProductsScreen()),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('a cached list is labelled', (tester) async {
      await pump(tester, cached: true);

      expect(find.byKey(const Key('cached-data-notice')), findsOneWidget);
      expect(find.text(defaultCopy), findsOneWidget);
      // The rows still render — labelled, not hidden.
      expect(find.text('Amul Milk 1L'), findsOneWidget);
    });

    testWidgets('a live list carries no such label', (tester) async {
      await pump(tester, cached: false);

      expect(find.byKey(const Key('cached-data-notice')), findsNothing);
      expect(find.text('Amul Milk 1L'), findsOneWidget);
    });
  });
}
