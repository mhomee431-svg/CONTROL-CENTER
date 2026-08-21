import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/cache/local_cache_service.dart';
import '../../../core/network/api_client.dart';
import 'models/product_details_models.dart';
import '../data/api_product_details_repository.dart';

final productDetailsRepositoryProvider = Provider<ProductDetailsRepository>((ref) {
  return ApiProductDetailsRepository(
    ref.watch(apiClientProvider),
    ref.watch(localCacheServiceProvider),
  );
});

abstract class ProductDetailsRepository {
  Future<ProductDetails> getProductDetails(String productId);
  Future<void> toggleSaveProduct(String productId, bool save);
}