import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import 'models/storage_models.dart';
import '../data/api_saved_and_history_repository.dart';

final savedAndHistoryRepositoryProvider = Provider<SavedAndHistoryRepository>(
  (ref) => ApiSavedAndHistoryRepository(ref.watch(apiClientProvider)),
);

abstract class SavedAndHistoryRepository {
  Future<List<SavedProductItem>> getSavedProducts();
  Future<void> saveProduct(SavedProductItem product);
  Future<void> removeProduct(String productId);

  Future<List<SavedShopItem>> getSavedShops();
  Future<void> saveShop(SavedShopItem shop);
  Future<void> removeShop(String shopId);

  Future<List<RecentSearchItem>> getRecentSearches();
  Future<void> addRecentSearch(String query);
  Future<void> removeRecentSearch(String query);
  Future<void> clearRecentSearches();

  Future<List<RecentlyViewedItem>> getRecentlyViewed();
  Future<void> addRecentlyViewed(RecentlyViewedItem item);
  Future<void> clearRecentlyViewed();
}