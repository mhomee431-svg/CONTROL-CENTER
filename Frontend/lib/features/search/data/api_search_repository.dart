import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../domain/search_repository.dart';
import '../domain/models/search_models.dart';

/// Real backend implementation of [SearchRepository].
class ApiSearchRepository implements SearchRepository {
  final ApiClient _apiClient;

  ApiSearchRepository(this._apiClient);

  @override
  Future<List<String>> getRecentSearches() async {
    // Recent searches are stored locally; the backend does not persist them in Phase 13.
    return [];
  }

  @override
  Future<List<String>> getPopularSearches() async {
    return ['Samsung Galaxy', 'Aashirvaad Atta', 'Dettol', 'Bajaj'];
  }

  @override
  Future<List<SearchSuggestion>> getSuggestions(String query) async {
    final data = await _apiClient.get(
      ApiEndpoints.searchSuggestions,
      queryParameters: {'q': query},
      requiresAuth: false,
    );

    if (data is List) {
      return data
          .map((e) => SearchSuggestion.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  @override
  Future<List<ShopProductResult>> searchProducts({
    required String query,
    required int page,
    required int limit,
    SortOption sort = SortOption.nearest,
    Map<String, dynamic>? filters,
  }) async {
    final sortValue = switch (sort) {
      SortOption.nearest => 'nearest',
      SortOption.lowestPrice => 'lowest_price',
      SortOption.highestRated => 'highest_rated',
      SortOption.recentlyUpdated => 'recently_updated',
    };

    final queryParameters = <String, dynamic>{
      'q': query,
      'page': page,
      'limit': limit,
      'sort': sortValue,
      if (filters?['in_stock'] == true) 'in_stock': true,
      if (filters?['max_distance'] is num)
        'radius_km': (filters!['max_distance'] as num).toDouble(),
    };

    final data = await _apiClient.get(
      ApiEndpoints.searchProducts,
      queryParameters: queryParameters,
      requiresAuth: false,
    );

    if (data is Map<String, dynamic>) {
      final results = data['results'] as List<dynamic>? ?? [];
      return results
          .map((e) => _mapResult(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  ShopProductResult _mapResult(Map<String, dynamic> json) {
    return ShopProductResult(
      id: json['id']?.toString() ?? '',
      productId: json['product_id']?.toString() ?? '',
      productName: json['product_name']?.toString() ?? '',
      productImageUrl: json['product_image_url']?.toString() ?? '',
      shopId: json['shop_id']?.toString() ?? '',
      shopName: json['shop_name']?.toString() ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      isAvailable: json['is_available'] == true,
      distanceInKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
      shopRating: (json['shop_rating'] as num?)?.toDouble() ?? 0,
      lastUpdated: DateTime.tryParse(json['last_updated']?.toString() ?? '') ??
          DateTime.now(),
      offerText: json['offer_text']?.toString(),
    );
  }
}