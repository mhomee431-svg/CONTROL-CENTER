import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/location/discovery_radius.dart';
import '../../domain/models/product_details_models.dart';
import '../../domain/product_details_repository.dart';
import '../../../saved_and_history/domain/models/storage_models.dart';
import '../../../saved_and_history/domain/saved_and_history_repository.dart';
import '../../../saved_and_history/presentation/controllers/saved_and_history_controllers.dart';

/// The discovery radius for one product's nearby shop offers.
///
/// Starts at null so the backend default (`radius_km=25` — the same boundary
/// the search results use) rules the first load. A customer who taps the widen
/// action in the product's empty state steps the shared ladder up one notch at
/// a time and every LIVE `productDetailsProvider` instance re-reads, because
/// that provider watches this. Same rules as the home feed: widening only,
/// never narrowing, and never a request above the server's 100 km cap.
final productSearchRadiusProvider =
    NotifierProvider<ProductSearchRadiusController, double?>(
      ProductSearchRadiusController.new,
    );

class ProductSearchRadiusController extends Notifier<double?> {
  @override
  double? build() => null;

  /// Widening takes effect through [productDetailsProvider] watching this —
  /// no explicit invalidate, so a value cannot be dropped without being
  /// re-read in the same frame.
  void widen() {
    final next = nextDiscoveryRadius(state);
    if (next == null) return;
    state = next;
  }
}

final productDetailsProvider = FutureProvider.autoDispose
    .family<ProductDetails, String>((ref, productId) async {
      final radiusKm = ref.watch(productSearchRadiusProvider);
      final productDetails = await ref
          .watch(productDetailsRepositoryProvider)
          .getProductDetails(productId, radiusKm: radiusKm);
      // Keep the saved state in sync
      ref
          .read(productIsSavedProvider(productId).notifier)
          .set(productDetails.product.isSaved);
      // Phase 9: record this view in the customer's local history.
      _recordRecentlyViewed(ref, productDetails);
      return productDetails;
    });

/// Lowest known price for a product, preferring live offers over MRP.
double _lowestPrice(ProductDetails details) {
  if (details.shopOffers.isEmpty) return details.product.mrp ?? 0;
  return details.shopOffers.map((o) => o.price).reduce((a, b) => a < b ? a : b);
}

/// Fire-and-forget recording of the product into "recently viewed".
/// Failures are swallowed so history never breaks the details screen.
void _recordRecentlyViewed(Ref ref, ProductDetails details) {
  final product = details.product;
  unawaited(() async {
    try {
      await ref
          .read(recentlyViewedNotifierProvider.notifier)
          .addProduct(
            RecentlyViewedItem(
              productId: product.id,
              name: product.name,
              imageUrl: product.imageUrls.isNotEmpty
                  ? product.imageUrls.first
                  : '',
              price: _lowestPrice(details),
              viewedAt: DateTime.now(),
            ),
          );
    } catch (_) {
      // History recording must never break the user flow.
    }
  }());
}

final productIsSavedProvider = NotifierProvider.autoDispose
    .family<ProductIsSavedNotifier, bool, String>(ProductIsSavedNotifier.new);

class ProductIsSavedNotifier extends Notifier<bool> {
  ProductIsSavedNotifier(this.productId);

  final String productId;

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
        await repo.removeProduct(productId);
      } else {
        final details = ref.read(productDetailsProvider(productId)).value;
        final product = details?.product;
        await repo.saveProduct(
          SavedProductItem(
            productId: productId,
            name: product?.name ?? '',
            brand: product?.brand ?? '',
            lowestPrice: details != null ? _lowestPrice(details) : 0,
            imageUrl: product != null && product.imageUrls.isNotEmpty
                ? product.imageUrls.first
                : '',
            savedAt: DateTime.now(),
          ),
        );
      }
      // Keep the Saved tab list consistent with this change.
      ref.invalidate(savedProductsNotifierProvider);
    } catch (_) {
      // If persistence fails, revert the state
      state = currentIsSaved;
    }
  }
}
