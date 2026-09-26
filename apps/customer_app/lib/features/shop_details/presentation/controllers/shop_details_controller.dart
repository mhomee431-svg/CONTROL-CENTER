import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../saved_and_history/domain/models/storage_models.dart';
import '../../../saved_and_history/domain/saved_and_history_repository.dart';
import '../../../saved_and_history/presentation/controllers/saved_and_history_controllers.dart';
import '../../domain/shop_details_repository.dart';
import '../../domain/models/shop_details_models.dart';

final shopDetailsProvider = FutureProvider.autoDispose
    .family<ShopProfile, String>((ref, shopId) async {
      final shopProfile = await ref
          .watch(shopDetailsRepositoryProvider)
          .getShopProfile(shopId);
      // Keep the saved state in sync
      ref.read(shopIsSavedProvider(shopId).notifier).set(shopProfile.isSaved);
      // Phase 9: record this visit in the customer's local history.
      _recordRecentlyViewedShop(ref, shopProfile);
      return shopProfile;
    });

/// Fire-and-forget recording of the shop into "recently viewed shops".
/// Failures are swallowed so history never breaks the details screen.
void _recordRecentlyViewedShop(Ref ref, ShopProfile shop) {
  unawaited(() async {
    try {
      await ref
          .read(recentlyViewedShopsNotifierProvider.notifier)
          .addShop(
            RecentlyViewedShopItem(
              shopId: shop.id,
              name: shop.name,
              address: shop.address,
              imageUrl: shop.imageUrl,
              rating: shop.rating,
              viewedAt: DateTime.now(),
            ),
          );
    } catch (_) {
      // History recording must never break the user flow.
    }
  }());
}

final shopIsSavedProvider = NotifierProvider.autoDispose
    .family<ShopIsSavedNotifier, bool, String>(ShopIsSavedNotifier.new);

class ShopIsSavedNotifier extends Notifier<bool> {
  ShopIsSavedNotifier(this.shopId);

  final String shopId;

  @override
  bool build() => false;

  void set(bool value) => state = value;

  /// Toggles the saved state optimistically and persists via the unified
  /// saved-and-history repository (backend-synced when logged in,
  /// device-local otherwise). Reverts the state if persistence fails.
  Future<void> toggle() async {
    final currentIsSaved = state;
    // Optimistically update the UI
    state = !currentIsSaved;

    try {
      final repo = ref.read(savedAndHistoryRepositoryProvider);
      if (currentIsSaved) {
        await repo.removeShop(shopId);
      } else {
        final profile = ref.read(shopDetailsProvider(shopId)).value;
        await repo.saveShop(
          SavedShopItem(
            shopId: shopId,
            name: profile?.name ?? '',
            address: profile?.address ?? '',
            imageUrl: profile?.imageUrl ?? '',
            rating: profile?.rating ?? 0,
            savedAt: DateTime.now(),
          ),
        );
      }
      // Keep the Saved tab list consistent with this change.
      ref.invalidate(savedShopsNotifierProvider);
    } catch (_) {
      // If persistence fails, revert the state
      state = currentIsSaved;
    }
  }
}
