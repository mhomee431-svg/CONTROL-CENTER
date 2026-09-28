import '../../../core/cache/local_cache_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../domain/shop_details_repository.dart';
import '../domain/models/shop_details_models.dart';

/// Real backend implementation of [ShopDetailsRepository] with local caching
/// for offline resilience. Inventory/availability data is never cached to avoid
/// presenting stale stock as confirmed live stock.
class ApiShopDetailsRepository implements ShopDetailsRepository {
  final ApiClient _apiClient;
  final LocalCacheService _cache;

  static const String _cachePrefix = 'shop_details_';

  ApiShopDetailsRepository(this._apiClient, this._cache);

  @override
  Future<ShopProfile> getShopProfile(String shopId) async {
    try {
      final data = await _apiClient.get(
        ApiEndpoints.shop(shopId),
        requiresAuth: false,
      );

      if (data is Map<String, dynamic>) {
        final products = (data['available_products'] as List<dynamic>? ?? [])
            .map((e) => _mapProduct(e as Map<String, dynamic>))
            .toList();

        // Public contact surface only: the backend exposes primary phone,
        // a public alternate (`secondary_phone`/legacy `whatsapp_number`),
        // and email. Anything else stays server-side.
        final secondaryPhone =
            data['secondary_phone']?.toString() ??
            data['alternate_phone']?.toString() ??
            data['whatsapp_number']?.toString() ??
            '';
        final email =
            data['email']?.toString() ?? data['contact_email']?.toString() ?? '';

        // Coordinates only count when they are real numbers in range; the
        // [ShopProfile.hasValidCoordinates] gate keeps map/directions honest.
        final latitude = (data['latitude'] as num?)?.toDouble() ?? 0;
        final longitude = (data['longitude'] as num?)?.toDouble() ?? 0;

        final profile = ShopProfile(
          id: data['id']?.toString() ?? shopId,
          name: data['name']?.toString() ?? '',
          imageUrl: data['image_url']?.toString() ?? '',
          rating: (data['rating'] as num?)?.toDouble() ?? 0,
          reviewCount: (data['review_count'] as num?)?.toInt() ?? 0,
          address: data['address']?.toString() ?? '',
          distanceInKm: (data['distance_km'] as num?)?.toDouble() ?? 0,
          openingHours: data['opening_hours']?.toString() ?? '',
          isOpenNow: data['is_open_now'] == true,
          phone: data['phone']?.toString() ?? '',
          about: data['description']?.toString() ?? '',
          lastInventoryUpdate:
              DateTime.tryParse(
                data['last_inventory_update']?.toString() ?? '',
              ) ??
              DateTime.now(),
          activeOffers: (data['active_offers'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList(),
          availableProducts: products,
          isSaved: data['is_saved'] == true,
          categories: (data['categories'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList(),
          isVerified: data['is_verified'] == true,
          latitude: latitude,
          longitude: longitude,
          secondaryPhone: secondaryPhone,
          email: email,
        );

        // Cache shop profile (non-inventory data) for offline use
        final cacheData = Map<String, dynamic>.from(data);
        cacheData.remove('available_products');
        await _cache.put('$_cachePrefix$shopId', cacheData);
        return profile;
      }
      throw Exception('Invalid shop details response');
    } catch (e) {
      // On failure, try to serve cached shop info (without live inventory)
      final cached = await _cache.get('$_cachePrefix$shopId');
      if (cached != null && cached.data is Map<String, dynamic>) {
        final data = cached.data as Map<String, dynamic>;
        return ShopProfile(
          id: data['id']?.toString() ?? shopId,
          name: data['name']?.toString() ?? '',
          imageUrl: data['image_url']?.toString() ?? '',
          rating: (data['rating'] as num?)?.toDouble() ?? 0,
          reviewCount: (data['review_count'] as num?)?.toInt() ?? 0,
          address: data['address']?.toString() ?? '',
          distanceInKm: (data['distance_km'] as num?)?.toDouble() ?? 0,
          openingHours: data['opening_hours']?.toString() ?? '',
          isOpenNow: false,
          phone: data['phone']?.toString() ?? '',
          about: data['description']?.toString() ?? '',
          lastInventoryUpdate: DateTime.now(),
          activeOffers: [],
          availableProducts: [],
          isSaved: data['is_saved'] == true,
          categories: (data['categories'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList(),
          isVerified: data['is_verified'] == true,
          latitude: (data['latitude'] as num?)?.toDouble() ?? 0,
          longitude: (data['longitude'] as num?)?.toDouble() ?? 0,
          secondaryPhone: data['secondary_phone']?.toString() ?? '',
          email: data['email']?.toString() ?? '',
        );
      }
      rethrow;
    }
  }

  ShopProductSummary _mapProduct(Map<String, dynamic> json) {
    return ShopProductSummary(
      productId: json['product_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      imageUrl: json['image_url']?.toString() ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      isAvailable: json['is_available'] == true,
    );
  }

  @override
  Future<void> toggleSaveShop(String shopId, bool save) async {
    if (save) {
      await _apiClient.post(ApiEndpoints.savedShop(shopId));
    } else {
      await _apiClient.delete(ApiEndpoints.savedShop(shopId));
    }
  }
}
