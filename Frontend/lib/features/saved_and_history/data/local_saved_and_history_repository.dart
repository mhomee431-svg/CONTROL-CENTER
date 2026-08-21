import 'dart:convert';
import '../../../core/storage/local_storage_driver.dart';
import '../domain/models/storage_models.dart';
import '../domain/saved_and_history_repository.dart';

class LocalSavedAndHistoryRepository implements SavedAndHistoryRepository {
  final LocalStorageDriver _storage;

  static const _kSavedProductsKey = 'saved_products_v1';
  static const _kSavedShopsKey = 'saved_shops_v1';
  static const _kRecentSearchesKey = 'recent_searches_v1';
  static const _kRecentlyViewedKey = 'recently_viewed_v1';

  LocalSavedAndHistoryRepository(this._storage);

  // --- SAVED PRODUCTS ---
  @override
  Future<List<SavedProductItem>> getSavedProducts() async {
    final raw = await _storage.getStringList(_kSavedProductsKey) ?? [];
    return raw.map((e) => SavedProductItem.fromJson(jsonDecode(e))).toList();
  }

  @override
  Future<void> saveProduct(SavedProductItem product) async {
    final list = await getSavedProducts();
    final updated = [product, ...list.where((p) => p.productId != product.productId)];
    await _storage.setStringList(
      _kSavedProductsKey,
      updated.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  @override
  Future<void> removeProduct(String productId) async {
    final list = await getSavedProducts();
    final updated = list.where((p) => p.productId != productId).toList();
    await _storage.setStringList(
      _kSavedProductsKey,
      updated.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  // --- SAVED SHOPS ---
  @override
  Future<List<SavedShopItem>> getSavedShops() async {
    final raw = await _storage.getStringList(_kSavedShopsKey) ?? [];
    return raw.map((e) => SavedShopItem.fromJson(jsonDecode(e))).toList();
  }

  @override
  Future<void> saveShop(SavedShopItem shop) async {
    final list = await getSavedShops();
    final updated = [shop, ...list.where((s) => s.shopId != shop.shopId)];
    await _storage.setStringList(
      _kSavedShopsKey,
      updated.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  @override
  Future<void> removeShop(String shopId) async {
    final list = await getSavedShops();
    final updated = list.where((s) => s.shopId != shopId).toList();
    await _storage.setStringList(
      _kSavedShopsKey,
      updated.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  // --- RECENT SEARCHES ---
  @override
  Future<List<RecentSearchItem>> getRecentSearches() async {
    final raw = await _storage.getStringList(_kRecentSearchesKey) ?? [];
    return raw.map((e) => RecentSearchItem.fromJson(jsonDecode(e))).toList();
  }

  @override
  Future<void> addRecentSearch(String query) async {
    if (query.trim().isEmpty) return;
    final list = await getRecentSearches();
    final item = RecentSearchItem(query: query.trim(), searchedAt: DateTime.now());
    final updated = [
      item,
      ...list.where((s) => s.query.toLowerCase() != query.trim().toLowerCase()),
    ].take(10).toList();
    await _storage.setStringList(
      _kRecentSearchesKey,
      updated.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  @override
  Future<void> removeRecentSearch(String query) async {
    final list = await getRecentSearches();
    final updated = list.where((s) => s.query != query).toList();
    await _storage.setStringList(
      _kRecentSearchesKey,
      updated.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  @override
  Future<void> clearRecentSearches() async {
    await _storage.remove(_kRecentSearchesKey);
  }

  // --- RECENTLY VIEWED ---
  @override
  Future<List<RecentlyViewedItem>> getRecentlyViewed() async {
    final raw = await _storage.getStringList(_kRecentlyViewedKey) ?? [];
    return raw.map((e) => RecentlyViewedItem.fromJson(jsonDecode(e))).toList();
  }

  @override
  Future<void> addRecentlyViewed(RecentlyViewedItem item) async {
    final list = await getRecentlyViewed();
    final updated = [
      item,
      ...list.where((v) => v.productId != item.productId),
    ].take(20).toList();
    await _storage.setStringList(
      _kRecentlyViewedKey,
      updated.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  @override
  Future<void> clearRecentlyViewed() async {
    await _storage.remove(_kRecentlyViewedKey);
  }
}