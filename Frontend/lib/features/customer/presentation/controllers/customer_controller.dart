import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/customer_repository.dart';
import '../../domain/models/customer_models.dart';

/// Fetches the customer's favourites.
final customerFavoritesProvider =
    FutureProvider.autoDispose.family<List<CustomerFavorite>, String?>(
        (ref, itemType) async {
  final repo = ref.watch(customerRepositoryProvider);
  return repo.getFavorites(itemType: itemType);
});

/// Fetches the customer's recently-viewed products.
final customerRecentlyViewedProvider =
    FutureProvider.autoDispose<List<RecentProduct>>((ref) async {
  final repo = ref.watch(customerRepositoryProvider);
  return repo.getRecentlyViewed();
});

/// Toggle-favourite controller — call [toggle] to add/remove a favourite.
final customerFavoriteToggleControllerProvider =
    NotifierProvider<CustomerFavoriteToggleController, AsyncValue<Map<String, dynamic>>?>(
  CustomerFavoriteToggleController.new,
);

class CustomerFavoriteToggleController
    extends Notifier<AsyncValue<Map<String, dynamic>>?> {
  @override
  AsyncValue<Map<String, dynamic>>? build() => null;

  Future<bool> toggle(String itemType, int itemId) async {
    state = const AsyncValue.loading();
    try {
      final repo = ref.read(customerRepositoryProvider);
      final result = await repo.toggleFavorite(itemType, itemId);
      state = AsyncValue.data(result);
      // Refresh the favourites list so the UI updates immediately.
      ref.invalidate(customerFavoritesProvider);
      return result['favorited'] == true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }
}

/// Records a product view (fire-and-forget from product details screen).
final recordRecentViewProvider =
    FutureProvider.autoDispose.family<void, RecentViewRequest>(
        (ref, req) async {
  final repo = ref.watch(customerRepositoryProvider);
  await repo.recordRecentView(req.productMasterId,
      variantId: req.variantId, shopProductId: req.shopProductId);
});

class RecentViewRequest {
  final int productMasterId;
  final int? variantId;
  final int? shopProductId;
  const RecentViewRequest(this.productMasterId,
      {this.variantId, this.shopProductId});
}