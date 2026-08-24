import '../../../core/cache/local_cache_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../domain/home_repository.dart';
import '../domain/models/home_data.dart';

/// Real backend implementation of [HomeRepository] with local caching
/// for offline resilience. Inventory data is never cached to avoid
/// presenting stale stock as confirmed live stock.
class ApiHomeRepository implements HomeRepository {
  final ApiClient _apiClient;
  final LocalCacheService _cache;

  static const String _cacheKey = 'home_feed';

  ApiHomeRepository(this._apiClient, this._cache);

  @override
  Future<HomeData> fetchHomeFeed({double? latitude, double? longitude}) async {
    try {
      final data = await _apiClient.get(
        ApiEndpoints.homeFeed,
        queryParameters: {
          'latitude': ?latitude,
          'longitude': ?longitude,
        },
        requiresAuth: false,
      );

      if (data is Map<String, dynamic>) {
        final homeData = _parseHomeData(data);

        // Cache the home feed for offline use (non-inventory data only)
        await _cache.put(_cacheKey, data);
        return homeData;
      }
      throw Exception('Invalid home feed response');
    } catch (e) {
      // On failure, try to serve cached data
      final cached = await _cache.get(_cacheKey);
      if (cached != null && cached.data is Map<String, dynamic>) {
        return _parseHomeData(cached.data as Map<String, dynamic>);
      }
      rethrow;
    }
  }

  HomeData _parseHomeData(Map<String, dynamic> data) {
    List<Product> parseProducts(String key) =>
        (data[key] as List<dynamic>? ?? [])
            .map((e) => Product.fromJson(e as Map<String, dynamic>))
            .toList();

    List<Promotion> parsePromotions(String key) =>
        (data[key] as List<dynamic>? ?? [])
            .map((e) => Promotion.fromJson(e as Map<String, dynamic>))
            .toList();

    return HomeData(
      categories: (data['categories'] as List<dynamic>? ?? [])
          .map((e) => Category.fromJson(e as Map<String, dynamic>))
          .toList(),
      popularProducts: parseProducts('popular_products'),
      nearbyShops: (data['nearby_shops'] as List<dynamic>? ?? [])
          .map((e) => Shop.fromJson(e as Map<String, dynamic>))
          .toList(),
      recentSearches: (data['recent_searches'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      recentlyViewed: parseProducts('recently_viewed'),
      recommendedProducts: parseProducts('recommended_products'),
      promotions: parsePromotions('promotions'),
    );
  }
}
