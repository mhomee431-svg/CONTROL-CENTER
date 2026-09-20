import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_providers.dart';
import '../domain/product_models.dart';

/// Product CRUD for one authorized shop.
///
/// Ownership (repository rule): creating and editing a LISTING lives here.
/// Everything that reads or mutates the shop's stock — the overview, delta
/// adjustments, movement history and the low-stock threshold — belongs to
/// [InventoryRepository] (features/inventory/data).
abstract class ProductRepository {
  Future<ShopProductItem> createProduct(
      int shopId, Map<String, dynamic> payload, String token);
  Future<ShopProductItem> updateProduct(
      int shopId, int productId, Map<String, dynamic> fields, String token);
}

class ApiProductRepository implements ProductRepository {
  ApiProductRepository(this._api);

  final ApiClient _api;

  @override
  Future<ShopProductItem> createProduct(
      int shopId, Map<String, dynamic> payload, String token) async {
    final data = await _api.post(
      ApiEndpoints.products('$shopId'),
      body: payload,
      token: token,
    ) as Map<String, dynamic>;
    return ShopProductItem.fromJson(data);
  }

  @override
  Future<ShopProductItem> updateProduct(int shopId, int productId,
      Map<String, dynamic> fields, String token) async {
    final data = await _api.patch(
      ApiEndpoints.product('$shopId', '$productId'),
      body: fields,
      token: token,
    ) as Map<String, dynamic>;
    return ShopProductItem.fromJson(data);
  }
}

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ApiProductRepository(ref.watch(apiClientProvider));
});

