import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_app/core/network/api_client.dart';
import 'package:hyperlocal_app/core/storage/local_storage_driver.dart';
import 'package:hyperlocal_app/features/saved_and_history/data/api_saved_and_history_repository.dart';
import 'package:hyperlocal_app/features/saved_and_history/data/local_saved_and_history_repository.dart';
import 'package:hyperlocal_app/features/saved_and_history/domain/models/storage_models.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'api_saved_and_history_repository_test.mocks.dart';

@GenerateMocks([ApiClient])
void main() {
  late MockApiClient api;
  late InMemoryStorageDriver driver;
  late LocalSavedAndHistoryRepository local;
  late ApiSavedAndHistoryRepository repo;

  setUp(() {
    api = MockApiClient();
    driver = InMemoryStorageDriver();
    local = LocalSavedAndHistoryRepository(driver);
    repo = ApiSavedAndHistoryRepository(api, local);

    when(api.post(any)).thenAnswer((_) async => null);
    when(api.delete(any)).thenAnswer((_) async => null);
    when(api.get(any)).thenAnswer((_) async => null);
  });

  SavedProductItem product(String id, {bool synced = false}) =>
      SavedProductItem(
        productId: id,
        name: 'Product $id',
        brand: 'Brand',
        lowestPrice: 999,
        imageUrl: '',
        savedAt: DateTime.now(),
        isSynced: synced,
      );

  SavedShopItem shop(String id, {bool synced = false}) => SavedShopItem(
    shopId: id,
    name: 'Shop $id',
    address: 'Address',
    imageUrl: '',
    rating: 4,
    savedAt: DateTime.now(),
    isSynced: synced,
  );

  group('local-only state stays on the device', () {
    test('recent searches are delegated to the local store', () async {
      await repo.addRecentSearch('headphones');
      await repo.addRecentSearch('earbuds');

      expect((await repo.getRecentSearches()).length, 2);
      verifyZeroInteractions(api);

      await repo.removeRecentSearch('headphones');
      expect((await repo.getRecentSearches()).first.query, 'earbuds');

      await repo.clearRecentSearches();
      expect(await repo.getRecentSearches(), isEmpty);
    });

    test('recently viewed products and shops never hit the API', () async {
      await repo.addRecentlyViewed(
        RecentlyViewedItem(
          productId: 'p1',
          name: 'P1',
          imageUrl: '',
          price: 10,
          viewedAt: DateTime.now(),
        ),
      );
      await repo.addRecentlyViewedShop(
        RecentlyViewedShopItem(
          shopId: 's1',
          name: 'S1',
          address: '',
          imageUrl: '',
          rating: 4,
          viewedAt: DateTime.now(),
        ),
      );

      verifyZeroInteractions(api);
      expect((await repo.getRecentlyViewed()).first.productId, 'p1');
      expect((await repo.getRecentlyViewedShops()).first.shopId, 's1');
    });
  });

  group('saved items are backend-synced', () {
    test(
      'saveProduct posts to the backend and mirrors locally as synced',
      () async {
        await repo.saveProduct(product('p9'));

        verify(api.post('/saved-products/p9')).called(1);
        final mirrored = await local.getSavedProducts();
        expect(mirrored.first.productId, 'p9');
        expect(mirrored.first.isSynced, isTrue);
      },
    );

    test('removeProduct deletes from backend and local mirror', () async {
      await repo.saveProduct(product('p9'));
      await repo.removeProduct('p9');

      verify(api.delete('/saved-products/p9')).called(1);
      expect(await local.getSavedProducts(), isEmpty);
    });

    test('getSavedProducts maps the API envelope', () async {
      when(api.get('/saved-products')).thenAnswer(
        (_) async => {
          'items': [
            {
              'product_id': '42',
              'name': 'Keyboard',
              'brand': 'KeyBrand',
              'lowest_price': 1499,
              'image_url': 'img.png',
              'saved_at': '2026-01-02T03:04:05.000',
            },
          ],
        },
      );

      final items = await repo.getSavedProducts();
      expect(items.single.productId, '42');
      expect(items.single.name, 'Keyboard');
      expect(items.single.isSynced, isTrue);
    });

    test('getSavedProducts falls back to the local queue on failure', () async {
      await local.saveProduct(product('offline'));
      when(api.get('/saved-products')).thenThrow(Exception('offline'));

      final items = await repo.getSavedProducts();
      expect(items.single.productId, 'offline');
    });
  });

  group('login sync of pending saves', () {
    test('pushes unsynced favorites then clears the local queue', () async {
      await local.saveProduct(product('guest-p1'));
      await local.saveProduct(product('already-synced', synced: true));
      await local.saveShop(shop('guest-s1'));

      await repo.syncPendingSaves();

      // Only unsynced entries are pushed.
      verify(api.post('/saved-products/guest-p1')).called(1);
      verifyNever(api.post('/saved-products/already-synced'));
      verify(api.post('/saved-shops/guest-s1')).called(1);

      // Queue is cleared after successful migration — nothing sensitive
      // lingers on the device.
      expect(await local.getSavedProducts(), isEmpty);
      expect(await local.getSavedShops(), isEmpty);
    });

    test(
      'keeps pending items queued when the backend is unreachable',
      () async {
        await local.saveProduct(product('guest-p1'));
        when(api.post('/saved-products/guest-p1'))
            .thenThrow(Exception('network down'));

        await repo.syncPendingSaves();

        final stillPending = await local.getSavedProducts();
        expect(stillPending.single.productId, 'guest-p1');
        expect(stillPending.single.isSynced, isFalse);
      },
    );
  });
}
