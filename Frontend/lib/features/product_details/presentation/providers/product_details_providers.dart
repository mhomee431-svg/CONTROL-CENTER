import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/product_details_models.dart';
import '../../domain/product_details_repository.dart';

final productDetailsProvider = FutureProvider.autoDispose
    .family<ProductDetails, String>((ref, productId) async {
  final productDetails =
      await ref.watch(productDetailsRepositoryProvider).getProductDetails(productId);
  // Keep the saved state in sync
  ref.read(productIsSavedProvider(productId).notifier).set(productDetails.isSaved);
  return productDetails;
});

final productIsSavedProvider =
    NotifierProvider.autoDispose.family<ProductIsSavedNotifier, bool, String>(
  ProductIsSavedNotifier.new,
);

class ProductIsSavedNotifier extends Notifier<bool> {
  ProductIsSavedNotifier(this.productId);

  final String productId;

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
      final repo = ref.read(productDetailsRepositoryProvider);
      await repo.toggleSaveProduct(productId, !currentIsSaved);
    } catch (_) {
      // If the API call fails, revert the state
      state = currentIsSaved;
    }
  }
}