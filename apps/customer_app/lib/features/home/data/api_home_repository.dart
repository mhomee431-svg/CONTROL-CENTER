import '../../../core/cache/local_cache_service.dart';
import '../../../core/catalog/approved_categories.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/json_map.dart';
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
        queryParameters: {'latitude': ?latitude, 'longitude': ?longitude},
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

  @override
  Future<ShopsByPinPage> fetchShopsByPincode(
    String pincode, {
    int page = 1,
    required int limit,
  }) async {
    final data = await _apiClient.get(
      ApiEndpoints.nearbyShops,
      queryParameters: {'pincode': pincode, 'page': page, 'limit': limit},
      requiresAuth: false,
    );

    if (data is Map<String, dynamic> && data['shops'] is List) {
      final shops = (data['shops'] as List)
          .map(_shopFromJson)
          .toList(growable: false);
      // A short page means the backend ran out, which is the only reliable
      // end-of-list signal when the response carries no total count.
      return ShopsByPinPage(shops: shops, hasMore: shops.length >= limit);
    }
    // No rows at all: an empty page is also the end of the list.
    return ShopsByPinPage.empty;
  }

  HomeData _parseHomeData(Map<String, dynamic> data) {
    List<Product> parseProducts(String key) =>
        (data[key] as List<dynamic>? ?? []).map(_productFromJson).toList();

    List<Promotion> parsePromotions(String key) =>
        (data[key] as List<dynamic>? ?? []).map(_promotionFromJson).toList();

    // Visibility is the backend's call (`is_active` on `/home/feed`). The only
    // thing the client still filters is the one rule the database cannot
    // express — grocery and restaurants are not product-discovery categories —
    // and that is a deny-list, so a newly published category appears here
    // immediately instead of needing an app release.
    final categories = (data['categories'] as List<dynamic>? ?? [])
        .map(_categoryFromJson)
        .where(
          (category) => ApprovedCategories.isProductBrowsable(category.name),
        )
        .toList(growable: false);

    return HomeData(
      categories: categories,
      popularProducts: parseProducts('popular_products'),
      nearbyShops: (data['nearby_shops'] as List<dynamic>? ?? [])
          .map(_shopFromJson)
          .toList(),
      recentSearches: (data['recent_searches'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      recentlyViewed: parseProducts('recently_viewed'),
      recommendedProducts: parseProducts('recommended_products'),
      promotions: parsePromotions('promotions'),
    );
  }

  // ── Tolerant field readers ──────────────────────────────────────────────
  //
  // These read the WIRE format directly rather than delegating to the models'
  // generated `fromJson`, for one concrete reason: the backend sends snake_case
  // (`image_url`, `price_range`, `is_verified`, `is_open_now`) while
  // json_serializable generates camelCase lookups, so the generated parsers
  // throw a TypeError on a real payload — taking out the whole Home screen,
  // Nearby Shops included. Both spellings are accepted here, so a cached
  // camelCase payload and a live snake_case one both parse.
  //
  // Every reader is total: missing or wrong-typed fields degrade to a default
  // instead of throwing, because one malformed shop must not empty the row.

  Shop _shopFromJson(Object? raw) {
    final json = JsonMap.tryParse(raw);
    return Shop(
      id: json.stringOr('id'),
      name: json.stringOr('name'),
      imageUrl: json.stringOr('image_url', json.stringOr('imageUrl')),
      distance: json.firstDecimalOf(['distance', 'distance_km']) ?? 0,
      rating: json.firstDecimalOf(['rating', 'average_rating']) ?? 0,
      isVerified: json.firstBooleanOf(['is_verified', 'isVerified']) ?? false,
      // NOT defaulted: an absent verdict must stay absent so the card renders no
      // badge instead of claiming the shop is open.
      isOpenNow: json.firstBooleanOf(['is_open_now', 'isOpenNow']),
      isAcceptingOrders: json.firstBooleanOf([
        'is_accepting_orders',
        'isAcceptingOrders',
      ]),
    );
  }

  Product _productFromJson(Object? raw) {
    final json = JsonMap.tryParse(raw);
    return Product(
      id: json.stringOr('id'),
      name: json.stringOr('name'),
      brand: json.stringOr('brand'),
      imageUrl: json.stringOr('image_url', json.stringOr('imageUrl')),
      priceRange: json.stringOr('price_range', json.stringOr('priceRange')),
    );
  }

  Category _categoryFromJson(Object? raw) {
    final json = JsonMap.tryParse(raw);
    return Category(
      id: json.stringOr('id'),
      name: json.stringOr('name'),
      iconUrl: json.stringOr('icon_url', json.stringOr('iconUrl')),
    );
  }

  Promotion _promotionFromJson(Object? raw) {
    final json = JsonMap.tryParse(raw);
    return Promotion(
      id: json.stringOr('id'),
      title: json.stringOr('title'),
      subtitle: json.stringOr('subtitle'),
      imageUrl: json.stringOr('image_url', json.stringOr('imageUrl')),
      ctaLabel: json.firstOf(['cta_label', 'ctaLabel']),
      ctaTarget: json.firstOf(['cta_target', 'ctaTarget']),
    );
  }
}
