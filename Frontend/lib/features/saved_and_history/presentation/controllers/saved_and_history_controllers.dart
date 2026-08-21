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

  Future<void> clearAll() async {
    final repo = ref.read(savedAndHistoryRepositoryProvider);
    await repo.clearRecentlyViewed();
    state = const AsyncData([]);
  }
}