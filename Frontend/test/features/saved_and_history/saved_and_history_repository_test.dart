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
}