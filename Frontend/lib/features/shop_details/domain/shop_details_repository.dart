import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/cache/local_cache_service.dart';
import '../../../core/network/api_client.dart';
import 'models/shop_details_models.dart';
import '../data/api_shop_details_repository.dart';

final shopDetailsRepositoryProvider = Provider<ShopDetailsRepository>((ref) {
  return ApiShopDetailsRepository(
    ref.watch(apiClientProvider),
    ref.watch(localCacheServiceProvider),
  );
});

abstract class ShopDetailsRepository {
  Future<ShopProfile> getShopProfile(String shopId);
  Future<void> toggleSaveShop(String shopId, bool save);
}