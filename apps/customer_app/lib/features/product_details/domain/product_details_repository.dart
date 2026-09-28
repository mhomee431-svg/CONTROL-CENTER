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
  Future<ProductDetails> getProductDetails(String productId);
  Future<void> toggleSaveProduct(String productId, bool save);
}
