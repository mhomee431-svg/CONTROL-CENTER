import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../domain/models/storage_models.dart';
import '../domain/saved_and_history_repository.dart';

/// Real backend implementation of [SavedAndHistoryRepository].
/// Saved products/shops are synced with the backend; recent searches and
/// recently viewed remain local-only in Phase 13.
class ApiSavedAndHistoryRepository implements SavedAndHistoryRepository {
  final ApiClient _apiClient;

  ApiSavedAndHistoryRepository(this._apiClient);

  // --- SAVED PRODUCTS ---
  @override
  Future<List<SavedProductItem>> getSavedProducts() async {
    final data = await _apiClient.get(ApiEndpoints.savedProducts);
    if (data is Map<String, dynamic>) {
      final items = data['items'] as List<dynamic>? ?? [];
      return items.map((e) => _mapSavedProduct(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  SavedProductItem _mapSavedProduct(Map<String, dynamic> json) {
    return SavedProductItem(
      productId: json['product_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      brand: json['brand']?.toString() ?? '',
      lowestPrice: (json['lowest_price'] as num?)?.toDouble() ?? 0,
      imageUrl: json['image_url']?.toString() ?? '',
      savedAt: DateTime.tryParse(json['saved_at']?.toString() ?? '') ?? DateTime.now(),
      isSynced: true,
    );
  }

  @override
  Future<void> saveProduct(SavedProductItem product) async {
    await _apiClient.post(ApiEndpoints.savedProduct(product.productId));
  }

  @override
  Future<void> removeProduct(String productId) async {
    await _apiClient.delete(ApiEndpoints.savedProduct(productId));
  }

  // --- SAVED SHOPS ---
  @override
  Future<List<SavedShopItem>> getSavedShops() async {
    final data = await _apiClient.get(ApiEndpoints.savedShops);
    if (data is Map<String, dynamic>) {
      final items = data['items'] as List<dynamic>? ?? [];
      return items.map((e) => _mapSavedShop(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  SavedShopItem _mapSavedShop(Map<String, dynamic> json) {
    return SavedShopItem(
      shopId: json['shop_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      imageUrl: json['image_url']?.toString() ?? '',
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      savedAt: DateTime.tryParse(json['saved_at']?.toString() ?? '') ?? DateTime.now(),
      isSynced: true,
    );
  }

  @override
  Future<void> saveShop(SavedShopItem shop) async {
    await _apiClient.post(ApiEndpoints.savedShop(shop.shopId));
  }

  @override
  Future<void> removeShop(String shopId) async {
    await _apiClient.delete(ApiEndpoints.savedShop(shopId));
  }

  // --- RECENT SEARCHES (local-only in Phase 13) ---
  @override
  Future<List<RecentSearchItem>> getRecentSearches() async => [];

  @override
  Future<void> addRecentSearch(String query) async {}

  @override
  Future<void> removeRecentSearch(String query) async {}

  @override
  Future<void> clearRecentSearches() async {}

  // --- RECENTLY VIEWED (local-only in Phase 13) ---
  @override
  Future<List<RecentlyViewedItem>> getRecentlyViewed() async => [];

  @override
  Future<void> addRecentlyViewed(RecentlyViewedItem item) async {}

  @override
  Future<void> clearRecentlyViewed() async {}
}