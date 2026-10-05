import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/local_cache_service.dart';
import '../../../core/network/api_client.dart';
import '../../location/presentation/controllers/location_controller.dart';
import 'models/product_details_models.dart';
import '../data/api_product_details_repository.dart';

final productDetailsRepositoryProvider = Provider<ProductDetailsRepository>((
  ref,
) {
  final location = ref.watch(locationControllerProvider).location;
  return ApiProductDetailsRepository(
    ref.watch(apiClientProvider),
    ref.watch(localCacheServiceProvider),
    latitude: location?.latitude,
    longitude: location?.longitude,
  );
});

abstract class ProductDetailsRepository {
  /// Shop offers come back inside the same `radius_km` the search page uses
  /// (default 25). The recovery action "look further" passes a wider value;
  /// everything else leaves the default, so the product page and the results
  /// list never silently disagree about how far "nearby" reaches.
  Future<ProductDetails> getProductDetails(
    String productId, {
    double? radiusKm,
  });
  Future<void> toggleSaveProduct(String productId, bool save);
}
