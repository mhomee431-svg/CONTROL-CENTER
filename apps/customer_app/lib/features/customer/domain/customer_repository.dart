import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import 'models/customer_models.dart';

/// Provider wiring — uses the real backend API.
final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return ApiCustomerRepository(ref.watch(apiClientProvider));
});

/// Abstract contract for customer data (favourites, recently viewed, share).
abstract class CustomerRepository {
  Future<List<CustomerFavorite>> getFavorites({String? itemType});
  Future<Map<String, dynamic>> toggleFavorite(String itemType, int itemId);
  Future<List<String>> getFavoriteTypes();
  Future<List<RecentProduct>> getRecentlyViewed({int limit = 20});
  Future<void> recordRecentView(int productMasterId, {int? variantId, int? shopProductId});
  Future<ProductSharePayload?> getSharePayload(int productMasterId);
  Future<void> recordShare(int productMasterId);
}

/// Real backend implementation.
class ApiCustomerRepository implements CustomerRepository {
  final ApiClient _api;
  ApiCustomerRepository(this._api);

  @override
  Future<List<CustomerFavorite>> getFavorites({String? itemType}) async {
    final data = await _api.get(
      ApiEndpoints.customerFavorites,
      queryParameters: itemType != null ? {'item_type': itemType} : null,
      requiresAuth: true,
    );
    final items = (data is Map ? data['items'] : data) as List<dynamic>? ?? [];
    return items
        .map((e) => CustomerFavorite.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Map<String, dynamic>> toggleFavorite(String itemType, int itemId) async {
    return await _api.post(
      ApiEndpoints.customerFavorites,
      queryParameters: {'item_type': itemType, 'item_id': itemId},
      requiresAuth: true,
    ) as Map<String, dynamic>;
  }

  @override
  Future<List<String>> getFavoriteTypes() async {
    final data = await _api.get(
      ApiEndpoints.customerFavoritesTypes,
      requiresAuth: true,
    );
    final types = (data is Map ? data['item_types'] : data) as List<dynamic>? ?? [];
    return types.map((e) => e.toString()).toList();
  }

  @override
  Future<List<RecentProduct>> getRecentlyViewed({int limit = 20}) async {
    final data = await _api.get(
      ApiEndpoints.customerRecentlyViewed,
      queryParameters: {'limit': limit},
      requiresAuth: true,
    );
    final items = (data is Map ? data['items'] : data) as List<dynamic>? ?? [];
    return items
        .map((e) => RecentProduct.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> recordRecentView(int productMasterId,
      {int? variantId, int? shopProductId}) async {
    await _api.post(
      ApiEndpoints.customerRecentlyViewed,
      queryParameters: {
        'product_master_id': productMasterId,
        'variant_id': ?variantId,
        'shop_product_id': ?shopProductId,
      },
      requiresAuth: true,
    );
  }

  @override
  Future<ProductSharePayload?> getSharePayload(int productMasterId) async {
    try {
      final data = await _api.get(
        ApiEndpoints.customerProductShare(productMasterId.toString()),
        requiresAuth: false,
      );
      final payload = (data is Map ? data['data'] : data) as Map<String, dynamic>?;
      if (payload == null) return null;
      return ProductSharePayload.fromJson(payload);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> recordShare(int productMasterId) async {
    try {
      await _api.post(
        ApiEndpoints.customerProductShare(productMasterId.toString()),
        requiresAuth: false,
      );
    } catch (_) {
      // Analytics only — never block sharing on errors.
    }
  }
}