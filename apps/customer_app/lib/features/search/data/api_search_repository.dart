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
    // Real popularity comes from aggregated platform searches
    // (GET /search/v2/popular). When the platform has no search history yet
    // (fresh database / new deployment) or the call fails, this returns an
    // empty list so the UI hides the section — never a hardcoded starter list,
    // which would be indistinguishable from genuine popularity data.
    try {
      final data = await _apiClient.get(
        ApiEndpoints.searchPopular,
        requiresAuth: false,
      );
      if (data is List) {
        return data
            .whereType<Map<String, dynamic>>()
            .map((e) => e['query']?.toString() ?? '')
            .where((q) => q.isNotEmpty)
            .toList();
      }
    } catch (_) {
      // Fall through to an empty list below.
    }
    return [];
  }

  @override
  Future<List<ShopProductResult>> lookupBarcode(
    String barcode, {
    double? latitude,
    double? longitude,
  }) async {
    final data = await _apiClient.get(
      ApiEndpoints.searchBarcode(Uri.encodeComponent(barcode.trim())),
      queryParameters: {'latitude': ?latitude, 'longitude': ?longitude},
      requiresAuth: false,
    );

    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(_mapBarcodeHit)
          .toList(growable: false);
    }
    return const [];
  }

  /// Maps one `GET /search/v2/barcodes/{barcode}` hit onto [ShopProductResult].
  ///
  /// The barcode payload omits the product image and reports nullable price /
  /// distance, so those stay empty rather than being invented.
  static ShopProductResult _mapBarcodeHit(Map<String, dynamic> json) {
    // A scanned product carries the same freshness evidence as a typed one.
    // A missing timestamp keeps the epoch sentinel, which the shared freshness
    // formatter renders as "Unknown" instead of a fabricated "just now".
    final lastUpdated = DateTime.tryParse(
      (json['last_inventory_update'] ?? json['last_updated'])?.toString() ?? '',
    );

    return ShopProductResult(
      id: json['shop_product_id']?.toString() ?? '',
      productId: json['product_id']?.toString() ?? '',
      productName: json['product_name']?.toString() ?? '',
      productImageUrl: '',
      shopId: json['shop_id']?.toString() ?? '',
      shopName: json['shop_name']?.toString() ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      isAvailable: json['is_available'] == true,
      distanceInKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
      shopRating: (json['shop_rating'] as num?)?.toDouble() ?? 0,
      lastUpdated: lastUpdated ?? DateTime.fromMillisecondsSinceEpoch(0),
      brand: json['brand_name']?.toString(),
      category: json['category_name']?.toString(),
      mrp: (json['mrp'] as num?)?.toDouble(),
      // Barcode hits carry the same open/order-acceptance enrichment as text
      // search (engine attaches it), so a scanned and a typed product agree.
      isOpenNow: json['is_open_now'] as bool?,
      isAcceptingOrders: json['is_accepting_orders'] as bool?,
      availability: _availabilityFrom(json['stock_status']?.toString()),
      freshness: _parseFreshnessStatus(json),
      freshnessStatusRaw: json['freshness_status']?.toString(),
    );
  }

  static InventoryAvailability _availabilityFrom(String? status) {
    return switch (status?.toLowerCase()) {
      'in_stock' || 'in-stock' || 'in stock' || 'available' =>
        InventoryAvailability.inStock,
      'out_of_stock' || 'out-of-stock' || 'out of stock' || 'unavailable' =>
        InventoryAvailability.outOfStock,
      'low_stock' || 'low-stock' || 'low stock' || 'limited' =>
        InventoryAvailability.lowStock,
      _ => InventoryAvailability.unknown,
    };
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
    SortOption sort = kDefaultSortOption,
    Map<String, dynamic>? filters,
    double? latitude,
    double? longitude,
  }) async {
    final sortValue = switch (sort) {
      SortOption.nearest => 'nearest',
      SortOption.lowestPrice => 'lowest_price',
      SortOption.highestRated => 'highest_rated',
      SortOption.recentlyUpdated => 'recently_updated',
      SortOption.relevance => 'relevance',
      SortOption.availability => 'availability',
      SortOption.offers => 'offers',
    };

    final queryParameters = <String, dynamic>{
      'q': query,
      'page': page,
      'limit': limit,
      'sort': sortValue,
      'latitude': ?latitude,
      'longitude': ?longitude,
      if (filters?['in_stock'] == true) 'in_stock': true,
      if (filters?['offers_only'] == true) 'offers_only': true,
      if (filters?['open_now'] == true) 'open_now': true,
      if (filters?['max_distance'] is num)
        'radius_km': (filters!['max_distance'] as num).toDouble(),
      if (filters?['min_rating'] is num)
        'min_rating': (filters!['min_rating'] as num).toDouble(),
      if (filters?['min_price'] is num)
        'min_price': (filters!['min_price'] as num).toDouble(),
      if (filters?['max_price'] is num)
        'max_price': (filters!['max_price'] as num).toDouble(),
      if (filters?['category'] != null) 'category': filters!['category'],
      if (filters?['brand'] != null) 'brand': filters!['brand'],
    };

    final data = await _apiClient.get(
      ApiEndpoints.searchProducts,
      queryParameters: queryParameters,
      requiresAuth: false,
    );

    if (data is Map<String, dynamic>) {
      final results = data['results'] as List<dynamic>? ?? [];
      return results.map((e) => _mapResult(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  ShopProductResult _mapResult(Map<String, dynamic> json) {
    // The search index publishes `last_inventory_update`; `last_updated` is
    // accepted as a tolerated alias. When neither is present we keep null so
    // freshness falls back to the explicit `freshness_status` instead of being
    // derived from a fabricated "now".
    final lastUpdated = DateTime.tryParse(
      (json['last_inventory_update'] ?? json['last_updated'])?.toString() ?? '',
    );
    final availability = _parseAvailability(json);
    final freshness = lastUpdated != null
        ? _deriveFreshness(lastUpdated)
        : _parseFreshnessStatus(json);

    return ShopProductResult(
      // The search index exposes the offer-level id as shop_product_id.
      id: (json['id'] ?? json['shop_product_id'])?.toString() ?? '',
      productId: json['product_id']?.toString() ?? '',
      productName: json['product_name']?.toString() ?? '',
      productImageUrl: json['product_image_url']?.toString() ?? '',
      shopId: json['shop_id']?.toString() ?? '',
      shopName: json['shop_name']?.toString() ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      isAvailable: json['is_available'] == true,
      distanceInKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
      shopRating: (json['shop_rating'] as num?)?.toDouble() ?? 0,
      // Unknown timestamp stays an explicit sentinel. Stamping DateTime.now()
      // here would make stale inventory look freshly verified.
      lastUpdated: lastUpdated ?? DateTime.fromMillisecondsSinceEpoch(0),
      variant: json['variant']?.toString(),
      mrp: (json['mrp'] as num?)?.toDouble(),
      shopImageUrl: json['shop_image_url']?.toString(),
      offerText: json['offer_text']?.toString(),
      shopAddress: json['shop_address']?.toString(),
      shopLatitude: (json['shop_latitude'] as num?)?.toDouble(),
      shopLongitude: (json['shop_longitude'] as num?)?.toDouble(),
      category: (json['category'] ?? json['category_name'])?.toString(),
      brand: (json['brand'] ?? json['brand_name'])?.toString(),
      reviewCount: (json['review_count'] as num?)?.toInt(),
      // Backend's open/order-acceptance evaluation. Null means "not reported",
      // which the card renders as nothing rather than guessing.
      isOpenNow: json['is_open_now'] as bool?,
      isAcceptingOrders: json['is_accepting_orders'] as bool?,
      availability: availability,
      freshness: freshness,
      freshnessStatusRaw: json['freshness_status']?.toString(),
    );
  }

  InventoryAvailability _parseAvailability(Map<String, dynamic> json) {
    final raw = (json['stock_status'] ?? json['availability'])
        ?.toString()
        .toLowerCase();
    if (raw != null) {
      switch (raw) {
        case 'in_stock':
        case 'in-stock':
        case 'in stock':
        case 'available':
          return InventoryAvailability.inStock;
        case 'out_of_stock':
        case 'out-of-stock':
        case 'out of stock':
        case 'unavailable':
          return InventoryAvailability.outOfStock;
        case 'low_stock':
        case 'low-stock':
        case 'low stock':
        case 'limited':
          return InventoryAvailability.lowStock;
        default:
          break;
      }
    }
    if (json['is_available'] == true) return InventoryAvailability.inStock;
    if (json['is_available'] == false) return InventoryAvailability.outOfStock;
    return InventoryAvailability.unknown;
  }

  FreshnessLevel _deriveFreshness(DateTime lastUpdated) {
    final age = DateTime.now().difference(lastUpdated);
    if (age.inMinutes <= 30) return FreshnessLevel.fresh;
    if (age.inHours <= 6) return FreshnessLevel.recent;
    return FreshnessLevel.stale;
  }

  /// Maps the backend's inventory freshness classification
  /// (RECENTLY_UPDATED / STALE / None) onto the UI freshness levels.
  ///
  /// Static so the barcode hit mapper and the result mapper can share one
  /// implementation — a scanned and a typed product must never classify
  /// freshness differently.
  static FreshnessLevel _parseFreshnessStatus(Map<String, dynamic> json) {
    final raw = json['freshness_status']?.toString().toLowerCase();
    if (raw == 'recently_updated') return FreshnessLevel.fresh;
    if (raw == 'stale') return FreshnessLevel.stale;
    return FreshnessLevel.unknown;
  }
}
