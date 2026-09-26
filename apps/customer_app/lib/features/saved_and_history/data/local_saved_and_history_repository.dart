import 'dart:convert';

import '../../../core/storage/local_storage_driver.dart';
import '../domain/models/storage_models.dart';
import '../domain/saved_and_history_repository.dart';

/// Fully-local implementation of [SavedAndHistoryRepository].
///
/// Used as the source of truth for guests/logged-out users (where saved
/// items are queued with `isSynced = false` until the next login) and as
/// the storage backend for all local-only history even when logged in.
class LocalSavedAndHistoryRepository implements SavedAndHistoryRepository {
  final LocalStorageDriver _storage;

  /// Sensible limits for locally retained history so storage stays bounded.
  static const int maxRecentSearches = 10;
  static const int maxRecentlyViewedProducts = 20;
  static const int maxRecentlyViewedShops = 20;
  static const int maxSavedProducts = 100;
  static const int maxSavedShops = 100;

  // Storage keys are namespaced per concern; none of the persisted payloads
  // contain tokens or personal data — only product/shop display fields.
  static const _kSavedProductsKey = 'saved_products_v1';
  static const _kSavedShopsKey = 'saved_shops_v1';
  static const _kRecentSearchesKey = 'recent_searches_v1';
  static const _kRecentlyViewedKey = 'recently_viewed_v1';
  static const _kRecentlyViewedShopsKey = 'recently_viewed_shops_v1';

  LocalSavedAndHistoryRepository(this._storage);

  Future<List<String>> _readList(String key) async =>
      await _storage.getStringList(key) ?? [];

  Future<void> _writeList(String key, List<String> items) =>
      _storage.setStringList(key, items);

  // --- SAVED PRODUCTS ---
  @override
  Future<List<SavedProductItem>> getSavedProducts() async {
    final raw = await _readList(_kSavedProductsKey);
    final items = raw
        .map((e) => SavedProductItem.fromJson(jsonDecode(e)))
        .toList();
    // Newest saves first.
    items.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return items;
  }

