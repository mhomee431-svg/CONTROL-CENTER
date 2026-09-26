import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/local_storage_driver.dart';
import '../../auth/presentation/controllers/auth_controller.dart';
import '../data/api_saved_and_history_repository.dart';
import '../data/local_saved_and_history_repository.dart';
import 'models/storage_models.dart';

/// Repository abstraction for all customer personalization data.
///
/// BACKEND-SYNCED STATE (Phase 13+ endpoints):
///   - Saved products / saved shops — synced with the account when the
///     user is authenticated.
///
/// LOCAL-ONLY STATE (never leaves the device):
///   - Recent searches (capped, deduped)
///   - Recently viewed products / shops (capped, deduped)
///
/// The [savedAndHistoryRepositoryProvider] selects the correct
/// implementation based on auth state:
///   - Authenticated  -> [ApiSavedAndHistoryRepository] (account-synced,
///     delegating local-only history to the local store).
///   - Guest/logged-out -> [LocalSavedAndHistoryRepository] (everything is
///     device-local; saved items are flagged `isSynced = false` so they can
///     be migrated to the account on the next login via [syncPendingSaves]).
abstract class SavedAndHistoryRepository {
  // --- SAVED PRODUCTS (backend-synced when logged in) ---
  Future<List<SavedProductItem>> getSavedProducts();
  Future<void> saveProduct(SavedProductItem product);
  Future<void> removeProduct(String productId);
  Future<void> clearSavedProducts();

  // --- SAVED SHOPS (backend-synced when logged in) ---
  Future<List<SavedShopItem>> getSavedShops();
  Future<void> saveShop(SavedShopItem shop);
  Future<void> removeShop(String shopId);
  Future<void> clearSavedShops();

  // --- RECENT SEARCHES (local-only) ---
  Future<List<RecentSearchItem>> getRecentSearches();
  Future<void> addRecentSearch(String query);
  Future<void> removeRecentSearch(String query);
  Future<void> clearRecentSearches();

  // --- RECENTLY VIEWED PRODUCTS (local-only) ---
  Future<List<RecentlyViewedItem>> getRecentlyViewed();
  Future<void> addRecentlyViewed(RecentlyViewedItem item);
  Future<void> removeRecentlyViewed(String productId);
  Future<void> clearRecentlyViewed();

  // --- RECENTLY VIEWED SHOPS (local-only) ---
  Future<List<RecentlyViewedShopItem>> getRecentlyViewedShops();
  Future<void> addRecentlyViewedShop(RecentlyViewedShopItem shop);
  Future<void> removeRecentlyViewedShop(String shopId);
  Future<void> clearRecentlyViewedShops();

  /// Prepares synchronization with the backend: pushes locally-saved
  /// (unsynced) favorites to the account after a successful login and
  /// clears them from the device once accepted. Best-effort; failures are
  /// swallowed so items stay queued for a later attempt.
  Future<void> syncPendingSaves();
}

final savedAndHistoryRepositoryProvider = Provider<SavedAndHistoryRepository>((
  ref,
) {
  final local = LocalSavedAndHistoryRepository(
    ref.watch(localStorageDriverProvider),
  );
  final authStatus = ref.watch(authControllerProvider).status;

  // Logged-in users get the backend-synced repository; guests and signed-out
  // users fall back to the fully-local one. Watching the auth state means
  // every dependent notifier automatically reloads on login/logout.
  if (authStatus == AuthStatus.authenticated) {
    return ApiSavedAndHistoryRepository(ref.watch(apiClientProvider), local);
  }
  return local;
});
