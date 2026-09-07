import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/storage_models.dart';
import '../../domain/saved_and_history_repository.dart';

// --- SAVED PRODUCTS NOTIFIER ---
final savedProductsNotifierProvider = AsyncNotifierProvider<SavedProductsNotifier, List<SavedProductItem>>(
  SavedProductsNotifier.new,
);

class SavedProductsNotifier extends AsyncNotifier<List<SavedProductItem>> {
  @override
  Future<List<SavedProductItem>> build() async {
    return ref.watch(savedAndHistoryRepositoryProvider).getSavedProducts();
  }

  Future<void> toggleSave(SavedProductItem product) async {
    final current = state.value ?? [];
    final exists = current.any((p) => p.productId == product.productId);
    final repo = ref.read(savedAndHistoryRepositoryProvider);

    if (exists) {
      await repo.removeProduct(product.productId);
    } else {
      await repo.saveProduct(product);
    }
    state = AsyncData(await repo.getSavedProducts());
  }

  /// Clear-all support for the saved products list.
  Future<void> clearAll() async {
    final repo = ref.read(savedAndHistoryRepositoryProvider);
    await repo.clearSavedProducts();
    state = const AsyncData([]);
  }
}

// --- SAVED SHOPS NOTIFIER ---
final savedShopsNotifierProvider = AsyncNotifierProvider<SavedShopsNotifier, List<SavedShopItem>>(
  SavedShopsNotifier.new,
);

class SavedShopsNotifier extends AsyncNotifier<List<SavedShopItem>> {
  @override
  Future<List<SavedShopItem>> build() async {
    return ref.watch(savedAndHistoryRepositoryProvider).getSavedShops();
  }

  Future<void> toggleSave(SavedShopItem shop) async {
    final current = state.value ?? [];
    final exists = current.any((s) => s.shopId == shop.shopId);
    final repo = ref.read(savedAndHistoryRepositoryProvider);

    if (exists) {
      await repo.removeShop(shop.shopId);
    } else {
      await repo.saveShop(shop);
    }
    state = AsyncData(await repo.getSavedShops());
  }

  /// Clear-all support for the saved shops list.
  Future<void> clearAll() async {
    final repo = ref.read(savedAndHistoryRepositoryProvider);
    await repo.clearSavedShops();
    state = const AsyncData([]);
  }
}

// --- RECENT SEARCHES NOTIFIER ---
final recentSearchesNotifierProvider = AsyncNotifierProvider<RecentSearchesNotifier, List<RecentSearchItem>>(
  RecentSearchesNotifier.new,
);

class RecentSearchesNotifier extends AsyncNotifier<List<RecentSearchItem>> {
  @override
  Future<List<RecentSearchItem>> build() async {
    return ref.watch(savedAndHistoryRepositoryProvider).getRecentSearches();
  }

  Future<void> addQuery(String query) async {
    final repo = ref.read(savedAndHistoryRepositoryProvider);
    await repo.addRecentSearch(query);
    state = AsyncData(await repo.getRecentSearches());
  }

  Future<void> removeQuery(String query) async {
    final repo = ref.read(savedAndHistoryRepositoryProvider);
    await repo.removeRecentSearch(query);
    state = AsyncData(await repo.getRecentSearches());
  }

  Future<void> clearAll() async {
    final repo = ref.read(savedAndHistoryRepositoryProvider);
    await repo.clearRecentSearches();
    state = const AsyncData([]);
  }
}

// --- RECENTLY VIEWED NOTIFIER ---
final recentlyViewedNotifierProvider = AsyncNotifierProvider<RecentlyViewedNotifier, List<RecentlyViewedItem>>(
  RecentlyViewedNotifier.new,
);

class RecentlyViewedNotifier extends AsyncNotifier<List<RecentlyViewedItem>> {
  @override
  Future<List<RecentlyViewedItem>> build() async {
    return ref.watch(savedAndHistoryRepositoryProvider).getRecentlyViewed();
  }

  Future<void> addProduct(RecentlyViewedItem item) async {
    final repo = ref.read(savedAndHistoryRepositoryProvider);
    await repo.addRecentlyViewed(item);
    state = AsyncData(await repo.getRecentlyViewed());
  }

  /// Remove-one-item support for the viewed products history.
  Future<void> removeProduct(String productId) async {
    final repo = ref.read(savedAndHistoryRepositoryProvider);
    await repo.removeRecentlyViewed(productId);
    state = AsyncData(await repo.getRecentlyViewed());
  }

  Future<void> clearAll() async {
    final repo = ref.read(savedAndHistoryRepositoryProvider);
    await repo.clearRecentlyViewed();
    state = const AsyncData([]);
  }
}

// --- RECENTLY VIEWED SHOPS NOTIFIER ---
final recentlyViewedShopsNotifierProvider =
    AsyncNotifierProvider<RecentlyViewedShopsNotifier, List<RecentlyViewedShopItem>>(
  RecentlyViewedShopsNotifier.new,
);

class RecentlyViewedShopsNotifier
    extends AsyncNotifier<List<RecentlyViewedShopItem>> {
  @override
  Future<List<RecentlyViewedShopItem>> build() async {
    return ref.watch(savedAndHistoryRepositoryProvider).getRecentlyViewedShops();
  }

  /// Called when a shop details page is opened. Deduping and the
  /// recency cap are handled by the repository.
  Future<void> addShop(RecentlyViewedShopItem shop) async {
    final repo = ref.read(savedAndHistoryRepositoryProvider);
    await repo.addRecentlyViewedShop(shop);
    state = AsyncData(await repo.getRecentlyViewedShops());
  }

  /// Remove-one-item support for the viewed shops history.
  Future<void> removeShop(String shopId) async {
    final repo = ref.read(savedAndHistoryRepositoryProvider);
    await repo.removeRecentlyViewedShop(shopId);
    state = AsyncData(await repo.getRecentlyViewedShops());
  }

  Future<void> clearAll() async {
    final repo = ref.read(savedAndHistoryRepositoryProvider);
    await repo.clearRecentlyViewedShops();
    state = const AsyncData([]);
  }
}
