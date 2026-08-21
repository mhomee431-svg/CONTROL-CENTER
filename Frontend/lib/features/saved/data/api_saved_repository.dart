import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../domain/saved_repository.dart';

class ApiSavedRepository implements SavedRepository {
  final ApiClient _apiClient;

  ApiSavedRepository(this._apiClient);

  @override
  Future<List<String>> getSavedProductIds() async {
    final data = await _apiClient.get(ApiEndpoints.savedProducts);
    final items = (data is Map<String, dynamic> ? data['items'] : null) as List? ?? [];
    return items
        .map((e) => (e as Map<String, dynamic>)['product_id'].toString())
        .toList();
  }

  @override
  Future<void> saveProduct(String productId) async {
    await _apiClient.post(ApiEndpoints.savedProduct(productId));
  }

  @override
  Future<void> unsaveProduct(String productId) async {
    await _apiClient.delete(ApiEndpoints.savedProduct(productId));
  }

  @override
  Future<List<String>> getSavedShopIds() async {
    final data = await _apiClient.get(ApiEndpoints.savedShops);
    final items = (data is Map<String, dynamic> ? data['items'] : null) as List? ?? [];
    return items
        .map((e) => (e as Map<String, dynamic>)['shop_id'].toString())
        .toList();
  }

  @override
  Future<void> saveShop(String shopId) async {
    await _apiClient.post(ApiEndpoints.savedShop(shopId));
  }

  @override
  Future<void> unsaveShop(String shopId) async {
    await _apiClient.delete(ApiEndpoints.savedShop(shopId));
  }
}