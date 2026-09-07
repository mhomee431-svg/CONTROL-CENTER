import 'package:flutter_test/flutter_test.dart';
import 'package:hyperlocal_customer_app/core/storage/local_storage_driver.dart';
import 'package:hyperlocal_customer_app/features/saved_and_history/data/local_saved_and_history_repository.dart';
import 'package:hyperlocal_customer_app/features/saved_and_history/domain/models/storage_models.dart';

void main() {
  late InMemoryStorageDriver driver;
  late LocalSavedAndHistoryRepository repo;

  setUp(() {
    driver = InMemoryStorageDriver();
    repo = LocalSavedAndHistoryRepository(driver);
  });

  group('Saved Products Persistence', () {
    test('saveProduct adds item and retrieves it correctly', () async {
      final product = SavedProductItem(
        productId: 'p100',
        name: 'Wireless Earbuds',
        brand: 'SoundBrand',
        lowestPrice: 2999,
        imageUrl: 'https://via.placeholder.com/150',
        savedAt: DateTime.now(),
      );

      await repo.saveProduct(product);
      final savedList = await repo.getSavedProducts();

      expect(savedList.length, equals(1));
      expect(savedList.first.productId, equals('p100'));
      expect(savedList.first.isSynced, isFalse);
    });

    test('removeProduct removes item from local storage driver', () async {
      final product = SavedProductItem(
        productId: 'p100',
        name: 'Wireless Earbuds',
        brand: 'SoundBrand',
        lowestPrice: 2999,
        imageUrl: 'https://via.placeholder.com/150',
        savedAt: DateTime.now(),
      );

      await repo.saveProduct(product);
      await repo.removeProduct('p100');
      final savedList = await repo.getSavedProducts();

      expect(savedList, isEmpty);
    });
  });

  group('Saved Shops Persistence', () {
    test('saveShop adds shop and retrieves it correctly', () async {
      final shop = SavedShopItem(
        shopId: 's100',
        name: 'Gupta Mobile & Electronics',
        address: 'MG Road, Delhi',
        imageUrl: 'https://via.placeholder.com/150',
        rating: 4.5,
        savedAt: DateTime.now(),
      );

      await repo.saveShop(shop);
      final savedShops = await repo.getSavedShops();

      expect(savedShops.length, equals(1));
      expect(savedShops.first.shopId, equals('s100'));
    });

    test('removeShop removes shop from local storage driver', () async {
      final shop = SavedShopItem(
        shopId: 's100',
        name: 'Gupta Mobile & Electronics',
        address: 'MG Road, Delhi',
        imageUrl: 'https://via.placeholder.com/150',
        rating: 4.5,
        savedAt: DateTime.now(),
      );

      await repo.saveShop(shop);
      await repo.removeShop('s100');
      final savedShops = await repo.getSavedShops();

      expect(savedShops, isEmpty);
    });
  });

  group('Recent Searches & History Limits', () {
    test('addRecentSearch dedupes and caps history to maximum 10 items', () async {
      for (int i = 0; i < 15; i++) {
        await repo.addRecentSearch('Search Query $i');
      }

      final searches = await repo.getRecentSearches();
      expect(searches.length, equals(10));
      expect(searches.first.query, equals('Search Query 14'));
    });

    test('addRecentSearch ignores empty/whitespace queries', () async {
      await repo.addRecentSearch('   ');
      final searches = await repo.getRecentSearches();

      expect(searches, isEmpty);
    });

    test('addRecentSearch dedupes case-insensitively', () async {
      await repo.addRecentSearch('Headphones');
      await repo.addRecentSearch('headphones');

      final searches = await repo.getRecentSearches();
      expect(searches.length, equals(1));
      expect(searches.first.query, equals('headphones'));
    });

    test('clearRecentSearches empties search history', () async {
      await repo.addRecentSearch('Headphones');
      await repo.clearRecentSearches();
      final searches = await repo.getRecentSearches();

      expect(searches, isEmpty);
    });

    test('removeRecentSearch removes a single query', () async {
      await repo.addRecentSearch('Headphones');
      await repo.addRecentSearch('Earbuds');
      await repo.removeRecentSearch('Headphones');

      final searches = await repo.getRecentSearches();
      expect(searches.length, equals(1));
      expect(searches.first.query, equals('Earbuds'));
    });
  });

  group('Recently Viewed & History Limits', () {
    RecentlyViewedItem viewedItem(String id) => RecentlyViewedItem(
          productId: id,
          name: 'Product $id',
          imageUrl: 'https://via.placeholder.com/150',
          price: 1000,
          viewedAt: DateTime.now(),
        );

    test('addRecentlyViewed caps history to maximum 20 items', () async {
      for (int i = 0; i < 25; i++) {
        await repo.addRecentlyViewed(
          RecentlyViewedItem(
            productId: 'p$i',
            name: 'Product $i',
            imageUrl: 'https://via.placeholder.com/150',
            price: 1000.0 + i,
            viewedAt: DateTime.now(),
          ),
        );
      }

      final viewed = await repo.getRecentlyViewed();
      expect(viewed.length, equals(20));
      expect(viewed.first.productId, equals('p24'));
    });

    test('re-viewing bumps the product to the front without duplicating',
        () async {
      await repo.addRecentlyViewed(viewedItem('p1'));
      await repo.addRecentlyViewed(viewedItem('p2'));
      await repo.addRecentlyViewed(viewedItem('p1'));

      final viewed = await repo.getRecentlyViewed();
      expect(viewed.length, equals(2));
      expect(viewed.first.productId, equals('p1'));
    });

    test('removeRecentlyViewed removes a single viewed product', () async {
      await repo.addRecentlyViewed(viewedItem('p1'));
      await repo.addRecentlyViewed(viewedItem('p2'));
      await repo.removeRecentlyViewed('p1');

      final viewed = await repo.getRecentlyViewed();
      expect(viewed.length, equals(1));
      expect(viewed.first.productId, equals('p2'));
    });

    test('clearRecentlyViewed empties view history', () async {
      await repo.addRecentlyViewed(
        RecentlyViewedItem(
          productId: 'p1',
          name: 'Product 1',
          imageUrl: 'https://via.placeholder.com/150',
          price: 1000,
          viewedAt: DateTime.now(),
        ),
      );
      await repo.clearRecentlyViewed();
      final viewed = await repo.getRecentlyViewed();

      expect(viewed, isEmpty);
    });
  });

  group('Recently Viewed Shops', () {
    RecentlyViewedShopItem viewedShop(String id) => RecentlyViewedShopItem(
          shopId: id,
          name: 'Shop $id',
          address: 'MG Road, Delhi',
          imageUrl: 'https://via.placeholder.com/150',
          rating: 4.5,
          viewedAt: DateTime.now(),
        );

    test('addRecentlyViewedShop records a shop visit', () async {
      await repo.addRecentlyViewedShop(viewedShop('s1'));
      final viewed = await repo.getRecentlyViewedShops();

      expect(viewed.length, equals(1));
      expect(viewed.first.shopId, equals('s1'));
    });

    test('re-visiting a shop does not duplicate it', () async {
      await repo.addRecentlyViewedShop(viewedShop('s1'));
      await repo.addRecentlyViewedShop(viewedShop('s2'));
      await repo.addRecentlyViewedShop(viewedShop('s1'));

      final viewed = await repo.getRecentlyViewedShops();
      expect(viewed.length, equals(2));
      expect(viewed.first.shopId, equals('s1'));
    });

    test('addRecentlyViewedShop caps history to maximum 20 shops', () async {
      for (int i = 0; i < 25; i++) {
        await repo.addRecentlyViewedShop(RecentlyViewedShopItem(
          shopId: 's$i',
          name: 'Shop $i',
          address: 'Address $i',
          imageUrl: 'https://via.placeholder.com/150',
          rating: 4,
          viewedAt: DateTime.now(),
        ));
      }

      final viewed = await repo.getRecentlyViewedShops();
      expect(viewed.length, equals(20));
      expect(viewed.first.shopId, equals('s24'));
    });

    test('removeRecentlyViewedShop removes one shop', () async {
      await repo.addRecentlyViewedShop(viewedShop('s1'));
      await repo.addRecentlyViewedShop(viewedShop('s2'));
      await repo.removeRecentlyViewedShop('s1');

      final viewed = await repo.getRecentlyViewedShops();
      expect(viewed.length, equals(1));
      expect(viewed.first.shopId, equals('s2'));
    });

    test('clearRecentlyViewedShops empties shop history', () async {
      await repo.addRecentlyViewedShop(viewedShop('s1'));
      await repo.clearRecentlyViewedShops();

      expect(await repo.getRecentlyViewedShops(), isEmpty);
    });
  });

  group('App restart persistence', () {
    test('data survives creating a new repository over the same storage',
        () async {
      // Simulate a first session.
      await repo.saveProduct(SavedProductItem(
        productId: 'p100',
        name: 'Wireless Earbuds',
        brand: 'SoundBrand',
        lowestPrice: 2999,
        imageUrl: 'https://via.placeholder.com/150',
        savedAt: DateTime.now(),
      ));
      await repo.saveShop(SavedShopItem(
        shopId: 's100',
        name: 'Gupta Mobile & Electronics',
        address: 'MG Road, Delhi',
        imageUrl: 'https://via.placeholder.com/150',
        rating: 4.5,
        savedAt: DateTime.now(),
      ));
      await repo.addRecentSearch('headphones');
      await repo.addRecentlyViewed(RecentlyViewedItem(
        productId: 'p1',
        name: 'Product p1',
        imageUrl: 'https://via.placeholder.com/150',
        price: 999,
        viewedAt: DateTime.now(),
      ));
      await repo.addRecentlyViewedShop(RecentlyViewedShopItem(
        shopId: 's1',
        name: 'Shop s1',
        address: 'Address',
        imageUrl: 'https://via.placeholder.com/150',
        rating: 4,
        viewedAt: DateTime.now(),
      ));

      // "Restart": brand-new repository instance, same underlying storage.
      final restarted = LocalSavedAndHistoryRepository(driver);

      expect((await restarted.getSavedProducts()).first.productId, 'p100');
      expect((await restarted.getSavedShops()).first.shopId, 's100');
      expect((await restarted.getRecentSearches()).first.query, 'headphones');
      expect((await restarted.getRecentlyViewed()).first.productId, 'p1');
      expect((await restarted.getRecentlyViewedShops()).first.shopId, 's1');
    });
  });

  group('Logout hygiene', () {
    test('purgeSyncedEntries drops mirrored items and keeps guest queue',
        () async {
      await repo.saveProduct(SavedProductItem(
        productId: 'synced',
        name: 'Synced Product',
        brand: 'Brand',
        lowestPrice: 100,
        imageUrl: '',
        savedAt: DateTime.now(),
        isSynced: true,
      ));
      await repo.saveProduct(SavedProductItem(
        productId: 'pending',
        name: 'Pending Product',
        brand: 'Brand',
        lowestPrice: 200,
        imageUrl: '',
        savedAt: DateTime.now(),
      ));
      await repo.saveShop(SavedShopItem(
        shopId: 'synced-shop',
        name: 'Synced Shop',
        address: 'Addr',
        imageUrl: '',
        rating: 4,
        savedAt: DateTime.now(),
        isSynced: true,
      ));

      await repo.purgeSyncedEntries();

      final products = await repo.getSavedProducts();
      expect(products.map((p) => p.productId), ['pending']);
      expect(await repo.getSavedShops(), isEmpty);

      // Device-level history is intentionally retained across logout.
      await repo.addRecentSearch('history keeper');
      await repo.purgeSyncedEntries();
      expect((await repo.getRecentSearches()).first.query, 'history keeper');
    });
  });
}

