import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_providers.dart';
import '../domain/shop_models.dart';

/// Shop management contract: listing, registration, profile & settings.
abstract class ShopRepository {
  Future<List<ShopSummary>> listMyShops(String token);
  Future<ShopDetail> getShopDetail(int shopId, String token);
  Future<ShopDetail> registerShop(Map<String, dynamic> payload, String token);
  Future<void> updateProfile(
      int shopId, Map<String, dynamic> fields, String token);
  Future<void> updateSettings(
      int shopId, Map<String, dynamic> fields, String token);
}

class ApiShopRepository implements ShopRepository {
  ApiShopRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<ShopSummary>> listMyShops(String token) async {
    final data =
        await _api.get(ApiEndpoints.shops, token: token) as Map<String, dynamic>;
    return ((data['shops'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ShopSummary.fromJson)
        .toList(growable: false);
  }

  @override
  Future<ShopDetail> getShopDetail(int shopId, String token) async {
    final data = await _api.get(ApiEndpoints.shop('$shopId'), token: token)
        as Map<String, dynamic>;
    return ShopDetail.fromJson(data);
  }

  @override
  Future<ShopDetail> registerShop(
      Map<String, dynamic> payload, String token) async {
    final data =
        await _api.post(ApiEndpoints.shops, body: payload, token: token)
            as Map<String, dynamic>;
    return ShopDetail.fromJson(data);
  }

  @override
  Future<void> updateProfile(
      int shopId, Map<String, dynamic> fields, String token) async {
    await _api.put(ApiEndpoints.shopProfile('$shopId'),
        body: fields, token: token);
  }

  @override
  Future<void> updateSettings(
      int shopId, Map<String, dynamic> fields, String token) async {
    await _api.put(ApiEndpoints.shopSettings('$shopId'),
        body: fields, token: token);
  }
}

final shopRepositoryProvider = Provider<ShopRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return ApiShopRepository(api);
});

