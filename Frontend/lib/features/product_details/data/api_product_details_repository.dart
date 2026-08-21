import '../../../core/cache/local_cache_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../domain/product_details_repository.dart';
import '../domain/models/product_details_models.dart';

/// Real backend implementation of [ProductDetailsRepository] with local caching
/// for offline resilience. Inventory/availability data is never cached to avoid
/// presenting stale stock as confirmed live stock.
class ApiProductDetailsRepository implements ProductDetailsRepository {
  final ApiClient _apiClient;
  final LocalCacheService _cache;

  static const String _cachePrefix = 'product_details_';

  ApiProductDetailsRepository(this._apiClient, this._cache);

  @override
  Future<ProductDetails> getProductDetails(String productId) async {
    try {
      final data = await _apiClient.get(
        ApiEndpoints.product(productId),
        requiresAuth: false,
      );

      if (data is Map<String, dynamic>) {
        final offers = (data['nearby_shops_offers'] as List<dynamic>? ?? [])
            .map((e) => _mapOffer(e as Map<String, dynamic>))
            .toList();

        final details = ProductDetails(
          id: data['id']?.toString() ?? productId,
          name: data['name']?.toString() ?? '',
          brand: data['brand']?.toString() ?? '',
          category: data['category']?.toString() ?? '',
          description: data['description']?.toString() ?? '',
          imageUrls: [if (data['image_url'] != null) data['image_url'].toString()],
          priceRange: data['price_range']?.toString() ?? '',
          isAvailableAnywhere: data['is_available_anywhere'] == true,
          nearbyShopsOffers: offers,
          isSaved: data['is_saved'] == true,
        );

        // Cache product details (non-inventory data) for offline use
        // Strip inventory/availability data before caching
        final cacheData = Map<String, dynamic>.from(data);
        cacheData.remove('nearby_shops_offers');
        await _cache.put('$_cachePrefix$productId', cacheData);
        return details;
      }
      throw Exception('Invalid product details response');
    } catch (e) {
      // On failure, try to serve cached product info (without live inventory)
      final cached = await _cache.get('$_cachePrefix$productId');
      if (cached != null && cached.data is Map<String, dynamic>) {
        final data = cached.data as Map<String, dynamic>;
        return ProductDetails(
          id: data['id']?.toString() ?? productId,
          name: data['name']?.toString() ?? '',
          brand: data['brand']?.toString() ?? '',
          category: data['category']?.toString() ?? '',
          description: data['description']?.toString() ?? '',
          imageUrls: [if (data['image_url'] != null) data['image_url'].toString()],
          priceRange: data['price_range']?.toString() ?? '',
          isAvailableAnywhere: false,
          nearbyShopsOffers: [],
          isSaved: data['is_saved'] == true,
        );
      }
      rethrow;
    }
  }

  ShopOffer _mapOffer(Map<String, dynamic> json) {
    return ShopOffer(
      shopId: json['shop_id']?.toString() ?? '',
      shopName: json['shop_name']?.toString() ?? '',
      shopImageUrl: json['shop_image_url']?.toString() ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      distanceInKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      isAvailable: json['is_available'] == true,
      lastUpdated: DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
      offerText: json['offer_text']?.toString(),
    );
  }

  @override
  Future<void> toggleSaveProduct(String productId, bool save) async {
    if (save) {
      await _apiClient.post(ApiEndpoints.savedProduct(productId));
    } else {
      await _apiClient.delete(ApiEndpoints.savedProduct(productId));
    }
  }
}