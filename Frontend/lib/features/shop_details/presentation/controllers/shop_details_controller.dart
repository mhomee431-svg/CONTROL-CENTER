import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/shop_details_repository.dart';
import '../../domain/models/shop_details_models.dart';

final shopDetailsProvider = FutureProvider.autoDispose
    .family<ShopProfile, String>((ref, shopId) async {
  final shopProfile =
      await ref.watch(shopDetailsRepositoryProvider).getShopProfile(shopId);
  // Keep the saved state in sync
  ref.read(shopIsSavedProvider(shopId).notifier).set(shopProfile.isSaved);
  return shopProfile;
});

final shopIsSavedProvider =
    NotifierProvider.autoDispose.family<ShopIsSavedNotifier, bool, String>(
  ShopIsSavedNotifier.new,
);

class ShopIsSavedNotifier extends Notifier<bool> {
  ShopIsSavedNotifier(this.shopId);

  final String shopId;

  @override
  bool build() => false;

  void set(bool value) => state = value;

  /// Toggles the saved state optimistically and persists via the repository.
  /// Reverts the state if the API call fails.
  Future<void> toggle() async {
    final currentIsSaved = state;
    // Optimistically update the UI
    state = !currentIsSaved;

    try {
      final repo = ref.read(shopDetailsRepositoryProvider);
      await repo.toggleSaveShop(shopId, !currentIsSaved);
    } catch (_) {
      // If the API call fails, revert the state
      state = currentIsSaved;
    }
  }
}