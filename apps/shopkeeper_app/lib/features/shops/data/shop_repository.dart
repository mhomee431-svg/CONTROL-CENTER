import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_providers.dart';
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

  /// Controlled Edit-Location workflow (IDOR-safe PATCH on the backend).
  Future<Map<String, dynamic>> updateShopLocation(
      int shopId, Map<String, dynamic> payload, String token);

  /// Approved merchant categories for the registration-wizard dropdown
  /// (backend-driven — the app never hardcodes category codes).
  Future<List<MerchantCategoryOption>> listMerchantCategories(String token);

  /// Documents/verification steps required for a merchant category
  /// (backend-driven — drives the wizard's Documents step).
  Future<CategoryRequirements> getCategoryRequirements(
      String token, String categoryCode);

  /// Attach an uploaded verification document to an authorized shop.
  Future<void> addShopDocument({
    required int shopId,
    required String documentType,
    required String documentUrl,
    String? documentNumber,
    required String token,
  });

  /// Replace the shop's weekly operating hours (HH:MM strings, all 7 days).
  Future<void> updateOperatingHours({
    required int shopId,
    required String openTime,
    required String closeTime,
    required String token,
  });
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

  @override
  Future<Map<String, dynamic>> updateShopLocation(
      int shopId, Map<String, dynamic> payload, String token) async {
    final data = await _api.patch(ApiEndpoints.shopLocation('$shopId'),
        body: payload, token: token) as Map<String, dynamic>;
    return data;
  }

  @override
  Future<List<MerchantCategoryOption>> listMerchantCategories(
      String token) async {
    final data = await _api.get(ApiEndpoints.businessCategories, token: token)
        as Map<String, dynamic>;
    return ((data['categories'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MerchantCategoryOption.fromJson)
        .toList(growable: false);
  }

  @override
  Future<CategoryRequirements> getCategoryRequirements(
      String token, String categoryCode) async {
    final data = await _api.get(
      ApiEndpoints.businessCategoryRequirements(categoryCode),
      token: token,
    ) as Map<String, dynamic>;
    return CategoryRequirements.fromJson(data);
  }

  @override
  Future<void> addShopDocument({
    required int shopId,
    required String documentType,
    required String documentUrl,
    String? documentNumber,
    required String token,
  }) async {
    await _api.post(
      ApiEndpoints.shopDocuments('$shopId'),
      token: token,
      body: {
        'document_type': documentType,
        'document_url': documentUrl,
        if (documentNumber != null && documentNumber.isNotEmpty)
          'document_number': documentNumber,
      },
    );
  }

  @override
  Future<void> updateOperatingHours({
    required int shopId,
    required String openTime,
    required String closeTime,
    required String token,
  }) async {
    await _api.put(
      ApiEndpoints.shopHours('$shopId'),
      token: token,
      body: [
        for (var day = 0; day < 7; day++)
          {
            'day_of_week': day,
            'open_time': openTime,
            'close_time': closeTime,
            'is_closed': false,
          },
      ],
    );
  }
}

final shopRepositoryProvider = Provider<ShopRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return ApiShopRepository(api);
});

