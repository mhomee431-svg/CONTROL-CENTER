import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../domain/models/storage_models.dart';
import '../domain/saved_and_history_repository.dart';
import 'local_saved_and_history_repository.dart';

/// Real backend implementation of [SavedAndHistoryRepository].
///
/// BACKEND-SYNCED: saved products/shops (account data).
/// LOCAL-ONLY: recent searches, recently viewed products/shops — these are
/// delegated to the local store and never leave the device, in both
/// logged-in and logged-out states.
class ApiSavedAndHistoryRepository implements SavedAndHistoryRepository {
  final ApiClient _apiClient;

  /// Local store used for all device-only history. Saved items queued here
  /// while the user was logged out are migrated to the account by
  /// [syncPendingSaves] after login.
  final LocalSavedAndHistoryRepository _local;

  ApiSavedAndHistoryRepository(this._apiClient, this._local);

  // --- SAVED PRODUCTS (backend-synced) ---
  @override
  Future<List<SavedProductItem>> getSavedProducts() async {
    try {
      final data = await _apiClient.get(ApiEndpoints.savedProducts);
      if (data is Map<String, dynamic>) {
        final items = data['items'] as List<dynamic>? ?? [];
        return items
            .map((e) => _mapSavedProduct(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (_) {
      // Offline resilience: fall back to any pending local saves so the
      // customer's saved list stays consistent across network failures.
      return _local.getSavedProducts();
    }
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
    // Mirror as synced so offline reads of the local queue stay correct.
    await _local.saveProduct(product.copyWith(isSynced: true));
  }

  @override
  Future<void> removeProduct(String productId) async {
    await _apiClient.delete(ApiEndpoints.savedProduct(productId));
    await _local.removeProduct(productId);
  }

  @override
  Future<void> clearSavedProducts() async {
    // No bulk endpoint yet — delete each saved product individually.
    final products = await getSavedProducts();
    for (final product in products) {
      await _apiClient.delete(ApiEndpoints.savedProduct(product.productId));
    }
    await _local.clearSavedProducts();
  }


  // --- SAVED SHOPS (backend-synced) ---
  @override
  Future<List<SavedShopItem>> getSavedShops() async {
    try {
      final data = await _apiClient.get(ApiEndpoints.savedShops);
      if (data is Map<String, dynamic>) {
        final items = data['items'] as List<dynamic>? ?? [];
        return items
            .map((e) => _mapSavedShop(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (_) {
      // Offline resilience: fall back to any pending local saves.
      return _local.getSavedShops();
    }
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
    await _local.saveShop(shop.copyWith(isSynced: true));
  }

  @override
  Future<void> removeShop(String shopId) async {
    await _apiClient.delete(ApiEndpoints.savedShop(shopId));
    await _local.removeShop(shopId);
  }

  @override
  Future<void> clearSavedShops() async {
    // No bulk endpoint yet — delete each saved shop individually.
    final shops = await getSavedShops();
    for (final shop in shops) {
      await _apiClient.delete(ApiEndpoints.savedShop(shop.shopId));
    }
    await _local.clearSavedShops();
  }

  // --- RECENT SEARCHES (always local-only) ---
  @override
  Future<List<RecentSearchItem>> getRecentSearches() =>
      _local.getRecentSearches();

  @override
  Future<void> addRecentSearch(String query) => _local.addRecentSearch(query);

  @override
  Future<void> removeRecentSearch(String query) =>
      _local.removeRecentSearch(query);

  @override
  Future<void> clearRecentSearches() => _local.clearRecentSearches();


  // --- RECENTLY VIEWED PRODUCTS (always local-only) ---
  @override
  Future<List<RecentlyViewedItem>> getRecentlyViewed() =>
      _local.getRecentlyViewed();

  @override
  Future<void> addRecentlyViewed(RecentlyViewedItem item) =>
      _local.addRecentlyViewed(item);

  @override
  Future<void> removeRecentlyViewed(String productId) =>
      _local.removeRecentlyViewed(productId);

  @override
  Future<void> clearRecentlyViewed() => _local.clearRecentlyViewed();

  // --- RECENTLY VIEWED SHOPS (always local-only) ---
  @override
  Future<List<RecentlyViewedShopItem>> getRecentlyViewedShops() =>
      _local.getRecentlyViewedShops();

  @override
  Future<void> addRecentlyViewedShop(RecentlyViewedShopItem shop) =>
      _local.addRecentlyViewedShop(shop);

  @override
  Future<void> removeRecentlyViewedShop(String shopId) =>
      _local.removeRecentlyViewedShop(shopId);

  @override
  Future<void> clearRecentlyViewedShops() =>
      _local.clearRecentlyViewedShops();

  // --- LOGIN SYNC ---
  @override
  Future<void> syncPendingSaves() async {
    // Migrate favorites the user saved while logged out (or as a guest)
    // into their account, then drop them from the device so no stale
    // duplicates linger locally.
    try {
      final pendingProducts = (await _local.getSavedProducts())
          .where((p) => !p.isSynced)
          .toList();
      for (final product in pendingProducts) {
        await _apiClient.post(ApiEndpoints.savedProduct(product.productId));
      }
      if (pendingProducts.isNotEmpty) {
        await _local.clearSavedProducts();
      }

      final pendingShops =
          (await _local.getSavedShops()).where((s) => !s.isSynced).toList();
      for (final shop in pendingShops) {
        await _apiClient.post(ApiEndpoints.savedShop(shop.shopId));
      }
      if (pendingShops.isNotEmpty) {
        await _local.clearSavedShops();
      }
    } catch (_) {
      // Best-effort: keep unsynced items queued for the next attempt.
    }
  }
}
