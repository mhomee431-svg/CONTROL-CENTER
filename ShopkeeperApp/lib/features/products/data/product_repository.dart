import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_providers.dart';
import '../domain/product_models.dart';

/// Product & inventory management contract for one authorized shop.
abstract class ProductRepository {
  Future<InventoryOverview> fetchInventoryOverview(int shopId, String token);
  Future<ShopProductItem> createProduct(
      int shopId, Map<String, dynamic> payload, String token);
  Future<ShopProductItem> updateProduct(
      int shopId, int productId, Map<String, dynamic> fields, String token);
}

class ApiProductRepository implements ProductRepository {
  ApiProductRepository(this._api);

  final ApiClient _api;

  @override
  Future<InventoryOverview> fetchInventoryOverview(
      int shopId, String token) async {
    final data = await _api.get('/api/v1/shopkeeper/shops/$shopId/inventory',
        token: token) as Map<String, dynamic>;
    return InventoryOverview.fromJson(data);
  }

  @override
  Future<ShopProductItem> createProduct(
      int shopId, Map<String, dynamic> payload, String token) async {
    final data = await _api.post('/api/v1/shopkeeper/shops/$shopId/products',
        body: payload, token: token) as Map<String, dynamic>;
    return ShopProductItem.fromJson(data);
  }

  @override
  Future<ShopProductItem> updateProduct(int shopId, int productId,
      Map<String, dynamic> fields, String token) async {
    final data = await _api.patch(
      '/api/v1/shopkeeper/shops/$shopId/products/$productId',
      body: fields,
      token: token,
    ) as Map<String, dynamic>;
    return ShopProductItem.fromJson(data);
  }
}

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ApiProductRepository(ref.watch(apiClientProvider));
});