  @override
  Future<void> saveProduct(SavedProductItem product) async {
    final list = await getSavedProducts();
    // De-duplicate: re-saving moves an existing product to the front.
    final updated = [
      product,
      ...list.where((p) => p.productId != product.productId),
    ].take(maxSavedProducts).toList();
    await _writeList(
      _kSavedProductsKey,
      updated.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  @override
  Future<void> removeProduct(String productId) async {
    final list = await getSavedProducts();
    final updated = list.where((p) => p.productId != productId).toList();
    await _writeList(
      _kSavedProductsKey,
      updated.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  @override
  Future<void> clearSavedProducts() => _storage.remove(_kSavedProductsKey);

  // --- SAVED SHOPS ---
  @override
  Future<List<SavedShopItem>> getSavedShops() async {
    final raw = await _readList(_kSavedShopsKey);
    final items = raw
        .map((e) => SavedShopItem.fromJson(jsonDecode(e)))
        .toList();
    items.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return items;
  }

  @override
  Future<void> saveShop(SavedShopItem shop) async {
    final list = await getSavedShops();
    final updated = [
      shop,
      ...list.where((s) => s.shopId != shop.shopId),
    ].take(maxSavedShops).toList();
    await _writeList(
      _kSavedShopsKey,
      updated.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  @override
  Future<void> removeShop(String shopId) async {
    final list = await getSavedShops();
    final updated = list.where((s) => s.shopId != shopId).toList();
    await _writeList(
      _kSavedShopsKey,
      updated.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  @override
  Future<void> clearSavedShops() => _storage.remove(_kSavedShopsKey);

  // --- RECENT SEARCHES ---
  @override
  Future<List<RecentSearchItem>> getRecentSearches() async {
    final raw = await _readList(_kRecentSearchesKey);
    final items = raw
        .map((e) => RecentSearchItem.fromJson(jsonDecode(e)))
        .toList();
    items.sort((a, b) => b.searchedAt.compareTo(a.searchedAt));
    return items;
  }

  @override
  Future<void> addRecentSearch(String query) async {
    final cleaned = query.trim();
    // Never retain empty queries.
    if (cleaned.isEmpty) return;
    final list = await getRecentSearches();
    final item = RecentSearchItem(query: cleaned, searchedAt: DateTime.now());
    final updated = [
      item,
      ...list.where((s) => s.query.toLowerCase() != cleaned.toLowerCase()),
    ].take(maxRecentSearches).toList();
    await _writeList(
      _kRecentSearchesKey,
      updated.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  @override
  Future<void> removeRecentSearch(String query) async {
    final list = await getRecentSearches();
    final updated = list.where((s) => s.query != query).toList();
    await _writeList(
      _kRecentSearchesKey,
      updated.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  @override
  Future<void> clearRecentSearches() => _storage.remove(_kRecentSearchesKey);

  // --- RECENTLY VIEWED PRODUCTS ---
  @override
  Future<List<RecentlyViewedItem>> getRecentlyViewed() async {
    final raw = await _readList(_kRecentlyViewedKey);
    final items = raw
        .map((e) => RecentlyViewedItem.fromJson(jsonDecode(e)))
        .toList();
    items.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
    return items;
  }

  @override
  Future<void> addRecentlyViewed(RecentlyViewedItem item) async {
    if (item.productId.isEmpty) return;
    final list = await getRecentlyViewed();
    // Re-viewing bumps the product to the front instead of duplicating it.
    final updated = [
      item,
      ...list.where((v) => v.productId != item.productId),
    ].take(maxRecentlyViewedProducts).toList();
    await _writeList(
      _kRecentlyViewedKey,
      updated.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  @override
  Future<void> removeRecentlyViewed(String productId) async {
    final list = await getRecentlyViewed();
    final updated = list.where((v) => v.productId != productId).toList();
    await _writeList(
      _kRecentlyViewedKey,
      updated.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  @override
  Future<void> clearRecentlyViewed() => _storage.remove(_kRecentlyViewedKey);

  // --- RECENTLY VIEWED SHOPS ---
  @override
  Future<List<RecentlyViewedShopItem>> getRecentlyViewedShops() async {
    final raw = await _readList(_kRecentlyViewedShopsKey);
    final items = raw
        .map((e) => RecentlyViewedShopItem.fromJson(jsonDecode(e)))
        .toList();
    items.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
    return items;
  }

  @override
  Future<void> addRecentlyViewedShop(RecentlyViewedShopItem shop) async {
    if (shop.shopId.isEmpty) return;
    final list = await getRecentlyViewedShops();
    final updated = [
      shop,
      ...list.where((v) => v.shopId != shop.shopId),
    ].take(maxRecentlyViewedShops).toList();
    await _writeList(
      _kRecentlyViewedShopsKey,
      updated.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  @override
  Future<void> removeRecentlyViewedShop(String shopId) async {
    final list = await getRecentlyViewedShops();
    final updated = list.where((v) => v.shopId != shopId).toList();
    await _writeList(
      _kRecentlyViewedShopsKey,
      updated.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  @override
  Future<void> clearRecentlyViewedShops() =>
      _storage.remove(_kRecentlyViewedShopsKey);

  // --- BACKEND SYNC PREP ---
  @override
  Future<void> syncPendingSaves() async {
    // The local store has no backend to push to. Pending items are kept
    // (flagged unsynced) so [ApiSavedAndHistoryRepository.syncPendingSaves]
    // can migrate them after login.
  }

  /// Logout hygiene: removes account-mirrored (already synced) favorites
  /// from the device so they never leak into another session, while
  /// preserving unsynced guest-saved items queued for the next login.
  Future<void> purgeSyncedEntries() async {
    final products = await getSavedProducts();
    final keptProducts = products.where((p) => !p.isSynced).toList();
    if (keptProducts.length != products.length) {
      await _writeList(
        _kSavedProductsKey,
        keptProducts.map((e) => jsonEncode(e.toJson())).toList(),
      );
    }

    final shops = await getSavedShops();
    final keptShops = shops.where((s) => !s.isSynced).toList();
    if (keptShops.length != shops.length) {
      await _writeList(
        _kSavedShopsKey,
        keptShops.map((e) => jsonEncode(e.toJson())).toList(),
      );
    }
  }
}
