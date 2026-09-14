import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_providers.dart';
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
    // `view=list` returns every item with last_updated + freshness_status +
    // source, which is what the Products screen renders; the overview shape
    // is preserved via _inventoryOverviewFromData so callers stay unchanged.
    final data = await _api.get(
      '/api/v1/shopkeeper/shops/$shopId/inventory',
      query: const {'view': 'list'},
      token: token,
    ) as Map<String, dynamic>;
    return _inventoryOverviewFromData({
      'summary': {
        'total': 0,
        'active': 0,
        'in_stock': 0,
        'low_stock': 0,
        'out_of_stock': 0,
        'total_units': 0,
      },
      'items': data['items'] ?? const [],
    });
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

/// Builds an [InventoryOverview] from a `view=list` response, deriving the
/// summary counts client-side so the whole app shares one data contract.
InventoryOverview _inventoryOverviewFromData(Map<String, dynamic> json) {
  final items = ((json['items'] as List<dynamic>?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(ShopProductItem.fromJson)
      .toList(growable: false);
  var inStock = 0, lowStock = 0, outOfStock = 0, totalUnits = 0;
  for (final item in items) {
    totalUnits += item.quantity;
    if (item.stockStatus == 'OUT_OF_STOCK') {
      outOfStock += 1;
    } else if (item.stockStatus == 'LOW_STOCK' ||
        item.stockStatus == 'LIMITED_STOCK') {
      lowStock += 1;
    } else if (item.stockStatus == 'IN_STOCK' ||
        item.stockStatus == 'PRE_ORDER' ||
        item.stockStatus == 'BACK_ORDER') {
      inStock += 1;
    }
  }
  final summary = (
    total: items.length,
    active: items.where((i) => i.isActive && i.isAvailable).length,
    inStock: inStock,
    lowStock: lowStock,
    outOfStock: outOfStock,
    totalUnits: totalUnits,
  );
  return InventoryOverview(items: items, summary: summary);
}

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ApiProductRepository(ref.watch(apiClientProvider));
});
